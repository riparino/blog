---
title: "The Tree, Not the List"
date: 2026-07-28 05:00:00 -0700
tags: [security operations, incident response, cybersecurity]
---

A cloud storage bucket goes public in a dev environment; someone notices, hesitates, checks with someone else, and eventually locks it down. A day later the same class of bucket goes public in production, and you'd expect the response to be faster, since the stakes are higher and the math isn't close, but instead it's the same hesitation, sometimes worse, because now being wrong happens somewhere people can see it.

Severity and willingness to act should move together, but in practice they don't, and once you notice that, it shows up everywhere: a weird process sits on an endpoint, nothing about it screams malware, and it goes half-investigated for a day because nobody wants to be the one who paged on-call over nothing; a firewall rule breaks silently and log volume climbs for a week before anyone connects the two; someone finds a DNS record pointing at infrastructure that no longer exists, a takeover waiting to happen, and it sits in a backlog because there's no clean next step, just a vague sense that someone should do something.

I've watched some version of this freeze at every place I've worked, small teams and large ones alike, and it isn't a story about one org or one team having a gap so much as it's a default. What's changed for me is where I'm standing now. Working this deep in cloud environments, where almost everything is an API call away and the connective tissue between resources is actually queryable, has made the shape of a fix visible in a way it never was when the evidence was scattered across systems that didn't talk to each other. The pieces below — reversibility as a decision rule, the investigation as a tree, reviewing the misses — feel, for the first time, like things that could be stitched together into something more cohesive and automatic than any one person's judgment, instead of staying tribal knowledge that lives and dies with whoever happens to hold it.

## Nothing, or the war room

My first instinct was to blame documentation — better runbooks, clearer playbooks, a wiki page for every scenario — but I have most of that already, and it isn't the bottleneck. The actual problem is that most of these situations don't offer a middle option: you either do nothing, or you declare an incident and put your judgment on record in front of the org, with nothing sized in between, so ambiguous signal gets rounded down to nothing, not because people don't know it might matter, but because the only escalation path available is loud, and being loud and wrong is what people are actually afraid of.

Compare that to the one case that reliably works: a posture tool flags a resource exposed to the internet, someone kills the exposing rule immediately, and only afterward do they figure out why, because that response is fast when the first move is cheap and fully reversible, and nobody's getting called out for closing an exposure that turns out to be nothing. The action is small enough that it doesn't need permission in the moment, because permission was implicitly granted the day someone decided exposed resources get shut off on sight.

That's a rule of thumb worth having on purpose instead of leaving implicit: can this be undone in five minutes? If so, act now and explain later; if not, that's the actual signal to escalate, not the ambiguity itself. It turns "is this serious enough to make noise about," a question people are bad at under pressure, into "can I take this back if I'm wrong," a question almost anyone can answer fast.

## More tools didn't build the judgment

Reversibility solves the freeze on the easy cases, but it doesn't solve the harder problem underneath all of this, which is that a lot of people genuinely don't know what to look at once they've decided to look.

I used to build my own dashboards by hand, because that was the only way to see anything, and the forcing function was built into the work: before you could look at something, you had to decide it was worth looking at. Now there's a posture tool, a SIEM, a dashboard for every team, all surfacing things constantly, and surfacing everything turns out to be functionally close to surfacing nothing, because nobody can hold thirty open questions in their head as things worth idle curiosity, so the default becomes only looking when something pages you, which is the opposite of proactive, even though the tooling is better than it's ever been.

None of that volume teaches anyone what to do with an alert once it fires; that's a different skill, and it doesn't come from having access — it comes from having gone deep enough, often enough, to know where the evidence actually lives for a given kind of question.

## What "going deep" actually looks like

Say a detection fires on a shell landing inside a container in a managed Kubernetes cluster; I already know, going in, that the platform has no container-level logging, so I only get the cloud provider's built-in threat detection and its activity logs, which means the investigation doesn't start with "what happened" — it starts with a set of hypotheses I can rule in or out against whatever evidence actually exists for each one.

```
shell_on_container:
  check: recent CI/CD pipeline runs against this workload
    -> if match: probably a deploy, not an attacker. confirm and close.
  check: does the access pattern look interactive
    -> if yes: pull identity sign-in logs, look for the session
       -> got an IP: cross-reference it against sign-in logs org-wide
  check: platform-native device telemetry for the underlying VM nodes
    -> the "pod" is really autoscaled VMs under the hood; check them directly
  check: posture tool's connectivity graph for the node
    -> what is this thing connected to, and how — not just what it's tagged as
```

Nobody handed me that tree; it's built from having hit this exact wall — no container logging, here's what actually exists instead — enough times that the next question is automatic. Someone without it doesn't lack access: the detection fired, the posture tool's connectivity graph is sitting right there, all of it available, and what's missing is knowing which tool answers which sub-question and what the answer tells you to check next, so with seven tools open, one alert on the screen, and no sense of where to start, it either gets escalated immediately or gets picked at without going deep enough to know it was nothing.

