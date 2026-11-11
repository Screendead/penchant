# Insights floors from the literature

Each outcome in `metricFloors` (`lib/insights/insights_report.dart`) gets the smallest change that a study has shown
to go with some measurable effect, as a number or a share of the person's own usual. A finding under its floor is
refused as too small to matter, and the card for a finding over it says what a change of the floor's size has been
shown to do. Researched 2026-11-09 with web search; every figure below was read in the source's abstract or a page
quoting it (named where it was not the paper itself). Author lists past the first are from memory where the search
did not show them; DOIs and PubMed ids were shown.

Kinds of basis, in the table and in the code comments:

- **Sourced**: the source reports an effect of a change of that size in that measure.
- **Consensus**: a clinical body set the size by expert judgement, with no effect measured at it.
- **Inferred**: the source measures a neighbouring quantity or population; the step from it is stated.
- **Kept**: nothing usable was found; #192's reasoned floor stays and the card carries no line.

Most sources are observational cohorts, where the figure is the reporting step of a dose-response (per 5 bpm, per
500 steps): the association is shown at that step, not that the change causes the outcome, and a smaller step is
an extrapolation. The cards say "went with" for these, never "caused".

## The floors

| Outcome | Floor | Basis | Source and what it showed |
| --- | --- | --- | --- |
| Time asleep | 21 min | Sourced | Al Khatib 2018: a sleep-extension trial gained 21 min of sleep a night over 4 weeks, and free sugar intake fell by about 10 g a day against controls (P = 0.042). Gruber 2012 (children): 27 min more sleep improved teacher-rated emotional lability and impulsivity. |
| Time in bed | 10 min | Kept | Al Khatib 2018 added 55 min in bed for 21 min of sleep; the effect is the sleep's, and no source shows an effect of time in bed itself. |
| Time awake in the night | 20 min | Consensus | Sateia 2017 (AASM insomnia guideline): 20 min of wake after sleep onset is the clinical-significance threshold for polysomnography, set by the task force's judgement before analysis. |
| Core sleep | 10 min | Kept | No source isolates light (N1 + N2) sleep. |
| Deep sleep | 10 min | Kept | Tasali 2008 suppressed slow-wave sleep by about 90% and insulin sensitivity fell about 25%; Herzog 2013, up to 20%. Both cut most of the night's deep sleep, so neither gives a smallest change. |
| REM sleep | 5% of usual time asleep | Sourced (share) | Leary 2020: each 5 percentage points less of the night in REM went with 13% higher mortality in MrOS (HR 1.13, 1.08 to 1.19) and 17% in the Wisconsin cohort. Floor = 0.05 x the person's median nightly time asleep; 10 min with under 14 nights of it. |
| Heart rate variability (SDNN) | half the person's night-to-night variation | Sourced (own noise) | Javaloyes 2019: cyclists whose training eased when 7-day HRV fell half a standard deviation below their own 4-week usual improved 40-min time trial 7.3% and peak power 5.1% over a fixed plan (the 0.5 SD rule read in HRV4Training's summary of the paper). 3 ms when there are too few nights to measure the variation. Hillebrand 2013 (1% higher SDNN, about 1% lower cardiovascular risk, read in a search summary, not the abstract) gives a slope, not a floor. |
| Resting heart rate | 5 bpm | Sourced | Vazir 2018 (ARIC, 15,680 people, 28 years): each 5 bpm rise from the previous visit went with 12% higher all-cause mortality (HR 1.12, 1.10 to 1.15). Zhang 2016's meta-analysis reports per 10 bpm (RR 1.09). |
| Heart rate while asleep | 5 bpm | Inferred | No source for sleeping heart rate alone; taken from resting heart rate (Vazir 2018), which a night's lowest rates track. |
| Heart rate, hours after a use | 2 bpm | Kept | A minute-level rate against the hour before; no source gives a smallest effect for it. |
| Breathing rate | 0.3 a minute | Kept | Baumert 2019: a mean nocturnal rate of 16 breaths a minute or more went with higher cardiovascular mortality (MrOS HR 1.57), but as a cut-off, not a change. Miller 2020 (preprint) flags illness from a rise against the person's own baseline without a size. |
| Blood oxygen | 1 percentage point | Inferred | Zoccali, Mallamaci and Tripepi 2002 (J Am Soc Nephrol): each 1% lower average nocturnal saturation went with 33% more fatal and non-fatal cardiovascular events, in 50 people on dialysis; a narrow population, and the floor already stood at 1. |
| Wrist temperature | 0.1 °C | Kept | Shilaih 2018: wrist skin temperature rises about 0.33 °C after ovulation, a measurable shift but a signal, not an effect of the change; no source gives one. |
| Step count | 500 steps | Sourced | Banach 2023 (meta-analysis of 17 cohorts, 226,889 people): each 500 more steps a day went with 7% lower cardiovascular mortality (HR 0.93, 0.91 to 0.95); each 1,000, 15% lower all-cause mortality. |
| Active energy | 85 kcal | Inferred | Strain 2020 (UK Biobank, 96,476 wrist-worn): 20 against 15 kJ/kg/day of activity energy went with 21% (4 to 35%) lower mortality. 5 kJ/kg/day at a 70 kg reference is 350 kJ, about 84 kcal; the app reads no body mass, and Apple's active energy approximates but is not the study's estimate. |
| Workout time | 15 min | Inferred | Wen 2011 (Lancet, over 400,000 Taiwanese adults, about 8 years): about 15 min a day (92 min a week) of moderate exercise went with 14% lower all-cause mortality than none, and each further 15 min a day with 4% lower. The exercise was self-reported, not recorded workouts; read in search summaries quoting the paper (added 2026-11-11). |
| Mindful time | 13 min | Inferred | Basso 2019 (Behav Brain Res, 42 non-meditators randomised): 13 min of guided meditation a day for 8 weeks lowered negative mood and state anxiety and improved attention and memory against 13 min of podcasts; nothing differed at 4 weeks. A daily dose kept up for weeks, not a one-day change; read in the PubMed abstract's summary (added 2026-11-11). |

