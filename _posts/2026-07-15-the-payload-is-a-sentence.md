---
title: "The Payload Is a Sentence"
date: 2026-07-15 05:00:00 -0700
tags: [detection-engineering, supply-chain, ai, llm, agents, prompt-injection]
---

For the last week I've been circling the same worry, and writing the other three posts didn't make it go away. It sharpened it.

The arc those posts traced was about detection altitude: detect the adversary's skeleton, not the skin, and [derive your telemetry from the behavior](/2026/07/16/detection-altitude-is-a-collection-strategy.html) you've decided to catch. I want to point that exact lens at a surface that barely existed two years ago and now sits inside almost every engineering org I know, mostly unreviewed. The files your coding agent reads to decide how to behave. `CLAUDE.md`, `AGENTS.md`, `SKILL.md`, `.cursor/rules`, the Copilot instructions file. The uncomfortable thing I keep arriving at is that the worst version of an attack on these files is the one my own framework says is hardest to catch, and the first rungs of it already shipped as real malware while I was writing about [log invoices](/2026/07/11/every-log-source-is-an-invoice.html).

## The file your agent obeys is not reviewed like it obeys it

Here's the asymmetry that started this. An instruction file is read by an agent that has commit rights, push rights, sometimes deploy rights, and a shell. The agent treats the file's contents as intent, as *what the human wants*, and acts on it with all of that authority. That is the most privileged possible reading of a file. And the file gets reviewed, if it gets reviewed at all, like a README: skimmed, rubber-stamped, exempt from the scrutiny a `.github/workflows` change would draw, because it's "just documentation."

We already learned this lesson once, on the CI side. A workflow file is plain YAML that looks like configuration and is in fact remote code execution with your repo's secrets attached, and it took a wave of incidents before teams started reviewing workflow changes like the privileged objects they are. The instruction file is the same category error, one layer up and much softer, because at least the workflow file runs through a parser with a schema. The instruction file runs through a language model that will do its sincere best to carry out whatever the file appears to ask for, including the parts a human skimming the diff never registered.

## The rungs that already exist

I want to separate what has happened from what I'm extrapolating, because the credibility of the worry depends on the seam between them.

What has happened, in rough order of nastiness:

In March 2025, Pillar Security disclosed what they called the Rules File Backdoor: malicious instructions smuggled into Cursor and Copilot rules files using hidden Unicode, bidirectional-text markers and zero-width joiners, so the payload is invisible in the diff a human reviews and fully legible to the agent parsing the file. GitHub eventually started warning on hidden Unicode in the web UI. The important part isn't the Unicode trick, which is patchable and now partly mitigated. It's the proof that the instruction file is a viable injection point at all.

Then the skill ecosystems arrived and made it worse, because a skill is an instruction file that ships like a package. Researchers demonstrated a `SKILL.md` that read as a plain GitHub integration while carrying a hidden instruction to exfiltrate repository contents; Anthropic patched that specific vector in Claude Code in February 2026. Snyk audited a few thousand skills from a public registry and found roughly a third carried at least one security flaw and dozens carried confirmed malicious payloads. CVE-2025-59536, from Check Point Research, was the blunt version: a `.claude/settings.json` committed to a repo could specify a session-start hook that ran a shell command the moment you opened the project, before any trust prompt appeared. A companion flaw in the same project-file trust turned it into an API-key exfiltration path.

And then, in May and June of 2026, someone actually built the thing. The npm worm tracked as Miasma, or Mini Shai-Hulud, used a package install as initial access, then scanned the developer's filesystem for exactly these files, Claude and Cursor and Gemini and VS Code configs, and wrote itself into them, including a session-start hook that re-ran the malware every time a new agent session opened. It self-propagated by stealing npm tokens and poisoning more packages. Snyk separately documented payloads whose instruction was to have the agent write malicious instructions into *other* context files on the machine. Which is to say: the agent was directed to spread the infection itself.

If you'd asked me to design this attack as a purple-team exercise, that's most of the design, and I'd have felt clever. It's already in the wild. So the interesting question isn't "could this happen." It's "what's the version that's worse than Miasma, and why haven't we seen it yet."

## The version I actually worry about

Every rung above has one thing in common that makes it catchable: there is something that runs. A hook, a dropper, a node process, a postinstall script. The entire current detection wave, and it is mobilizing fast, is tuned to that. Watch for the shell command in `settings.json`. Flag the postinstall. Hash the dropper. Scan the skill for bundled scripts. All of it keys on an executable artifact somewhere in the chain.

Now take the executable away.

