# Optional goals and limits: now, later or never

## What exists today (from the code and the idea file)

- A habit holds a name, unit, category, archived flag, owner and creation time (`lib/data/vice.dart`). No goal,
  limit or target exists anywhere in `lib/`.
- Today's tally row shows a coloured dot, the habit's name, the day's total and a + that logs one
  (`lib/widgets/tally_row.dart`). It never compares the total with anything.
- Trends draws the habit's daily or weekly totals, a moving average, total / average / peak, and a cursor line
  (`lib/trends/trends_chart.dart`). No horizontal reference line.
- Insights already finds "where the line is" in an amount, per habit and Health measure, e.g. "On days with 3
  glasses or more logged for Wine, your deep sleep that night averages 18 min less than on days with fewer"
  (`lib/insights/insights_report.dart`, kind `doseLine`). The code's own definition: the cut that best splits your
  days, tested against every cut it tried, and "not a claim that nothing changes under the line"
  (`lib/insights/what_follows.dart`).
- Jack's earlier calls: the app is a neutral journal; harm-reduction, moderation and quit-counter positionings were
  rejected; "cutting down may coexist, but the journal is the point"; a clean day is quietly positive with no streak
  pressure; new optional fields on habits are allowed without a further call. The idea file's only recommendation
  (Claude's, never decided): a daily or weekly limit per habit, set in the habit's settings, after the paid 1.1,
  free; never in onboarding; never a limit taken from public health guidance.

## Option A: leave as is (never build)

What Jack sees: nothing changes (`optionA.html`: today's Today, Trends and the existing Insights card).
Effort: none. Risk: none to the product's stance. Cost day to day: none.
What he gives up: someone who wants to stay under a number does the comparison in his head against the tally;
Insights' line stays a finding with nothing to act on in the app.

## Option B: a quiet personal line per habit (recommended)

What changes:
- Edit Habit gains "Your line (optional)": None / A day / A week, and a stepper. Default None.
- Today: a habit with a line shows "of 3" beside its total and a thin bar under the row with a tick at the line.
  Going over runs the bar past the tick in the same habit colour. No red, no alerts, no streaks, no "clean day"
  change. A habit without a line looks exactly as now. A weekly line counts the last 7 days, the same rolling
  weeks Trends uses ("22 of 30 · 7 days").
- Trends: a dashed line labelled "your line 3" across the chart, and "days over your line" replaces "peak" in the
  stats. A weekly line shows in the by-week view; in the by-day view a caption says so (inferred design choice).
- Nothing in Insights, reminders or onboarding mentions it.

Effort: M, about 3 days. Two optional fields on the habit (amount, and day or week), sealed with the habit's other
content because a line says what the person intends (inferred: the update path reseals all content, so the
Firestore rules likely need no change, to confirm in the build); the form; a last-7-days total for Today's weekly
line (one more query of an existing shape and index); the Trends line; tests.
Risks: drifts toward a reduction tool if the copy slips (mitigated: off by default, neutral words, no colour
change); one more number on a crowded row at large text sizes (the total already shrinks first, per the row's code);
the weekly total adds a query to Today.
Cost day to day: taps per log unchanged (still 1). Setting a line: open the habit, Edit, pick, step, Save, once.
Permissions asked: none.

## Option C: B, plus Insights offers its line

Everything in B, and on an Insights "line in the amount" card (only when the habit has no line yet) a button
"Mark 3 a day as Wine's line", with Undo. `optionC.html` shows the card and the confirmation.
Effort: M, about 4 days (B plus a day).
Risks: turns a statistical finding into something that reads as advice. The cut is simply where the data split most
cleanly, which the code says is not a safe threshold; it can move or vanish as more days come in, leaving a line
that no longer matches any finding. It is the first place the app proposes a number to the person, which is the
step toward the moderation positioning Jack rejected. It also appears only for habits with a sleep or Health finding.
Cost day to day: as B; setting a line can be 1 tap from Insights. Permissions: none new (Insights already uses
Health where granted).

## Timing

B or C can be built at any point; nothing depends on 1.1 except that the idea file assumed after it. Both would be
free. "Later" is A for now with the same choice reopened after 1.1.

## Recommendation

**B, free, built after the items already queued for this run (not tied to 1.1).** It is the smallest thing that
serves someone who wants a number without changing the app for anyone who does not: off by default, invisible
until set, no colour, alerts or streaks, consistent with the neutral-journal call. C's one-tap offer is not worth
its cost: the Insights line is defined as the best split of past days, explicitly not a safe amount, so offering it
as a limit would say something the analysis does not support. A is a fair choice if Jack wants no comparison of any
kind in the app; it costs nothing to revisit.
