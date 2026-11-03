# Market scan: vice trackers, self-tracking journals and the Apple platform

*Dated 2026-11-03. The vice-tracker sections are from 2026-11-02; the journal, platform, statistics and brand sections were added 2026-11-03 from web searches and fetches of primary pages (Apple developer documentation, vendor help centres, pub.dev). Method of the 2026-11-02 part: web search snippets, plus one fetch of Apple's App Review Guidelines page, which gave verbatim text.* Markers: **SOURCED** comes from those results, **INFERENCE** is reasoning, and **UNVERIFIED** is a claim that was not checked against a primary source. Sources disagree on prices, so treat every price as indicative and check the live App Store listing before using it.

## Vice trackers (2026-11-02)

| App | Model (SOURCED, indicative) | Ratings and complaints (SOURCED) |
|---|---|---|
| **I Am Sober** (sobriety counter and community) | The core tracker and the community are free. Plus is reported at $9.99/mo or $39.99/yr with a 7-day trial; Lifetime at $64.99–69.99; 12-month plans at $23.99–49.99 (UK £29.99–37.99). | About 4.9★ from about 173K iOS ratings. The top complaint is a paywall on basic features (about 10% of users, per one summary), plus emotionally intense community posts. |
| **Reframe** (alcohol reduction, coaching and content) | Reported at $13.99/mo (Access) and $19.99–24.99/mo (Silver), with a $100/yr web plan. Pricing is described as "personalized". | 4.8★ from more than 18K reviews. Main complaint: a 7-day trial that converts to an annual plan. Rated BBB F on 8 billing complaints (refunds mostly granted), with unanswered support emails and Trustpilot apologies for unclear pricing. UNVERIFIED: a 2026 data breach with 3 lawsuits. |
| **Sunnyside** (mindful drinking, AI coach) | 15-day trial, then Basic at $8.25 (billing period not stated). Raised $11.5M; TechCrunch covered its AI coach launch (2023). | — |
| **Quitzilla** (generic quit tracker) | The free tier tracks 2 habits. Premium is $5.99/mo, $29.99/yr, $24.99 for 6 months or $89.99 lifetime. | Users say you can only have 2 habits unless you subscribe. |
| **MyDrinkaware** (UK charity) | Free. Tracks units, calories, drink-free days and spend; some listings say sleep too. | The developer has acknowledged complaints that a redesign removed old tracking features. |
| **Generic habit trackers** (secondary blogs; figures conflict) | Streaks: one-time $4.99–5.99, with a habit cap reported as 12 or 24. Way of Life: $4.99 one-time, or free with a $29.99 lifetime option. Habitify: $2.49–4.99/mo, with 3 free habits. Habitica: free, with Premium cosmetics at about $4.99/mo. | — |

The scan found nothing on "Less".

## Patterns

- SOURCED: capping free users at 2–3 habits is the standard paywall in generic trackers.
- SOURCED: lifetime purchases in the sobriety apps sit around $65–90.
- SOURCED: the biggest complaints are aggressive paywalls, trials that convert to annual plans unexpectedly, and support that is hard to reach.
- INFERENCE: the other apps either cover alcohol only (Reframe, Sunnyside, MyDrinkaware) or count days abstinent (quit trackers). The scan found no mainstream app that logs quantities across several vices with a radar view, but the search was not exhaustive.
- INFERENCE: three models fit the evidence:
  - a one-time or lifetime unlock, which avoids the billing complaints;
  - a cheap subscription with a clear trial;
  - a free tier capped at 2–3 vices.
- INFERENCE: positioning on those complaints would be "no dark-pattern billing, private data, works offline".

## App Store Review Guidelines (verbatim where quoted)

Source: <https://developer.apple.com/app-store/review/guidelines/>

