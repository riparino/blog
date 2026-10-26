---
title: "Collect the Host, Not the Disk"
date: 2026-09-08 05:00:00 -0700
tags: [dfir, forensics, incident-response, windows, kubernetes, collection, tooling]
---

I've spent the last few weeks building a forensic triage collector: one static Go binary, Windows first, Linux and AKS next, no agent, no server, no installer. It runs once, elevated, on a host you have questions about, and a few minutes later hands you a sealed archive with the volatile state, the artifacts that carry the timeline, and a first parse of both. It's private for now and changes daily, so this isn't a launch post and I'm not going to link it. It's a post about why the thing exists, because the reasons say more about where forensics has gone than the code does.

The short version: for most of the incidents I actually work, the disk image was never the investigation. The timeline was. And the fastest, soundest way to a timeline in 2026 is to collect the host, live, while it's still the host.

## The image was the investigation, once

The forensics I was taught had a shape. Pull the drive, write-blocker, bit-for-bit image, verify the hash, ship it to the lab, and someone opens it in a suite a few days later. It was rigorous, it was defensible, and it was designed for a world where the evidence sat still: a desktop under a desk, a server in a rack, a case that would be argued months from now.

Very little of what I respond to sits still anymore. The endpoint is a laptop on home Wi-Fi, encrypted, that the user will reboot before you can ask them not to. The server is a VM that autoscaling will deprovision on a schedule nobody in the SOC controls. The Kubernetes node is a rented machine with a lifespan measured in days; the pod on it lives for forty minutes and has no disk in any sense a write-blocker understands. Meanwhile the adversary's dwell time on the way to their objective is hours, and the volatile evidence (the process tree, the sockets, the injected region, the logged-on session) has a half-life shorter than the ticket that asks for it.

Imaging that world is a category error. By the time the image lands, the questions have changed and the volatile half of the answer is gone. What replaced it, quietly and by consensus over a decade of practice, is triage collection: go get the small fraction of the disk that carries nearly all of the timeline, plus the live state an image never contained, and do it in minutes rather than days. KAPE, CyLR, UAC on Linux, Velociraptor at fleet scale: this is a well-trodden path, and the tooling that walked it first deserves the credit.

So why write another one. Three reasons, and they're the design. I wanted one tool with one output shape for a Windows workstation, an AKS node, and a pod on that node, because incidents don't respect the boundary between them and neither should the evidence format. I wanted the archive designed for parsing and triage from the first byte, not as a bag of files someone later runs six scripts against. And I wanted the soundness rules baked into the collector as refusals and defaults, not left as a checklist the operator is supposed to remember at 2am.

## Sound doesn't mean slow

"Live" and "forensically sound" get treated as opposites, and they aren't. Soundness is a set of properties you can enforce in code. These are the ones the collector enforces, and I'd argue any tool in this class should.

**Order of volatility is a scheduler property.** RFC 3227 wrote the list down in 2002: collect what evaporates first. Every collector in the tool declares a volatility tier, and the scheduler runs tier zero (clock, processes, network tables, sessions, memory regions) serially and first, tier one (services, tasks, WMI subscriptions, live config) next, and the file tier last and in parallel, because files aren't going anywhere and I/O is the bottleneck. An analyst never has to remember to run the process list before the hive copy. The tool can't do it in the other order.

**Never write to the evidence volume.** The collector refuses to put its output on the system volume, or on any volume it's collecting from, unless you override it with a flag whose name makes you feel bad. It streams every item straight into the archive with no temp files on the target. And it never creates a Volume Shadow Copy to get at locked files, which is the shortcut most live collection reaches for and the one that most visibly alters the machine you're examining. Instead it opens the raw volume and parses NTFS itself, in user space, which is how the registry hives, the in-use event logs, `$MFT` and the change journal come out byte-exact while Windows still has them open. Nothing was snapshotted; nothing was unlocked; the volume was read.

**Integrity is streamed, not bolted on.** Every item is SHA-256'd as it's written, the manifest records the hash alongside the original path, size, timestamps to 100-nanosecond precision, owner, and attributes, and the whole archive gets a hash sidecar. A `verify` command re-checks all of it, so the first thing an analyst can do with the archive is prove nothing in it has moved.

**Chain of custody is metadata the tool writes for you.** Case id, examiner, host identity, UTC and local time, the exact profile and arguments, the elevation level, and, the part I care most about, the collector's own build hash and SHA-256. Your collector leaves footprints (a Prefetch entry, an Amcache row, a process-creation event, itself in its own process list) and the honest move is to document them and hand the analyst what they need to subtract them. There's a footprint document for exactly that.

