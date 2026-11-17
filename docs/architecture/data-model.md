# Data model: collections, fields, rules, units, lines, strength, days, indexes

**Data model.** The app is Penchant and its UI says "habit" (Jack, 2026-11-05, #81); Dart identifiers, routes,
Firestore names and export columns keep "vice", to stay compatible with stored data and old exports. Flat top-level
collections joined by `viceID` (and `dayNotes` and `urges`, Urges below): `vices` (`name`, `unit`, `ownerID`, `createdAt`, `archived`, `category`, optional
`unitLabel`, `unitSingular`, `costPerUnit`, `currency`, `lineAmount`, `linePeriod`) and
`activities` (`viceID`, `quantity`, `ownerID`, `createdAt`, optional `amount` and `updatedAt`, and sealed content:
`triggers` and the optional `urge`, `note`, `zone`, `writtenAt`, `loggedVia`); a third, `summaries`, is server-written (Server side,
below).

An activity's sealed content is `ActivityContent` (`lib/data/activity_content.dart`, capture detail C, Jack,
2026-11-13), the one place it is read and written: `urge` an int 1 to 5 (Barely to Couldn't not); `note` one line of
at most 500 UTF-16 code units, trimmed, absent when empty; `zone` the device's IANA time zone at logging
(`logZoneProvider`, read at launch and resume, never awaited by a log, so absent until it answers); `writtenAt` the
device clock in epoch milliseconds when the entry was first written (not server time, which would stamp a queued
offline log with its sync time); `loggedVia` `oneTap`, `sheet` or `widget` (onboarding's first logs count as
`sheet`). A missing or mistyped value parses as absent; `zone`, `writtenAt` and `loggedVia` are set on create and
never edited. The amount sheet and editor (`AmountFields`) and the picker after a log (`askWhatWasGoingOn`) ask for
urge and note (`lib/widgets/urge_note_fields.dart`); the sheet's own picker asks triggers only. `answersTooLong`
refuses answers whose JSON beside the longest silent fields would pass the envelope's 4094 bytes. It also holds the
optional `followUpQuestion`, `followUpQuote` and `followUpAnswer` (Follow-up question), sealed only. Insights reads
`urge` (Random check-ins) and `loggedVia` (Say it to log and Catch up) alone, and still places an entry abroad on the
viewer's hour; the export appends `urge`, `note`,
`time_zone`, `written_at`, `logged_via` after `triggers`. An older build that edits an entry's triggers rebuilds the
envelope from its triggers alone and drops the rest (accepted, Jack, 2026-11-13).

`triggers`: at most 10 strings of 1 to 60 UTF-16 code units, each a node-id path in the starter tree
(`lib/data/trigger_tree.dart`, e.g. `work/meeting`; shipped ids never change) or a free-text label. Only
`lib/data/activity_triggers.dart` touches it, so sealing it (`r2-e2ee`) is one file: a missing or mistyped list parses
as empty, writes omit an empty one, the export joins with `; `. Rules cannot loop, so `validTriggers` in
`firestore.rules` checks each of the 10 indexes.

The starter tree is 174 tags in 11 areas (round 21, Jack, 2026-11-15: "Adopt it all"); `test/triggers_test.dart` pins
the 40 paths shipped first. The picker (`TriggerChoices`) has one field that searches every tag (`searchTriggers`)
and adds the typed text as own words when no label matches it exactly.

**Day notes** (round 20). `dayNotes/{uid}_{yyyy-MM-dd}`: plaintext `ownerID`, `day` (the local day asked about),
`createdAt`, optional `updatedAt`, and `sealed` holding `text` (1 to 2000 UTF-16 units), `triggers` and the optional `followUpQuestion`,
`followUpQuote`, `followUpAnswer` (Follow-up question); born sealed, so the rules refuse any
other field, require the id to be the writer's uid and the day, and let an update change `sealed` (and `updatedAt`)
alone.
`DayNote` (`lib/data/day_note.dart`), `TrackerWrites.setDayNote` (a create unless passed the note it replaces) and
`deleteDayNote`, the provider chain in `lib/providers/day_note_provider.dart`. Account deletion, the guest sweep and
the server's orphan sweep take their collections from `Account.ownedCollections` and `OWNED_COLLECTIONS`
(`functions/cleanup.js`), which must match; the export adds a day-notes CSV. `DayNoteSheet`
(`lib/widgets/day_note_sheet.dart`, route `/day-notes/yyyy-MM-dd`, `dayNoteRoute`) is two `NotePanels`, text then
tags; Today shows the note's first line under the tallies. Insights reads the tags alone (What sets it off,
below), never the text or follow-up.

