# e2e triage (2026-11-09)

Per test in `integration_test/`: KEEP (needs the real app, emulators or keychain), MOVE (to a widget test),
DELETE (covered elsewhere). Durations are from CI run 42690070034 (iOS). MAC* = takes the split-pane path in the
1200 pt Mac window, not Mac-specific behaviour.

Background: `test/` has no fake Firestore; every query body and every write checked against the real rules runs only
in e2e. A DELETE stands only where each query or write it exercises is still run and asserted by some KEEP test.
`ensureE2EBinding` forces Flutter auth fields, so no e2e test touches the macOS native fields. `writeTimeout` is 10 s,
and every offline write the tests wait on costs about 10 s.

| File :: test | Call | Reason |
|---|---|---|
| about_version :: Settings shows the version the binary was built with | KEEP MAC, fold into smoke | real `PackageInfo` channel reading the built bundle |
| about_version :: the keychain keeps a journal key per uid | KEEP MAC, fold into smoke | real Keychain (synced vs this-device item, conflict refusal) |
| about_version :: AES-GCM runs in CryptoKit, not Dart | KEEP MAC, fold into smoke | only a device shows the native AES path is taken |
| accessibility :: screen readers hear the dial, each bead and tally, and the graph | MOVE | covered by test/accessibility_test, vice_tracker_test "each bead is a button…", trends_sheet_test "peeks…"; add: Log out of the semantics tree under the open sheet (trends_sheet_test) |
| accessibility :: an activity can be recorded at the largest text size | DELETE | test/accessibility_test "at text scale 3.0" group; its write is plain record, owned by smoke |
| account_switch :: signing out and in as someone else never shows the first account's data | MOVE | leak lives in the riverpod chain; add graph, history, single-activity and count wrappers to activity_providers_test "never returns the previous user's data…" |
| account :: registering sends a verification email; a reset link sets a new password | KEEP | real Auth verify/reset emails, new password signs in, Firestore usable after terminate |
| account :: Account Settings shows the profile as saved and a verification made outside the app | KEEP | SDK `reload()` + `userChanges()` picking up an outside verification |
| account :: export shares a CSV row per entry and a JSON…, offline fails | KEEP (trim) | `fetchData` from the server failing offline; format checks duplicate export_test, trim to row counts |
| account :: deleting an account removes its documents and its sign-in… | KEEP | real re-auth, batched delete under the rules, Auth deletion |
| activity_flows :: arrows and the calendar change the shown day and stay enabled | DELETE | vice_tracker_test "arrows change the day…", "a day whose data never arrives…", "the date pill opens a calendar…" |
| activity_flows :: Undo on the record snackbar deletes the activity just recorded | DELETE | vice_tracker_test "the recorded snackbar offers Undo…", writes_test "records the activity, closes, and Undo deletes…"; delete under rules owned by offline_test |
| activity_flows :: a tally's + logs one now, a wedge logs one, Undo removes the latest | DELETE | vice_tracker_test "+ logs one now…", "opens a wedge for each habit…"; real one-tap write owned by guest_test |
| activity_flows :: the tallies follow each habit added and the day shown… | KEEP (trim) | last e2e owner of the past-day day query; drop clear-day copy and new-habit rows (vice_tracker_test) |
| activity_flows :: a trigger picked while recording is stored and shown on the history row | MOVE | add dialog passes `triggers` (writes_test record dialog) and history row label (history_page_test); pass triggers in sealed_fields_test's record |
| activity_flows :: an activity can be deleted from the history page and from the editor | DELETE | offline_test does both deletes and asserts the server; UI in writes_test |
| activity_flows :: editing a legacy activity writes only the field the user changed | MOVE | writes_test activity editor group with legacy fakes; rules in rules.test.js; add `setEntryTime` to write_flows' decimal edit |
| archive :: an archived vice leaves recording and Today, keeps its history… | MOVE | widget_state_test "an archived vice", trends_sheet_test; add "no wedge for an archived habit" to vice_tracker_test |
| bounded_queries :: Today totals an account with more vices than an `in` filter takes | KEEP | only real Firestore refuses an `in` over 30 |
| bounded_queries :: the history page shows 50 entries at a time… | KEEP | history query's `limit` and order run only on real Firestore |
| category_migration :: a launch cut short leaves legacy vices half filled… | KEEP (trim) | transaction against the server copy, rules accepting a category-only update; drop the Edit Habit UI step |
| cold_start :: a signed-in launch goes straight home… | KEEP | Auth SDK's first `authStateChanges` event with a session |
| error_states :: a vice list the rules deny shows why, with a Retry | KEEP | the plugin's real error type and code for a denied listen |
| guest :: a guest who signs out erases their journal from the server | KEEP | anonymous Auth, password-less deletion under the rules |
| guest :: a guest who adds an email keeps their entries… | KEEP | real `linkWithCredential` keeps the uid; live data after terminate |
| key_service :: with E2EE on, the first launch makes a key… | KEEP MAC, fold into smoke | real keychain, `keys/{uid}` transaction under the rules |
| log_fan :: a press dragged onto a wedge logs one on release… | MOVE | vice_tracker_test Log fan group; add: released above the fan logs nothing, fan stays open |
| log_fan :: a screen reader logs one from Log's actions and from a wedge… | MOVE | vice_tracker_test; add: custom action writes, semantics tap and long-press on a wedge |
| navigation :: Manage Data's Edit renames a vice and changes its unit | DELETE | sealed_fields_test makes the same edit and asserts sealed content; UI in writes_test "Edit Habit" |
| navigation :: Trends opens over Today, and Log comes back on its edge | DELETE | test/navigation_test "has no tabs…", trends_sheet_test "peeks…, opens on a tap, and closes again" |
| navigation :: Settings opens only real pages, and signing out lands on sign-in | MOVE | add "no Notifications or Privacy rows" to test/navigation_test; sign-out via Settings owned by account_test and guest_test |
| navigation :: a session that ends under pushed pages returns to sign-in | MOVE | MyApp popping routes on a uid change → widget_state_test |
| offline :: entries logged, edited and deleted offline… sync once | KEEP (trim) | offline queue, pending metadata, `count()` fallback, replay; log via `logOne` instead of the dialog |
| onboarding :: a new account picks two presets and logs one | DELETE | test/onboarding_test "picking two presets…", "the flow stays up…"; `startApp` + key owned by smoke |
| rejected_write :: an entry saved offline that the server refuses… is named | KEEP, fold into the Undo test | same setup as the next test; move its asserts there |
| rejected_write :: an Undo of an entry the server refuses is not called not deleted | KEEP | only the emulator checks the SDK/rules ordering writes_test fakes |
| rejected_write :: an Undo refused before its own timeout… | KEEP | same ordering question, other timing window |
| rejected_write :: an entry queued offline that is lost before the next launch is named… | KEEP | real `terminate()` dropping the queue, journal file, bounded server read |
| sealed_fields :: with a key, habits and entries are stored sealed… | KEEP | only e2e owner of `updateVice` reseal under the real rules |
| sealing_migration :: a launch with a key seals every legacy plaintext vice | KEEP | server paging past 500 docs and the rules' plaintext-to-sealed conversion |
| smoke :: register, add a vice, record an activity, see it listed | KEEP MAC | whole stack via `startApp`: key service, keychain, CryptoKit, Auth, listeners, `count()` |
| split_view :: from 900 pt Trends is a pane beside Today… | DELETE | test/split_view_test covers 900/1200/1600, resize, day point, keys; the e2e sets `physicalSize` itself |
| trends :: Trends buckets stored activities by day and by week… | KEEP (trim) | last e2e owner of the graph range query; drop weekly and day-open parts (trends_sheet_test) |
| write_flows :: archiving a vice takes it off Today and unarchiving brings it back | DELETE | real archive write owned by the next test; UI in writes_test |
| write_flows :: a vice stored without the archived field shows on Today… | KEEP | Firestore drops documents missing a filtered field; legacy doc under the rules |
| write_flows :: the editor saves a changed quantity | DELETE | offline_test edits a quantity and asserts the server; UI in writes_test |
| write_flows :: a decimal quantity is stored as its amount… | KEEP | SDK encoding of `amount`/`quantity` against the rules' types; takes the `createdAt` fold |

Mac job: smoke_test alone, with about_version and key_service folded in. No e2e test covers the native auth fields
(the harness forces Flutter fields) or the saved window frame.