- **1.4.1 Medical:** "Medical apps that could provide inaccurate data or information, or that could be used for diagnosing or treating patients may be reviewed with greater scrutiny." Such apps "should remind users to check with a doctor".
- **1.4.3 Substances:** "Apps that encourage consumption of tobacco and vape products, illegal drugs, or excessive amounts of alcohol are not permitted. Apps that encourage minors to consume any of these substances will be rejected." I Am Sober and MyDrinkaware both list 17+, which is evidence for the rating, not a rule.
- **3.1.1:** unlocking features requires in-app purchase.
- **3.1.2(a):** an auto-renewable subscription "must provide ongoing value". It must last at least 7 days and be available on all of the user's devices.
- **3.1.2(c):** describe clearly what the user gets before asking them to subscribe.
- **4.2 Minimum functionality:** an app must be more than a repackaged website.
- **5.1.1 (login):** if an app lacks significant account-based features, let people use it without a login.
- **5.1.1(v):** "If your app supports account creation, you must also offer account deletion within the app." Deletion must not be unnecessarily difficult. Sources: <https://developer.apple.com/help/app-review/guideline-reference/5-1-1-account-deletion>, <https://developer.apple.com/support/offering-account-deletion-in-your-app>.
- **5.1.2(i):** get permission before sharing personal data with third parties, including third-party AI.
- **5.1.3 Health data** (verbatim, 2026-11-03): (i) "Apps may not use or disclose to third parties data gathered in the health, fitness, and medical research context—including from… HealthKit API…—for advertising, marketing, or other use-based data mining purposes other than improving health management, or for the purpose of health research, and then only with permission… You must disclose the specific health data that you are collecting from the device." (ii) "Apps must not write false or inaccurate data into HealthKit… and may not store personal health information in iCloud."
- **5.1.2(vi):** HealthKit data "may not be used for marketing, advertising or use-based data mining, including by third parties."
- **5.1.1(i):** a privacy policy is required in App Store Connect and in the app, and it must confirm that any third party with access to user data gives "the same or equal protection".
- **2.5.1:** "HealthKit should be used for health and fitness purposes and integrate with the Health app."

## Self-tracking journals (2026-11-03)

Prices in USD from the US store or the vendor, indicative.

| App | Insight method (SOURCED) | Integrations and processing | Price (SOURCED) |
|---|---|---|---|
| **Exist** | Pairwise correlations with a strength and 1–5 star confidence; needs 3 weeks of data per attribute; recalculated weekly, published Mondays; tries a one-day offset when same-day finds nothing, no longer lags. The API exposes r, p, stars and plain-English text. | Apple Health, Calendar, Oura, Garmin, Withings, RescueTime, weather. INFERENCE: processed in the cloud. | 6.99/mo or 62.90/yr, 30-day trial, no free tier, no lifetime |
| **Bearable** | Averages of an outcome on days with a factor against days without, same day and the following 7; minimum 3 entries each way, recommends 7; no significance test or multi-factor model described; warns about confounding. | Apple Health. Processing location not stated. | Most features free; premium 34.99/yr or 6.99/mo; Factor Effect is premium |
| **Daylio** | "Advanced statistics" per mood, activity or group; weekly reports. | Entries stored on the phone, optional encrypted iCloud backup; no Apple Health in the listing. | IAPs 4.99–59.99; secondary sources: 4.99/mo, 35.99/yr, 59.99 lifetime |
| **Welltory** | HRV-centred; journal events compared with stress and recovery trends; "Meet My Patterns" maps tags against stress. | Apple Health and 1,000+ devices. INFERENCE: cloud (AI coach). | Premium 99.99–119.99/yr; lifetime 299.99 |
| **Gyroscope** | AI coach and reports; no explicit correlation method in the listing. Free tier: 4 trackers, 30 days. | Apple Health, calendar. Privacy label lists email used for third-party advertising. | "About $1 a day"; IAPs 9–299 |
| **Guava Health** | Correlations "not necessarily cause and effect"; manual runs free, automatic scanning premium. | — | Reported about 8/mo (weak source) |
| **How We Feel** | HealthKit sleep and exercise patterns, AI weekly review. | Data on the device unless the user opts in to research. | Free (nonprofit) |
| **Apple Health State of Mind** | Shows "Associations" and "Life Factors" beside mood entries, not as statistics. | Built in. | Free |

