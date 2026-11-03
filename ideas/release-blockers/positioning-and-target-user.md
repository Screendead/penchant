# Position the app as a neutral journal for learning about yourself

**Priority:** release blocker

## What

The app is a journal for the things people consume or do by habit. They log each one in detail, and the app shows
the trends and what goes with them, so the user learns about themselves. Cutting down can coexist as an optional goal
(see [optional goals](../growth-later/optional-goals-and-limits.md)), but the journal and its insights are the point.
What remains to build is the copy that says so: the store description and keywords, the onboarding line, the About
text, and a short tone guide that every later screen follows.

## Decision

Decided by Jack 2026-11-03 (C15): **a neutral journal, for seeing trends and learning about yourself.** His note asks
for intelligent insights into what causes use (calendar events; triggers that get more specific as you drill down and
remember your common ones; free text) and what follows from using one vice against another (Apple Health, including
historical data, telling apart which vice a health effect goes with), at maximum granularity, with sensitive
processing and storage on the device. Set aside: multi-substance moderation, alcohol-only moderation, and a
quit/streak counter.

## Why the copy matters

- SOURCED ([market scan](../market-scan.md)): the self-tracking journals (Bearable, Exist, Daylio, Welltory) sell
  correlation insight; the vice apps (Reframe, I Am Sober, Quitzilla) sell reduction or abstinence.
- INFERENCE: no listing the scan found combines detailed vice logging with health and calendar correlation, so the
  copy has to name both halves, or search files the app with one of them.
- SOURCED (C16): the framing is neutral, so the copy describes and never judges: "logged", never "slipped"; "nothing
  logged", never "clean".
- SOURCED (PR #53): logging works with no signal; entries are kept on the device and marked until they sync. The
  offline idea that shipped it ended with "put 'works offline' in the store copy"; that step lives here now.
- INFERENCE ([market scan](../market-scan.md)): positioning on the competitors' main complaints would be "no
  dark-pattern billing, private data, works offline".

## Recommendation

Claude's recommendation: lead the listing on the question the app answers ("what goes with your habits?"), then four
proof points: detailed logging with triggers, insights computed on your device, logging that works with no signal, no
subscription. Write the tone guide as part of [neutral framing](neutral-framing-and-age-rating.md), and spend the
keyword field on terms the subtitle leaves out (journal, habits, triggers, sleep, HRV).

**Effort:** S (copy)

**Revenue impact:** Foundational. It sets the audience (self-trackers who pay for insight, not people in a recovery
programme) and the price anchor.

**Depends on:** [brand name](brand-name.md).

**Needs Jack:** no
