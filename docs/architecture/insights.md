# Insights sources: Health, Calendar and Reminders, triggers, experiments, places, daylight, note search

**Health** (iOS only; `ios/Runner/HealthChannel.swift`, `lib/insights/health_source.dart`). Nothing read from
Health leaves the device: not Firestore, analytics or crash reports. The only writes are a strength habit's entries, on
the person's say-so (A habit's strength, `data-model.md`): `numberOfAlcoholicBeverages` and `dietaryCaffeine`, never in
`readTypes`, so Insights cannot read Penchant's own samples back as an outcome; keep them out of it. Insights' daily values live in
`health-daily.json` in Caches (not backed up; `lib/insights/health_sync.dart`); each open asks the channel's
`changes` (an `HKAnchoredObjectQuery` per type from its saved anchor, state in Caches' `health-sync.json`, pure part
`HealthDays.SyncState`, tested by `tools/health-days.test.sh`) and rereads only the days named, the days since, sleep
by calendar year, and in full a type with no anchor or a deletion (HealthKit gives a deleted sample no date), then
acknowledges the generation once the store is written. Hours after a use (`lib/insights/hours_after.dart`) times each moment
from that day's waking: the night in Health, else, for a day with none (a Watch charged overnight), `wakingFromSteps`:
the first sustained steps after the longest still span from 18:00 the evening before to 15:00, read one span a night
under `wakingStepsKey`, apart from the `stepCount` spans around moments. Such moments are never set against a recorded
night's (that waking runs late), the finding's basis says waking was estimated from steps (`stepWakingDays`), and the
hour-before comparison leaves them out. Menstrual flow is read as days with flow (value 1, never the
amount) and is no outcome: `InsightsInput.from` takes it out of the outcomes and `cyclePhases`
(`lib/insights/cycle_phase.dart`) infers each day's phase from those days alone (menstrual through the bleed, luteal
the 14 days before the next start, follicular between; only in whole cycles of 24 to 38 days). The five day-after
comparisons hold it fixed as a `DayCondition` (indicator columns in `_timeTerms`) when every phase has a week of the
comparison's days; such a finding's `heldFixed` names it and its basis line says so, and nothing else shows the cycle.
`HKObserverQuery`s with hourly background delivery
(`com.apple.developer.healthkit.background-delivery`), started in `didFinishLaunching`, mark changes while the app is
closed. The Health sheet resets the anchors; a store over 30 days old is read again in full. State of Mind (iOS 18+,
`#available`-gated; older systems read no rows and observe nothing) is `moodValence`: the day's mean valence, -1 to
1, of its daily-mood logs, else its momentary emotions (`HealthDays.moodRows`). Insights judges it only from 14 days
with a log (`withEnoughMood`), floors it at half the SD of the person's daily valence (`FloorRule.ownSpread`; Jack,
round 16 `mood-floor` A, after Norman 2003) and words it without numbers (`MetricCopy.inWords`: "slightly less
pleasant", Health's labels for levels). Each change to `readTypes` raises `healthReadTypesVersion`.

**Calendar and Reminders** (iOS, plus the Mac's tag picker below; EventKit, full access asked from a card on Insights, read-only, nothing kept on
the device or sent anywhere: each open reads again). `ios/Runner/CalendarChannel.swift` gives each timed event's start,
end and number of people listed, never who (`lib/insights/calendar_source.dart`, a year per read), which
`lib/insights/after_event.dart` compares with the hour after, and `lib/insights/calendar_days.dart` makes into daily
features (time in meetings, events, back-to-back runs, events of `calendarCrowdedAttendees` or more people, events over
`calendarLongMinutes`), each judged from `calendarDayMinDays` days above 0: whether a habit is used on more of the days
above the feature's median, with weekend, trend, period and the day before's use held fixed, in the page's family with a
10-point floor (`CalendarDay`, `report.calendarDays`, cards under What sets it off). The features never become
outcomes, so nothing compares meetings after a use. `ios/Runner/RemindersChannel.swift` gives each reminder's due and completion times alone
(`lib/insights/reminders_source.dart`), made into two daily outcomes beside Health's: reminders completed that day
(`remindersCompleted`) and due that day but not done by its end (`remindersMissed`), each from its first day above 0
and judged only with `minSessionDays` such days. Both providers turn a failure or a 30 s timeout into nothing, since
provider errors reach Crashlytics. Like everything in Insights they wait for Health values. Outside Insights, the
trigger picker (`showTriggerPicker`'s `at`: the record sheet and editor pass the sheet's time, `logOne`'s "What was
going on?" the log's; the widget's prompt passes none) reads the hour before the entry once as it opens, only with full
access already granted, and offers `work/meeting` first under "Suggested from your calendar" when an event of 15 minutes
or more ended in that hour (`lib/insights/calendar_suggestion.dart`, 3 s timeout, never picked until tapped). On macOS
that suggestion is the calendar's only use (no Insights there): the macOS Runner compiles the same
`CalendarChannel.swift` (sandbox entitlement `com.apple.security.personal-information.calendars`, Runner only), and
the picker reads `pickerCalendarSourceProvider` (`lib/providers/mac_calendar_provider.dart`), which there answers
no access until Settings' macOS-only "Suggest tags from Calendar" switch is on (per device, off by default; turning
it on asks for access, a refusal points to System Settings); `calendarSourceProvider`, which Insights reads, stays
iOS-only.

What sets it off also compares triggers (`lib/insights/trigger_amounts.dart`, cards in
`lib/widgets/trigger_amounts_card.dart`): per habit, the amount per entry on entries tagged a trigger against its other
tagged entries (untagged ones say nothing, so they are left out, and the card says how many were tagged), each day's
mean per entry as the unit, in the page's false-discovery family. A trigger counts under its tree path, its top-level
area, or as its free-text label; `HabitUse.triggers` carries them from the opened entries, so a locked entry reads as
untagged. Day-note tags are compared the same way at day level (`lib/insights/day_tags.dart`, cards in
`lib/widgets/day_tags_card.dart`): `insightsProvider` reads every note once per open through `allDayNotesProvider`
(a failed read leaves them out; a locked note reads as untagged) and `dayTagsFrom` passes each tagged day as
`InsightsInput.dayTags`. Per habit, the rows are the tagged days of its span (untagged days say nothing and are left
out, a day with no entry counts as 0) and the response its `lateDayTotal`, fitted on the tag with the habit's usual
total on that weekday (over its whole span), a trend, period levels and the day before's total held fixed, widened by
`judgeDays` and its block bootstrap like `calendarDays`; at least `minExposedDays` days each side and 10 residual days,
in the page's family, floor 20% (`dayTagFloor`, the entry triggers', read on both the held-fixed and the shown
difference). `test/insights/day_tags_test.dart` holds its null simulations (independent tags, and tags kept for the
heavy weekdays, which without the weekday column gave 42% false cards) and its power. Where a habit's day-tag finding
and its entry-trigger finding name the same tag or area and point the same way, `dayTagCards` says both on one card
("By day and by entry") and takes it off the trigger card. Each unarchived habit on no before-a-use, pair (either side), calendar, place trigger or day-tag card gets one reason, on a
drill-in page (`InsightsSetsOffPage`) as What it costs keeps its refusals: `setsOffRefusals`
(`lib/insights/sets_off_refusal.dart`) picks the most telling refused comparison by `refusalRank`, else says the habit
has no entries or nothing to compare against.

