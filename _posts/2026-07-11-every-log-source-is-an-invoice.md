---
title: "Every Log Source Is an Invoice"
date: 2026-07-11 12:00:00 -0700
---

For most of my career, every post-mortem for a missed detection ended on the same sentence: we didn't have the logs. Lateral movement through a segment nobody instrumented. A service account authenticating from some box whose event log never left the building. The details changed, the conclusion didn't, and after you've sat through enough of those meetings the lesson burns in. When in doubt, collect more. Better to have it and not need it.

I want to be fair to that lesson, because it used to be true. On-prem enterprises were genuinely starved for telemetry. Coverage was accidental. What got logged depended on which sysadmin built which server in which year. Turning on one more source really did buy you visibility you didn't have, and "collect everything" was the right answer to the world we were operating in.

It's not the world we're in anymore, and the reflex it trained is now wrecking budgets and burning out analysts.

Some context for why this is on my mind. I've been reading through the detection engineering books Packt has put out over the last couple of years, and they're good. The field finally gets treated like engineering: rules in version control, tests, validation, named owners, an actual lifecycle instead of folklore. But read them with your cloud bill open in the other window and something jumps out. All that discipline lands on the rules. The telemetry underneath the rules is still treated as a given. You acquire it on reflex and you keep it on faith.

## The constraint flipped

A cloud-native environment does not have a telemetry scarcity problem. The control plane logs every operation in every subscription whether you asked for it or not. The identity provider emits four log families on its own (sign-in, audit, provisioning, risk). Kubernetes brings its own four. Every API gateway logs every call, every key vault logs every key operation, every storage account can log every object touch. Then the security stack itself: endpoint, identity, posture, app sec, each with an alert stream plus raw events. And now AI workloads are showing up with model invocation traces and tool-call logs on top of everything else. No single source is unreasonable. Add them up and you're staring at petabytes a year, growing every quarter.

Here's the arithmetic problem, and it's the same one that runs the alert queue. My team works through a few hundred thousand alerts a year, so none of this is abstract for me. Take one rule producing 500 alerts a day at 70% precision. On paper that's a strong detection. In practice it's 150 false positives a day, and if each one takes an analyst a couple of hours to run down, that single rule eats 300 analyst-hours a day before anyone has touched a true positive. The rule isn't wrong. It's unaffordable. And unaffordable rules all die the same death: tuned down until the recall is gone, or switched off outright.

Every SOC lead I know has lived that story at the alert layer. Almost nobody prices it one layer down, at ingestion, where the same economics run with bigger numbers and nobody watching. The constraint on a detection program today isn't the data you don't have. It's the consequences of the data you do have. A saturated queue. Enrichment nobody has capacity to build. A storage bill quietly competing with headcount. Enough moving parts that the whole program gets brittle.

## A liability with a recurring invoice

Try this exercise on your own environment. For each log source, ask three questions:

- Which detection does this enable?
- Which investigation does this speed up?
- Which compliance obligation does this satisfy?

A source that goes zero for three is not an asset waiting for its moment. It's a liability with a recurring invoice, and the ingestion line you can see is the smallest charge on it. Storage tiers get assigned once and never revisited. Parsers break when a vendor changes their schema and someone has to notice, then fix them. Retention runs years past any detection value on the strength of a compliance assumption nobody ever validated. And every source you add is one more table an analyst has to consider at 3am. A source that's present but poorly understood doesn't speed investigations up. It slows them down.

I'll say the uncomfortable version out loud: an organization that collects everything is not safer than one that collects deliberately. It's just poorer. Every dollar going to telemetry nobody uses is a dollar not going to the detections, the enrichment, and the analysts that actually turn data into protection.

## Derive it backward

There are two ways most logging architectures actually get built, and both run backward. The first is reactive: a threat shows up, the team realizes it doesn't have the logs, and everyone scrambles to turn on a connector. Threat, then logs, then detection, which guarantees every new capability lags the threat by weeks. The second is what platform teams tend to do: turn on every diagnostic setting, ship it all to the SIEM, sort it out later. Collect, then store, then build. That fixes the lag, at a cost that scales with the size of your environment and bears no relationship to the value of anything collected. Stay on that path long enough and you'll eventually discover that a serious chunk of your analytics spend covers telemetry no detection references and no investigation has ever pulled up.

The sequence that works runs the other direction: threat model, then detection requirements, then telemetry requirements, then logging architecture.

Worked example. Take a threat your model actually cares about, say identity compromise leading to sensitive data access. The detection requirement falls out of it: alert when a principal touches a sensitive store it has never accessed before, outside the known ETL windows, with enough confidence that an analyst can act without rebuilding the case from raw logs, and within minutes, because exfil finishes inside a single session. From there the telemetry requirement falls out too. Storage access logs on the sensitive accounts specifically, with the caller, auth type, and status fields intact. Sign-in logs for session context. A maintained list of which stores are sensitive and who's supposed to be in them. Only then do you architect the logging. Diagnostics go on for the accounts that hold sensitive data, not for the hundreds of accounts holding build artifacts and Terraform state, where the volume dilutes the signal and pads the bill. Analytics tier for the ninety days the detection actually needs, archive after that for the compliance tail. Automation keeps the sensitive-store list current, so a newly classified store enters scope without a human remembering to add it.

Run it that way and volume drops while coverage goes up, because the data that matters arrives with the right fields at the right fidelity, sitting next to the reference data that makes the alert actionable. Your logging becomes a function of your threat model instead of a byproduct of whatever the platform's diagnostic defaults happen to be.

## What it costs

I don't trust arguments that only list benefits. So, the bill.

The first objection is always "what if we need it later," and it's legitimate. That's the forensic argument. The answer isn't deletion, it's tiering. Data with plausible investigation value but no detection on it goes to cheap storage, or gets trimmed at ingestion (strip the unused fields, drop the routine events) into something that keeps its forensic value without paying hot-tier rates for years. In my experience that kind of transform cuts a source's volume roughly in half while preserving every field anyone actually queries. You pay for the transformation once. The savings recur for the life of the data. Which is why "collect less" is the wrong slogan for all of this. The slogan is collect deliberately.

The second cost is the real one. This approach turns logging from a default into a discipline somebody has to own. The threat model has to be genuinely maintained or everything derived from it rots at the same rate. Those reference lists are standing operational commitments, not one-time configs. If nobody owns the chain, it decays quietly, and it decays in exactly the places your coverage map claims you're fine.

## Where the noise starts

The reason I care about this isn't really the bill, though the bill is real. It's the queue.

We talk about alert fatigue like it starts at the analytics rule, like the fix is one more round of tuning on whatever rule is screaming this week. But by the time a badly chosen log source has become an alert in front of a human, every option left is a bad one. Tune the rule down and give back recall. Eat the noise and burn analyst trust you won't easily get back. The noise your team is drowning in was purchased months earlier, at ingestion, when a source got switched on because it was available rather than because anything required it. Signal-to-noise isn't a property you add at the rule layer. You either engineer it at the ingestion layer or you apologize for it at the queue.

Fifteen years ago the mark of a good detection program was that the data was there when you needed it. Now the mark is being able to say why the data is there at all. Every source traces to a detection or an investigation. Every detection traces to a threat somebody actually modeled. Logging stops being an inventory and starts being a consequence of the threats you've chosen to defend against.

That old post-mortem line, "we didn't have the logs," deserves an update for the world we operate in now. The failure mode didn't go away. It flipped. We had the logs. We had all of them. That was the problem.

---

*Disclosure: this post was written with the assistance of AI, after only a few thousand input prompts to make it sound like me. The opinions, the scars, and the alert queue are all mine.*