Workout and mindful time count a day without a session as 0, so a person whose longest day never reaches the floor
cannot show a difference of it either way; the engine leaves such a metric out rather than add its comparisons to
the false-discovery family (`withSessionZeros`). The rule reads the person's days alone, never which followed a habit.

## The noise check

A floor must not sit inside the person's own night-to-night scatter. For each daily outcome the engine measures that
scatter as the typical error of consecutive days (Hopkins 2000): the standard deviation of the differences between
each day and the next, over the whole span, divided by √2. Differencing next-door days leaves out slow drift (season,
fitness), so it is the night-to-night part alone. The floor used is the larger of the literature floor and half that
typical error, half being the smallest worthwhile change for an individual that Javaloyes 2019 acts on (and the
sports-science convention it follows). It needs 14 pairs of consecutive days; with fewer, the literature floor stands
alone. A rule that resolves to nothing (a flat series, nights of no sleep) keeps the table's floor, since a floor of 0
would pass every finding. Heart rate in the hours after a use has no daily series and no check; HRV in the hours
after a use is judged against the same per-person HRV floor as its daily average, the one HRV floor there is, though
its card carries no line (below).

For scale, without any person's data: Quer 2020 (92,457 wearable users, 33 million days) found resting heart rate
moves about 3 bpm day to day within a person, so half of it, about 1.5 bpm, is under the 5 bpm floor. The check
is expected to bind where the floor is small against the scatter (core, deep and REM sleep, time in bed, wrist
temperature), and nearly always for steps and active energy, whose day-to-day scatter within a person runs to
thousands of steps and hundreds of kcal against floors of 500 and 85: there the person's floor, not the literature's,
decides, while the card line still names the literature's size. No person's series has been run through it yet.

Reading "inside the noise" as the whole typical error (rather than half) would refuse most sleep findings, since a
mean over many nights is properly smaller than one night's scatter; reading it as the standard error of the
comparison adds nothing, since every finding already clears its confidence interval. Half is the middle, and the
call is Jack's.

## Card lines

One line per card, for the headline's outcome, in short form; none for a kept floor, and none for an hours-after
headline, which sets minutes against the hour before rather than days or nights. A refusal names the person's
floor rounded up at the digits shown ("under 22 min" for 21.4; "under 0.4 ms" for 0.35), so "under" stays true.

- Time asleep: "21 min more sleep a night cut sugar eaten by about 10 g a day (Al Khatib 2018)."
- Time awake: "Sleep medicine counts 20 min less awake in the night as a clinical change (AASM 2017)."
- REM sleep: "Each 5% less of the night in REM went with 13% higher mortality (Leary 2020)."
- HRV: "Easing training when HRV fell half a usual swing improved cyclists' time trials 7% (Javaloyes 2019)."
- Resting heart rate: "Each 5 bpm rise went with 12% higher mortality over 28 years (Vazir 2018)."
- Heart rate while asleep: "Each 5 bpm rise in resting heart rate went with 12% higher mortality (Vazir 2018)."
- Blood oxygen: "Each point lower at night went with 33% more heart events, in dialysis (Zoccali 2002)."
- Steps: "Each 500 more steps a day went with 7% lower heart-disease death (Banach 2023)."
- Active energy: "About 85 kcal more a day (5 kJ per kg at 70 kg) went with 21% lower mortality (Strain 2020)."
- Workout time: "About 15 min of exercise a day went with 14% lower mortality than none (Wen 2011)."
- Mindful time: "13 min of meditation a day for 8 weeks lowered negative mood against a podcast (Basso 2019)."

## Sources