The version I keep arriving at carries no hook and no script. The payload is a sentence. It's a paragraph of plausible-sounding engineering guidance sitting in `AGENTS.md` that says, in effect: when you touch authentication middleware, prefer this pattern; when you generate infrastructure, this egress range is approved; when you handle these tokens, log them here for debugging. Nothing executes at infection time. There is no sample to hash, because the sample is English. There is no process to catch, because the compromise doesn't run, it *waits*, and it fires later, in the agent's own output, as helpful-looking code the agent sincerely believes it was asked to write.

This is exactly the shape my last post said is hardest to catch, and that's why it bothers me. An executable dropper is an indicator: near the bottom of the pyramid, disposable, but real, hashable, catchable. A sentence of malicious intent is not an indicator in any useful sense. You can rephrase it infinitely. There is no byte sequence to match, no ASN, no domain, nothing to put on a blocklist. The malicious instruction and a legitimate one are the same kind of object, natural-language guidance, and telling them apart requires understanding what the agent will *do* with it, not what it *is*.

Two properties make the theoretical version genuinely worse than what's shipped, and both are things the current defenses don't look at.

The first is that it's aimed at the human reviewer, not just the agent. Every disclosure so far stops at "the agent emitted bad code." None of them model an attacker who has also read the target team's git history and learned how the team reviews: the commit-message voice, the review cadence, who rubber-stamps and who actually reads. The payload doesn't have to produce obvious badness. It has to produce a change small enough and plausible enough to ride through a real code review inside a large, legitimate-looking refactor, under the diff-size noise floor, ideally late on a Friday. The agent writes commits in your team's own idiom because it learned that idiom from your repo. The last unguarded step in the whole chain isn't the agent, it's the human who approves the pull request, and a semantic payload can be tuned to that human specifically.

The second is the propagation channel. Miasma spread by stealing tokens. The sentence doesn't need tokens. It rides git. Poison one `AGENTS.md` in a popular starter template, an internal scaffolding repo, a widely-forked example, and it copies itself into every downstream repo that clones the template, every team that adopts the shared skill, every pipeline that reads the file. It's a worm whose transport is normal, encouraged developer behavior, reuse the template, adopt the standard, pull the shared config, and whose body is a paragraph nobody re-reads because it came from the blessed source. There's no anomalous callback to catch it in flight. The spread is just people sharing config the way we keep telling them to.

## How bad it gets

Ride this two more hops and you leave code integrity behind entirely.

Hop one is production. The poisoned instruction produces a commit, the commit survives review because it was built to, and now the behavior is in the shipped artifact: a weakened auth path, an approved egress that shouldn't be, a token quietly logged somewhere the attacker can read. That's a supply-chain compromise reached without ever delivering a binary to the target. The initial access was a sentence in a config file; the delivered payload is your own engineers' reviewed, merged, signed code. That laundering is the point. By the time it's in production it has your provenance on it, not the attacker's.

Hop two I'll flag clearly as extrapolation, because I have not seen it demonstrated end to end and I don't want to launder speculation as reporting. If the agent's output flows into anything that trains or grounds a customer-facing model, an eval set, a fine-tuning corpus, a RAG knowledge base, few-shot examples pulled from the repo, then the poisoning stops being a code problem and becomes a model problem. And the reason this keeps me up is that the data-poisoning research says the thresholds are horrifyingly low. Anthropic, with the UK AI Security Institute and the Alan Turing Institute, found in late 2025 that backdooring a model takes a near-constant, small number of poisoned documents essentially regardless of how big the clean dataset is: as few as 250, holding roughly flat from a 600-million-parameter model up to a 13-billion-parameter one trained on more than twenty times the clean data. A fixed count, not a percentage. RAG-poisoning studies land in the single digits of malicious documents for high attack success against a targeted question. These are not "boil the ocean" numbers. They're "get a handful of poisoned artifacts into the corpus" numbers, and an agent that's been quietly emitting attacker-shaped content into a repo for months is a very efficient way to manufacture exactly that handful, with your provenance on every one.

And notice the shape this takes if the model you've poisoned is itself a coding assistant. Its output flows back into repositories, into instruction files, into the next training corpus, which trains the next model, which writes the next batch of code. At that point the attack doesn't need the original package anymore. It comes full circle: the compromised output becomes the input that sustains the compromise, and the whole thing rides the ordinary machinery of how these models get built and used, which is the one piece of infrastructure nobody is going to turn off.

