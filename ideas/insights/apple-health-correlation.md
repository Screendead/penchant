# Read Apple Health, including years of history, to see what follows each vice

**Priority:** insights (1.1, Pro)

## What

With the user's permission, read health outcomes from HealthKit and hand them to the
[insights engine](insights-engine.md), which relates them to the journal:

- **Outcomes read:** sleep analysis with stages (`asleepCore`, `asleepDeep`, `asleepREM`, `awake`, `inBed`), HRV
  (`heartRateVariabilitySDNN`), `restingHeartRate`, `heartRate`, `respiratoryRate`, `walkingHeartRateAverage`,
  `oxygenSaturation`, `appleSleepingWristTemperature`, `stepCount`, `activeEnergyBurned`, and State of Mind (iOS 18).
- **History:** on first connection, backfill every sample the system allows, so a new user with a year of Watch data
  gets insights against their journal's start immediately, and baselines from before the journal began.
- **Incremental:** an observer query plus an anchored object query to pick up new samples, with background delivery
  as a later step.
- **Optional write-through:** logs of alcohol and caffeine written to Health as `numberOfAlcoholicBeverages` and
  `dietaryCaffeine`, off by default.

Everything read stays on the device, in the engine's local store; none of it goes to Firestore, analytics or crash
reports.

## Why

- SOURCED (C15): Jack wants what follows from one vice against another (sleep, HRV, heart rate and more), including
  historical data, with the effect attributed to the right vice over time.
- SOURCED ([HKQuantityTypeIdentifier](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier)):
  every type above exists. No type covers nicotine, vaping or cannabis, so those vices are journal-only.
- SOURCED ([earliestPermittedSampleDate](https://developer.apple.com/documentation/healthkit/hkhealthstore/earliestpermittedsampledate())):
  history before install is readable back to a system-wide limit. SOURCED
  ([getEarliestAuthorizedSampleDate](https://developer.apple.com/documentation/healthkit/hkhealthstore/getearliestauthorizedsampledate(for:completion:))):
  iOS 27 lets a user limit an app to recent data; "treat all data before that date as unknown — not an absence of
  data".
- SOURCED (same page): an app "can't distinguish between denied and full access". INFERENCE: an empty result must
  read as "no data yet", never as "you slept zero hours".
- SOURCED ([guidelines](https://developer.apple.com/app-store/review/guidelines/) 5.1.3(i), (ii);
  [HealthKit privacy](https://developer.apple.com/documentation/healthkit/protecting-user-privacy)): no advertising or
  data mining; disclose the specific data read; no personal health information in iCloud; nothing to a third party
  without express permission. Apple names no rule for one's own non-iCloud server. INFERENCE: on-device only removes
  the grey area entirely.
- SOURCED ([`health` on pub.dev](https://pub.dev/packages/health)): version 13.3.2 covers sleep stages, HRV, heart
  rates, respiratory rate, oxygen, wrist temperature, steps, energy and caffeine on iOS, but not alcohol, State of
  Mind, the iOS 27 authorized-date call, or anchored sync. It has no macOS support, and HealthKit has no data on macOS
  anyway.

## Options

- **A.** The `health` package for reads, plus a small Swift channel for what it lacks.
- **B.** A Swift channel for everything (types, anchored queries, write-through, authorized dates).
- **C.** Read daily aggregates only (`HKStatisticsCollectionQuery`) rather than samples.

## Recommendation

Claude's recommendation: **B with C's aggregates.** The engine needs daily and nightly values, not raw samples, and
statistics queries return them in one call per type per year, which keeps the local store small. A focused Swift
channel avoids depending on a package that lacks half of what is needed. Ship it in 1.1 as Pro, since history is
backfilled whenever it arrives. Ask permission from the insights screen, never at first run.

**Effort:** L

**Revenue impact:** High: the most screenshot-able Pro feature ("on nights after 3+ drinks your HRV is 12% lower").

**Depends on:** [insights engine](insights-engine.md); [privacy policy](../release-blockers/privacy-policy-and-labels.md); [granular logging](granular-logging-and-data-model.md).

**Needs Jack:** no