- Al Khatib HK, Hall WL, Creedon A, et al. Sleep extension is a feasible lifestyle intervention in free-living adults
  who are habitually short sleepers: a potential strategy for decreasing intake of free sugars? A randomized
  controlled pilot study. *Am J Clin Nutr* 2018;107(1):43–53. doi:10.1093/ajcn/nqx030
- Gruber R, Cassoff J, Frenette S, Wiebe S, Carrier J. Impact of sleep extension and restriction on children's
  emotional lability and impulsivity. *Pediatrics* 2012. PubMed 23071214
- Sateia MJ, Buysse DJ, Krystal AD, Neubauer DN, Heald JL. Clinical practice guideline for the pharmacologic
  treatment of chronic insomnia in adults: an American Academy of Sleep Medicine clinical practice guideline.
  *J Clin Sleep Med* 2017;13(2):307–349. PMC5263087
- Tasali E, Leproult R, Ehrmann DA, Van Cauter E. Slow-wave sleep and the risk of type 2 diabetes in humans.
  *PNAS* 2008;105(3):1044–1049. PubMed 18172212
- Herzog N, Jauch-Chara K, Hyzy F, et al. Selective slow wave sleep but not rapid eye movement sleep suppression
  impairs morning glucose tolerance in healthy men. *Psychoneuroendocrinology* 2013.
- Leary EB, Watson KT, Ancoli-Israel S, et al. Association of rapid eye movement sleep with mortality in middle-aged
  and older adults. *JAMA Neurol* 2020. doi:10.1001/jamaneurol.2020.2108
- Javaloyes A, Sarabia JM, Lamberts RP, Moya-Ramon M. Training prescription guided by heart-rate variability in
  cycling. *Int J Sports Physiol Perform* 2019;14(1):23–32. doi:10.1123/ijspp.2018-0122 (0.5 SD rule as quoted by
  hrv4training.com/blog2/training-prescription-guided-by-heart-rate-variability)
- Hillebrand S, Gast KB, de Mutsert R, et al. Heart rate variability and first cardiovascular event in populations
  without known cardiovascular disease: meta-analysis and dose-response meta-regression. *Europace*
  2013;15(5):742–749.
- Vazir A, Claggett B, Cheng S, et al. Association of resting heart rate and temporal changes in heart rate with
  outcomes in participants of the Atherosclerosis Risk in Communities study. *JAMA Cardiol* 2018;3(3):200–206.
  PMC5885888
- Zhang D, Shen X, Qi X. Resting heart rate and all-cause and cardiovascular mortality in the general population: a
  meta-analysis. *CMAJ* 2016;188(3):E53–E63. doi:10.1503/cmaj.150535
- Quer G, Gouda P, Galarnyk M, Topol EJ, Steinhubl SR. Inter- and intraindividual variability in daily resting heart
  rate in 92,457 adults. *PLoS ONE* 2020;15(2):e0227709. doi:10.1371/journal.pone.0227709
- Baumert M, Linz D, Stone K, et al. Mean nocturnal respiratory rate predicts cardiovascular and all-cause mortality
  in community-dwelling older men and women. *Eur Respir J* 2019;54(1):1802175. doi:10.1183/13993003.02175-2018
- Miller DJ, Capodilupo JV, Lastella M, et al. Analyzing changes in respiratory rate to predict the risk of COVID-19
  infection. medRxiv 2020. doi:10.1101/2020.06.18.20131417 (preprint)
- Zoccali C, Mallamaci F, Tripepi G. Nocturnal hypoxemia predicts incident cardiovascular complications in dialysis
  patients. *J Am Soc Nephrol* 2002.
- Shilaih M, Goodale BM, Falco L, et al. Modern fertility awareness methods: wrist wearables capture the changes in
  temperature associated with the menstrual cycle. *Biosci Rep* 2018;38(6):BSR20171279. PMC6265623
- Banach M, Lewek J, Surma S, et al. The association between daily step count and all-cause and cardiovascular
  mortality: a meta-analysis. *Eur J Prev Cardiol* 2023;30(18):1975–1985. doi:10.1093/eurjpc/zwad229
- Strain T, Wijndaele K, Dempsey PC, et al. Wearable-device-measured physical activity and future health risk.
  *Nat Med* 2020. doi:10.1038/s41591-020-1012-3
- Wen CP, Wai JPM, Tsai MK, et al. Minimum amount of physical activity for reduced mortality and extended life
  expectancy: a prospective cohort study. *Lancet* 2011;378(9798):1244–1253. PubMed 21846575
- Basso JC, McHale A, Ende V, Oberlin DJ, Suzuki WA. Brief, daily meditation enhances attention, memory, mood, and
  emotional regulation in non-experienced meditators. *Behav Brain Res* 2019;356:208–220.
  doi:10.1016/j.bbr.2018.08.023
- Hopkins WG. Measures of reliability in sports medicine and science. *Sports Med* 2000;30(1):1–15.
