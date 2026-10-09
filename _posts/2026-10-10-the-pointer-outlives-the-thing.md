---
title: "The Pointer Outlives the Thing"
date: 2026-10-10 05:00:00 -0700
tags: [dns, subdomain-takeover, detection-engineering, cloud security, security operations]
---

Picture a company. Call it Meridian, it doesn't matter, because the only thing that makes Meridian special is that it's careful, and careful is exactly the kind of place this happens to. 

One day a subdomain under one of Meridian's corporate domains suddenlly starts serving commodity malware via a distribution page. Hundreds of further subdomains under the original appear. Not a lookalike domain, not a typo-squat. The real domain, a real subdomain under it, every label beneath that subdomain, all resolving to someone else's content, all behind a valid TLS certificate issued for Meridian's name. Nobody logged into anything. No credential was phished, no token stolen, no box popped. The attacker never touched a single system Meridian owns.

What they took over was a pointer Meridian forgot to delete.

I want to walk through why this happens, because once you see the shape of it you'll understand that it isn't an edge case. It's a routine consequence of tearing down cloud resources in the wrong order, the preconditions are sitting in a lot of zones right now, and the barrier to exploiting it is low enough that it gets done at scale by people who aren't targeting you specifically. Then I'll cover what I built to catch it, including two correctness problems that would have made the detector quietly lie to me, and what actually prevents it. I'll keep every name generic: call the apex `example.com`, the subdomain `legacy`, and the cloud provider "the platform."

## The setup nobody thinks of as fragile

If you run a subdomain as its own DNS zone, which is normal when a different team or pipeline needs to manage that subtree on its own, the parent zone doesn't hold the records for it. It holds a *delegation*: a handful of `NS` records that say "for anything under `legacy.example.com`, go ask those name servers over there." On a managed cloud DNS service, "over there" is a set of the platform's shared name servers, assigned to your child zone when you created it.

So the parent zone for `example.com` ends up with something like this for the subdomain:

```
legacy.example.com.  NS  ns1-NN.<platform-dns>.
legacy.example.com.  NS  ns2-NN.<platform-dns>.
legacy.example.com.  NS  ns3-NN.<platform-dns>.
legacy.example.com.  NS  ns4-NN.<platform-dns>.
```

where `NN` is which of the platform's name-server sets your child zone landed on. That's the whole delegation. Four records in the parent, pointing into a shared pool. It looks completely benign, and for as long as the child zone exists it is.

## Where the asset actually lives

Now the subdomain gets retired. The team deletes the child zone and the resources behind it. Cleanup, closed ticket, done.

Except the four `NS` records in the parent zone don't get deleted, because they live in a *different* zone, often owned by a different team, managed by different automation. Nothing about deleting the child made them go away, and the platform gives no warning that they're now pointing at nothing. The parent still tells the world "go ask those name servers for `legacy`," and those name servers no longer have anything to say. Queries fail. To anyone looking, the subdomain is just dead.

Here's the part that flips it from dead to dangerous. Those name servers in the delegation aren't private to you. They're a shared pool the platform hands out to every customer. And on these services, anyone with an account can create a DNS zone for a name they don't own. The platform does not check that you control the parent domain before letting you create a zone called `legacy.example.com`. When it hands that new zone a name-server set, if it hands out the same set the stale delegation still points at, then by the ordinary rules of DNS the parent is now delegating your name to a zone a stranger controls. The pool of sets is small, and assignment is far from random, so landing on a specific one is cheap and repeatable. I'm deliberately not writing the recipe, because the recipe isn't the point. The point is that it's a known, reliable technique, and the person doing it needs nothing from you except that you left the delegation up.

From there they own the name and everything under it. They point a wildcard at their own content, so `legacy` and every host beneath it resolves to them. Because they now control DNS for the name, they can get a domain-validated TLS certificate for it without any trouble, which is why the hijacked pages served clean HTTPS under the real corporate domain. That is the whole attack. The thing they took was never a system. It was a pointer that outlived the thing it pointed at.

## Say the root cause as one sentence

It's ordering. The pointer in the parent outlived the resource it pointed at, and the pointer, not the resource, was the asset that had to be removed first.

That sentence is the entire bug, and it generalizes past this one flavor. The same mistake with a `CNAME` or `A` record instead of a delegation, pointing at a platform resource (an app host, a storage endpoint, a CDN, a load balancer) that got deleted while the DNS record stayed, gives an attacker the same prize by a slightly different door: they re-claim the resource name and inherit your hostname. Different record type, different backing resource, identical root cause. Whenever a name you publish points at something ephemeral, the name has to die first, or not at all.

One honest note about this kind of incident. You can usually confirm the preconditions after the fact: the subdomain was a delegated child zone, the backing resources were deleted, the name later served someone else's content. The attacker's exact method is harder to pin down, because leftover-delegation reuse and a few neighboring vectors all produce the same symptom. It doesn't change the fix. Everything below catches the whole family, not one member of it.

## How widespread this is, and why "we're careful" doesn't save you

I used to half-assume this was a problem for organizations that don't clean up after themselves. The measurement literature says otherwise, and the numbers are worth sitting with.

A Palo Alto Networks Unit 42 study built a detector over passive DNS and found roughly 317,000 unsafe dangling records, and crucially, they appeared in exactly the zones you'd expect to be well run: hundreds under `.edu`, some under `.gov`, thousands inside the most popular domains on the internet. A 2026 study from Silent Push started with 12,500 apex domains, found 16,000 dangling subdomains, and automated the takeover of 4,000 of them. Certitude demonstrated takeovers against governments, universities, and media outlets, and said the thousand-plus organizations they found were "the tip of the iceberg." Academic work scanning the top of the Tranco list keeps finding the same thing at every sample size anyone picks.

