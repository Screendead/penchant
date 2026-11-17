# App structure: platforms, providers, reads and writes, account, offline, tests

Flutter over Firebase Auth + Firestore (project `screendead-vice-tracker`) for iOS 15+ and macOS 12+ only (macOS 12 is
Xcode 27's and Flutter's floor); `firebase_options.dart` throws elsewhere. Both platforms are bundle ID
`com.screendead.penchant` (tests `com.screendead.penchant.RunnerTests`) on one Firebase iOS app registration
(`r2-mac-config`, 2026-11-05: the console offered no macOS app), so `macos/Runner/GoogleService-Info.plist` copies the
iOS file and the macOS options carry its `ios` app id.

**Riverpod without codegen.** `lib/providers/` is all hand-written. `userProvider` is a plain `StreamProvider` over
`authStateChanges()`, `userProfileProvider` one over `userChanges()`. Each Firestore query is a `...ForUserProvider`,
a `StreamProvider.autoDispose.family` over a snapshot stream, behind a uid-supplying wrapper (Provider chain). The
Manage Data count is a `FutureProvider.autoDispose.family` over a `count()` aggregation; while `offlineProvider` says
offline or the server cannot answer, it counts cached documents, says which, and retries after a server failure. Don't
add a query provider that watches `userProvider` itself: that shape leaked the previous user's data.
`trackerWritesProvider` is a plain `Provider` of the write layer; `packageInfoProvider` a `FutureProvider` over
`PackageInfo.fromPlatform()` for the version in Settings > About; `todayProvider` a `NotifierProvider` of the start of
the local day, moved on at local midnight and app resume; `appearanceProvider` one of Light / Dark / Match system, per
device in shared_preferences. Match that style.

**Reads and writes both go through providers.** Widgets read via `ref.watch(...)` on a provider of `AsyncValue` and
write via `ref.read(trackerWritesProvider)`: one `TrackerWrites` (`lib/writes/tracker_writes.dart`) makes every screen
write, each to one document. Its methods (`addVice`, `updateVice`, `setViceArchived`, `newActivityID`,
`recordActivity`, `updateActivity`, `deleteActivity`) return a `SentWrite`: the SDK's future unchanged, the document,
and for an update the fields set. Timeouts, error messages and Undo stay in the widgets, which pass the write to
`ref.read(rejectedWritesProvider.notifier).settle(write, '<what, named at write time>')`. That runs `settleWrite`
(`lib/writes/settle_write.dart`): an acknowledgement within `writeTimeout` (10 s; `e2e.yml` builds with
`--dart-define=WRITE_TIMEOUT_MS=5000`) is success, a timeout is queued (the UI says it will
sync, `record-timeout`), and only a `FirebaseException` fails. It keeps listening: a later refusal goes to
`RejectedWrites` (`lib/writes/rejected_writes.dart`, the signed-in user's refused changes, cleared on uid change),
which `MaterialApp.builder` (`lib/widgets/rejected_writes_banner.dart`) shows above every screen until dismissed. The
SDK keeps queued writes across launches but answers only the launch that made them, so `settle` also journals each
write (`lib/writes/queued_write_journal.dart`, a JSON file per Firebase project in Application Support) until its
future completes. On sign-in, a launch takes the user's leftover entries, awaits `waitForPendingWrites()` (it resolves
after a refusal as after success), reads each document's server copy with an `ownerID` query bounded to its id (the
rules deny a get of a missing document), and names in the banner each write that copy lacks (`refusedAmong`). A failed
check keeps its writes for the next launch; sign-out and account deletion clear the journal with the cache.

