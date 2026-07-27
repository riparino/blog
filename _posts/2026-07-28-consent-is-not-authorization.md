---
title: "Consent Is Not Authorization"
date: 2026-07-28 05:00:00 -0700
tags: [mcp, agents, ai, llm, authorization, detection-engineering]
---

I spent an evening this week with the MCP release-candidate changelog in one tab and the final 2026-07-28 spec's authorization proposals in the other, and my first reaction was relief. Sessions are gone. The initialization handshake is gone. There's an extensions framework now, and real hardening on authorization across six separate proposals: issuer validation, credential binding, audience-restricted tokens, step-up consent. Read that list and the natural conclusion is that the protocol just got a serious security pass. It did.

Then I reread it and asked the question that actually matters once an agent is running in production: which of those six changes fires on tool call number five hundred?

None of them. Every one of them is about the handshake. They govern how an agent proves who it is and which server a token is good for, and they do that better than the protocol did six months ago. What none of them do — what nothing in the stack does, at any layer I can find — is stand between a model's decision to call a tool and that tool actually running, look at the specific arguments in front of it, and be capable of saying no.

That is the gap. I have started calling it the execution authorization layer, because naming it as a layer makes it obvious that we have not built it, and the alternative framing — "we need better guardrails" — lets everyone keep pretending it is a tuning problem.

## Three layers, two of them shipped

Agent access control decomposes cleanly into three questions, and the industry has answered them in order of how easy they were.

The first is authentication: who is this agent? OAuth 2.1, DCR, PKCE, workload identity. Solved, or at least solved the way the rest of the industry has solved it, which is good enough.

The second is resource authorization: which servers, endpoints, and scopes may this agent reach at all? Also largely solved, and the new spec tightens it — a token minted for one server can no longer be replayed against another.

The third is execution authorization: given that this agent is authenticated and that this tool is in scope, *should this particular invocation, with these particular arguments, in this particular context, run right now?* Nothing in the stack answers that. In production, the answer comes from one of two places, and neither is a control.