Two things fall out of that. First, the floor is high: estimates run from thousands to hundreds of thousands of affected names depending on how you count, which means the base rate of "some subdomain somewhere in your estate dangles" is not low. Second, careful organizations are in the dataset. This isn't a hygiene failure that discipline alone fixes, because the discipline required is *ordering across team boundaries* — the parent zone and the child resource are usually owned by different people, and nothing in the normal teardown of one touches the other. That seam is where the dangle lives, and it's structural, not sloppy. It's exactly why a place like Meridian ends up in this story.

And the economics favor the attacker completely. They don't need to know your name in advance. They can sweep passive DNS for delegations that point into a cloud pool and no longer resolve, then try to claim them in bulk. Your subdomain isn't a target, it's a search result. That's the part I'd want a leadership audience to internalize: the attack doesn't scale because attackers got clever, it scales because the precondition is common and finding it is a database query.

## Detecting it: compare two facts that can't both be wrong

The detector I built rests on one idea. You cannot tell whether a delegation is safe by asking DNS, because DNS resolution can't distinguish "this name is gone" from "someone else owns this name now." Both look like a working or failing lookup. You have to compare two *independent* facts:

1. **The delegations you publish** — every `NS` delegation, and every takeover-prone `CNAME`/`A`, read from the authoritative parent zones wherever they live.
2. **The zones you actually own** — read from the cloud *control plane*, the API that lists your resources, not from DNS.

A delegation is hijackable when it points into the platform's name-server pool but no zone of that name exists in your owned inventory. The control-plane inventory is the authority; live resolution is used only to corroborate. That's the whole design, and it's deliberately boring, because the boring version is the one that doesn't fool itself.

It also flags the `CNAME`/`A`-to-a-deleted-resource variant, and "orphan" zones you own that nothing delegates to, which are either dead weight or a sign that the parent lives at a provider you haven't pointed the scanner at yet.

I proved it against a scratch tenant I stood up and tore down: healthy delegation, then delete the child and leave the delegation, watch it flag HIGH, then remove the delegation, watch it go clean. Four states, the detector right on each.

## Two ways the detector almost lied to me

I'm dwelling on these because a dangling-DNS detector that silently finds nothing is worse than no detector at all. It doesn't just fail, it issues you a clean bill of health you'll believe.

**The first build found zero delegations and reported everything clean.** It was wrong. The control-plane command that lists DNS records returns its JSON keys capitalized, while the rest of the DNS commands on the same CLI return them in camelCase. My parser looked for the camelCase keys, found none, and concluded there were no delegations anywhere. Running against real data caught it; a unit test with hand-written fixtures never would have, because I'd have written the fixtures in whatever casing I assumed. The parser is case-insensitive now. If you build your own, this one will bite you.

**The second was about where you look.** The fast, tenant-wide resource index, the thing you'd naturally reach for to sweep every subscription at once, indexes DNS *zones* but not their *record sets*. So a detection built only on it can see that a zone exists but cannot see the delegations inside it, which means it cannot see NS dangles at all. The working architecture uses the fast index for the zone inventory and a scheduled job that reads the actual delegations through the DNS API, then feeds findings into the SIEM as one high-severity incident per dangling name. If I'd trusted the index alone I'd have shipped a detector blind to the exact thing it was built for.

Both mistakes have the same flavor as [the one I keep writing about](/2026/07/13/the-passkey-enrollment-log-finally-earns-its-keep-hunting-o-unc-066.html): the detection keyed on a field or a source I assumed behaved one way and didn't verify. Ground it against real data or it will fail silently, and silent failure in detection is the only kind that matters.

## Preventing it, in order of leverage

1. **Fix the teardown order.** Remove the parent delegation first, confirm the name no longer resolves, *then* delete the child zone or resource. Bake it into the runbook and into the infrastructure-as-code destroy sequence as an explicit dependency, so the pipeline physically cannot delete the backing resource before the record that points at it. This is the whole fix; everything else is a net under it.

2. **Scan continuously.** Run the detector daily against every subscription and alert on anything HIGH. It's read-only and needs only read access. This is the control that catches the dangle the day the child zone is deleted, instead of whenever someone notices the malware being served under your name.

3. **Prefer records over child zones.** A lot of subdomains don't need their own zone at all. Put the records directly in the parent and the delegation-dangle risk doesn't exist, because there's no delegation. Delegate only when a subtree genuinely needs independent management.

4. **Use lifecycle-aware record types** for cloud resources where the platform offers them. They return a clean "doesn't exist" when the target is deleted instead of leaving a pointer an attacker can claim.

5. **Lock production zones** so a child zone can't be deleted out from under a live delegation. This is a backstop for one vector only; it does nothing for the `CNAME`-to-deleted-resource case. Useful, but not a substitute for the ordering fix.

6. **Point the scanner at every provider your parents live in.** Estates commonly spread parent domains across several DNS providers, which is both normal and exactly why the seam exists. A dangle doesn't care which provider the parent lives at, so the detection can't either.

## The part that stays with me

What bothers me most about an incident like this isn't the payload itself. It's how little the attacker needs, and how much it looks like nothing while it's wrong. There's no alert to miss, because from the inside everything was deleted and quiet. The vulnerability isn't a system that's exposed, it's a system that's *gone*, and the record that remembers it is the liability. We spend enormous effort watching the things we run. This is a reminder to watch the things we've stopped running, because the names outlive them, and a name that points at nothing is an invitation addressed to whoever finds it first.

The discipline is one sentence, and it's worth ending on: the name dies first, or it doesn't die at all.

---

*Disclosure: AI was used for proofing.*