**Self-experiments** (iOS only; round 17 option C, Jack, 2026-11-13). A "what follows" finding (`InsightKind.use`, lag
of a day or more) on a sleep, heart or activity measure shown in numbers (`canExperiment`) offers "Test this for 6
weeks" while no plan runs (one at a time). `ExperimentPage` sets 2, 4, 6 or 8 weeks, each with the 95% half-width to
expect, t(2n − 2) × spread × √(2/n), the spread being the measure's SD over the last 90 days (14 values at least).
The days come from a stored seed (`lib/insights/experiment.dart`, mulberry32, since `dart:math`'s `Random` promises no
sequence across SDKs): each week draws 3 or 4 "none" days, each pair of weeks 4 and 3, every week from its own stream
so "Run it 4 more weeks" keeps the days planned. The rule is always "none after 18:00" against "as usual", never "have
it". Today shows the day's strip above the dial and shades 18:00 to midnight on "none" days. Once the last measure is
in, Insights' "Your experiment" compares the measure after "none" days with after "as usual" days by a 95% Welch
interval, intention to treat: a "none" day with the habit logged from 18:00 to 05:00 is a missed day and still counts
as "none" (`analyseExperiment`; `test/experiment_test.dart` runs a null simulation and a planted effect). The plan
(`ExperimentStore`, plans only; results are worked out again from Health and the journal on each open, so the report's
types and `insightsViewFormat` are unchanged) is the sealed file `experiment` under Application Support, not Caches
(`DeviceFiles.keptForUser`, same layout, other users' folders removed on first use, cleared with the rest on sign-out
and deletion), so the Mac never sees it. Its optional notification (`experimentNotices`, ids from 1000, a week ahead,
topped up on each launch, cancelled on stop, finish and sign-out) says "Experiment, day 9 of 42" and never names the
habit; permission is asked only when it is turned on. Stopping removes the plan with no result.

