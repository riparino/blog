---
title: "The Harness, Not the Model"
date: 2026-08-25 05:00:00 -0700
tags: [ai, agents, llm, autonomy, detection-engineering, security operations]
---

An "AI stack" diagram came across my LinkedIn feed last week. You've seen it, or one of its cousins, because some version of it circulates every few weeks: five tidy boxes, infrastructure at the bottom, then models, then orchestration, then agents, then applications on top, each layer resting on the one below like a wedding cake. It's not wrong. That's what made it hard to articulate why it bothered me for days, until I landed on it: the diagram is a parts list. It shows you the AI. It doesn't show you the work.

Here's the test I'd put to any stack diagram: the operational questions should land somewhere on it. Why can't the agent deploy this fix to production? Who authorized that tool call at 2am? What re-validates every automated decision when the model version underneath changes? Point to the box where those answers live. On the five-box diagram you can't, because the answers live in layers it doesn't draw, and those turn out to be most of the layers.

So I drew the whole thing, for the environment I actually work in: a cloud-native healthcare data platform where AI is simultaneously in the product, doing the engineering, and running a growing share of the security operation. Every layer, including the ones that only show up after something goes wrong. The model, the box the LinkedIn genre treats as the point, is one row of thirteen, near the bottom, and nearly everything that determines whether any of this works sits above it.

## The full stack

Read it bottom-up. Everything below a layer is what that layer stands on, and the three boxes at the top are the reason the rest exists.

```
+----------------------------------------------------------------------------+
| humans          intent · policy authorship · review of exceptions ·        |
|                 review of the misses · accountability, which never         |
|                 delegates                                                  |
+----------------------------------------------------------------------------+
| the work                                                                   |
|   +----------------------+ +----------------------+ +--------------------+ |
|   | product AI           | | engineering harness  | | security decision  | |
|   | the features the     | | agents that ship and | | layer              | |
|   | customer sees; the   | | maintain the         | | agents that triage,| |
|   | domain LM inside     | | platform: code,      | | adjudicate, and    | |
|   | the data pipeline    | | infra, migrations,   | | maintain the       | |
|   |                      | | the 2am page         | | detection estate   | |
|   +----------------------+ +----------------------+ +--------------------+ |
+----------------------------------------------------------------------------+
| authorization   policy written in English, versioned in git · autonomy     |
|                 graduated per task class: shadow -> assisted ->            |
|                 autonomous · the reversibility rule · high-impact paths    |
|                 never enter the pipeline                                   |
+----------------------------------------------------------------------------+
| evaluation      replay against historical cases · regression gates on      |
|                 every prompt, policy, tool, and model change ·             |
|                 agreement-rate calibration · adversarial testing           |
+----------------------------------------------------------------------------+
| environments    dev -> test -> staging -> prod as a credential ladder;     |
|                 the rung an agent holds is the trust it has earned for     |
|                 that task class, and it is revocable                       |
+----------------------------------------------------------------------------+
| orchestration   agent loops · tool calling · sandboxed execution ·         |
|                 multi-agent handoff · workflow state                       |
+----------------------------------------------------------------------------+
| context         system prompts · instruction files · skills · retrieval    |
|                 · memory · the MCP tool surface — executable-as-intent,    |
|                 and the least-reviewed privileged config in the org        |
+----------------------------------------------------------------------------+
| gateway         routing · quotas · content filters · caching · cost        |
|                 attribution per caller                                     |
+----------------------------------------------------------------------------+
| models          domain LM · frontier models by API · embeddings ·          |
|                 classical ML · a registry with versions and deprecations   |
+----------------------------------------------------------------------------+
| data            the clinical corpus behind the de-identification           |
|                 boundary · classification · RAG stores · lineage · the     |
|                 training pipeline's inputs                                 |
+----------------------------------------------------------------------------+
| substrate       cloud, GPU serving, private endpoints, egress control,     |
|                 tenant isolation                                           |
+----------------------------------------------------------------------------+

two rails run the full height of the stack, touching every layer:

identity    every caller at every layer is a principal, human or agent:
            scoped, short-lived, attributable. no shared god-token
            anywhere on the diagram.
telemetry   every layer emits into the same pipeline that watches the
            rest of the estate: invocation traces, tool calls, decision
            records, instruction-file diffs.
```