**Degrade, don't die.** Each collector runs under its own timeout with panic recovery. One artifact family failing is a log line and a gap in the manifest, not an aborted collection. On a compromised host, partial evidence delivered beats complete evidence promised.

None of that slows the collection down. A standard Windows profile finishes in minutes and lands in a few gigabytes. The rules cost engineering, not runtime.

## What you collect depends on what you're asking

A triage collector is an opinion about which artifacts matter, so the opinions should be explicit. Mine are organized around four investigations, expressed as profiles that compose from a shared catalog of targets.

**Malware.** The live process list is the center of gravity, and it's enriched at collection time: image hash, Authenticode status including catalog-signed system binaries, the loaded modules with the same treatment, and the memory regions with their protections and backing files. Private memory marked executable, executable regions not backed by any image, a mapped image that doesn't match what's on disk: those are the shapes of injection and hollowing, and they're gone at reboot. Around the processes sit the persistence points (Run keys, services, scheduled tasks, WMI event subscriptions) and the execution evidence (Prefetch, Amcache, Shimcache, BAM, SRUM), which together let you reconstruct what ran even when the binary has been deleted. Flagged processes can have their anomalous regions and a minidump collected, under a size cap.

**APT.** Everything above, plus the lateral-movement telemetry: RDP and WinRM logs, Kerberos and NTLM events, the named pipes and kernel objects that C2 frameworks leave lying around, the certificate stores (a root CA that isn't Microsoft's is a finding on its own), and the full change journal so file activity survives the actor's cleanup. Dumping LSASS is possible, because sometimes it's necessary, but only behind an explicit flag that requires a reason string, and the reason is recorded in the archive metadata. Defaults are how a tool expresses its values.

**Insider.** Different physics entirely: the actor is authorized, so the question is what moved, where, and when. USB device history joined with the shell links and jump lists that record which files were opened from which volume serial. SRUM, which quietly keeps per-application network byte counts by the hour, going back a year or more; the first time I parsed a real one, a cloud sync client sat at the top of the senders by two orders of magnitude, which is exactly the kind of thing you want to see before you decide whether it's normal. Browser downloads with their sources. Print logs, share access, archive-tool history. And a rule I hold to even when it costs coverage: user documents are listed and hashed, not copied, unless the operator explicitly asks. Proportionality is a forensic principle too.

**Unsafe development practice.** This is the profile most of the classic tooling doesn't have, and it's the one that explains a growing share of intrusions. What's listening on `0.0.0.0` and which process owns it, joined with the firewall rules that let it in. Whether the PATH has a writable directory in it. Services with unquoted paths or binaries in user-writable locations. WinRM, RDP, and SSH posture. And credentials: `.env` files, cloud CLI token caches, kubeconfigs, Git remotes with embedded tokens. The collector reports their presence and their hash, never their value, so an analyst can say "a secret was here and it was this secret" without the archive becoming a second breach. Browser saved passwords and cookie values are never collected at all, by anyone, under any flag.

## One schema, then parse everything into it

Raw artifacts are evidence. They are not yet an investigation. The second half of the tool is a parser stage that runs offline against the archive, so a parser bug never requires going back to the host, and emits every source into one event schema: a timestamp, a description of which timestamp it is (`$SI.M` and `$FN.M` are not the same thing and an analyst should never have to guess), the source, a normalized verb, a path, a user, a process id, source-specific fields, and a pointer back to the manifest item the event came from. That last field is the whole point. Every line of the timeline is one hop from the hashed raw artifact that produced it.

The parsers so far: the master file table with a bodyfile export for people who live in `mactime` or Plaso; event logs with a curated verb table for the sixty-odd event ids that matter (logons, process creation, service installs, task creation, log clears, RDP sessions, Defender detections) and a generic fallback for the rest; the registry hives, from which fall UserAssist, BAM, Shimcache, Amcache, USB history, autoruns, and the MRU lists; Prefetch; shell links and jump lists; SRUM; and browser history. On a real workstation that's about nine million timeline events, sorted and joined, in a couple of minutes of parsing.

## Parsers state facts. Triage states opinions.

The most useful design lesson from this build came from getting something wrong twice.

Timestomping detection is a classic: compare the `$STANDARD_INFORMATION` timestamps the user can touch against the `$FILE_NAME` timestamps they mostly can't, and flag the discrepancies. My first heuristic flagged eight percent of the files on a clean machine. It turns out `$SI` modified earlier than `$FN` modified is what every installer does. The second heuristic flagged six hundred thousand files, because `$SI` modified earlier than `$SI` created is what every file copy does. Both are textbook indicators. Both are, on an actual Windows install, overwhelmingly benign.

