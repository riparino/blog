---
title: "Detection Altitude Is a Collection Strategy"
date: 2026-07-14 05:00:00 -0700
---

Two posts ago I argued that you should derive your telemetry backward (threat model, then detection requirement, then telemetry requirement, then logging architecture) and stop collecting on reflex. In my last post I put a live actor through that pipeline and showed the Entra passkey-enrollment stream earning its place. What I didn't say in either post is that the whole derivation rests on a hidden assumption, and if that assumption doesn't hold, the argument collapses. This post is about the assumption.

## The unstated dependency

Deriving telemetry from a threat model only works if your detections are expressible as *behaviors*. If the thing you actually detect on is indicators, meaning this hash, this IP, this domain, then the backward derivation is impossible, because you cannot know in advance which indicators you'll need. Indicators are unknowable before the incident and perishable after it. An organization whose detection capability lives at the indicator level has no rational choice but to hoard, because "collect everything" is the only sane response to "we can't predict what we'll have to match against."

So the hoarding reflex I spent a whole post attacking isn't really a discipline problem at all. It's a symptom, and specifically it's what detecting at the wrong altitude looks like from the budget side. You can't lecture an indicator-driven SOC into collecting deliberately, because deliberate collection isn't available to them: their detection model makes collection undecidable, and undecidable collection defaults to hoarding every time.

That's the missing term between the two posts. Behavioral detection is the mechanism that makes deliberate collection *possible in the first place.*

## Why behaviors are derivable and indicators aren't

The difference comes down to what constrains each one. An indicator is an accident of a particular campaign: the attacker picked that domain, compiled that binary, rented that box. Nothing about your threat model predicts it, so nothing about your threat model tells you what to collect for it. You find out what you needed only after you needed it.

A behavior is constrained by the adversary's objective and by the physics of your environment, and both of those you can reason about ahead of time. To take over an identity and steal data, an attacker has to authenticate, has to add or alter an authentication method or token to persist, and has to touch the data. Those aren't stylistic choices; they're load-bearing steps in the objective. Strip away the specific kit and the invariant remains.

The previous post's passkey campaign is one skin stretched over that skeleton. Storm-2949's MFA-fatigue-into-SSPR play is a different skin over the same bones. Whatever runs this pattern next quarter with fresh infrastructure and a new lure is a third. If your detection keys on the skeleton, you catch all three; if it keys on a skin, you catch one and wait to be told about the next.

## The Pyramid of Pain, pointed at the wrong axis on purpose

David Bianco drew the Pyramid of Pain in 2013, out of the APT1 period, to make a point about detection: indicators sit in tiers by how much it costs the adversary to change them when you deny them. Hashes and IPs are at the bottom because they're trivial to swap. Domains cost a little more. Tools cost real effort. Tactics, techniques, and procedures sit at the apex because they're learned behavior, and forcing an adversary to relearn how they operate is the most expensive thing you can do to them. Detect high on the pyramid and you impose durable cost; detect low and you're playing whack-a-mole with things the attacker regenerates for free.

That's the canonical reading, and it's about *detection* strategy. The two posts before this one imply a second reading on a different axis: **detection altitude also determines whether your collection is decidable.**

Here's the same pyramid, read as a collection argument. Detect at the bottom and you can't derive your telemetry, because the indicators you'll need are unknowable in advance, so you hoard. Detect at the top and each log source becomes justifiable from the threat model, because a behavior traces cleanly back to a modeled threat in a way an indicator never can. The unit of justification changes. At the bottom it's "which detection does this source enable," and you can't answer it before the fact. At the top it becomes "which behavior do I need to be able to see," and that you *can* answer, because you wrote the threat model that names the behavior.

Move up the pyramid and collection becomes a design problem with a right answer. Stay at the bottom and it stays a hoarding problem with no floor.

## The whole argument lives in two queries

I already shipped the worked example in the last post without naming it as one. The passkey post carried two sign-in-correlated queries, and the difference between them is exactly this axis.

The retro-hunt query keyed on the actor's ASNs, DDoS-Guard and IQWeb, which is the infrastructure Okta published. That's a skin, near the bottom of the pyramid, it's disposable by design, and I told you to run it once and throw it away precisely because the moment the actor re-hosts it goes silent and starts lying to you about being clean. It depends on an indicator I can only know after someone else caught the campaign.

