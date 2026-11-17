# iPhone and Watch extras: Night out, Apple Watch, Read a label

**Read a label** (iOS only; round 24, "Read a drink's label with the camera", on-device half). The habit form's
Strength header has "Read a label" while `labelSourceProvider` (`lib/label/label_source.dart`) is non-null, which is
iOS only, so the Mac and tests show none. `LabelSheet` (`lib/label/label_sheet.dart`) asks for a photo through
`ios/Runner/LabelChannel.swift`: the system camera (`UIImagePickerController`, `NSCameraUsageDescription`) or
`PHPickerViewController` with no photo library given, so no library access is asked; the image is loaded in memory,
Vision's `VNRecognizeTextRequest` (accurate, language correction off) reads it off the main thread, and only the
lines of text cross the channel. Nothing keeps, logs or sends the photo or the lines; the sheet says so. `readLabel`
(`lib/label/label_reading.dart`, pure, `test/label_reading_test.dart`) never guesses: a strength counts only beside
alc, alcohol, abv or vol (on its line, or alone beside a line of that word), otherwise it is offered unpicked; volume
in ml, cl or l is sure, fl oz and pints offered as both US and UK unless a metric size beside them agrees within 2%;
a volume after "per" or "/" is a reference, not the container; caffeine is an mg figure the word caffeine labels (its
line, or alone on the next), per-100 ml only times the one volume found; out of bounds (ABV over 80, under 5 ml) is
left out. One sure value is picked; several, or only unsure ones, are chips with none picked. "Fill in" only sets the
form's fields (alcohol: serving and ABV; caffeine: mg); the form's Save writes them as typed ones. No Claude
fallback yet: the card's recommendation was to add it only if the pattern misses often.

**Night out** (iPhone, iOS 17+; round 24). A habit tile's long-press menu (`TileAction`, `lib/widgets/tally_row.dart`)
offers "Start a night" (`lib/night_out/`), which starts a Live Activity (`NightOut`, `ios/PenchantWidgets/NightOut.swift`,
compiled into the app and the widget extension; drawn by `NightWidget.swift`) counting that habit from now, with a +1
button (`NightLogIntent`, a `LiveActivityIntent`, so it runs in the app's process) that queues a log like a widget's
(`loggedVia` `widget`). Only `NSSupportsLiveActivities` in the app's Info.plist: no entitlement, no push token, local
updates only. By default the Lock Screen says "Tonight" in ink; the habit's name and colour only if chosen at the
start. The night (`NightRecord`, `NightPlan.swift`, pure, `tools/night-plan.test.sh`) lives in the App Group: `base`, the
habit's total since the start in the entries the app last saw, plus the ids of logs made outside the app since (the +1,
widgets, controls, Siri: `LogOneIntent` and `UndoLogIntent` tell it). While the app runs, `nightOutSyncProvider` (kept
alive by `MyApp`) listens to the habit's entries since the start (`viceActivitySinceForUserProvider`) and reconciles
over `com.screendead.penchant/night_out` (`ios/Runner/NightChannel.swift`): new `base`, and an outside log is dropped once
seen or once off the queue unseen (refused or undone), so an Undo, edit or delete in the app shows on the Lock Screen at
once. It ends at the first 06:00 at least an hour away, or 8 hours after the start if sooner (ActivityKit ends a Live
Activity at 8 hours); no code runs then, so the stale date hides the +1 and the next launch, resume or tap ends it. One
night at a time. Native ends it at launch (`AppDelegate`) and Dart on resume and on a user change (sign-out, account
deletion) when it is over, not the signed-in user's, or removed from the Lock Screen. Today shows `NightStrip` with End
while it runs. Not offered on the Mac (`nightOutProvider` is null there).

**Apple Watch** (round 24 "Log from an Apple Watch"). `PenchantWatch` (`com.screendead.penchant.watchkitapp`,
SwiftUI, watchOS 10+, `ios/PenchantWatch/`) and its complications `PenchantWatchWidgets` (a WidgetKit extension
inside it, `ios/PenchantWatchWidgets/`) are targets of `ios/Runner.xcodeproj` (`tools/add-watch-target.rb`), embedded
in Runner at `Watch/`. The watch holds no key, token or entry: only the iPhone's last `WatchContext`
(`WatchModel.swift`, compiled into Runner too: the account's uid, the iPhone's day, the widgets' top 8 habits in the
app's order with unit words, mark and today's total, and the ids of the watch's logs those totals count) and its own
outbox, in its App Group. A tap on a row (`HabitList.swift`) logs one: `WatchJournal` (`WatchSession.swift`) hands a
`WatchMessage` (an entry id made on the watch, the uid, the habit id, the tap time) to `WCSession.transferUserInfo` at
once, plays the success haptic and shows the context's total plus its own uncounted logs. Undo, for 8 seconds,
cancels a transfer still waiting and sends an undo after one that has left. On the iPhone `WatchLink`
(`ios/Runner/WatchLink.swift`, activated in `didFinishLaunching` after `BackgroundFlush.register()`) puts the log on
`LogQueue` with `via` `watch`, dropping an id it has already taken, so the widgets' flush writes it sealed, with
`loggedVia` `watch` (an older build reads the name as absent). An undo goes through `LogQueue.undo`, and only for an
id it has taken: the rules refuse deleting an entry that was never written. It answers with
`updateApplicationContext` on each snapshot save, on clear (no uid: the watch then shows nothing), on `removeLogs`
and on each message. The totals are `WatchContext.build`: the stored snapshot's column for today (none if the app has
not run today), the queue's unwritten logs, and `WatchTally`, which holds a ledger of what a flush wrote since the
last snapshot save (the headless flush saves none) and the queue entries a saved snapshot already counts. On a day
the iPhone has not reported, the watch counts only its own logs and says so (`WatchBoard.current`); a log the iPhone
has not counted after 20 seconds is shown as waiting. The complications (accessory circular, corner, inline and
rectangular, one recommendation per habit) show one habit's total, reload at local midnight, and open the app on that
habit (`WatchHabitLink`): Apple allows buttons in accessory widgets on iPhone and iPad only, so logging from the watch
face is two taps. Flutter finds the companion by `WKCompanionAppBundleIdentifier` in `ios/PenchantWatch/Info.plist`
(the folder must keep the target's name) and then leaves `-sdk` and `ARCHS` off xcodebuild.
`tools/watch-model.test.sh` runs the model's tests on the Mac; `-penchantDemo list|logged|new-day|signed-out|empty`
(debug builds) shows made-up habits with no session. Not yet run on a watch, or on a watch simulator.
