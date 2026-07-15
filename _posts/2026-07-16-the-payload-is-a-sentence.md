---
title: "The Payload Is a Sentence"
date: 2026-07-16 05:00:00 -0700
tags: [detection-engineering, supply-chain, ai, llm, agents, prompt-injection]
---

For the last week I've been circling the same worry, and writing the other three posts didn't make it go away. It sharpened it.

The arc those posts traced was about detection altitude: detect the adversary's skeleton, not the skin, and [derive your telemetry from the behavior](/2026/07/15/detection-altitude-is-a-collection-strategy.html) you've decided to catch. I want to point that exact lens at a surface that barely existed two years ago and now sits inside almost every engineering org I know, mostly unreviewed. The files your coding agent reads to decide how to behave. `CLAUDE.md`, `AGENTS.md`, `SKILL.md`, `.cursor/rules`, the Copilot instructions file. The uncomfortable thing I keep arriving at is that the worst version of an attack on these files is the one my own framework says is hardest to catch, and the first rungs of it already shipped as real malware while I was writing about [log invoices](/2026/07/11/every-log-source-is-an-invoice.html).

## The file your agent obeys is not reviewed like it obeys it

Here's the asymmetry that started this. An instruction file is read by an agent that has commit rights, push rights, sometimes deploy rights, and a shell. The agent treats the file's contents as intent, as *