The standing detection keyed on the skeleton: an authentication-method registration inside a short window of a sign-in from an ASN that user has never used. No indicator anywhere in it. It survives the actor re-hosting, and it survives the actor switching techniques entirely, because the behavior it watches (persist by adding a credential, from somewhere anomalous) is downstream of the objective, not the tooling. That query is derivable from the threat model. I could have written it before O-UNC-066 existed, and it'll still be standing after Pink rebrands.

One is a thing you match. The other is a thing you model. That's the pyramid, and it's why only one of the two belongs in your rule set.

## The bill, because a post that only sells the upside is the thing I warned you about

Behavioral detection is not free and it does not mean "collect less." It means collect a different *shape*, and it comes with costs the first post's own logic demands I put on the table.

**Behaviors need baselines, and baselines need retained history.** The standing detection fires on "an ASN this user has never used," which means something has to have kept enough sign-in history to define "never." That actually amends the three-question test from the invoice post. Some sources earn their keep not by enabling a detection directly but by being the baseline substrate a behavioral detection stands on. So the test grows a fourth question: *does this source establish or enrich a baseline that a detection depends on?* A log that's useless in isolation can be load-bearing as history.

**A single behavior is noisy; the fidelity is compositional.** First-seen-ASN on its own fires on every business trip and every new VPN egress. What makes the standing detection worth an analyst's minutes is the conjunction: new network *and* a credential change *and* inside the same hour. The rarity lives in the sequence, not in any one event. Get the composition wrong and you've rebuilt the alert-fatigue problem from the first post one layer up; get it right and the analyst-hour math finally works in your favor. This is the actual craft, and it's where most behavioral programs either pay off or quietly bankrupt themselves.

**It demands fielded, entity-resolved data at ingest, not raw blobs you grep later.** To correlate a registration with a sign-in you need the who, the from-where, and the against-what already resolved and sitting next to your reference data. That is the same "right fields at the right fidelity, next to the reference data that makes the alert actionable" that the invoice post asked for, which means behavioral detection is the *reason* you shape and strip at ingest instead of warehousing raw JSON. Deliberate collection stops being a cost-cutting story and becomes a capability you're building toward.

## MITRE is already scoring this

If the collection reading of the pyramid were only my own extrapolation, I'd flag it as such. It isn't. The MITRE Center for Threat-Informed Defense has been building the formal version since 2023 under the name Summiting the Pyramid, and its whole purpose is to score how robust a detection is (how hard it is for an adversary to evade) by scrutinizing what the analytic actually depends on. Detections that lean on swappable artifacts score low; detections anchored to behavior score high. The Sigma repository now carries a robustness flag from this work, so you can see the score on open analytics.

The part that matters for the collection argument is where they took it next. The v4.0 release adds a methodology for the *minimum telemetry required* to detect ambiguous, living-off-the-land techniques, and Telemetry Confidence scores that rate how effective a given log source is against a given technique. Read that back against the invoice post. That is a formal, published answer to "which sources do I actually need, and how much does each one buy me," computed from the behavior you're trying to catch, not from a diagnostic default someone left on. Their 2026 roadmap frames it as making collection purposeful and measuring telemetry completeness against ATT&CK. The field is converging on the same place from the research side that the budget forced me to from the operations side: your log sources should be a function of the behaviors you've decided to detect, and you can now put numbers on it.

## The synthesis

You don't collect deliberately by being frugal. You collect deliberately by detecting behaviors, because a behavior is the only detection target that derives from a threat model instead of from yesterday's incident. Frugality is the byproduct; altitude is the cause.

That closes the arc these three posts were tracing: why you should collect deliberately, what a source that earns its keep looks like in the wild, and now the mechanism underneath both. Detect high on the pyramid and the question "why is this log here" finally has an answer you can derive instead of defend. Detect low and you're back to collecting everything and hoping, paying the invoice on telemetry no behavior ever needed.

Point your detections at the skeleton. The collection strategy falls out of it for free.

---

*Sources: David Bianco, "The Pyramid of Pain" (2013). MITRE Center for Threat-Informed Defense, "Summiting the Pyramid" (project and v4.0 documentation, incl. Telemetry Confidence scoring) and the CTID 2026 roadmap. Actor and query specifics carry over from the prior post and its cited Okta / Unit 42 reporting.*

*Disclosure: written with AI assistance. The threat model, the argument, and the opinions are mine.*
