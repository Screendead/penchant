# Close each week with a review of what the journal found

**Priority:** insights (1.1, Pro)

## What

Every Monday, a review screen (and an optional local notification) shows:

- the week's totals per vice against the user's own previous four weeks, with no judgement attached;
- the busiest hours and the most common triggers;
- any insight card that newly passed the [engine's](insights-engine.md) gates, and any that stopped holding;
- what is still collecting data.

It is computed on the device from the engine's store.

## Why

- SOURCED ([Exist](https://kb.exist.io/article/18-how-long-does-it-take-to-find-correlations)): Exist recalculates
  weekly and publishes new correlations on Mondays. SOURCED ([Daylio](https://apps.apple.com/us/app/daylio-journal/id1194023242)):
  Daylio sells weekly reports. INFERENCE: a weekly cadence gives the engine fresh data between runs, so it reports
  fewer flickering results, and gives users a reason to return.
- SOURCED (C15, C17): insights are the point, sold as a one-time unlock.

## Options

- **A.** A weekly review screen in Pro.
- **B.** A, plus a shareable image of the week (no raw numbers by default).
- **C.** An opt-in AI-written summary through an LLM API. It sends journal data off the device, against C15's privacy
  condition, and its running cost suits a subscription, not a one-time unlock.

## Recommendation

Claude's recommendation: **A, with the engine in 1.1.** Skip C under the current calls.

**Effort:** M (on top of the engine)

**Revenue impact:** Medium to high: the recurring moment that shows Pro working.

**Depends on:** [insights engine](insights-engine.md); [business model](../monetisation/business-model-and-paywall.md).

**Needs Jack:** no