The rules check `ownerID` against the stored document on read, update and delete and the incoming one on create, fix
each collection's field set and types on create, allow updates only to `name`/`unit`/`archived`/`category` (vices) and
`quantity`/`createdAt`/`amount`/`triggers` (activities), and validate only changed fields, so legacy documents (vices
without `archived`, names over 60, zero quantities, activities whose vice is gone) stay readable and editable.
`updatedAt` (activities and day notes, `lib/data/updated_at.dart`): plaintext, never sealed, set by `TrackerWrites` and
the first-launch migrator to `FieldValue.serverTimestamp()` on every create and update of those two collections and
never on a vice; the rules accept it only equal to `request.time` and refuse removing it, and older builds' writes
without it still pass. It is never parsed into a model, so a pending write's unresolved value reaches no widget, and it
stays out of `SentWrite.fields`.
Enforced, and mirrored by `lib/data/limits.dart`'s validators: a vice name of 1 to 60 UTF-16 code units (rules
`size()`, Dart `String.length`); a new quantity an int of at least 1, so a free day is not a zero entry; an amount, if
present, above 0; a new activity's `viceID` naming a vice the writer owns, via one `get()` (billed even if denied).

A decimal Quantity stores `amount` plus `quantity` rounded up (`storedMeasure`, `lib/data/vice_activity.dart`), so
builds reading only `quantity` still count it; a whole one, `quantity` alone unless the entry has an amount. Charts,
totals and labels use `ViceActivity.measure`: the amount if present and `quantity` still equals its rounding up, else
`quantity` (an older build's edit changes only `quantity`, and wins). Only `ViceActivity.fromJson` reads the amount
and only `TrackerWrites` writes it, so sealing it (`r2-e2ee`) touches two places. `parseAmount` (`lib/formats.dart`)
takes the region's decimal mark or a point and refuses grouping. Parsers never throw: `lib/data/json_fields.dart`
defaults a missing or mistyped field (empty string, `false`, 0, nearest int for a double, null for an amount not a
positive number, `Unit.item`; `createdAt` the epoch, or now while pending writes leave its server timestamp
unresolved). A new field needs a rules change and a test.

`Unit` (`lib/data/unit.dart`) and `ViceCategory` (`lib/data/category.dart`; not `Category`, which Flutter's foundation
exports) are stored by enum name; `Unit` supplies singular/plural labels. Rules check a category against the same
list, optional on create since older versions omit it. A missing one parses as `other` with `Vice.categoryStored`
false; `categoryMigrationProvider` (`lib/writes/category_migration.dart`, kept alive by `MyApp`) writes
`guessCategory(name)` to each such vice in the signed-in user's live list, once per vice per launch, via
`fillViceCategory`, a transaction that writes only if the server copy lacks a category, since a launch's first
snapshot is cached and on a second device can predate a category picked elsewhere. Offline it fails and a later
snapshot or launch retries; nothing queues. An archived vice leaves recording and Today's dial, tallies and Log fan;
Manage Data still opens its history and Trends lists it last (Today and Trends, below).

**Units and price.** A vice may carry its own unit label (`unitLabel`, 1 to 20 UTF-16 code units, in place of the
`Unit` preset's words: `Vice.units`, a `UnitWords`) with its form for one (`unitSingular`, same bounds, ignored
without a label; a count of 1 and "per" use it, else the label serves for both), a `costPerUnit` (above 0, at
most 100,000) and its ISO 4217 `currency`, all optional and sealed only: this build never writes them in plaintext, so
the habit form refuses a label or price change while no journal key is loaded. `lib/data/limits.dart` bounds them
(the rules repeat the bounds for a plaintext write) and `json_fields.dart` reads a missing or out-of-range one as null.
The form starts a price in another habit's currency, else the device region's (`deviceCurrency`). Spend is the
habit's `measure` total times its price (`Vice.spendOf`): Trends shows it under the stats for the last 7 days
(`lastSevenDaysTotal`) and the range. An older build's `updateVice` reseals only `name`, `unit` and `category`, so an
edit of the habit there drops the label and price (archiving does not reseal); null falls back to the preset and no
spend. No per-entry cost yet.

**A habit's line** (Jack, 2026-11-13, round 17 `goals` C). Optional `lineAmount` (above 0, at most 100,000, decimals
as an entry's amount) and `linePeriod` (`day` or `week`), sealed only like the price, read together as `Vice.line`
(`HabitLine`, `lib/data/habit_line.dart`; half a line or a value out of bounds reads as none, and an older build's edit
drops it). Set in the habit form (None / A day / A week and a stepper; off by default) or from Insights: a card whose
finding is a line in the amount (`doseLine`) offers "Mark 3 a day as Wine's line" (`LineOffer`,
`lib/widgets/line_offer.dart`) on an unarchived, unlocked habit, offers to change another line showing it, and says
so once set; its state is the stored line, so every card agrees. It is a mark to read totals against, never a goal: no
colour change, alert or streak past it. Today's habits are tiles two across (`TallyGrid`, one across past 1.3× text; `TallyRow` is
the tile: name, total, +, a zero's name and number greyed). A tile with a line reads "2 of 3 a day" (a week line "22 of
30 in 7 days", the 7 days ending on the shown day, `viceActivityWeekProvider`, queried only while a habit has a week
line) over a bar with a tick at the line, three quarters along until the total passes the bar's end
(`TallyRow.lineScale`). Trends draws it as a straight dashed ink line labelled "your line 3", only over buckets of its
period and not in Spend (else a caption says which view shows it), and "Over your line" replaces Peak.