INFERENCE from the table:

- None publishes a multi-factor method, multiple-comparison control, or lags beyond one day (Bearable's 7-day window is
  a plain average). Exist is the only one that shows p-values, and its API example gives p = 0.029 four stars, which
  suggests no correction for many tests.
- Only How We Feel and Daylio state on-device storage, and neither does real correlation analysis.
- Only Daylio and Welltory sell a one-time purchase among those priced.

## Apple platform facts for the insight features (2026-11-03)

**HealthKit**

- SOURCED: the quantity types include `heartRate`, `heartRateVariabilitySDNN`, `restingHeartRate`, `walkingHeartRateAverage`, `respiratoryRate`, `oxygenSaturation`, `appleSleepingWristTemperature`, `stepCount`, `activeEnergyBurned`, `bloodAlcoholContent`, `numberOfAlcoholicBeverages` (iOS 15, writable) and `dietaryCaffeine`. No type covers nicotine, vaping or cannabis.
- SOURCED: sleep analysis values include `inBed`, `awake`, `asleepCore`, `asleepDeep`, `asleepREM` and `asleepUnspecified`. `HKStateOfMind` needs iOS 18 / macOS 15. Wrist temperature and walking heart rate are read-only.
- SOURCED: `earliestPermittedSampleDate` is "a systemwide platform constraint that applies equally to all apps"; earlier history is readable back to it. iOS 27 adds `getEarliestAuthorizedSampleDate(for:)`: users can limit history, and data before that date is "unknown — not an absence of data".
- SOURCED: "Your app can't distinguish between denied and full access"; denied reads return only samples the app saved itself.
- SOURCED: background delivery needs an entitlement, wakes at most once per period (hourly for some types), and does not run in the Simulator; the store is encrypted while the device is locked.
- SOURCED: on macOS 13 and later the framework exists "but your app can't read or write HealthKit data" and `isHealthDataAvailable()` returns `false`; Apple DTS confirmed this in 2025.
- SOURCED: "You must not disclose any information gained through HealthKit to a third party without express permission… You must also provide a privacy policy for any app that uses the HealthKit framework." The licence agreement bars iCloud/CloudKit for "sensitive, individually-identifiable health information".
- INFERENCE: Apple names no rule for an app's own non-iCloud backend; whether Google as Firestore's processor is a "third party" is undefined. Keeping HealthKit data and anything derived from it on the device removes the question.
- SOURCED: `health` 13.3.2 (pub.dev, carp.dk) supports iOS 15+ and Android only; it covers sleep stages, HRV, heart rates, respiratory rate, oxygen, wrist temperature, steps, energy, mindfulness and caffeine, but not alcohol or State of Mind.

**EventKit**

- SOURCED: since iOS 17 / macOS 14, apps request full or write-only access; write-only "doesn't let it read any events"; "your app can't request read-only access". Keys: `NSCalendarsFullAccessUsageDescription`, `NSCalendarsWriteOnlyAccessUsageDescription`; an app with only the old key is denied automatically. Sandboxed Mac apps also need `com.apple.security.personal-information.calendars`.
- SOURCED: `requestAccess(to:)` is deprecated and on iOS 17 returns an error without prompting.
- SOURCED: `predicateForEvents` matches at most a four-year span. INFERENCE: chunked queries reach further back.
- SOURCED: `device_calendar` 4.3.3 was last published two years ago; `device_calendar_plus` 0.12.0 is current, with full and write-only tiers, but no macOS. INFERENCE: no plugin covers macOS.

**Age ratings**

- SOURCED: since July 2025 the tiers are 4+, 9+, 13+, 16+ and 18+; 17+ is gone. "Alcohol, Tobacco, or Drug Use or References" rates 13+ when infrequent and 18+ when frequent; developers may choose a higher rating.

## Statistics for on-device n-of-1 insight (2026-11-03)