The five-box LinkedIn diagram covers the bottom four rows and a corner of the product box. Everything else is the part you can't buy, which is a strange thing to leave out of a diagram, since it's also the part that decides whether the bottom four rows ever produce anything.

## The rows everyone already draws

I'll be brief about the bottom of the stack, because the LinkedIn genre isn't wrong about it, just incomplete.

Substrate is real engineering but it's the most commodity layer here, and the interesting property is the boundary work: private endpoints, egress control, tenancy. Data is where healthcare stops being a generic column in someone's market map: the de-identification boundary is a property of the data layer, and half the security architecture above it exists to keep that property true. Models, plural, is the row the genre draws as the star, and in practice it's an inventory: a domain language model that normalizes clinical records, frontier models rented by API, embedding models, and a long tail of classical ML that was "AI" before the rebrand. The register that matters isn't which models; it's that they carry versions and deprecation dates, which means everything above them inherits change it didn't ask for.

The gateway is the first layer the five-box diagram usually skips, and it's the one that makes the model layer governable at all: one place where every model call gets routed, throttled, content-filtered, cached, and, the part I care about, attributed. A model call is an invoice with a caller on it. Readers of [the log-source post](/2026/07/11/every-log-source-is-an-invoice.html) can guess how I feel about AI spend that can't name which workload incurred it.

## Where the demo ends

The context layer is where things stop being infrastructure and start being behavior. System prompts, instruction files, skills, retrieval, memory, the MCP tool surface: this is the layer that tells the agent who it is and what the org wants, and I spent [an entire post](/2026/07/15/the-payload-is-a-sentence.html) on the fact that it's executable-as-intent while being reviewed like documentation. Nothing in this post retracts that worry. The diagram makes it worse-looking, actually, because you can now see how much sits on top of that layer.

Orchestration is the layer the demos live in: the loop, the tool calls, the sandbox, the handoffs. It's also where most organizations currently stop, and the diagram shows why that's a strange place to stop. An agent with orchestration but nothing above it is a very capable process with nowhere legitimate to act: it can reason about your systems but holds no rung on any environment ladder, no policy that says what it may do without asking, no eval gate that would let anyone trust it further. That's not a safety posture. It's a parked capability, and the parking is usually an accident of nobody owning the next three layers.

## The load-bearing rows

The environments row is the one I'd defend hardest, because it encodes the actual difference between a demo and a colleague, and it isn't intelligence. It's access with a shape. An engineer's agent that can run the test suite but never touch staging can't validate its own work; an agent that can reach production without having earned it is an incident with a start date. So the ladder: dev, test, staging, prod, each rung a separate credential scope, each held per task class, each revocable. The rung the agent holds is the trust it has earned, and "earned" is doing real work in that sentence, because the next two rows are what earning means.

Evaluation is the proof machinery: replay against historical cases, regression gates on every change to a prompt, a policy, a tool schema, or the model version underneath, adversarial testing for the surfaces where the adversary writes the input. I made this argument for triage in [Page on Decisions, Not Alerts](/2026/07/14/page-on-decisions-not-alerts.html) and it generalizes cleanly: any material change replays before it ships, and an agent's track record is a dataset, not a vibe.

Authorization is where the eval results become permission. Policy written in English, versioned in git, precise enough to replay: what the agent may do autonomously, what it does with a human assisting, what it must never do without a page. Autonomy graduates per task class, shadow to assisted to autonomous, and high-impact paths never enter the pipeline at all. The decision rule that runs the whole layer is the one from [the tree post](/2026/07/27/the-tree-not-the-list.html): can this be undone in five minutes? Reversible actions are where autonomy starts, and irreversibility is the signal to escalate, for an agent exactly as for a human, except the agent applies the rule the same way at 3am as at 3pm.

None of these three rows contains a model. That's the part the five-box diagram structurally cannot say: the capability of the whole stack is set by rows that have no AI in them.

## The next gen of work

The top of the diagram is the claim I actually want to make, and it's the part I've started calling the next gen of work. Three boxes, one stack.

The product box is the only one the LinkedIn genre draws: the AI the customer sees, plus the domain model working inside the data pipeline. It rides every layer below: its calls go through the same gateway, its retrieval hits the same governed stores, its releases pass the same eval gates, its traces land in the same telemetry.

