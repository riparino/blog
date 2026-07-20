---
title: "Directions, Not Numbers"
date: 2026-07-20 05:00:00 -0700
tags: [side-projects, rc-racing, tuning, cloudflare-workers, react]
---

Five posts in nine days about telemetry economics, triage layers, and poisoned instruction files. This one is about none of that. On weekends I race 1/8-scale off-road buggies, and over the last couple of weekends I built two small tools for race day: a track-condition tuning sheet and a "when's my race up" clock. Both are an evening's worth of code, and neither contains a single line about security.

I set out to write a post that didn't either. I failed, because the same three habits I spend all week defending showed up at the pit table without being invited. I'll point at them when they appear, briefly, and then we can all go back to arguing about shock oil.

## Pick a car, pick a surface, get a direction

The tuner is one React component, no build step required, that answers the question every heat of every club race starts with: the track changed, what do I change? It covers six buggies across Mugen, Mayako, and Tekno — a nitro and electric pair from each brand — and six surfaces, from blown-out dust bowl to blue groove to mud. Pick the car, pick the condition, and it gives direction across eleven setup categories: diffs, shock oil and pistons, springs, bars, links, ride height, toe, steering geometry, tires, wing, and the nitro-vs-electric stuff at the bottom.

The design decision that makes it work is in the word *direction*. The app almost never tells you a number. It tells you a move:

```js
bumpy: {
  diff: [
    { s: "Front diff",  d: "HOLD —",    v: "baseline",
      n: "Not the first lever for bumps." },
    { s: "Center diff", d: "THINNER ▼", v: "one step down (or more — see car note)",
      n: "Softer power delivery keeps the rear from skating over chop on throttle." },
    { s: "Rear diff",   d: "THICKER ▲", v: "one step up",
      n: "Keeps both rear wheels driving when one is airborne through holes." },
  ],
  ...
}
```

That's not laziness; it's the only honest way to write a multi-car tuning sheet. The kit baselines these cars ship with are genuinely different philosophies. Mugen sends the MBX8R out with 5k/5k/2k diffs and #550 shock oil, and runs that unusually thin center even on the electric car so the Eco drives like its nitro sibling. Tekno's 2.2 kits are 7k/5k/5k with dual-piston shock stacks and a 24/26mm ride height — already race-tuned for rough tracks out of the box. Mayako publishes medium-THICK-medium as an explicit design philosophy and means it. An absolute number — "run 450 oil," "run a 7k center" — is correct for one of those cars and quietly wrong for the other five. The direction survives on all six: *one step thinner, because the shocks have to cycle faster than the chop.* The number is a property of the car. The reason is a property of the physics.

Readers of [the detection-altitude post](/2026/07/16/detection-altitude-is-a-collection-strategy.html) can see where this is going, so I'll keep it to one paragraph: a direction relative to a baseline is a behavior, and an absolute setting is an indicator. "Run 450 oil" is a hash — right until the platform underneath it changes, then silently wrong. "One step thinner than *your* baseline, for this reason" transfers across every car in the pits, the same way a detection written against the skeleton transfers across campaigns. I did not plan for my hobby app to restate the Pyramid of Pain. It did anyway, because relative-to-baseline is just what durable advice looks like.

Two smaller things I want on the record. First, when the factory has spoken, the factory wins: the app carries per-car overrides, so on a rough track the Mayako card tells you to drop the center to 5–7k — a huge move off its own thick baseline — because that's Mayako's published rough-track guidance, not my opinion. Second, provenance is marked. The README separates what came from a kit manual, what came from the lube bag in the box, and what's community practice, and every unconfirmed value renders with a ≈ in front of it. I spent [a whole post](/2026/07/13/the-passkey-enrollment-log-finally-earns-its-keep-hunting-o-unc-066.html) making a point of stating attribution confidence plainly. Shipping a tuning sheet that laundered forum consensus into factory spec would have been an embarrassing way to end the week.

## When's my race up

The second tool exists because of a failure mode every club racer knows: you're races 14, 38, and 61 on an eighty-race day, LiveRC tells you what's *completed*, and somewhere around race 30 you wander to the pit table, open a diff, and hear your class called to the stand with your car in eight pieces.

`rc-timer` started as a Python script polling LiveRC from a terminal and grew into a Cloudflare Worker anyone at the event can open on their phone. Track subdomain, driver name, done — the URL is shareable, it refreshes every 75 seconds, and each of your remaining races shows an ETA and a countdown. At twenty minutes out the row turns red and says GET READY, with an optional push notification.

