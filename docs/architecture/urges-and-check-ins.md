# Urges, random check-ins and the heavy-day prompt

**Urges** (round 24 "Log an urge", Jack, 2026-11-16). An urge that need not have become an entry: long-press (or
secondary-click) a tile on Today, or its screen reader's custom action "Urge", or Option-Cmd-1 to 9 and the Mac's
Log > Urge menu, opens `UrgeSheet` (`lib/widgets/urge_sheet.dart`): strength 1 to 5 on the entries' scale and words
(`UrgeField`), and Done; `noteUrge` (`lib/writes/note_urge.dart`) writes it now with Undo, returning a past day to
today. Collection `urges`, born sealed (`bornSealedCollections`): plaintext `ownerID`, `viceID`, `createdAt` (the
device clock, as an entry's, so an offline urge still matches the range query; not stamped with `updatedAt`), and
`sealed` holding `UrgeContent` (`lib/data/urge.dart`): `strength`, `zone`, and `outcome` (`passed`, `stillThere`,
`hadOne`) with `outcomeAt`, present together. Rules: owner only, that field set on create, `viceID` a vice the writer
owns (`ownsVice` last), updates change `sealed` alone. One query shape, `ownerID` and a `createdAt` window newest first
(`urgesProvider`, `lib/providers/urge_provider.dart`, index `urges` (`ownerID`, `createdAt` desc)), over every habit,
filtered on the device. If the person turns on "Ask “Still there?” in 15 minutes" in the sheet (per device,
`urgeCheckInProvider`; the first turn-on asks notification permission), a quiet notification 15 minutes later
(`scheduleUrgeCheck`, ids 3000 to 3999, the lowest free one; payload `urge:<id>`, never the habit or strength) offers
Passed, Still there and Had one under category `urge-check`. All three are foreground actions: iOS hands a background
action to a separate engine with no sign-in or journal key to seal with. The answer waits in
`pendingUrgeAnswerProvider` until Today has a key, reads the urge (`TrackerWrites.readUrge`), reseals it with the
outcome (`answerUrge`), and for Had one opens the amount sheet on that habit; a tap on the notification opens the
urge's sheet. Answering in the app, Undo and Delete cancel that urge's check-in; sign-out and deletion cancel them all.
Trends draws the chosen habit's urges as hollow rings along the chart's foot at their times (`urgeChartPositions`), a
bar after every other so touch indices hold, and names their count in the summary and the readout; Trends' day view
lists the day's urges (`UrgeRow`), each opening its sheet (strength, "What happened?", Delete). Never in totals,
averages, Insights, Ask or the letter. Neutral words: no praise, streaks or counts of urges passed. The export adds
`penchant-urges-<date>.csv` and an `urges` array.

**Random check-ins** (round 24 "A few random check-ins a day"). Off by default, per device: Settings > Reminder >
Random check-ins, with From and Until (default 9:00 to 21:00, at least 3 hours, same day); turning on asks
notification permission. `CheckIns` (`lib/reminder/check_ins.dart`) draws `checkInsPerDay` (3) moments a day with
`Random.secure()`, one uniform to the second in each third of the window (`drawCheckInTimes`), for
`checkInDaysAhead` (5) days, and keeps them in shared_preferences with the last day drawn: launch (via
`dailyNudgeStartupProvider`) and each answer only add days, never redraw a waiting prompt (redrawing on each open
would tie prompt times to app use); a new window redraws all. Each prompt is a quiet notification "Any urge right
now?" (`scheduleCheckIns`, ids 5000 to 5999 rolling, category `check-in`, payload `check-in:<answer id>:<prompt
ms>`, never a habit) with foreground actions 0 to 5 (as urges', for the journal key); a tap on its body opens
`CheckInSheet` (`lib/widgets/check_in_sheet.dart`, 0 to 5, one tap answers, Not now, Turn off check-ins). The press
waits in `pendingCheckInProvider` (a repeated press of one prompt is ignored) until Today has sign-in and a key, then
`answerCheckIn` (`lib/writes/answer_check_in.dart`) writes it with Undo (delete) and withdraws the notification.
Collection `checkIns`, born sealed, naming no habit: plaintext `ownerID` and `createdAt` (device clock when the press
came), `sealed` holding `CheckInContent` (`lib/data/check_in.dart`): `strength` 0 to 5, `promptedAt`, `zone`,
`answeredVia`. Rules: owner only, that field set on create, no update (Undo deletes). Its one query is `ownerID`
equality alone (`allCheckInsProvider`, `lib/providers/check_in_provider.dart`: every answer read once per Insights
open, the automatic index); the export (`penchant-check-ins-<date>.csv`, a `checkIns` array), account deletion and
the guest sweep read it too. Turn-off cancels every prompt, shown or waiting; sign-out and deletion `forget()` the
setting and the drawn prompts. Insights compares them with entries' urges (`lib/insights/check_in_urges.dart`, card
`lib/widgets/check_in_urges_card.dart` under What sets it off): per unarchived habit, over the days (`lateDayOf`)
holding both an answered check-in and an entry of it with an urge, that day's mean urge at entries less its mean at
check-ins, a check-in's 0 read as 1 (an entry's scale starts at 1, so the scales alone would put entries higher; the
card shows those means and counts the 0s). The differences are tested against 0 through `judgeDays` (an
intercept-only fit: the lag-1 widening and the weekly block bootstrap), from `minCheckInUrgeDays` (14) such days, in
the page's family, floor one point (`checkInUrgeFloor`); a refusal joins `setsOffRefusals` last in source order.
Every check-in counts for every habit (it asks about any urge), and a late answer counts at the time it was given.
`test/insights/check_in_urges_test.dart` holds the null simulations (one urge read both ways; a mean-zero drift in
entries alone, where the test by itself rejects at about 8% and the floor keeps cards out) and the power.

**Heavy-day prompt** (`lib/reminder/heavy_day.dart`, `heavy_day_nudge.dart`; off by default, in Reminder settings
with its time, default 21:00). A habit's day is heavy when its total is strictly above the nearest-rank 90th
percentile of its days with use among the 90 before it, given 10 such days and a first entry 30 days old; one
bounded `get()` of those days per launch, only while the switch is on. Then one notification at the set time,
"Anything different about today?", naming no habit or amount (first seen after that time: 09:00 the next morning,
about yesterday), cancelled when the day stops being heavy and on sign-out; a tap opens that day's note. Logs made
while the app is closed count from the next launch or resume.