- SOURCED: autocorrelation and shared trends distort raw cross-correlation; prewhiten or detrend before choosing lags.
- SOURCED: effective sample size for two autocorrelated series: N_eff ≈ N(1−ρxρy)/(1+ρxρy).
- SOURCED: Benjamini–Hochberg controls the false discovery rate across many tests; the moving-block bootstrap gives intervals for dependent data.
- SOURCED: distributed-lag models fit effects over several lags at once; group-level findings often fail for individuals.
- SOURCED: observational self-tracking findings are hypotheses that a randomised n-of-1 trial can test.
- SOURCED: alcohol lowers that night's HRV and raises heart rate dose-dependently (n = 4,098); 400 mg of caffeine 6 hours before bed cut measured sleep by more than an hour.
- INFERENCE: per-user OLS with every vice as a covariate, an autoregressive term and weekday effects, solved by QR or Cholesky on 5–15 columns, runs in milliseconds in Dart with no library; mixed models only pay if users are pooled, which C15 rules out.

## Brand quick check (2026-11-03)

A quick check, not legal clearance: web searches for App Store listings and brands, plus DNS, whois and registry lookups; no trademark-office search. Every exact `.com` and `.app` for the 19 names checked is registered. Conflicts found:

- Habitus: <https://apps.apple.com/mx/app/habitus-task-manager/id6447605855>, <https://apps.apple.com/dk/app/habitus-health/id1611013562>, <https://markinton.com/trademark/habitus-99740922>
- Inkling: <https://apps.apple.com/us/app/-/id6747737232>, <https://apps.apple.com/us/app/inkling/id923550071>
- Cairn: <https://apps.apple.com/app/id6774183808>, <https://apps.apple.com/us/app/cairn-the-trail-safety-app/id964300002>
- Almanac: <https://apps.apple.com/app/id6504696550>
- Undercurrent: <https://www.iphoneaddict.fr/apps/forme-sante/undercurrent-symptom-tracker-622.html>
- Tidemark: <https://en.wikipedia.org/wiki/Tidemark>
- Proclivity: <https://www.cbinsights.com/company/proclivity-systems>
- Tendency (nearby names): <https://apps.apple.com/app/id6783605288>, <https://apps.apple.com/us/app/-/id6782339912>
- Marginalia: <https://apps.apple.com/app/id6758641325>, <https://apps.apple.com/app/id6753642717>
- Tally: <https://apps.apple.com/app/id1034223758>, <https://apps.apple.com/app/id6642680091>, <https://apps.apple.com/app/id957912407>
- Wont (same idea): <https://apps.apple.com/us/app/id6747329357>
- Plume (sound-alike of Plumb): <https://apps.apple.com/app/plume-journaling/id6754373902>
- Vane: <https://apps.apple.com/app/id6763763425>
- Bearing (sound-alike of Bearable): <https://apps.apple.com/ie/app/id1482581097>
- Telltale: Telltale Games (from knowledge; not checked against a register).

No conflict was found for Penchant, Kenning, Sounding or Leaning.

## Gaps

The scan did not cover:

- the last 14K characters of the guidelines page, which include 5.1.1(i) on privacy policies and the privacy nutrition labels;
- primary pricing pages for Reframe, I Am Sober, Quitzilla or Streaks;
- direct Reddit or review text beyond what summaries quote;
- EU or UK regulation of alcohol apps (Google Play is moot: Android is removed, C6);
- conversion benchmarks, and RevenueCat pricing;
- trademark registers (USPTO, UKIPO, EUIPO) for the brand candidates;
- whether the Flutter `in_app_purchase` plugin exposes StoreKit 2's verified transactions;
- the App Store subtitle length and universal-purchase rules (stated from memory in the pitches).

## Sources

