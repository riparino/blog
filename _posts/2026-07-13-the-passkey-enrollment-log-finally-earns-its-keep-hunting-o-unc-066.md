---
title: "The Passkey Enrollment Log Finally Earns Its Keep: Hunting O-UNC-066"
date: 2026-07-13 05:00:00 -0700
---

Last week I argued that most log sources are liabilities with a recurring invoice: telemetry you collect on reflex and keep on faith, that never traces back to a detection anyone modeled. A few people wrote in asking for the inverse: a source that actually earns its keep. Here's one, and it happens to sit in front of a campaign that's live right now.

The source is the Entra authentication-methods audit stream, and the threat that makes it worth the money is a group that turns your passkey rollout, the thing your identity team has been begging users to adopt, into the phishing lure itself.

## The actor

Okta Threat Intelligence published on this cluster on July 6, 2026. They track it as O-UNC-066. Palo Alto Networks Unit 42 tracks the same activity as CL-CRI-1147 and reports it under the extortion brand Pink, which stood up a data leak site on May 31, 2026. Unit 42 places Pink inside The Com, the same decentralized cybercrime milieu that produced Scattered Spider, ShinyHunters, and LAPSUS$. The motivation is data extortion: get in, pull data out of SharePoint and OneDrive, then name-and-shame on the DLS to force payment.

Victimology, per Okta, spans food and beverage, technology, healthcare, automotive, construction, and aviation. That spread tells you what this is: not a targeted intrusion set picking a single vertical, but a repeatable social-engineering script run at scale against whichever help desk or user picks up the phone.

Attribution confidence here is reasonable but worth stating plainly: Okta observed the phishing kit and the infrastructure directly; the Pink/The Com linkage comes from Unit 42; and Okta notes it did not directly confirm a Microsoft account compromise from its own vantage point, so it's inferring the account-takeover objective from the kit's design. If you have Recorded Future, this is the first place to spend your pivots: confirm the DLS victim list against the sectors above, and validate the Com affiliation against RF's own clustering rather than taking the vendor label at face value.

## The technique: weaponizing the security upgrade

As of May 2026, Microsoft admins can run passkey registration campaigns, the sign-in "nudges" that prompt users to enroll a passkey, and in some configurations those nudges are on by default, which means the pretext already exists inside the tenant. The actor just has to phone a user and say the quiet part your own IT team has been saying for months: you need to set up a passkey.

The delivery is voice phishing (vishing). The actor registers domains with the word `passkey` baked in (Okta listed `assignpasskey[.]com`, `deploypasskey[.]com`, `passkeydeploy[.]com`, `passkeyadd[.]com`, `setpasskey[.]com`) and stands up per-target subdomains that mimic the victim org's Entra sign-in page. Generic Microsoft chrome loads from Microsoft's real CDN; the victim-specific logo and background are pre-staged in the kit backend. Infrastructure has been hosted on DDoS-Guard (AS57724) and IQWeb FZ-LLC (AS59692).

The kit is where it gets unusual, because it isn't a transparent adversary-in-the-middle proxy, which is the pattern most of your AiTM detections are tuned for, but an operator-controlled PHP panel. A human operator steers the victim through the auth stages in near real time using a one-second heartbeat polling loop, adapting the page flow to whatever MFA the victim actually gets challenged for: TOTP, push with number matching, SMS OTP. The documented kit stages: `/gate` (anti-analysis checks), `/identify` (username), `/password` (credentials POSTed to `/backend.php`), then `/processing` (a stall screen while the operator replays the creds against the real Microsoft login). There's even a decoy step asking the user to save and confirm a word from a BIP-39 seed phrase — which has no role in real Entra passkey enrollment and appears to exist purely to make the ceremony feel legitimate to a user who's never done this before.

The endgame: while the victim thinks they're enrolling a passkey, the operator enrolls their own passkey against the victim's account, and can name it something benign so the legitimate Microsoft "new passkey registered" email doesn't raise alarm.

## Why "we deployed passkeys" doesn't save you here

Passkeys are phishing-resistant as an authentication method, because the private key never leaves the authenticator and there's nothing to replay, but the enrollment ceremony is a different surface entirely. Phishing resistance protects the sign-in; it does nothing to stop a socially-engineered user from adding an attacker's credential to their own account. The moment you make self-service passkey setup easy, which is exactly what a registration campaign does, you've created a workflow that a caller can walk a user through.

So the control that matters isn't whether you have passkeys, it's who is allowed to enroll one, from where, and how you find out when it happens.

## Deriving the detection

Same discipline as always: threat model, then detection requirement, then telemetry requirement, then the query. Don't start from "what can I write in KQL."

Threat: an attacker socially engineers a user into enrolling an attacker-controlled passkey (or any auth method), then uses the account to exfiltrate from SharePoint/OneDrive.

Detection requirement: alert when a security-info / passkey registration happens in a context that doesn't look like a normal user self-service enrollment. Specifically, shortly after a sign-in from infrastructure or a network the user has never used, with enough context that an analyst can act without rebuilding the case.