**Places** (iOS only; Core Location visits, opt-in from a card on Insights: When In Use first, then the upgrade to
Always, which Apple shows at most once; `NSLocation...UsageDescription` strings, no background mode or paid
capability). `ios/Runner/PlacesChannel.swift` makes its `CLLocationManager` in `didFinishLaunching`, since the system
relaunches the app for a visit, and holds each visit (arrival, departure, coordinates, accuracy) in memory only, never
on disk, until Dart takes it (`lib/insights/places_source.dart`: `take`, then `ack` once sealed; `reported` on each
visit). `placesProvider` (`lib/providers/places_provider.dart`, built at launch by `MyApp`) drains them at launch, on
each report and on resume, once a key is loaded, into the sealed device file `places`: `PlaceStore`
(`lib/insights/places.dart`) clusters visits within 150 m into places numbered from 1 ("Place n" until renamed on the
card) and keeps the stays. A visit reported while no key is loaded is lost if the process ends first. `atPlace`
compares, per habit and per place (the 5 with the most waking time), the share of a day's 07:00-23:00 entries logged
during a stay there with the share of those hours spent there, by day, on days with an entry and an hour both there
and elsewhere: 14 days at least, in the report's false-discovery family, floor 10 points. Findings show under What
sets it off; names stay out of the engine and the report codec (results carry the place id). Once location is on, the card's
"Add history from your photos" (`lib/providers/photos_provider.dart`, on request only, never observing the library)
asks PhotoKit for read access and `ios/Runner/PhotosChannel.swift` reads each user-library asset's creation date and
location alone, off the main thread; limited access reads only the shared photos. Tapping a place on the card opens
`PlaceSheet` (`lib/widgets/place_sheet.dart`; Jack, 2026-11-13) to name it: when the person was there, from the stays,
and, only with photo access already given (it never asks), thumbnails of up to 12 photos taken during its stays (a fetch by date:
reading every asset's location took seconds) and within the place's 150 m (the channel's `near`, in memory only, never kept). Its "Show on map" asks `PlacesChannel`'s `mapSnapshot`
(`MKMapSnapshotter`) only on the tap: the one time a place's coordinates leave the device, to Apple, and the sheet
says so first. No address lookup. The card lists the places the engine judges, then the 5 others with the most time,
photo stays included. `photoRuns`
(`lib/insights/photo_stays.dart`) makes a stay of two or more photos within 150 m on one day, at most 90 minutes
apart, spanning 15 minutes or more; a lone photo gives nothing. `PlaceStore.withPhotoRuns` replaces the photo stays
(source `photos` in the file, format 2; format 1 still opens), joins them to the same places without moving a visited
one, and `withoutPhotos` removes them and the places only photos gave. `atPlace` ignores photo stays: time outside
them is unknown, and in simulation (#296) photos set off by a habit raised false cards above the family's rate even
counting only the hours they cover, with too few days to find a real difference. They only find and name places;
`roughLocationOfPlaces` ignores them too.

**Note search** (`lib/notes/note_search_page.dart`, `/search`, from the Penchant menu and the Mac's Edit > Find,
Cmd-F, which `MyApp` hands `AppMenuBar` while someone is signed in and the app is not covered). It searches entry
notes, day notes and saved follow-up answers on the device, from the whole-journal read and `allDayNotesProvider`;
locked items are skipped and counted. Word search (`lib/notes/note_search.dart`, pure) folds case and diacritics
(`FoldedText` keeps each folded unit's span of the original for highlights), drops English stop words unless the
query is nothing else, lets a word of three letters or more match words it begins, and ranks every word (or the
query as written) above some words (more of them first), recent first within each; results group by day and open
the entry editor or day note sheet by their routes. Meaning search (`lib/notes/note_meaning.dart`) asks
`ios/Runner/SentenceEmbeddingChannel.swift` (both Runners) for Apple's `NLEmbedding.sentenceEmbedding` in the
device's first language, embeds notes lazily in batches of 64, keeps the vectors in memory for the signed-in uid,
and adds notes matching no word from cosine 0.40, below every word match under "Close in meaning". It is off by
default behind a per-device switch on the page (`noteSearchMeaning`), shown only where the embedding exists:
on `tools/note-search-trial.swift`'s made-up notes it put an expected note in the top 3 for 8 of 15 queries against
words' 10 and combined 11, and 1 of its 25 meaning-only results was expected. Keep that script's rules in step.

**Daylight** (`lib/insights/daylight.dart`, no network, no permission of its own). A `RoughLocation`, whole degrees,
held in memory only: the place with the most stay time (`roughLocationOfPlaces`), else the device time zone's city
(`deviceTimeZoneProvider`, `flutter_timezone`, 2 s timeout; `lib/insights/zone_locations.dart`, generated from the
system's `zone.tab` by `tools/zone-locations.py`); an unknown zone gives none. One location serves the whole span
(travel ignored). `sunTimes` is the sunrise equation with NOAA's terms (upper limb, refraction), polar days 24 or 0
hours. `dayLengths` is a `DayCondition.measure` (a quantity, not levels) in `InsightsInput.conditions`: `_timeTerms`
adds it as one centred column only when every day has a value, its own inflation against the trend, month and shift
terms and the habit's column's beside them are both within `maxVarianceInflation`, so it never turns a comparison into
a refusal by itself. Over months it is nearly all month levels and trend and seldom joins; a finding that held it says
"compared at the same length of day". No "after sunset" comparison: at a fixed clock hour, a habit logged in the
evening would look tied to darkness through winter alone.