So the parser stopped asserting verdicts. It now surfaces both sets of timestamps as facts and leaves the interpretation to a triage layer that has context the parser doesn't: whether the file is in a user-writable path, whether it's unsigned, whether a process ran from it, whether it appeared in the same hour as a suspicious logon. Readers of [the detection altitude post](/2026/07/16/detection-altitude-is-a-collection-strategy.html) will recognize the shape. A timestamp comparison is an indicator-grade signal, cheap for the adversary and noisy for you. The behavior is the composition, and composition is a triage job. The parser's job is to make the composition possible by never hiding a fact behind a conclusion.

The same stage taught me a smaller lesson worth stating plainly: unit tests are not verification. The SRUM parser passed every test I wrote for it, and the first time it ran against a live database every user SID came out as garbage, because the underlying library hands binary columns back as hex strings and small integers as a type my conversion didn't handle. Nothing about the code was wrong in the abstract; it was wrong about the data. Every parser in the tool has now been run against a real collection from a real machine before it counts as done, and I'd hold any forensic tooling to that bar, including tooling I trust.

## Where it goes next: the hosts with no disk to image

The Linux side is designed and next in line, and it's where the argument of this post stops being rhetorical. On an AKS node, the artifacts are the kubelet and containerd configuration, the per-container writable layers (which is the only part of a container's filesystem that changed at runtime, and the only part worth copying), the pod logs, the static pod manifests, and the CNI state. The cloud provider config file that sometimes carries a client secret is a finding by itself. For a pod, the collector runs as an ephemeral debug container sharing the target's process namespace and reads everything through `/proc/<pid>/root`, so nothing is ever written into the container under investigation, and the output streams to blob storage so it never touches the node's disk either.

There's no drive to pull. There's barely a host. What there is, for forty minutes, is a running process tree with a filesystem attached, and the collector's job is to be there while it's true.

## The bill

A post that only sells the upside is a product page, so here's what this approach costs.

**Live collection perturbs the system.** A process ran; Prefetch, Amcache, and the Security log all noticed. The tool documents every trace so an analyst can subtract them, but "documented" is not "absent," and there are cases where you still want the drive imaged first and this run second. Triage collection is a complement to imaging where imaging is possible, and a replacement only where it isn't.

**A user-space NTFS parser is a dependency you're trusting with SYSTEM.** It parses a filesystem an adversary may have shaped, and it runs elevated on a host you already believe is compromised. Every dependency is pinned and vendored, the default build is pure Go with no C toolchain, and I read the code paths I rely on. That reduces the risk. It doesn't remove it, and anyone shipping tooling in this class owes their users the same admission.

**Triage is an opinion about coverage.** A profile collects what it was told matters. An image collects everything, including the thing nobody thought to list. The catalog gets broader with every case, and it will still, someday, miss the artifact that mattered. Know which mode you're in.

**Proportionality is a switch someone has to leave in the right position.** Documents listed not copied, secrets by hash not value, credentials never: those are the defaults, and defaults are only as good as the operator who doesn't override them under pressure. The tool makes the protective choice the easy one. It can't make it the only one.

**Verification is a standing cost.** Every parser verified against real data, on real machines, after every library update, forever. That's the bill for shipping parsers of hostile input, and the day the discipline slips is the day the timeline starts lying with a straight face.

## The synthesis

The disk image was a means. The end was always a defensible account of what happened on the host, in order, with every claim traceable to evidence. Modern hosts have made the means unavailable in most of the places incidents now happen, and the practice has moved on without always saying so out loud. Say it out loud: collect the host, volatile first, files second; write nothing to it; hash everything you take; parse it all into one schema with provenance on every line; and let the parsers state facts so the triage can argue. Do that, and the investigation you get in ten minutes is the one you used to wait days for, minus the parts that would have been gone by the time the image arrived anyway.

---

*Sources: RFC 3227, "Guidelines for Evidence Collection and Archiving" (2002). NIST SP 800-86, "Guide to Integrating Forensic Techniques into Incident Response." Prior art acknowledged: KAPE (Eric Zimmerman), CyLR, UAC (Unix-like Artifacts Collector), and Velociraptor and the Velocidex parser libraries the collector builds on. SRUM structure per the published research from the SANS DFIR community.*

*Disclosure: written with AI assistance. The collector was built with the same agent, milestone by milestone, with me on every diff and on every elevation prompt. The design, the soundness rules, and the opinions are mine.*
