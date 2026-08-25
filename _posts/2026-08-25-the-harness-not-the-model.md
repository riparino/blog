---
title: "The Harness, Not the Model"
date: 2026-08-25 05:00:00 -0700
tags: [ai, agents, llm, autonomy, detection-engineering, security operations]
---

An "AI stack" diagram came across my LinkedIn feed last week. You've seen it, or one of its cousins, because some version of it circulates every few weeks: five tidy boxes, infrastructure at the bottom, then models, then orchestration, then agents, then applications on top, each layer resting on the one below like a wedding cake. Here it is, redrawn, so we're looking at the same picture:

```
+--------------------------+
|       applications       |
+--------------------------+
|          agents          |
+--------------------------+
|      orchestration       |
+--------------------------+
|          models          |
+--------------------------+
|      infrastructure      |
+--------------------------+
```

It's not wrong. That's what made it hard to articulate why it bothered me for days, until I landed on it: the diagram is a parts list. It shows you the AI. It doesn't show you the work.

Here's the test I'd put to any stack diagram: the operational questions should land somewhere on it. Why can't the agent deploy this fix to production? Who authorized that tool call at 2am? What re-validates every automated decision when the model version underneath changes? Point to the box where those answers live. On the five-box diagram you can't, because the answers live in layers it doesn't draw, and those turn out to be most of the layers.

So I drew the whole thing, for the environment I actually work in: a cloud-native healthcare data platform. And I drew it for the operations side, deliberately — not the AI in the product, but the AI that does the work. What I want is a model of AI workers: engineers, product and security both, handing real work to agents that hold real access and do it securely, with every layer those workers stand on drawn in — the infrastructure, where the orchestrator takes hold, the prompts, the guardrails, the controls. The model, the box the LinkedIn genre treats as the point, is one layer of thirteen, near the bottom, and nearly everything that determines whether any of this works sits above it. The irony of answering a five-box diagram with a thirteen-layer one is not lost on me; the extra layers are the argument.

## The full stack

Read it bottom-up. Everything below a layer is what that layer stands on, and the two boxes just under the humans row are the reason the rest exists.

```
+----------------------------------------------------------------------------+
| humans          intent · policy authorship · review of exceptions ·        |
|                 review of the misses · accountability, which never         |
|                 delegates                                                  |
+----------------------------------------------------------------------------+
| the work                                                                   |
|   +---------------------------------+  +---------------------------------+ |
|   | engineering harness             |  | security decision layer         | |
|   | agents that ship and maintain   |  | agents that triage, adjudicate, | |
|   | the platform: code, infra,      |  | and maintain the detection      | |
|   | migrations, the 2am page        |  | estate                          | |
|   +---------------------------------+  +---------------------------------+ |
+----------------------------------------------------------------------------+
| authorization   policy written in English, versioned in git · autonomy     |
|                 graduated per task class: shadow -> assisted ->            |
|                 autonomous · tool-call gates enforced outside the model ·  |
|                 the reversibility rule · high-impact paths never enter     |
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
| context         system prompts · instruction files · skills · retrieval ·  |
|                 memory · the MCP tool surface — executable-as-intent, and  |
|                 the least-reviewed privileged config in the org            |
+----------------------------------------------------------------------------+
| gateway         routing · quotas · content filters · caching · cost        |
|                 attribution per caller                                     |
+----------------------------------------------------------------------------+
| models          frontier models by API · embeddings · classical ML · a     |
|                 registry with versions and deprecations                    |
+----------------------------------------------------------------------------+
| data            the clinical corpus behind the de-identification           |
|                 boundary · classification · the RAG stores workers         |
|                 retrieve from · lineage                                    |
+----------------------------------------------------------------------------+
| substrate       cloud, GPU serving, private endpoints, egress control,     |
|                 tenant isolation                                           |
+----------------------------------------------------------------------------+

two rails, the stack's last two layers, run its full height:

identity    every caller at every layer is a principal, human or agent:
            scoped, short-lived, attributable. no shared god-token
            anywhere on the diagram.
telemetry   every layer emits into the same pipeline that watches the
            rest of the estate: invocation traces, tool calls, decision
            records, instruction-file diffs.
```

Hold the two diagrams next to each other. The five boxes cover the bottom three rows and the orchestration row; the fifth box, applications, is the product — the one thing a diagram of the work deliberately leaves out. Everything else here is the part you can't buy, which is a strange thing to leave out of a diagram, since it's also the part that decides whether the rows it does draw ever produce anything.

## The rows everyone already draws

I'll be brief about the bottom of the stack, because this is the territory the genre already covers.