**A habit's strength** (round 24, "Strength and standard units"). Optional `strengthUnit` (`ukUnit`, `grams`,
`standardDrink` or `mg`), `servingMl` (above 0, at most 5,000), `abv` (above 0, at most 100), `drinkGrams` (above 0, at
most 100) and `caffeineMg` (above 0, at most 2,000), read together as `Vice.strength` (`HabitStrength`,
`lib/data/habit_strength.dart`): an alcohol definition needs its serving size (a standard drink also its grams), the
usual ABV or mg is optional, and a missing or out-of-range value reads as absent. Unlike the price and the line they
were sealed from the start: the vices update key list leaves them out, so the rules refuse them in plaintext on any
vice. An entry may carry its own `abv` or `caffeineMg` (`ActivityContent`, rounded to two places by `roundStrength`,
which `answersTooLong` allows for), which wins over the habit's; an older build's edit drops the habit's, as it drops
the price. Units follow the NHS (nhs.uk/live-well/alcohol-advice/calculating-alcohol-units): ABV × ml ÷ 1,000 UK
units, 8 g a unit; a standard drink is grams of alcohol the person sets, so no country's definition is built in.
Set in the habit form's Strength section (None / Alcohol % / Caffeine mg); the amount sheet and editor offer
"Strength this time" (`StrengthField`) only for a habit with one. Trends' Units view and its tiles count each entry
at its strength (`bucketUnits`); entries with none count nothing and the view says how many. It only measures: no
guideline, colour or warning. The export appends `own_abv`, `own_caffeine_mg`, `strength_total`, `strength_unit`.
Insights and Ask read none of it. On iOS a habit with a strength may also write its entries to Apple Health
(`lib/health_write/`; the habit form's "Also write to Apple Health", off by default, per device and habit in
shared_preferences `healthWrite.<uid>`, applied on Save; turning it on asks write access to that one type, a refusal
turns it off and says where to change it). Alcohol writes `numberOfAlcoholicBeverages`, one per serving (the entry's
`measure`, whatever its ABV: Apple's standard drink is "one beer, glass of wine, or mixed drink"); caffeine writes
`dietaryCaffeine`, the entry's mg at its own strength else the habit's, and an entry with none writes nothing. Each
sample sits at the entry's `createdAt` with `HKMetadataKeySyncIdentifier` `penchant.entry.<activity id>`, sync version
the device clock in ms (a later save replaces it) and `PenchantHabit` `penchant.habit.<vice id>`; nothing else about
the journal is kept. `healthWriteSyncProvider` (kept by `MyApp`) keeps Health in step with the 30 days the widgets'
snapshot already listens to (`viceActivityRecentForUserProvider`), so logs from anywhere (this phone, a widget flushed
in the background, the Mac) are written when the running app sees them, an edit rewrites, and an entry gone from the
window (a delete, an Undo) is removed; what it last wrote is held in memory only, so each launch rewrites the window
once, unchanged. `TrackerWrites.deleteActivity` also deletes the sample, for entries older than the window. Turning a
habit off stops writing and offers once (`deleteHabit`) to remove its samples. Sign-out and account deletion leave
samples in Health (the switch's footnote says so). The Mac, PenchantSync and the iOS headless flush never touch
Health (the headless engine has no `HealthChannel`; its calls fail quietly).

**Days.** An entry counts on the local day, in the viewer's current zone, of its `createdAt` instant. Day windows and
graph buckets are local midnights from `lib/data/day.dart` (never `Duration(days:)`, which drifts an hour across DST).
The logging zone is not stored, so an entry near midnight can move a day in another zone; storing it would be a new
activity field, optional under `r2-data-model` (not built). `createdAt` is the device clock at logging (or the picked
time), not server time: a pending `FieldValue.serverTimestamp()` matches no `createdAt` range query until
acknowledged, so an offline entry would vanish from Today, and the server would stamp it with the sync time. Jack kept
the device clock (`r4-server-time`, 2026-11-06), so a wrong or hand-set clock places an entry at that time. Vices per
user and vice lists stay uncapped for 1.0 (`r4-vice-cap`, Jack, 2026-11-06).

**Indexes.** A new composite query shape needs a `firestore.indexes.json` entry; until deployed, Firestore throws
`failed-precondition` at runtime, and the emulators never enforce indexes. `test/firestore_indexes_test.dart` (#90)
parses every query chained from `.collection(...)` in `lib/` and fails when one needs a composite index the file
lacks, when a `where` with a Firestore filter argument or an `orderBy` sits outside such a chain, or when a chain uses
`limitToLast` (whose reversed sorts it does not model). The delta read's `ownerID` + `updatedAt` range has its own
(`activities`: `ownerID` asc, `updatedAt` asc); nothing reads every day note, so they have none.
