# Sell a weekly insights report computed on the device

**Priority:** monetisation

## What

A weekly summary covering:

- totals against each limit;
- the change from last week;
- the busiest day and time of day;
- the vices that tend to be logged on the same days.

It builds on the usage graph's existing day/week bucketing and moving average, and needs no new fields.

A second step adds optional context to each log: a mood score from 1 to 5, situation chips (social, alone, stressed, bored, celebrating), and an "urge resisted" log that records a craving without consumption.

## Why

- INFERENCE: users pay for reflection, not for logging. A weekly report gives Pro its clearest ongoing value. If Jack later chooses a subscription, this is what justifies it under [3.1.2(a)](https://developer.apple.com/app-store/review/guidelines/).
- SOURCED ([market scan](../market-scan.md)): Sunnyside and Reframe charge for coaching-style insight.
- SOURCED (Apple 5.1.2(i)): sending vice data to a third-party AI needs explicit permission. 1.4.1 rules out treatment claims.
- INFERENCE: logging resisted urges gives positive reinforcement on a day whose count is not zero, which is core harm-reduction practice.

## Options

- **A.** An on-device weekly report from the existing data, sold as Pro.
- **B.** A, plus context tags and urge logging. This adds optional fields to `activities`.
- **C.** B, plus an opt-in AI coach through an LLM API. It needs a consent screen and a server proxy, and its per-user cost suits a subscription, not a one-time unlock.

## Recommendation

Claude's recommendation, not a decision: **A as the first Pro expansion after 1.1, then B.** On-device statistics keep the privacy story intact and need no backend. B goes through the same data-shape question as [per-vice goals](../v1-must-haves/per-vice-goals-and-limits.md). C is worth considering only if Jack picks a subscription.

**Effort:** L

**Revenue impact:** Medium to high over time. It is the main reason to buy Pro after the history gate.

**Depends on:**
- [per-vice goals](../v1-must-haves/per-vice-goals-and-limits.md)
- [business model](business-model-and-paywall.md)
- [`weekly-bucketing-leaves-a-short-trailing-bucket`](../../tech-debt/widget-state-and-view-logic/weekly-bucketing-leaves-a-short-trailing-bucket.md)
- [`graph-build-method-recomputes-everything`](../../tech-debt/widget-state-and-view-logic/graph-build-method-recomputes-everything.md)

**Needs Jack:** no