Substrate is real engineering but it's the most commodity layer here, and the interesting property is the boundary work: private endpoints, egress control, tenancy. Data is where healthcare stops being a generic column in someone's market map: the de-identification boundary is a property of the data layer, and half the security architecture above it exists to keep that property true. Models, plural, is the row the genre draws as the star, and for the workers it's an inventory: frontier models rented by API, embedding models, and a long tail of classical ML that was "AI" before the rebrand. The register that matters isn't which models; it's that they carry versions and deprecation dates, which means everything above them inherits change it didn't ask for.

The gateway is the first layer the five-box diagram usually skips, and it's the one that makes the model layer governable at all: one place where every model call gets routed, throttled, content-filtered, cached, and, the part I care about, attributed. A model call is an invoice with a caller on it. Readers of [the log-source post](/2026/07/11/every-log-source-is-an-invoice.html) can guess how I feel about AI spend that can't name which workload incurred it.

## Where the demo ends

The context layer is where things stop being infrastructure and start being behavior. System prompts, instruction files, skills, retrieval, memory, the MCP tool surface: this is the layer that tells the agent who it is and what the org wants, and I spent [an entire post](/2026/07/15/the-payload-is-a-sentence.html) on the fact that it's executable-as-intent while being reviewed like documentation. Nothing in this post retracts that worry. The diagram makes it worse-looking, actually, because you can now see how much sits on top of that layer.

Orchestration is the layer the demos live in: the loop, the tool calls, the sandbox, the handoffs. It's also where most organizations currently stop, and the diagram shows why that's a strange place to stop. An agent with orchestration but nothing above it is a very capable process with nowhere legitimate to act: it can reason about your systems but holds no rung on any environment ladder, no policy that says what it may do without asking, no eval gate that would let anyone trust it further. It's a parked capability, and the parking is usually an accident of nobody owning the next three layers.

## The load-bearing rows

The environments row is the one I'd defend hardest, because it encodes the actual difference between a demo and a colleague, and it isn't intelligence. It's access with a shape. An engineer's agent that can run the test suite but never touch staging can't validate its own work; an agent that can reach production without having earned it is an incident with a start date. So the ladder: dev, test, staging, prod, each rung a separate credential scope, each held per task class, each revocable. The rung the agent holds is the trust it has earned, and "earned" is doing real work in that sentence, because the next two rows are what earning means.

Evaluation is the proof machinery: replay against historical cases, regression gates on every change to a prompt, a policy, a tool schema, or the model version underneath, adversarial testing for the surfaces where the adversary writes the input. I made this argument for triage in [Page on Decisions, Not Alerts](/2026/07/14/page-on-decisions-not-alerts.html) and it generalizes cleanly: any material change replays before it ships, and an agent's track record is a dataset, not a vibe.

Authorization is where the eval results become permission. Policy written in English, versioned in git, precise enough to replay: what the agent may do autonomously, what it does with a human assisting, what it must never do without a page. Autonomy graduates per task class, shadow to assisted to autonomous, and high-impact paths never enter the pipeline at all. The decision rule that runs the whole layer is the one from [the tree post](/2026/07/27/the-tree-not-the-list.html): can this be undone in five minutes? Reversible actions are where autonomy starts, and irreversibility is the signal to escalate, for an agent exactly as for a human, except the agent applies the rule the same way at 3am as at 3pm. And none of this is the model grading its own homework. The ladder bounds what an agent can reach; tool-call gates, checked outside the model against the agent's graduation level, bound what it may do within reach, with the irreversible classes intercepted for approval. The authority comes from the policy and the gates, not from the model's reading of either.

## Two tenants, one stack

The top of the diagram is the claim I actually want to make. In conversations I've been calling it the next gen of work, which I realize is exactly the kind of phrase the five-box diagram ships wrapped in, so here is the mechanical version: the work moves up the stack, and the humans move with it.

The engineering harness is the box I want engineers to live in. The work becomes intent plus review instead of typing: the agent writes the change, opens the pull request, runs it through CI, and holds exactly the environment rung its task class has earned. The part that matters more to me than shipping is maintaining, because shipping was already fun; maintenance is where careers go quiet.