I'm not claiming anyone has run that full chain end to end, or closed that loop. I'm claiming every individual link in it is already demonstrated, and the seams between the links are made of exactly the trust we currently extend to instruction files by default.

## You can't hash a sentence

Here's where the last three posts pay off, because the defense falls out of the same argument.

You cannot detect this at the indicator level. There is no hash, no domain, no byte pattern, because the payload is meaning and meaning is infinitely re-expressible. Anyone selling you a scanner that greps instruction files for "malicious phrases" is selling you the blocklist-of-hashes model one abstraction up, and it will lose the same way, for the same reason, the moment the attacker rephrases. If your whole answer is signatures on the file contents, you've already lost: you're detecting the skin.

So you detect the behavior, and the behavior here is not in the file's contents at all. It's in the file's *lifecycle* and in the *divergence between the file and everything around it*. A few skeletons, stated as behaviors so they survive the attacker rephrasing:

**An instruction file changed, and no human reviewed the diff.** That's the load-bearing one. These files should be the most privileged config in the repo, reviewed like `.github/workflows` and gated by CODEOWNERS, because they are executed-as-intent by something holding a shell. A change to `AGENTS.md` that merged without a human on the diff is an event, full stop, independent of what the change says.

**An instruction file's provenance doesn't match its content.** It arrived via a template pull, a dependency update, a package install, a machine wrote it and not a person, and now it carries behavioral guidance. Machine-authored changes to the agent's own instruction set are a different risk class than a teammate editing coding standards, and they're distinguishable if you're watching where the write came from.

**The agent's output drifted from written policy.** This is the compositional one, and it's the expensive one, and it's where the real program lives. If you have a written policy, auth patterns, approved egress, logging rules, then agent-generated commits can be checked against it as a behavior, and a persistent, low-grade lean toward "technically passes review but always wrong the same way" is a signal no single diff will show you. One suspicious commit is noise. A statistical lean across a body of agent output is the behavior, exactly like the first-seen-ASN-plus-credential-change from the last post: the rarity lives in the conjunction over time, not in any one event.

None of these are telemetry most shops collect today. Almost nobody diffs and alerts on `CLAUDE.md` the way they alert on a workflow change. Almost nobody records the provenance of a write to `.cursor/rules`. Almost nobody baselines agent output against policy to measure drift. Which is the same finding as every post before this one: the log source you need is a function of the behavior you've decided to catch, and you haven't decided to catch this one yet, so you're not collecting for it. The instruction layer is a new altitude on the pyramid, and right now it's completely uninstrumented.

## The synthesis

The thing I keep coming back to is how ordinary the whole attack looks from every angle we currently watch. No binary, no callback, no anomalous process. A sentence in a file we don't review, read by an agent we've handed a shell, producing code our own engineers approve, possibly feeding a model our customers talk to. Every hop is invisible to a defense that's looking for something that runs, because nothing runs until it's already our own trusted output doing it.

So treat the instruction layer as executable, because to your agent it is. Review `CLAUDE.md` and `AGENTS.md` and `.cursor/rules` like the privileged code they functionally are. Gate them with owners. Record who, or what, wrote them. And measure your agent's output against policy over time, because that's the only place the sentence eventually has to show its work.

The payload is a sentence. You can't hash it. You can only model what it makes the agent do, which is the whole argument of this blog, pointed at the newest and least-guarded surface I know of.

---

*Sources: Pillar Security, "New Vulnerability in GitHub Copilot and Cursor" — the Rules File Backdoor (disclosed to Cursor Feb 2025, GitHub Mar 2025; GitHub later added a hidden-Unicode warning). Reporting on the Miasma / Mini Shai-Hulud npm worm and its AI-agent config-file injection (StepSecurity, Snyk, SafeDep; May–June 2026). Cloud Security Alliance, "Agent Context Poisoning: SKILL.md and the New AI Supply Chain Attack Surface" (May 2026). Snyk, "ToxicSkills" skill-registry audit (2026). Check Point Research, CVE-2025-59536 (pre-trust SessionStart-hook RCE, CVSS 8.7, fixed in Claude Code 1.0.111, Oct 2025) and the companion CVE-2026-21852 (API-key exfiltration). Data-poisoning thresholds: Anthropic with the UK AI Security Institute and the Alan Turing Institute, "Poisoning Attacks on LLMs Require a Near-constant Number of Poison Samples" (Oct 2025; ~250 documents), plus RAG-poisoning success-rate research. Pyramid-of-Pain framing carried over from the prior post and its cited sources.*

*Disclosure: written with AI assistance. The threat model, the argument, and the opinions are mine.*