That's the actual gap tool sprawl doesn't close: more surfaces just means more leaves, and nobody's handing out the branches to go with them.

Readers who followed [the detection altitude post](https://blog.opsecured.net/2026/07/16/detection-altitude-is-a-collection-strategy.html) already know the shape of the first branch in that tree: knowing what you *don't* have — no container-level logging, in this case — is itself a piece of the map, and it's the kind of thing that never makes it into a runbook because it's infrastructure trivia, not procedure.

## Reviewing the misses, not just the fires

There's a second gap hiding behind the first one: post-incident reviews only happen after something got declared, so the DNS record that sat in a backlog for two weeks, the process that got glanced at and dismissed — nobody ever revisits those to check whether the call was right, which means the org never actually learns its own threshold; only the individual who made the call does, silently, and it leaves with them if they ever do.

If the tree above is what expertise looks like in the moment, reviewing the misses is how you'd actually transfer it — not "here's the runbook for a confirmed incident," but "here's the thing three people looked at and closed as nothing, walk through why that was the right call and what would have flipped it." That's a different kind of practice than a tabletop on a confirmed breach, and almost nobody runs it, because it requires admitting you have a backlog of things you decided, without much ceremony, weren't worth escalating.

Concretely, that means two things happening on a real cadence, not sitting as an aspiration in a wiki page nobody opens. First, a standing, low-ceremony review — pull a handful of things that got closed as nothing over the past couple weeks, and have whoever made the call walk the group through the actual reasoning, in order: what they checked first, what each answer ruled in or out, and what single piece of evidence would have flipped it to an escalation. It doesn't need the weight of a postmortem, because nothing happened; it needs the habit of narrating a tree that normally stays silent inside one person's head. Second, and this is where the mentorship piece stops being a nice idea and becomes a mechanism: that review is the actual teaching moment, not the live incident. A live incident is close to the worst environment to learn in — the stakes are real, a junior person is watching someone perform under pressure, and there's no room to stop and ask "why not" at every branch without slowing down something that matters. A closed-out miss has none of that. Sit a T2 down next to the senior responder who made the call, on a ticket that's already resolved and boring, and have them re-walk the tree together, out loud, with room to interrupt. Do that regularly, on both directions — reviewing misses as a team, and pairing on them specifically for anyone still building the tree — and the expertise stops living in exactly one head, because more than one person has now walked the branches themselves instead of just hearing about them after the fact.

None of that works without leadership treating it as legitimate, on purpose. The instinct that makes people freeze on an ambiguous signal in the first place — fear of being wrong somewhere visible — doesn't disappear just because the venue changed from a war room to a review meeting. If a miss review turns into a place where someone's judgment call quietly gets held against them later, in a performance conversation or a promotion that doesn't happen, people stop bringing their real misses and start bringing only the safe, obvious ones, and the whole exercise collapses back into exactly the theater it was supposed to replace. That's a leadership problem, not a process problem: someone with actual authority has to show up to these, say out loud that they'd have made the same call, and mean it, because the review only works if being wrong in the room is cheaper than staying quiet about it. The same person has to protect the time itself, too — a recurring thirty minutes is nothing until the week gets busy, and it's busy every week, so it survives only if someone senior enough treats it as non-negotiable instead of the first thing that gets cut when the calendar fills up.

## The bill

Reversibility as a rule of thumb breaks down the moment something is only mostly reversible — a rule you can flip back, but not before something read from the exposed thing while it was open; teaching the tree instead of the runbook is slower and harder to standardize, because it's closer to mentorship than documentation, and it doesn't scale the way a wiki page does; and reviewing the things that didn't become incidents means creating a record of every judgment call that turned out fine, which is exactly the kind of paper trail people get nervous about keeping, for reasons that have nothing to do with security.

## The synthesis

The tooling problem and the confidence problem turn out to be the same problem wearing two costumes: more dashboards without more judgment just means more things nobody's sure whether to look at, and neither one gets fixed by buying something. What actually closes the gap is a habit, not a tool — reviewing what got closed as nothing on a real cadence, and treating that review as the mentorship mechanism itself, instead of hoping the tree transfers by osmosis the one time a year a junior person happens to be on the call during a real incident. It costs nothing to start and doesn't need a budget or a vendor, but it does need someone with actual authority willing to protect it once it exists, because the only thing that kills a review like this faster than a full calendar is one bad experience where someone's honest miss got held against them later. Start it with a recurring thirty minutes and someone willing to narrate their own reasoning out loud, including the parts that feel too obvious to say; keep it alive by making sure whoever runs it has enough standing that the room actually believes them when they say nothing said here leaves the room. I've believed some version of the diagnosis for a long time; what's new is that cloud has made the shape of a fuller fix visible enough to look buildable, but the review-and-pair habit is the part that never had to wait for that.

---

*Disclosure: written with AI assistance for formatting and research. This one took quite a few hours.*