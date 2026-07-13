---
title: "Page on Decisions, Not Alerts"
date: 2026-07-14 05:00:00 -0700
tags: [sentinel, soc, detection-engineering, llm, triage, ai]
---

Most Sentinel analytics are doing two jobs at once, and they're bad at holding both. An analytic observes a condition, and it interrupts a human. That means every rule has to be a high-recall sensor and a high-precision decision at the same time, and when precision falls short the response is always the same: tune it down, add exclusions, or quietly train people to ignore the source. The queue gets quieter. You also give up recall in exactly the place adversaries like to operate, which is low-signal, ambiguous, cross-domain behavior that no single rule was ever going to catch cleanly.

I've been working through what it looks like to split those two jobs apart. The short version: treat detections as sensors, and build a separate layer whose only job is turning signals into decisions.

## A smoke detector is not a fire department

A detection is evidence. It tells you something happened. Whether that something matters depends on the actor, the asset, data sensitivity, change context, related signals, and history, none of which live inside the rule that fired. A decision is a different object entirely. It says what happens next.

So the design shift is to stop asking every analytic to be page-worthy. Most rules become candidate signals: normalized observations that flow into a triage layer instead of straight into PagerDuty. That layer gathers context, applies written policy, and produces one of a small set of dispositions: close benign, correlate as duplicate, monitor, open a non-paging work item, escalate to Tier 2, or page on-call.

The first stage gets to be noisy because its output is internal. The second stage optimizes for precision because its output reaches a human at 2am. This is basic cascade architecture, and it's the same economics argument I made in [Every Log Source Is an Invoice](/2026/07/11/every-log-source-is-an-invoice.html) applied one layer up: you paid to collect the telemetry, so stop paying again in human attention for every observation it generates.

## Where the LLM fits, and where it doesn't

The triage layer I'm describing is LLM-guided, and I want to be careful about what that means, because "let the model decide security risk" is not it.

The model is a reasoning interface over approved tools and approved policies. It receives a candidate signal, normalizes the entities, pulls the evidence a policy requires (identity risk, device compliance, resource ownership, data classification, change records, related alerts, telemetry health), builds an investigation graph, and applies policy gates. Its authority comes from the policy, not from conversational freedom. It can close a case only when a specific policy authorizes closure and every evidence requirement is met. Anything else escalates.

The governing rule is fail open. Missing evidence, degraded telemetry, ambiguous policy, tool failure: all of these escalate rather than close. If the Purview classification lookup fails, the agent does not infer benign. It records the missing evidence and hands the case to a human with the gap named. Missing evidence is itself evidence, and treating it that way is most of what makes autonomy defensible.

## Policy as English

This is the part I find most interesting in practice. Every SOC already has triage policy. It lives in response KBs, tribal knowledge, and playbook conditions, and it's enforced with whatever consistency a tired responder can manage while finding the right Confluence page under time pressure. Two people read the same KB and do different things. That's not a people problem, it's a medium problem.

The fix is to make the KB executable without making it code. A production English-language policy has structure: scope, required evidence, escalation criteria, closure criteria, forbidden actions, an owner, and a review cadence. Something like:

> If diagnostic settings are changed on a production or sensitive-data-adjacent resource, verify the actor, the change record, the before/after logging state, and related alerts. Escalate if logging was disabled, routed away from approved destinations, or the actor and change are not approved. Close only if the change is approved, expected, and logging remains healthy. If required evidence is missing, escalate as evidence-insufficient.

That's readable by a detection engineer, an IR lead, and an auditor. It's also precise enough to replay against historical cases and version in git. The LLM interprets it consistently at 3am the same way it does at 3pm, which is more than I can say for humans, myself included.

## Every decision leaves a record

The artifact analysts review changes too. Instead of an alert plus a pile of raw logs to pivot through, the agent hands over an investigation graph: identity, device, resource, classification, change context, and related signals already connected, with a timeline. Attacks rarely arrive as one obvious signal. A risky sign-in, a privilege change, a logging modification, and a first-time access to sensitive data are each individually dismissible, and together they're the whole story. The graph is the object worth reviewing.

Every graph resolves into a decision record: disposition, severity with mission impact, confidence, evidence used, evidence missing, the policy path that produced the outcome, and the recommended next action. A decision without that record isn't acceptable for autonomous operation, because you can't audit it, replay it, or improve it. This also quietly solves the tuning problem. When the agent closes the same benign automation pattern forty times a week, that's not just relief, it's a structured tuning backlog with evidence attached.

## Autonomy is earned, not enabled

None of this starts with the model closing cases. It starts in shadow mode: the agent evaluates alerts in parallel while current paging behavior stays exactly as it is. Agreement rate with human disposition, evidence completeness, and false-closure risk become the calibration dataset. Disagreements aren't failures, they're the interesting part, and each one gets categorized: evidence gap, policy ambiguity, model reasoning error, or human inconsistency. That last category shows up more often than anyone wants to admit.

Only after those metrics clear predefined gates does an alert class graduate to assisted triage, then to autonomous disposition for narrow low-risk categories. High-impact conditions never enter that pipeline at all. Confirmed exfiltration, privileged identity compromise, logging disabled on critical stores: those keep a direct-page path where the agent enriches after the page, not before. And every material change to the model, prompts, policies, or tool schemas has to pass replay against historical incidents, near-misses, and synthetic cases before it ships. Autonomy is a maturity level per alert class, not a switch.

The biggest risk in the whole design is false confidence: believing the agent understood a case when it didn't. The mitigation isn't avoiding AI, it's refusing to accept any decision that doesn't show its evidence, name what's missing, and cite the policy it applied. The agent may reduce toil. It may not reduce accountability.

## What actually changes for humans

The on-call queue becomes an exception queue. Responders stop reconstructing context from scratch for every raw analytic and start reviewing adjudicated risk: evidence gaps, high-impact uncertainty, and cases where policy deliberately requires judgment. The Tier 1 skill set shifts from memorizing KB edge cases to challenging evidence quality and correcting policy outcomes, which is a better use of experienced people anyway.

There's a role hiding in this model that I think detection engineering grows into: someone who owns the conversion of evidence into action. Call it a decision engineer. They own policy quality, evaluation cases, routing behavior, and evidence completeness, because in this model the work product is no longer the alert. It's the decision, and the counterintuitive result is that detection count should go up, not down. You can afford broad behavioral analytics when a noisy observation costs a policy evaluation instead of a page.