The part I actually care about is how the ETA is computed, because the obvious approach — multiply races remaining by "about eight minutes" — is a static assumption, and race days do not honor static assumptions. Instead the worker measures the day it's actually having:

```js
/**
 * Compute race pace from completion timestamps.
 * Uses the 25th percentile of inter-race gaps so ETAs err on the early side.
 */
export function measuredPace(completions) {
  if (completions.length < 4) return { paceMinutes: DEFAULT_PACE_MIN, samples: 0 };

  const times = completions.slice(-(PACE_WINDOW + 1)).map(c => c.completedAt);
  const gaps = [];
  for (let i = 0; i + 1 < times.length; i++) {
    const g = (times[i + 1] - times[i]) / 60000;
    if (g > 0 && g <= BREAK_GAP_MIN) gaps.push(g);
  }
  if (gaps.length < 3) return { paceMinutes: DEFAULT_PACE_MIN, samples: gaps.length };
  return { paceMinutes: percentile(gaps, 25), samples: gaps.length };
}
```

Pace is the gap between consecutive completed races over the last twelve, with anything longer than twenty minutes discarded as a lunch break rather than cadence. The anchor is the most recent completion, so every finished race re-anchors the whole forecast and delays self-correct on the next poll. When a race is actively running, a socket connection to LiveRC's live timing tightens the anchor in real time off the race clock.

And it's the 25th percentile, not the median, which is the one deliberate bias in the whole tool. The two failure modes are not symmetric. An estimate that runs early costs you five minutes of standing at the drivers' stand watching someone else's main. An estimate that runs late costs you the race you spent a week preparing for. So the estimator is tilted toward the cheap failure on purpose — which regular readers will recognize as the same argument as fail-open triage in [Page on Decisions, Not Alerts](/2026/07/14/page-on-decisions-not-alerts.html): when you must be wrong, choose the direction of wrongness whose cost you can afford. Same logic, better weather.

The other habit that snuck in: the tool names its own evidence gaps. Early in the day, before three clean inter-race gaps exist, the API doesn't silently pretend it knows the pace — it returns a warning: `Pace is the 8-min default — only 2 usable gaps so far`. Parse failures on a heat sheet don't vanish either; they come back as warnings naming the round that couldn't be read. Missing evidence is itself evidence, even when the case being adjudicated is whether you have time for a sandwich.

Under the hood it's the unglamorous kind of engineering: regex over LiveRC's HTML (no DOM in a Worker), unit tests running against fixtures of real captured pages so parser changes can't silently rot, and a 45-second per-track cache so a whole pit lane of drivers watching the same event costs LiveRC one fetch cycle instead of forty.

## The bill

Small tools still get an honest invoice. The timer is a screen scraper, and screen scrapers are a standing bet that someone else's markup won't change; the fixtures, the tests, and the warnings channel are the hedge, not a fix. The tuning sheet is direction, not gospel — the ≈ values are typical for the platform, unconfirmed by anyone with a dyno, and the app's own footer tells you to change one thing at a time. And both tools were built in evenings with a coding agent doing most of the typing, which, three posts after [The Payload Is a Sentence](/2026/07/15/the-payload-is-a-sentence.html), means yes — I read every diff. It would take a certain amount of nerve to publish that post on Wednesday and merge unreviewed agent output on Saturday.

## The synthesis

I went to the track to stop thinking about detection engineering and came home having rebuilt it in miniature, twice. Know your baseline and express every change as a direction relative to it, because directions transfer and numbers don't. Measure the thing instead of assuming it, re-anchor on every new observation, and when you must be wrong, be wrong in the direction you can afford. Say plainly what's confirmed, what's typical, and what you simply don't know yet.

The last line of the tuning sheet reads: *change one thing at a time and let tires do the first 70% of the work.* Swap two nouns and it could close a detection backlog review. Apparently the discipline doesn't care whether the thing being tuned is a rule set or a buggy — which is either reassuring or a sign I need a second hobby.

---

*Sources: kit baselines from the Mugen lube bag, the Tekno manuals, and Mayako's setup wiki, as marked in the tuner's README; everything with a ≈ is community practice, not factory spec.*

*Disclosure: written with AI assistance, like the tools themselves. The setups, the scraped heat sheets, and the main event I missed with a diff in pieces are all mine.*