- I Am Sober: <https://apps.apple.com/app/id672904239>, <https://www.choosingtherapy.com/i-am-sober-app-review/>, <https://apppricinglab.com/app/apple/672904239>
- Reframe: <https://www.choosingtherapy.com/reframe-app-cost/>, <https://de.trustpilot.com/review/reframeapp.com>, <https://www.healthline.com/health/mental-health/reframe-app-review>
- Sunnyside: <https://www.sunnyside.co/>, <https://techcrunch.com/2023/11/15/mindful-drinking-app-sunnyside-lands-11-5m-to-launch-its-ai-powered-coach/>
- Quitzilla: <https://apps.apple.com/us/app/quitzilla-quit-tracker/id1533076568>, <https://quitzilla.com/>
- MyDrinkaware: <https://www.drinkaware.co.uk/tools/mydrinkaware-app>, <https://apps.apple.com/gb/app/mydrinkaware-alcohol-tracker/id901389586>
- Habit trackers: <https://toolradar.com/tools/streaks/pricing>, <https://toolradar.com/tools/habitify/pricing>, <https://habitdoom.com/blog/best-habit-tracker-iphone-2026>
- Journals: <https://kb.exist.io/article/37-what-are-correlations>, <https://kb.exist.io/article/18-how-long-does-it-take-to-find-correlations>, <https://kb.exist.io/article/55-will-exist-find-correlations-across-multiple-days>, <https://developer.exist.io/reference/correlations/>, <https://exist.io/>, <https://bearable.app/support/howto/the-factor-effect-report/>, <https://bearable.app/support/troubleshooting/my-correlations-are-wrong-dont-make-sense/>, <https://bearable.app/pricing>, <https://apps.apple.com/us/app/daylio-journal/id1194023242>, <https://makeheadway.com/blog/daylio-review/>, <https://apps.apple.com/us/app/welltory-heart-rate-monitor/id1074367771>, <https://apps.apple.com/us/app/id1104085053>, <https://guavahealth.com/health-insights>, <https://apps.apple.com/us/app/-/id1562706384>, <https://support.apple.com/guide/iphone/log-your-state-of-mind-iph6a6decb13/ios>
- HealthKit: <https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier>, <https://developer.apple.com/documentation/healthkit/hkcategoryvaluesleepanalysis>, <https://developer.apple.com/documentation/healthkit/hkstateofmind>, <https://developer.apple.com/documentation/healthkit/hkhealthstore/earliestpermittedsampledate()>, <https://developer.apple.com/documentation/healthkit/hkhealthstore/getearliestauthorizedsampledate(for:completion:)>, <https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data>, <https://developer.apple.com/documentation/healthkit/executing-observer-queries>, <https://developer.apple.com/documentation/healthkit/protecting-user-privacy>, <https://developer.apple.com/documentation/healthkit/hkhealthstore/ishealthdataavailable()>, <https://developer.apple.com/forums/thread/798780>, <https://developer.apple.com/support/terms/apple-developer-program-license-agreement/>, <https://pub.dev/packages/health>
- EventKit: <https://developer.apple.com/documentation/eventkit/accessing-the-event-store>, <https://developer.apple.com/documentation/eventkit/ekeventstore/requestaccess(to:completion:)>, <https://developer.apple.com/documentation/eventkit/ekeventstore/predicateforevents(withstart:end:calendars:)>, <https://pub.dev/packages/device_calendar>, <https://pub.dev/packages/device_calendar_plus>
- Age ratings: <https://developer.apple.com/news/?id=ks775ehf>, <https://developer.apple.com/help/app-store-connect/reference/app-information/age-ratings-values-and-definitions/>
- Statistics: <https://online.stat.psu.edu/stat510/Lesson09>, <https://xskillscore.readthedocs.io/en/stable/api/xskillscore.effective_sample_size.html>, <https://www.jstor.org/stable/2346101>, <https://projecteuclid.org/euclid.aos/1176347265>, <https://pmc.ncbi.nlm.nih.gov/articles/PMC4098103>, <https://pmc.ncbi.nlm.nih.gov/articles/PMC6142277>, <https://pmc.ncbi.nlm.nih.gov/articles/PMC6087468>, <https://www.aafp.org/content/dam/AAFP/documents/patient_care/nrn/design-implementation-n1-trials.pdf>, <https://mental.jmir.org/2018/1/e23>, <https://pmc.ncbi.nlm.nih.gov/articles/PMC3805807/>