The engineering harness is the box I want engineers to live in. The work stops being typing and becomes intent plus review: the agent writes the change, opens the pull request, runs it through CI, and holds exactly the environment rung its task class has earned. The part that matters more to me than shipping is maintaining, because shipping was already fun; maintenance is where careers go quiet. Dependency updates, migrations, the failing canary, the 2am page: an agent that holds the runbook as a tree of checks, takes the reversible actions itself, and pages a human at the first irreversible branch is not a fantasy architecture. It's the same graduated-autonomy machinery already drawn three rows down, pointed at operational toil.

And the security decision layer is the same box wearing our clothes. When we redesigned triage to remove tier 1, the write-up I produced wasn't, on reflection, a SOC document. It was this diagram with different nouns: candidate signals instead of backlog tickets, dispositions instead of merged PRs, [policy-gated closure](/2026/07/14/page-on-decisions-not-alerts.html) instead of deploy rights, decision records instead of commit history, shadow mode instead of a feature branch. Detection content is code, so the engineering harness applies to it directly, and the detections the agents maintain are the ones watching the telemetry rail of this very stack, which closes a loop I find genuinely satisfying: the stack defends itself with the same architecture it works with.

Which is why I keep insisting these aren't three stacks. An org that builds an "AI platform" for product, a separate agent setup for engineering, and an "AI SOC" as a third thing is running ten shared rows three times to differ in the top one, and every seam between the copies is a place where an attacker, an outage, or an invoice hides. The whitepaper crowd calls this an organizational bifurcation problem. I'd put it more plainly: you don't have three AI strategies, you have one harness with three tenants, and the sooner the org chart admits it the fewer layers get built twice.

The humans box stays on top, and not as decoration. Somebody authors the policy, reviews the exceptions, and runs [the review of the misses](/2026/07/27/the-tree-not-the-list.html), because the graduation gates are only as honest as the people auditing them. Accountability never delegates: the agent may hold the pager, but a person owns what it did with it.

## The bill

A diagram that only advertises benefits is a sales deck, so here's what this one costs.

The harness concentrates exactly the surface I spent July worrying about. Instruction files, skills, memory, tool registries: the context row is executable, and the moment agents hold environment rungs, it's executable with credentials. The payload-is-a-sentence problem doesn't get better in this architecture; it gets a bigger blast radius, and the telemetry that would catch it, instruction-file lifecycle events, provenance on context writes, drift between agent output and written policy, is telemetry almost nobody collects yet. If you build the top of this stack before instrumenting the middle, you've built the incident first.

The identity rail is a population explosion. Every agent per task class per environment rung is a principal with a lifecycle, which means hundreds of scoped non-human identities that need issuance, rotation, attestation, and retirement, managed by identity practices that mostly still assume a principal is a person with a badge photo. Nothing about short-lived, attributable, least-privilege agent credentials is exotic, but at this volume it's an operations program, not a checkbox.

Evaluation is a standing commitment that rots quietly. The replay corpora, the regression gates, the agreement-rate baselines: all of it decays the way reference lists decay, and an autonomy gradient calibrated against last quarter's model version is a lie with a dashboard. Healthcare adds its own drag, honestly: some task classes will never graduate, because the reversibility rule fails permanently anywhere patient data could move, and the decision records aren't just engineering hygiene here, they're what you show a regulator.

And someone has to own the harness. Not the product, not the SOC, the shared ten rows, and today that owner doesn't cleanly exist on most org charts, including in places that have already built half of this. Unowned shared infrastructure doesn't stay unowned; it gets owned by whoever's outage it causes.

## The synthesis

The five-box diagram isn't wrong, it's a diagram of the part you can buy, and the part you can buy is rapidly becoming the commodity part. The models will keep improving on someone else's roadmap, on someone else's schedule, and every competitor rents the same ones. What compounds in your favor is everything above the model row: the environment ladders, the eval gates, the policies precise enough to replay, the decision records, the telemetry that lets you trust an agent with the next rung. That's the harness, it improves on your roadmap, and it's where the next gen of work either becomes real or stays a demo. Draw the whole stack, because every layer you leave off the diagram is a layer you'll meet later in a post-mortem, and it will not be wearing a tidy box.

---

*Disclosure: written with AI assistance, by an agent working inside a small version of exactly the harness this post describes: push rights to a branch, no rights to main, a human on the diff. The diagram, the opinions, and the review are mine.*
