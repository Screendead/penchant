# Pick the brand: Penchant, with a descriptive subtitle

**Priority:** release blocker

## What

C19 fixed the pattern, "\<Brand\>: \<descriptive subtitle\>"; this pitch picks the brand. The brand has to suit a
neutral self-insight journal: about leanings and patterns, not vice or sobriety; short; easy to say and spell; free
of a same-category App Store app or a well-known software mark.

## Candidates

Quick checks run 2026-11-03 by web search of App Store listings, a web search for brand and trademark conflicts, and
DNS, whois and registry lookups. **This is a quick check, not legal clearance:** no USPTO, EUIPO or UKIPO search was
run, and "no app found" means web search surfaced none. Every exact `.com` and `.app` for every name below is
registered (mostly parked or for sale), so plan on a variant (`get<name>.app`, `<name>journal.com`) or a purchase.

| Brand | Rationale | Quick check | Verdict |
|---|---|---|---|
| **Penchant** | A habitual liking: names the leaning without judging it. | No app found; no software or wellness brand found. `.com` held through MarkMonitor since 1995 (a brand owner, unknown); `.app` parked. | Clear-ish |
| **Kenning** | Old English "knowing": self-knowledge. | No app or notable brand found. `.com` parked; `.app` has a live site, content unclear. | Clear-ish |
| **Sounding** | A depth reading: measuring what lies beneath. | No app or brand found. `.com` hosts a site titled "Sounding"; `.app` parked. | Clear-ish |
| **Tendency** | Plain word for a pattern. | No exact app; "Tend: Habit Tracker" and "Tenday" are close. `.com` live; `.app` parked. | Clear-ish, bland |
| **Plumb** | To plumb: to get to the bottom of something. | No app found, but "Plume - Journaling" sounds alike. `.com` resolves with no page; `.app` parked. | Clear-ish, sound-alike risk |
| **Wont** | "As is my wont": habit, archaic and neutral. | No exact app; "dont - break bad habits" is the same idea. `.com` live; `.app` 404. | Clear-ish, reads as a typo of "won't" |
| **Leaning** | What you lean towards. | No app or brand found. `.com` 403; `.app` registered, no site. | Clear-ish, weak and has a political sense |
| **Tidemark** | The line a tide leaves: trends over time. | No iOS app; Tidemark is a live enterprise-planning software company (tidemark.com). | Crowded |
| **Proclivity** | A natural inclination. | No app; Proclivity Systems is a funded healthcare-marketing tech firm. | Crowded, health-adjacent mark |
| **Bearing** | Where you are heading. | No exact app, but sounds like Bearable, a direct competitor. | Crowded |

Dropped after the check, with the conflict found: **Habitus** (a habit app, and a "reflection journal, no streaks"
web app with almost this brief; a US filing in April 2026), **Inkling** ("Inkling: Start Journaling"), **Cairn**
("Cairn: Reflect & Grow" and a trail-safety app that owns `cairn.app`), **Undercurrent** (a private symptom log in
Health & Fitness, updated October 2026), **Almanac**, **Marginalia**, **Telltale** (Telltale Games), **Tally** (several
habit counters, one pricing bad habits), **Vane** ("Vane: Habit Tracker"). Evidence URLs are in the
[market scan](../market-scan.md).

## Subtitle and bundle ID

- **Subtitle pattern:** \<what it is\> + \<what it finds\>, within App Store Connect's 30-character subtitle (from
  memory, to verify). For example "Habit journal & sleep insights" (30), "Habit & trigger journal" (23).
- **Bundle ID:** `com.screendead.<brand>`, for example `com.screendead.penchant`, on both iOS and macOS, so the Mac app
  can share the iPhone app's record and its Pro purchase (universal purchase; from memory, to verify in App Store
  Connect help). It replaces the doubled `com.screendead.tracker.tracker`, and it cannot change once a build is
  uploaded.

## Recommendation

Claude's recommendation: **Penchant**, with "Habit journal & sleep insights" as the subtitle. It is the only clear-ish
name that says "this is about your leanings" without saying "vice" or "problem", it reads well in the pattern, and the
check found no app or software brand on it. Backups: Kenning, then Sounding. Before committing: a direct App Store
search on a device, a trademark search in classes 9, 42 and 44 (USPTO, UKIPO, EUIPO), and a decision on the domain
variant.

**Effort:** S. The rename itself is [name and bundle ID](name-and-bundle-id.md).

**Revenue impact:** Direct, through search and store conversion; a rename after launch costs reviews and ranking.

**Depends on:** [positioning](positioning-and-target-user.md).

**Needs Jack:** yes — Which brand (recommended: Penchant), which subtitle, and should a trademark search be paid for
before the first TestFlight upload?