Telemetry requirement: the Entra authentication-methods audit events (in `AuditLogs`), sign-in context (`SigninLogs`), and file-operation logs for the exfil stage (`OfficeActivity`). All three are first-party and, if you're already ingesting Entra and M365 into Sentinel, already paid for, which is what a source earning its keep actually looks like.

A note on grounding, because it's the whole point of the last post: I verified every table and column below against the Microsoft Azure Monitor table references before publishing. One thing I deliberately did not do is hardcode a nested JSON path for the method type (e.g. digging into `TargetResources[].modifiedProperties` to isolate "FIDO2" specifically). That structure varies and I couldn't verify a stable path, so keying a detection on it would be exactly the kind of assumed-field-name mistake that breaks silently. Instead the queries key on the verified operation names and correlate with sign-in context, which is the stronger signal anyway. If you want method-level granularity, sample your own tenant's records first and confirm the path before you trust it.

Four queries follow, and they are not four options to choose between. The first is orientation, the second is a one-time retro-hunt you run and then throw away, the third is the analytic rule you actually deploy, and the fourth catches the exfil if the first three miss. Only #3 belongs in your rule set.

### 1. Baseline hunt: security-info and passkey registrations

Start by just seeing the events. These `OperationName` values and the `LoggedByService` value are from the Entra audit activity reference; the `TargetResources[0].userPrincipalName` extraction is Microsoft's own documented pattern.

```kusto
AuditLogs
| where TimeGenerated > ago(7d)
| where LoggedByService == "Authentication Methods"
| where OperationName in ("User registered security info",
                          "User registered all required security info",
                          "Get passkey creation options")
| where Result == "success"
| extend UPN = tostring(TargetResources[0].userPrincipalName)
| project RegTime = TimeGenerated, UPN, RegOperation = OperationName,
          RegCorrelationId = CorrelationId, InitiatedBy
| order by RegTime desc
```

### 2. Retro-hunt: were we already hit?

This one is not a detection, and you should not deploy it as a scheduled analytic rule. It answers a single, backward-looking question you have exactly once (did this already happen to us before we knew the campaign existed?) and then it stops being useful.

The reason it works at all is a quirk of the kit's design. Because the panel operator replays the harvested credentials against the real Microsoft sign-in page from their own infrastructure, the sign-in Entra records carries the operator's IP and ASN, not the victim's. The victim's browser only ever talks to the phishing domain, which never appears in your tenant's logs. So the operator's hosting is the thing you can actually see, and `SigninLogs.AutonomousSystemNumber` is where you see it.

Run it once over as long a lookback as your retention allows. The campaign has been active since April, so 30 days is the floor rather than the target. Triage every hit by hand, then retire it.

```kusto
// Retro-hunt only. Do NOT schedule this as an analytic rule.
// Widen the 30d windows to match your retention; campaign dates to April 2026.
let actorAsns = dynamic(["57724", "59692"]);  // DDoS-Guard, IQWeb: pull current infra from RF first
let regs =
    AuditLogs
    | where TimeGenerated > ago(30d)
    | where LoggedByService == "Authentication Methods"
    | where OperationName in ("User registered security info",
                              "User registered all required security info")
    | where Result == "success"
    | extend UPN = tolower(tostring(TargetResources[0].userPrincipalName))
    | project RegTime = TimeGenerated, UPN, RegOperation = OperationName;
SigninLogs
| where TimeGenerated > ago(30d)
| where AutonomousSystemNumber in (actorAsns)
| where ResultType == "0"
| extend UPN = tolower(UserPrincipalName)
| project SignInTime = TimeGenerated, UPN, IPAddress, ASN = AutonomousSystemNumber,
          Location, AppDisplayName, UserAgent
| join kind=inner regs on UPN
| where RegTime between (SignInTime .. (SignInTime + 1h))
| project UPN, SignInTime, RegTime, IPAddress, ASN, Location, AppDisplayName, UserAgent, RegOperation
| order by RegTime desc
```

Two caveats that matter. DDoS-Guard and IQWeb are shared hosters, so an ASN match is a reason to look, not proof of compromise, so triage the hits rather than paging on them. And pull the current infrastructure from Recorded Future before you run this, because the ASNs Okta published in July will not be the ASNs in use by the time you read this.

The reason to keep this query firmly in the retro-hunt bucket is the failure mode if you don't. An IOC-anchored rule that runs on a schedule keeps returning zero results long after the actor has re-hosted, and a rule returning zero looks exactly like "we're clean" when it actually means "my indicators are stale." That's worse than having no rule, because it buys false confidence. Which is why the standing detection has to be the next one.

### 3. The standing detection

This is the one you deploy. It flags a security-info registration within 60 minutes of a sign-in from an ASN the user hasn't touched in the prior two weeks. There's no indicator dependency anywhere in it, so it survives the actor re-hosting, and it will catch the next group that runs this play with entirely different infrastructure.

