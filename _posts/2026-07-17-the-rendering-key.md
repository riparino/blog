---
title: "The Rendering Key: Symmetric Text Steganography on a Character Grid"
date: 2026-07-17 06:00:00 -0700
tags: [steganography, cryptography, detection, red-team]
---

## The mechanism

The base idea is an acrostic generalized: rather than reading the first letter of each line, you read characters at positions selected by a pseudorandom walk over a 2D character grid. A text file maps to a grid when you hard-wrap it at a fixed width W — the character at byte offset r×W + c lands at grid position (row r, column c). To embed a secret, select grid positions via a CSPRNG seeded from KDF(shared\_secret, nonce), and place each secret character at its assigned position in the cover text. Extraction reverses this: same key, same nonce, same CSPRNG walk, read the characters out.

The CSPRNG walk can be any deterministic traversal of the position space — the simplest is rejection-sampling (row, col) pairs until you have the count you need. The walk function choice affects detection resistance but not the extraction logic, which just retraces whatever the embedder did.

The nonce functions like an IV: per-message, not secret, transmitted alongside the cover object. It kills correlation between transmissions with the same key and prevents precomputation of position walks across messages.

Here's what it looks like. Grid is 60 characters wide, 8 rows. Key: `demo_key`, nonce: `blog_nonce_01`. Seed derived from SHA-256(`demo_key:blog_nonce_01`)[:4] → `3500985302`. Cover text:

```
Networks protocol data fields for sessions: monitoring and e
vents and filter scope1, layer routing across flags,-type en
activate mode -verbose alls-stream config for ingress rules.
v1.0 proto-2a or application baseline hash verification: ok 
TLS layer3 inspection and packet stat byte index per session
 data across trust boundaries and policy action logging ok. 
Session timeout5.3 retries3 limit3 on authentication failure
Source port classification: 1 rule is matched per context id
```

The CSPRNG yields positions `(2,6), (3,38), (1,22), (6,15), (2,14), (7,28), ...` in extraction order. With those positions marked:

```
Networks [p]rotocol data fields for sessions: [m]onitoring and e
vents and filter scope[1], laye[r] routing across flag[s],[-]type en
a[c]tiva[t]e mode [-]verbose all[s][-]stream config for ingress rules.
v[1].0 proto[-]2[a] or application baseline [h]ash verification: ok 
TLS layer[3] inspection and packet sta[t] byte inde[x] per session
 data across trust boundaries and policy [a]ction logging ok. 
Session timeout[5].[3] retries[3] limit[3] on authentication failure
Source port classification: [1] rule is matched per context id
```

`→ th15-1s-a-s3cr3t-3xamp13`

The positions look scattered because they are — the CSPRNG walk has no spatial structure an observer can leverage without the key.

## The rendering key

The idea that motivated this was about window width. A text file soft-wrapped at the terminal window width produces a different character grid at 72 columns than at 80 — the character at (row r, column c) under one width is at a different position under another. Window width is therefore a functional key parameter: two readers with different window sizes are reading different grids.

That's security through obscurity as stated, because the window width is a tiny parameter space with no connection to a shared secret. The interesting move is to derive the grid dimensions from the shared secret: `(width, height, ...) = KDF(shared_secret, nonce)`. Now the receiver needs the shared key before they can reconstruct the grid, let alone trace the position walk. The grid parameters are out-of-artifact key material — absent from the file, irrecoverable from static analysis.

The more precise formal analogy is visual cryptography: the file is share one, the grid configuration derived from the key is share two, and neither alone reconstructs the message. An analyst who has the file and not the key has no coordinate system to work in.

One implementation note: if the shared secret is a random key, HKDF-SHA256 is appropriate for the grid parameter derivation. If it's a passphrase, low entropy means you want a memory-hard KDF (Argon2id) to make offline brute force expensive.

## Formal structure

This converges to symmetric-key text steganography with PRNG-selected embedding positions, structurally identical to what Steghide and F5 do for image steganography applied to a character grid instead of a pixel matrix. The pattern is: treat the cover medium as an indexed array of positions, use a keyed PRNG to select which positions carry payload, modify those positions to encode the message. The differences are the cover medium and the capacity constraints it imposes.

The formal antecedents are Simmons's subliminal channel (1983) — a message hidden in a cover object that is itself meaningful, where the key selects the channel — and environment-keyed stegosystems, where part of the key material lives in the receiver's environment rather than in the artifact. The rendering configuration (grid dimensions) is that environmental component: without it, the receiver has no coordinate system and the file is indistinguishable from ordinary text.

## Practical constraints and how to address them

**Rendering dependence.** If grid dimensions come from actual window rendering, two clients with different terminal sizes won't agree on the grid. The fix is to specify dimensions in the protocol, derive them from the KDF, and have both parties hard-wrap at the protocol width. The "rendering key" framing is still conceptually accurate, but rendering happens at the protocol layer rather than the display layer.

**Cover text generation.** Historically the blocking problem for text steganography: generating natural-sounding text where specific arbitrary characters appear at specific positions is hard constraint satisfaction over natural language, and prior approaches either produced obviously synthetic text or had very low capacity. LLMs change this — you can prompt against positional constraints and get plausible results, which wasn't feasible five years ago. What I haven't characterized is which generation strategy works best: direct positional prompting, candidate generation and filtering, or constrained decoding at inference time. The manual example above shows the problem concretely — positions requiring non-alphabetic characters (`1`, `3`, `5`, `-`) fell in technical vocabulary like version strings and config identifiers (`timeout5.3`, `retries3`), cover text that only appears naturally under tight constraints. LLM generation handles those positions more naturally, but the compliance rate and quality trade-off at scale is an open question.

**Constraint failure tolerance.** No generation approach satisfies every positional constraint without degrading text quality at some fraction of positions. ECC over the embedding positions is the right answer: encode the secret with enough redundancy that you can reconstruct from a subset of positions, which relaxes the per-position constraint. The error model is generation failures — positions where satisfying the character requirement would make the text anomalous. The right code rate depends on the generation approach and cover text domain; I haven't worked through it.

**Frequency anomalies.** Uniform random position selection will, over many messages with the same key, produce detectable deviations in character frequency at embedding positions relative to the surrounding text. Spread-spectrum distribution — selecting positions so that the embedded characters mirror the natural character frequency of the cover text — closes this attack surface, the same way F5 does for JPEG DCT coefficient selection.

## Detection posture

Static analysis of the file finds nothing. There's no modified metadata, no LSB layer, no whitespace encoding, no frequency anomaly in the file as a flat byte stream. The structure is in the grid, and the grid depends on key material not present in the file.

A detector suspecting steganography faces exhaustive search over (extraction function family) × (key space). The function family isn't small — CSPRNG walks parameterized by seed, grid dimensions, and walk order, with no canonical enumerable set. With a proper KDF, the key space dominates: even correctly identifying that the scheme uses CSPRNG-selected grid positions doesn't help without the shared secret.

The realistic detection path is statistical: compare character frequency at candidate positions against the ambient frequency of those characters in the surrounding text. Without spread-spectrum, there's a measurable anomaly at the embedding positions; with spread-spectrum, that signal disappears. What's left is the naturalness of the cover text itself — and if generation is LLM-assisted with adequate constraint compliance, there's nothing structurally anomalous to find in the file.
