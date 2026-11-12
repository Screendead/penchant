# Build an on-device insights engine that separates vices and refuses to report noise

**Priority:** insights (1.1, Pro)

## What

One Dart module, run in a background isolate, that turns the journal plus Health and Calendar into insight cards.

**Where data lives.** Raw logs stay in Firestore, the only source of truth. Health samples and calendar events stay in
the system stores and are read on demand. The engine keeps one local SQLite file per device: daily features (each
vice's total and timing, triggers, context, check-in state), nightly Health aggregates, calendar features, and the
fitted results. Nothing in it is synced or backed up (excluded from iCloud backup), and it is deleted with the
account.

**How it regenerates.** The file carries the engine version and a watermark per source (Firestore update time, a
HealthKit anchor, the calendar change token). New data recomputes only the affected days; a new engine version, a
changed schema or a corrupt file drops it and rebuilds from scratch. INFERENCE: a few years of daily rows is a few
thousand rows, so a full rebuild takes seconds.

**Two families of insight.**

- *What comes before use:* hour-of-day and weekday patterns, the most common triggers per vice (at the deepest
  trigger level with enough data; the amount on tagged entries per trigger is built), and calendar exposure (does use follow meetings more than chance, against the
  user's own hours with no meeting).
- *What follows use:* for each Health outcome (sleep duration and stages, overnight HRV, resting heart rate, next-day
  steps, State of Mind), a regression on every vice at once.

**How confounding between vices is handled.** For an outcome on day *d*, fit by least squares:

> outcome(d) ~ each vice's amount on d, d−1 and d−2 + each vice's late-day share + weekday/weekend + outcome(d−1) + trend

Every vice is in the same model, so each coefficient is that vice's association holding the others fixed: alcohol's
link to HRV is not credited to the coffee that came with it. A small ridge penalty keeps the fit stable. If two vices
are too entangled to separate (variance inflation above about 5, or co-occurrence on more than 80% of days), the card
says "can't tell coffee and alcohol apart yet" instead of a number. Sleep is aligned to the night that follows day
*d*, not the calendar date.

**How it avoids presenting noise as insight.** A card appears only when all of these hold:

1. at least 21 usable days, with at least 7 exposed and 7 unexposed days for that vice;
2. the p-value, computed with an effective sample size corrected for autocorrelation, survives Benjamini–Hochberg
   false-discovery control at q = 0.1 across every vice × outcome × lag tested that week (built for the comparisons
   whose rows are days, what follows a day's use and what comes before one: `serialInflation` in
   `lib/insights/stats.dart` counts n(1−r)/(1+r) days, r being the lag-1 autocorrelation of the habit's column times
   that of the residuals, over rows a calendar day apart);
3. the effect clears a practical size (built: a floor per outcome, `metricFloors` in
   `lib/insights/insights_report.dart`, such as 10 minutes of sleep or 3 ms of HRV; an amount or a time judged across
   the habit's interquartile range of days);
4. a 7-day moving-block bootstrap interval excludes zero (built for the same comparisons:
   `blockBootstrapInterval`, 2,000 seeded redraws of the habit's coefficient with the other terms' fit held, run only
   on a result that passed every other check).

Each card shows the effect with its interval and the number of days behind it, uses "goes with", never "causes", and
lists the pairs still collecting data ("9 of 21 days"). A day with nothing logged counts as a zero
(`r2-days`).

## Why

- SOURCED (C15): Jack asked for intelligent insights on what causes use and what follows it, telling vices apart, with
  sensitive processing and storage on the device and regenerable from the raw data.
- SOURCED ([Exist](https://kb.exist.io/article/18-how-long-does-it-take-to-find-correlations),
  [Bearable](https://bearable.app/support/howto/the-factor-effect-report/)): competitors use pairwise correlations or
  with/without averages, with floors of 3 weeks (Exist) or 3–7 days each way (Bearable), lag at most one day (Exist)
  and no multi-factor model or multiple-comparison control published. INFERENCE: from Exist's API example, a
  p = 0.029 earns 4 of 5 stars, which suggests no correction.
- SOURCED ([Penn State STAT 510](https://online.stat.psu.edu/stat510/Lesson09)): autocorrelation and shared trends
  distort raw cross-correlation; prewhitening or an autoregressive term fixes it.
  ([effective sample size](https://xskillscore.readthedocs.io/en/stable/api/xskillscore.effective_sample_size.html)):
  N_eff ≈ N(1−ρxρy)/(1+ρxρy).
- SOURCED ([Benjamini–Hochberg 1995](https://www.jstor.org/stable/2346101)); ([moving-block bootstrap](https://projecteuclid.org/euclid.aos/1176347265)).
- SOURCED ([PMC6142277](https://pmc.ncbi.nlm.nih.gov/articles/PMC6142277)): group-level findings often fail for
  individuals, which argues for per-person models.
- SOURCED ([JMIR 2018](https://mental.jmir.org/2018/1/e23); [Drake et al. 2013](https://pmc.ncbi.nlm.nih.gov/articles/PMC3805807/)):
  alcohol lowers that night's HRV dose-dependently; caffeine 6 hours before bed cut measured sleep by more than an
  hour. These justify the lags and the late-day timing term.
- INFERENCE: the thresholds above are Claude's choices, not from a source. Unit-test the maths against R or
  statsmodels on fixed fixtures.

## Options

- **A. Pairwise correlations** per vice and outcome, Exist-style. Simple, and credits one vice for another's effect.
- **B. Per-person multiple regression** with the gates above.
- **C. B, plus "experiments":** the app proposes a randomised two-week n-of-1 trial (for example, alternate no-coffee
  days) to test an association it found
  ([n-of-1 design guide](https://www.aafp.org/content/dam/AAFP/documents/patient_care/nrn/design-implementation-n1-trials.pdf)).
- **D. Pooled mixed models** across users. Needs data to leave the device, so it is out under C15.

## Recommendation

Claude's recommendation: **B for 1.1, C as the first Pro addition after it.** B is a few hundred lines of Dart (normal
equations or QR on matrices of 5–15 columns, a t-distribution CDF, BH and a bootstrap loop), and the gates are the
product: "honest insights, computed on your phone" is the claim no competitor makes. The "before use" family needs no
Health or Calendar, so it can light up for every Pro user from their 1.0 journal.

**Effort:** XL

**Revenue impact:** High: it is what Pro sells.

**Depends on:** [granular logging](granular-logging-and-data-model.md); [Apple Health](apple-health-correlation.md); [calendar](calendar-integration.md); [`weekly-bucketing-leaves-a-short-trailing-bucket`](../../tech-debt/widget-state-and-view-logic/weekly-bucketing-leaves-a-short-trailing-bucket.md).

**Needs Jack:** no