```kusto
let lookback = 14d;
let userAsnBaseline =
    SigninLogs
    | where TimeGenerated between (ago(lookback + 1d) .. ago(1d))
    | where ResultType == "0"
    | summarize KnownAsns = make_set(AutonomousSystemNumber)
        by UPN = tolower(UserPrincipalName);
let recentSignins =
    SigninLogs
    | where TimeGenerated > ago(1d)
    | where ResultType == "0"
    | extend UPN = tolower(UserPrincipalName)
    | project SignInTime = TimeGenerated, UPN, IPAddress,
              ASN = AutonomousSystemNumber, Location, UserAgent;
let recentRegs =
    AuditLogs
    | where TimeGenerated > ago(1d)
    | where LoggedByService == "Authentication Methods"
    | where OperationName in ("User registered security info",
                              "User registered all required security info")
    | where Result == "success"
    | extend UPN = tolower(tostring(TargetResources[0].userPrincipalName))
    | project RegTime = TimeGenerated, UPN, RegOperation = OperationName;
recentRegs
| join kind=inner recentSignins on UPN
| where SignInTime between (RegTime - 60m .. RegTime)
| join kind=leftouter userAsnBaseline on UPN
| extend FirstSeenAsn = isnull(KnownAsns) or not(set_has_element(KnownAsns, ASN))
| where FirstSeenAsn
| project UPN, SignInTime, RegTime, IPAddress, ASN, Location, UserAgent, RegOperation
| order by RegTime desc
```

Tune the window and the baseline period to your environment. A legitimate first-time passkey enrollment on a new corporate egress will trip this, which is fine, because a human should glance at a passkey enrollment tied to a never-before-seen network anyway. That's the point of a source that earns its keep: the false positives are still worth a look.

### 4. The exfil stage

Account takeover is only the means; SharePoint and OneDrive theft is the end, so watch for the mass-download pattern. `OfficeWorkload`, `Operation`, `UserId`, `ClientIP`, and `SourceFileName` are all verified `OfficeActivity` columns; `FileDownloaded` and `FileSyncDownloadedFull` are the canonical download operations.

```kusto
OfficeActivity
| where TimeGenerated > ago(24h)
| where OfficeWorkload in ("OneDrive", "SharePoint")
| where Operation in ("FileDownloaded", "FileSyncDownloadedFull")
| summarize FileCount = count(),
            DistinctFiles = dcount(SourceFileName),
            SampleFiles = make_set(SourceFileName, 25),
            IPs = make_set(ClientIP, 10),
            FirstSeen = min(TimeGenerated),
            LastSeen = max(TimeGenerated)
    by UserId
| where DistinctFiles > 200   // tune to your environment's normal
| order by DistinctFiles desc
```

Correlate a hit here back to Query 3 on `UserId` / `UPN`. A first-seen-ASN sign-in, a passkey registration, and a download spike on the same account inside a few hours is the whole kill chain in three tables.

## Hardening

Detection is the backstop; the cheaper wins are upstream, and they're all in the vendor guidance:

- Constrain who can self-enroll. Restrict passkey (FIDO2) self-service setup, and where feasible require enrollment from a managed/compliant device via Conditional Access. If a registration campaign is driving your rollout, scope it rather than leaving the nudge on by default tenant-wide.
- Treat inbound "enroll a passkey" calls as hostile by default. Any passkey/MFA enrollment request that originates from a phone call the user didn't initiate should be verified out-of-band through a known channel before anyone touches a URL.
- Verify the help desk, both directions. Establish a scripted way for users to confirm they're actually talking to IT, and for IT to confirm the user, before any credential change.
- Audit existing passkeys on privileged accounts. Don't assume "MFA is on" means the account is clean. Review which passkeys are enrolled, and flag names that look off or enrollments you can't tie to a known device.

## Where this leaves the invoice argument

The Entra authentication-methods audit stream is not a glamorous source: it isn't big, it doesn't light up dashboards, and if you asked most SOCs to justify its retention they'd shrug. But run the three-question test on it and it goes three for three, because it enables a detection (attacker passkey enrollment), it speeds an investigation (the full ATO-to-exfil chain lives across it and two sibling tables), and it satisfies a compliance obligation (credential-change auditing). That's the profile of a source worth paying for, and it's the same source most orgs already ingest without ever pointing a detection at it.

Which is the actual argument. Collecting deliberately only pays off if you then point something at what you collected.

---

*Sources: Okta Threat Intelligence (July 6, 2026); Palo Alto Networks Unit 42; corroborated across BleepingComputer, SecurityWeek, The Hacker News, and TechNadu reporting. Table and field references verified against Microsoft's Azure Monitor `AuditLogs`, `SigninLogs`, and `OfficeActivity` schema documentation prior to publication.*

*Disclosure: written with AI assistance. The threat model, the KQL, and the opinions are mine.*
