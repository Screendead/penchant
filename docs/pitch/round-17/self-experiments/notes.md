# Self-experiments: whether to build them

The question: should Penchant turn one of its findings (say, "on nights after Wine, your deep sleep averages 14 min
less") into a planned test? The app would pick evenings at random, Jack would follow the plan, and at the end the app
would report the difference with an honest range.

## What exists today (from the code)

- Insights (iPhone only; the Mac shows "Available on iPhone", `lib/insights_page.dart`) compares Health measures on
  nights after days with a habit against nights without it. Every habit and measure goes into one model.
- A card shows only when it passes these checks: at least 21 usable days, with 7 days with the habit and 7 without
  (`lib/insights/what_follows.dart`); a correction for testing many habits and measures at once (false-discovery rate
  0.1); a minimum size per measure; and a range that excludes zero.
- Each card shows a sentence, a range bar, "Range: 6 to 22 min less" and "From 212 days, 61 of them with Wine"
  (`_FindingCard`, `findingSentence`, `findingRange`, `findingBasis`). The numbers in the mock-ups are invented.
- The wording says "goes with", never "causes". The page's footnote says a pattern "doesn't show that one thing causes
  another". A self-experiment exists to close that gap. For example, Wine might fall on late, social evenings, and the
  late night might be what costs the deep sleep.
- Notifications already exist. They are the daily reminder and the Monday weekly review (`lib/reminder/daily_nudge.dart`,
  through `flutter_local_notifications`). Both are off until switched on in Settings > Reminder, which is when iOS asks
  permission. The weekly review's text "says nothing about your journal" (`lib/reminder_settings.dart`).
- The ideas file lists experiments as option C of the insights engine (`ideas/insights/insights-engine.md`). The backlog
  puts them under "Later" (`ideas/README.md`).

## Something to know before choosing: an honest test takes about 6 weeks, not 2

The test compares nights on random "none" days with nights on "as usual" days. How sure the answer is depends on how
much the measure already varies from night to night. The figures below are my calculation, using the standard formula
for comparing two group averages (a 95% range from the t-distribution). I assumed deep sleep varies by about 16 min
from night to night. That spread is an assumption: I cannot see Jack's Health data. The plan screen would use his real
spread.

| Length | Nights each way | Answer good to about |
|---|---|---|
| 2 weeks | 7 | ±19 min |
| 4 weeks | 14 | ±12 min |
| 6 weeks | 21 | ±10 min |
| 8 weeks | 28 | ±9 min |

- **The 2-week test in the original idea cannot settle a 14-minute effect.** Its range would almost always include zero.
- **Six weeks usually can.** By my calculation, if the true effect is 14 min, the result excludes zero about 4 times
  in 5.
- **Smaller true effects need longer.** Findings drawn from past data tend to overstate their effect (inferred, a
  general statistical tendency). So a real effect may be smaller than 14 min, and the likeliest disappointing result
  is "can't tell", not "no effect".
- **Both mock-ups show both outcomes.** The result screens show a clear answer and a "can't tell" card.

The rule is always "none after 18:00" against "as usual", never "have Wine". So the test measures what skipping evening
Wine does, compared with his normal evenings. The app never tells him to drink.

## Option A: leave as is

- **What he'd see:** nothing changes (`optionA.html`). Findings stay "goes with".
- **If he wanted to test one himself:** he could change his evenings without the app's help. Insights would pick up
  the change eventually, but the days would not be random, so it proves no more than today's cards do.
- **Effort:** none. **Risk:** none.
- **Day to day:** nothing.

## Option B: experiment from a finding card, shown in the app only

- **What he'd see** (`optionB.html`):
  - A "Test this for 6 weeks" button on a sleep, heart or activity finding.
  - A plan screen: the rule, a length picker that shows the expected certainty for each length, start and end dates,
    and how many "none" days there are. Each week gets 3 or 4 of each kind of day, so weekends fall on both sides.
  - A strip on Today above the dial: "No Wine after 18:00 today · day 9 of 42", with the evening shaded on the dial.
  - A result card in Insights when the plan ends.
- **What the result card shows:**
  - The difference and its range.
  - Nights counted.
  - Days the plan was kept, read from his own logs. Wine logged after 18:00 on a "none" day is a missed day, and it
    still counts as a "none" day, which keeps the comparison fair.
  - The old finding, for comparison.
  - "Can't tell" with "Run it 4 more weeks" when the range includes zero.
- **What it involves under the hood:**
  - The days come from a stored random seed, so the plan is a few numbers.
  - The analysis reuses the existing Insights maths. A randomised comparison is simpler than what Insights already
    fits.
  - Nothing new is logged. Adherence comes from the journal.
- **Where the plan lives (my design choice):** on the iPhone only, in an encrypted file in Application Support. The
  existing encrypted files sit in Caches, which iOS can clear, and a 6-week plan must not vanish. Because the plan is
  on the iPhone only, the Mac's Today would not show the day's assignment. Syncing the plan through Firestore would fix
  that, but it means a new collection, a rules change and rules tests: about 1 more day.
- **Effort:** M, about 4 to 5 days (my estimate). That covers the plan screen, the day schedule, the Today strip, the
  analysis, the result card, the storage and the tests.
- **Risks:**
  - He only learns a day's assignment when he opens the app. The decision about Wine is made in the evening, often
    with the app shut. Missed days dilute the result toward "can't tell" (inferred).
  - The test cannot be blind: he knows which kind of day it is. Watch-measured sleep is less prone to expectation
    than mood ratings, but not immune (inferred).
  - A late Wine on a "none" day can carry over to the next night. That adds noise, not bias, because days are random
    (inferred).
- **Day to day:** taps per log are unchanged. No permissions are asked. The real cost is about 21 evenings without
  Wine after 18:00 over 6 weeks, and remembering to look at Today.

## Option C: option B plus a daily notification with the day's assignment

- **What he'd see** (`optionC.html`): everything in B, plus a notification at a time he picks (17:30 in the mock-up):
  "Experiment, day 9 of 42. Today is a none day, from 18:00."
  - It never names the habit, in line with the weekly review notification. Anyone glancing at his lock screen learns
    nothing.
  - Tapping it opens Today with the strip.
- **Extra effort:** about 1 day on top of B. The notification plugin and the permission handling already exist; this
  adds one more scheduled message whose text changes each day. M overall, about 5 to 6 days.
- **Permissions:** if the daily reminder is already on, nothing new is asked. If not, iOS asks once when he turns on
  the experiment's notification. It is optional; without it, C works like B.
- **Risks:** as B, minus most of the "didn't know today's assignment" risk.
  - iOS keeps at most 64 pending local notifications per app. That is from memory and not checked here. A 6-week plan
    is 42 of them, beside the reminder's, so the app would schedule a rolling week and top it up whenever it opens.
  - A notification left on during a trip or illness is noise. Pausing the plan would need a "Pause" (not mocked).
- **Day to day:** taps per log are unchanged. One quiet notification a day while a test runs, and none otherwise.

## A wording call that comes with B or C

The result card is the first place Penchant could say more than "goes with". The mock-up says "on the nights you had
no Wine after 18:00, your deep sleep was 12 min more". That is factual, and the random days are what make it mean
cause. "Skipping Wine raised your deep sleep" would be stronger, and still honest for a randomised test. This wording
is Jack's call.

## Recommendation: C, built after the current Insights work

Reasons:

1. **The assignment has to reach him at the moment he decides, in the evening.** B depends on him opening the app
   first. Every missed day weakens a 6-week test that is already only just sure enough. C closes that gap for about one
   extra day of work, and it adds no permission prompt if the daily reminder is on.
2. **It answers the one question Insights cannot: whether Wine causes the drop or just comes with it.** It uses
   numbers the app already has, and he logs nothing extra.
3. **The plan screen is honest about length.** It states the expected certainty before he commits. A 2-week test
   would mostly come back "can't tell", which would undermine trust in Insights.

The test of whether to do it at all is whether he would actually spend 6 weeks with half his evenings free of Wine
after 18:00. If not, A is the right answer, and nothing is lost: Insights keeps working as it does. Timing: after the
current Insights steps (the literature-based minimum sizes are next), since experiments build on findings that have
passed every check.