The amount sheet (`RecordNewActivityDialog`, `lib/widgets/record_new_activity_dialog.dart`, a modal bottom sheet)
takes one `newActivityID()` per sheet, so a retry after a failed save writes the same document. The entry editor
(`ViceActivityEditorPage`) is the same sheet over the stored entry, with Delete. Their stepper (`AmountFields`) steps
by 5 for a habit whose stored typical is 10 or more (`storedTypicalsProvider`), landing on multiples of 5, else by 1. One-tap "log one"
(`logOne`, `lib/writes/log_one.dart`: a tally's `+`, a Log-fan wedge tap) logs the habit's default quantity now with a
new id per tap, so two taps are two entries. Its Undo bar (`showUndoBar`, `lib/widgets/undo_bar.dart`;
`undo-duration`: 8 seconds) also asks "What was going on?" (`askWhatWasGoingOn`, `lib/writes/what_was_going_on.dart`:
the trigger picker for that entry, its pick saved by `updateActivity`, nothing after Undo; opening it closes the bar,
so the picker offers Undo log while open, which the record sheet's and editor's pickers do not), and shows at once, since the entry is on the device when written, and says queued after 10 s
unanswered. Both Undo through `undoLog`.

**What was going on?** (round 20, Jack, 2026-11-15). `askWhatWasGoingOn` opens `WhatWasGoingOnSheet`
(`lib/widgets/what_was_going_on_sheet.dart`), three panels over `NotePanels` (`lib/widgets/note_panels.dart`): the
note, tags, the urge. Only Back and Next move between them (no swipe; an off-stage panel takes no focus, semantics or
taps), with Done, the step count and Undo log on each; what it saves, and how, is as before. With a `NoteReader`
(below) and a note, the tags panel shows the note and turns each phrase the reader quotes into a selected chip the
person can drop; with no reader, no note, an error or 10 s without an answer it is the hand picker, which is always
there. Nothing is saved until Done. The record sheet and the entry editor keep `showTriggerPicker`, which returns
the triggers alone.

Every Firebase Auth call goes through `ref.read(accountProvider)`, one `Account` (`lib/account/account.dart`):
sign-in, register (plus verification email), anonymous guest start, linking a guest to email and password (same uid,
then verification email), password reset, re-authentication, profile and email changes, sign-out, and account-wide
Firestore work. `fetchData` pages the user's vices and activities for export from the server, so offline it fails
rather than return a partial cache (`lib/account/export.dart` builds CSV and JSON; `exportShareProvider` hands them to
the share sheet). `deleteAccount` re-authenticates (not a guest: no password), deletes every owned document in batches
of 500, then the Auth user; a failure after the first batch is a `DeletionIncompleteException`; any other removed
nothing. A guest's sign-out is that deletion (Jack, 2026-11-06), since nothing can sign back in to a guest's uid and
its documents would stay on the server for good; offline it fails before removing anything and the guest stays signed
in. Sign-out and deletion first wait up to 5 s for pending writes, throwing `UnsyncedEntriesException` rather than
discard them silently or let one land after the sweep, then `terminate()` Firestore and `clearPersistence()`. The Dart
instance keeps the settings `firebase_init.dart` gave it (cache, or emulator host); the plugin builds a fresh native
instance from them on the next call. User-facing Auth error text comes from `authErrorMessage`
(`lib/account/auth_errors.dart`), never Firebase's message; account and deletion copy is in
`lib/account/account_copy.dart`.

**Provider chain.** Each `...ForUserProvider` family is keyed on the uid (and its other parameters) and wrapped by a
plain `Provider.autoDispose` (or `.family`) of `AsyncValue` selecting the uid from `userProvider` via
`watchForSignedInUser` (`lib/providers/signed_in_user.dart`): `viceListProvider` and the activity day, history, graph,
single-activity and count providers. `unarchivedViceListProvider` filters `viceListProvider` on the device rather than
querying `archived`: a field filter matches only documents holding the field, and vices written before 2024-08-14 lack
it. The wrapper is loading, with no value, while nobody is signed in, and each user's query is a separate provider,
because riverpod carries a provider's last value into a rebuild's loading state: one provider rebuilt on a user change
leaked the previous account's data. Widgets watch the wrapper; tests override it with an `AsyncValue`, or override the
family to test the wrapper. Families and wrappers are all `autoDispose`, so leaving a day, range or page closes its
listener; an unwatched wrapper would keep its family's listener open, deaf once sign-out terminates Firestore, so the
same user signing back in would see a frozen list. No activity provider depends on the vice list: the day query
filters on `ownerID` and `createdAt` alone (an `in` filter on vice IDs takes at most 30) and Today drops activities of
vices it does not draw. `null` means loading; an empty list, no data. Never gate UI on `ref.read(provider.future)`: in
riverpod 3 a read with no other listener pauses the stream and the future never resolves; render loading and error
from the watched `AsyncValue`. A `User` is a snapshot that profile updates and `reload()` never change; only
`userChanges()` re-emits after them, and also on every token refresh. So only screens showing the profile watch
`userProfileProvider`: Account Settings (calling `Account.reloadUser()` on opening and app resume, for a verification
made elsewhere), Settings (a `select` on email and guest status), and Today's `guestDaysLeftProvider`
(`lib/account/guest_expiry.dart`, the warning before Firebase's 30-day clean-up deletes a guest account). Linking a
guest leaves `userProvider`'s `User` anonymous, so guest checks ask `Account.isGuest`; the chain stays on
`userProvider`.

**Query bounds.** Day and graph queries are bounded by their date window; history pages 50 at a time
(`ViceActivityHistoryPage.pageSize`, plus one to learn whether older entries exist); the calendar sheet reads one
month for its dots (the day query's shape and index); the editor listens to its one document; Manage Data counts each
vice's activities with a server-side `count()`, which is not live, ignores writes queued on the device, and fails
offline. Insights, Ask and the weekly review read every activity from 2000 (the date picker's floor) to today, an
unbounded activity query, through `readJournal` (`lib/providers/journal_read.dart`, behind
`viceActivityRangeForUserProvider`): once per open, not a listener, so a log written meanwhile shows on the next open.
A device's first read for a uid, one 7 days after its last full read, and every read where Firestore has no disk cache
(emulator builds) is the full `get()`; it keeps a cursor per uid in shared_preferences (the newest server `updatedAt`
seen less 5 minutes, or the epoch, and the full read's date; timestamps only, cleared with the cache on sign-out and
deletion). Any other open asks the server for entries with `updatedAt` at or after the cursor, one `count()` of the
range, and reads the range from the cache with the delta laid over it; a count that differs (a delete elsewhere, an
evicted entry, an unstamped create by an older build) or any failure (offline, an index building) falls back to the
full `get()`, which offline answers from the cache. An older build's edit elsewhere changes neither cursor nor count,
so this device may miss it for up to 7 days. Ordinary open (an estimate): a read per entry the delta returns (at least
the newest, which the 5-minute overlap returns again) plus 1 per 1,000 entries counted; a full read costs one per
entry. A shorter range (the heavy-day window, a review week) is a plain `get()`. Ask also reads every day note once
per open (`allDayNotesProvider`: `ownerID` equality alone, the automatic index). Habits learns whether
entries of a deleted (or foreign) habit exist by one more `count()`, every owned activity, less each habit's count
(`deletedHabitCountProvider`, shown only when every count is the server's); only then is its "Deleted habit" row there,
and `DeletedHabitPage` reads every owned activity once per open (the export's shape, paged by document id, from the
server), then every owned vice, to list those of no vice. Their deletes are confirmed on the page, with no Undo: the
rules refuse recreating an entry whose vice the writer does not own. The vice lists have no limit (`r4-vice-cap`, under
Days).

Tests in `test/` run without Firebase, overriding providers in a `ProviderScope` or `ProviderContainer`
(`test/fakes.dart` builds models and a mocked `User`). Firestore writes go through `TrackerWrites` and Auth calls
through `Account`, so fakes cover every write path: `test/fake_writes.dart` records each write (for
`trackerWritesProvider.overrideWithValue`), `test/fake_account.dart` likewise for `accountProvider` and
`exportShareProvider`. Code calling `FirebaseFirestore.instance` or `FirebaseAuth.instance` directly is untestable
that way; `integration_test/` drives the real app on an iOS Simulator against the emulators instead (Commands covers
it and the rules suite).

**Offline.** Production Firestore has disk persistence and an explicit 100 MB cache (`_configureFirestoreCache`,
`lib/firebase_init.dart`); the emulator path has persistence off. Every write awaits through `settleWrite` (Reads and
writes, above). `ViceActivity.pending` carries `hasPendingWrites`; the day and history providers listen with
`includeMetadataChanges: true` so the server's acknowledgement clears it. `offlineProvider` is true once a vices
listener has answered from cache for three seconds; it drives the offline banner and an empty day's offline wording.
`syncStatusProvider` (`lib/providers/sync_status_provider.dart`) drives the header's Synced/Syncing pill and the menu
footer: `TrackerWrites` reports each write as issued, and the tracker calls `waitForPendingWrites()` again after each
(a wait covers only writes issued before it, earlier sessions' included), so Synced means every write is acknowledged.
The day's "not yet synced" note shows only offline. The whole-journal read (Query bounds) waits up to 2 s for queued
writes before its `count()`, which skips the cache and queued writes, and offline answers from the cache as before.