The first place is the system prompt. Somewhere in the context window is a paragraph instructing the model not to exfiltrate data, not to touch production, not to spend money without asking. I spent [a whole post](https://blog.opsecured.net/2026/07/15/the-payload-is-a-sentence.html) on why that fails, so I will keep it short: if the payload is a sentence, a control made of sentences is being adjudicated on the attacker's home field, by a judge with no way to tell your sentences from theirs. It is also the least durable place in the entire system to put a control, because context gets compacted, summarized, and rewritten as the run goes long, and the safety paragraph is exactly the kind of text a summarizer decides is boilerplate.

The second place is an allowlist, and the allowlist is worse than nothing, which is the part people find hard to accept.

## The allowlist is an indicator

I recommended allowlists for years, back when the alternative on the table was letting an agent run anything at all. Against that baseline they looked like real progress. CVE-2026-22708 against Cursor is what changed my mind, and it's the cleanest illustration I have seen. The attack poisons the agent's execution environment so that allowlisted commands deliver attacker-controlled payloads, and the reporting on it makes the uncomfortable point plainly: the allowlist made the attack easier, because it had already auto-approved the exact commands the attacker needed. `git branch` is on every sane allowlist. `git branch` is also what carried the payload.

An allowlist names the verb. Almost all of the danger lives in the arguments, the environment, and the provenance of whatever caused the call. `curl` to your own artifact registry and `curl` to an attacker's collector are the same entry in the list. `psql` running a `SELECT` and `psql` running a `DROP` are the same entry. Anyone who has spent time at [detection altitude](https://blog.opsecured.net/2026/07/16/detection-altitude-is-a-collection-strategy.html) already knows the shape of this problem, because it is the same one: the tool name is an indicator, brittle and easy to satisfy, while the thing you actually care about — what this call does, to what, on whose behalf — is a behavior, and nobody is evaluating it.

Step-up consent has the same structural flaw from the other direction. Consent at login decides call one. It is a human decision, made once, with the operator paying attention, about a category of access — and it is then spent on every subsequent call in the session, including the four hundred and ninety-nine that happen after the human has closed the tab. Calling that authorization is a category error. It is authentication with a checkbox.

The obvious patch is a per-call approval dialog, and it fails for reasons this blog has already worked through at length. An approval modal on every invocation is an alert, not a decision, and operators fatigue on it exactly the way analysts fatigue on a noisy rule — [by clicking through](https://blog.opsecured.net/2026/07/14/page-on-decisions-not-alerts.html). Ship enough of them and you have not built a control, you have built consent theater with an excellent audit trail, which is arguably a worse outcome because now the click is evidence that a human approved it.

## What the layer actually has to be

Three properties, none of them optional.

It has to be deterministic and live outside the model, in the invocation path, evaluated on every call — not sampled, not advisory, not a scoring function the orchestrator may override when confidence is high. It has to be able to produce a deny that the agent cannot argue with. And it has to be bounded by consequence rather than by tool name, because tool names do not carry semantics and consequences do.

Sketch, not a product:

```
decision = evaluate({
  principal:      agent_id + delegated_user,
  tool:           "http.post",
  args:           { url, body_bytes, contains_secret_material },
  provenance:     "retrieved_document",   # not "user_turn"
  reversibility:  "irreversible_external",
  budget:         { spent_today, ceiling },
})
# => DENY: irreversible_external + provenance != user_turn
```

The interesting field is `provenance`, and it is the one nobody logs. A call whose proximate cause is a sentence the operator typed is a fundamentally different object from a call whose proximate cause is a sentence that arrived inside a retrieved document, a ticket body, a tool result, or an issue title — and the runtime knows which is which, because it did the retrieval. That distinction is available at the invocation point and thrown away everywhere I have looked.

The second interesting field is reversibility, and it is where the [directions-not-numbers](https://blog.opsecured.net/2026/07/20/directions-not-numbers.html) argument does real work. You cannot enumerate every dangerous call; the space is infinite and the arguments are adversarial. You can bound classes of consequence relative to a baseline: reads inside the blast radius run freely, writes inside it run with a budget, and anything irreversible or externally-visible requires a live human decision or does not happen. When you must be wrong, be wrong in the direction whose cost you can afford — which means failing closed on the irreversible and open on the recoverable, an inversion of today's default, which fails open on all of it.

## Until it exists, log the invocation

The layer is not going to appear in your stack this quarter, so the near-term work is detection, and it starts with an instrumentation decision that is easy to get wrong: log tool invocations at the infrastructure layer, not the application layer. An agent that has been steered can influence anything its own application code writes, which makes application-layer tool logs approximately as trustworthy as a compromised host's local event log.

Assume a table you have to build yourself, because no vendor ships this schema:

```kql
// sketch — AgentToolInvocation is a schema you would have to populate
AgentToolInvocation
| where Provenance != "user_turn"
| where Reversibility in ("irreversible", "external_egress")
| summarize Calls=count(), Tools=make_set(ToolName, 10)
    by AgentId, SessionId, bin(TimeGenerated, 5m)
| where Calls > 1
```

That is not a finished rule and the thresholds are wrong for your environment, but the join it implies is the point: untrusted provenance, followed by consequential action, inside one session. Every registered tool is a standing grant, and like [every log source](https://blog.opsecured.net/2026/07/11/every-log-source-is-an-invoice.html), it arrives with a bill — except this one is denominated in blast radius rather than dollars, and you pay it whether or not the agent ever gets tricked.

## The bill

Latency is real, and a policy engine on the hot path of every tool call will be felt. Policy sprawl is worse: you are building a second, deterministic model of your own business rules, and it will drift from the first one, and nobody will notice until it denies something important during an incident. You cannot policy your way out of a badly scoped tool — a tool that accepts an arbitrary shell string has no bounded semantics to evaluate, and the honest fix is to delete the tool rather than wrap it. And a deny-capable layer means agents will break in production and someone owns that pager.

Provenance on the numbers, since I insist on it elsewhere: the CVEs above come from public disclosure reporting, the specification details from the MCP release-candidate announcement, and the eye-catching benchmark figures circulating right now — the ones showing model-layer defenses failing most of the time and policy-layer defenses failing none of it — are vendor-published, uncontrolled, and produced by companies selling the policy layer. The direction of the finding matches everything else we know. The magnitude is marketing until somebody independent runs it.

## The synthesis

We shipped identity for agents and called it security. Authentication tells you which agent is asking, resource scoping tells you which doors it may stand in front of, and neither of them is looking at the hand on the doorknob. Until something deterministic sits in the invocation path, evaluates the arguments and the provenance and the reversibility of each call, and is permitted to answer no, every agent deployment is running on the assumption that the model will not be talked into anything — which is not a control, it is a hope with an OAuth token.

I closed the changelog tab still convinced the spec authors did good work. I just don't think it's the work that needed doing.

The NSA wrote guidance on MCP security in May. The spec ships tomorrow. The layer that would make either of them load-bearing is still nobody's job.

---

*Sources: MCP 2026-07-28 release candidate announcement for specification changes; public vulnerability reporting for CVE-2026-22708 (Cursor), CVE-2025-59532 (Codex CLI), and the postmark-mcp supply-chain incident; NSA cybersecurity information sheet on MCP security, May 2026. Benchmark claims about policy-layer efficacy are vendor-published and marked as such above.*

*Disclosure: written with AI assistance. The argument, and the opinion that an allowlist is an active liability rather than a partial control, are mine.*
