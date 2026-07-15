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

**Cover text generation.** Historically the blocking problem for text steganography: generating natural-sounding text where specific arbitrary characters appear at specific positions is hard constraint satisfaction over natural language, and prior approaches either produced obviously synthetic text or had very low capacity. LLMs close this. The constraint — "character X must appear at column Y in this line" — is exactly the kind of soft lexical requirement an LLM resolves naturally through synonym selection, clause reordering, or minor rephrasing, and you can prompt-iterate or rejection-sample when the first attempt misses. The manual example above shows the problem as a human faces it — positions requiring non-alphabetic characters (`1`, `3`, `5`, `-`) forced technical vocabulary like version strings and config identifiers (`timeout5.3`, `retries3`) that look slightly constrained. An LLM generating a security advisory, a commit message, or a business email reaches for the same vocabulary without visible strain and with far more degrees of freedom for satisfying each position.

**Constraint failure tolerance.** Given LLM-assisted generation, the original case for ECC — tolerating positions where the required character couldn't be placed without making the text anomalous — largely disappears. The remaining argument for ECC is transit robustness: if cover text routes through a channel that modifies it (email clients adding `>` quote markers, line-length normalization, quoted-printable encoding), grid positions shift and extraction fails silently. For a file-based scheme where the cover object is transmitted intact, ECC isn't needed. For a conversation protocol — messages assembling the grid across an email thread — the right answer is a canonical normalization step before extraction (strip quoting, normalize line endings, reconstruct the grid from message bodies) rather than error correction over the payload.

**Frequency anomalies.** Uniform random position selection will, over many messages with the same key, produce detectable deviations in character frequency at embedding positions relative to the surrounding text. Spread-spectrum distribution — selecting positions so that the embedded characters mirror the natural character frequency of the cover text — closes this attack surface, the same way F5 does for JPEG DCT coefficient selection.

## Detection posture

Static analysis of the file finds nothing. There's no modified metadata, no LSB layer, no whitespace encoding, no frequency anomaly in the file as a flat byte stream. The structure is in the grid, and the grid depends on key material not present in the file.

A detector suspecting steganography faces exhaustive search over (extraction function family) × (key space). The function family isn't small — CSPRNG walks parameterized by seed, grid dimensions, and walk order, with no canonical enumerable set. With a proper KDF, the key space dominates: even correctly identifying that the scheme uses CSPRNG-selected grid positions doesn't help without the shared secret.

The realistic detection path is statistical: compare character frequency at candidate positions against the ambient frequency of those characters in the surrounding text. Without spread-spectrum, there's a measurable anomaly at the embedding positions; with spread-spectrum, that signal disappears. What's left is the naturalness of the cover text itself — and if generation is LLM-assisted with adequate constraint compliance, there's nothing structurally anomalous to find in the file.

The more interesting attack surface is a conversation rather than a single file. The grid can be assembled across a thread of emails or messages — each message contributes some rows, and the thread encodes the secret in aggregate. Individual messages are ordinary correspondence because they are ordinary correspondence: two people discussing a project, coordinating a meeting, whatever the cover requires. Static analysis of any message finds nothing. Correlating across the thread requires knowing which messages participate, what the grid dimensions are, and which key to use. The traffic pattern itself — people exchanging email — provides its own cover.

## As an attack

Miasma's limitation as a covert channel was outbound exfil — stolen npm tokens still had to travel somewhere, and "somewhere" is a connection. Replace that channel with this scheme and the connection disappears.

The attack chain: initial access via a poisoned `CLAUDE.md` or `AGENTS.md`, combined with a session-start hook (same class as CVE-2025-59536) that runs before trust prompts and harvests credentials from `~/.aws/credentials`, `~/.ssh/`, local `.env` files, injecting them into session context. The malicious instruction directs the agent to embed the harvested data using the scheme — pre-shared key baked into the payload, date-as-nonce, grid parameters derived at runtime. Every subsequent agent output satisfies the embedding constraints as a side effect of normal generation: PR descriptions, commit messages, code review comments, documentation. The attacker collects from whatever surface the agent writes to — a GitHub repo they have read access to, an email thread they monitor. There's no C2 server, no outbound connection, and no anomalous traffic beyond whatever API calls the agent was already making.

Infrastructure requirements drop accordingly: a pre-shared key embedded in the initial payload, a watched collection surface, an extraction script. The session-start hook handles harvesting; the instruction file handles embedding. Either component alone is weaker — the hook without the steg scheme still needs a connection to move data out, and the instruction file without the hook is limited to whatever the user explicitly shares in session. Together they're autonomous and persistent across every agent session the developer opens.

The instruction file is the right injection point for reasons the [prior piece on this surface](/2026/07/15/the-payload-is-a-sentence.html) covers in more detail: it's read with agent-level privilege — commit access, push access, shell — and reviewed if at all like a README. A developer diffing a poisoned `CLAUDE.md` is not running it through a steg detector, and a malicious embedding instruction looks like an ordinary behavioral directive.

What the defender sees at runtime: the agent's normal output, no network anomalies, no filesystem artifacts beyond the initial compromise. The statistical detection path requires knowing to look, knowing roughly what scheme is in use, and analyzing enough of the agent's output to accumulate signal. With spread-spectrum distribution, even that path is closed.