Walk the 2am page through it, the version I want and don't yet have. A canary starts failing an hour after a dependency bump lands. The agent holding the page reads the runbook the way [the tree post](/2026/07/27/the-tree-not-the-list.html) describes an investigation, as hypotheses to rule in or out: recent deploys against this workload first, and there's the bump, sitting at the top of the deploy history. Rolling back the platform's own deploy is undoable in five minutes, so the reversibility rule authorizes it without waking anyone; the rollback goes out from the staging-and-rollback rung the agent actually holds, the canary re-runs clean, and by morning there's a pull request pinning the dependency with the whole decision record attached: what fired, what was checked, what policy authorized the rollback, what evidence closed it. Now re-run the same page, except the failing service is mid-way through a data migration. The next action isn't reversible, and the agent doesn't get to be clever about that, because irreversibility is a gate, not a judgment call. So it pages a human, and what the human wakes to is not an alert but the tree already walked: evidence gathered, reversible steps taken, the irreversible branch named as the reason a person is now awake. Every mechanism in that story is three rows down in the diagram; nothing about it requires a smarter model than the ones we already rent.

And the security decision layer is the same box wearing our clothes. When we redesigned triage to remove Tier 1, the write-up I produced wasn't, on reflection, a SOC document. It was this diagram with different nouns: candidate signals instead of backlog tickets, dispositions instead of merged PRs, [policy-gated closure](/2026/07/14/page-on-decisions-not-alerts.html) instead of deploy rights, decision records instead of commit history, shadow mode instead of a feature branch. Detection content is code, so the engineering harness applies to it directly, and the detections the agents maintain are the ones watching the telemetry rail of this very stack, which closes a loop: the stack defends itself with the same architecture it works with.

Which is why I keep insisting these aren't two stacks. An org that builds an agent setup for engineering and an "AI SOC" as a second, separate thing is running the same shared layers twice to differ in the work row alone, and the seam between the copies is a place where an attacker, an outage, or an invoice hides. Call it an organizational bifurcation problem if you want the whitepaper version of the sentence; I'd put it more plainly: you don't have two AI strategies, you have one harness with two tenants, and the sooner the org chart admits it the fewer layers get built twice.

The humans box stays on top, and not as decoration. Somebody authors the policy, reviews the exceptions, and runs [the review of the misses](/2026/07/27/the-tree-not-the-list.html), because the graduation gates are only as honest as the people auditing them, myself included. Accountability never delegates: the agent may hold the pager, but a person owns what it did with it.

## The bill

A diagram that only advertises benefits is a sales deck, so here's what this one costs.

The harness concentrates exactly the surface I spent July worrying about. Instruction files, skills, memory, tool registries: the context row is executable, and the moment agents hold environment rungs, it's executable with credentials. The payload-is-a-sentence problem doesn't get better in this architecture; it gets a bigger blast radius, and the telemetry that would catch it (instruction-file lifecycle events, provenance on context writes, drift between agent output and written policy) is telemetry almost nobody collects yet. If any of that agent output feeds a training corpus, the [poisoning arithmetic](/2026/07/15/the-payload-is-a-sentence.html) applies to it too. Build the top of this stack before instrumenting the middle and you've built the incident first.

The identity rail is a population explosion. Every agent per task class per environment rung is a principal with a lifecycle, which means hundreds of scoped non-human identities that need issuance, rotation, attestation, and retirement. At this volume that's an operations program of its own, run against identity practices that mostly still assume a principal is a person with a badge photo.

Evaluation is a standing commitment that rots quietly. The replay corpora, the regression gates, the agreement-rate baselines: all of it decays the way reference lists decay, and an autonomy gradient calibrated against last quarter's model version is a lie with a dashboard. Healthcare adds its own drag: some task classes will never graduate, because the reversibility rule fails permanently anywhere patient data could move, and the decision records here do double duty as engineering hygiene and as the thing you hand a regulator.

And someone has to own the harness. Not engineering, not the SOC, the shared rows underneath both tenants, and today that owner doesn't cleanly exist on most org charts, including in places that have already built half of this. Unowned shared infrastructure doesn't stay unowned; it gets owned by whoever's outage it causes.

## The synthesis

The five-box diagram is a diagram of the part you can buy, and the part you can buy is the part someone else operates: the models improve on a vendor's roadmap, get re-priced on a vendor's schedule, and get deprecated on a vendor's timeline, and none of that asks your permission. Everything above the model row is the part you operate, and it's where the actual outcomes live, because those are the layers that either pay down toil and incidents or quietly generate them. That's the harness. It's the part that decides whether the work at the top of the diagram becomes real or stays a demo, and it's built out of the least glamorous rows on the page: credential ladders, replay corpora, policies somebody maintains, telemetry somebody prices. Draw the whole stack, because every layer you leave off the diagram is a layer you'll meet later in a post-mortem, and it will not be wearing a tidy box.

---

*Disclosure: written with AI assistance, by an agent working inside a small version of exactly the harness this post describes: push rights to a branch, no rights to main, a human on the diff. The diagram, the opinions, and the review are mine.*
