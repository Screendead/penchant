# Sealed fields, the key service, sealed device files and backup

**Sealed fields** (`r2-e2ee`). A vice may hold its content fields (`name`, `unit`, `category`, `unitLabel`,
`unitSingular`, `costPerUnit`, `currency`, `lineAmount`, `linePeriod`) in one `sealed` bytes
field instead: the `lib/crypto/sealer.dart` envelope (`version | nonce | ciphertext | tag` around JSON padded to
64/256/1024/4096 bytes), the document path as associated data, so only the user's key opens it, only on that document.
An activity seals its content (`triggers`, `urge`, `note`, `zone`, `writtenAt`, `loggedVia`); `quantity`, `amount`, `createdAt`, `viceID`, `ownerID` stay plaintext (Jack,
2026-11-06: a server job aggregates amounts), and `monthlySummaries` reads only `viceID` and `quantity`. A vice's
`ownerID`, `createdAt` and `archived` stay plaintext, so queries, indexes and `count()` are unchanged. A new content
field joins `contentFields` (`lib/data/sealed.dart`) and the rules' `sealedAlone` and `changedContent` calls, unless
the rules' create and update key lists refuse it in plaintext, as they do an activity's fields after `triggers`.
Rules refuse a create without `sealed` or with content beside it (Jack, 2026-11-09, `plaintext-creates` C), bound
`sealed` to 30 to 4125 bytes, refuse removing it, still let legacy plaintext documents be read and edited, and let an
update convert one by setting `sealed` and deleting the plaintext fields (a deleted field is an affected key). They
cannot read sealed content, so there `lib/data/limits.dart` is the only guard. The envelope binds the
document path only: an entry's plaintext time, quantity and habit, a vice's `archived`, and a roll-back to an older
`sealed` value are not detected, an accepted limit (Jack, 2026-11-11, round 14 `tamper` A).

`lib/data/sealed.dart` holds `FieldSealer` (sole implementation `lib/crypto/journal_field_sealer.dart`),
`sealerProvider` (null while no key exists: `TrackerWrites.canCreate` is false and `addVice`/`recordActivity` throw, so
every create path checks it first, says the journal key has not loaded and keeps the input; onboarding's Continue
waits; widget logs stay queued; updates stay plaintext. `e2eeEnabled` in `lib/crypto/e2ee_enabled.dart` is true, and
turning it off would strand every sealed journal and leave nothing creatable) and `SealedOpener`, run by each query
provider over its snapshots (`asyncMap`) and by the export. It never throws: a document that will not open parses as
`locked`, with a placeholder name and default content, reported once per listener. With a sealer, `TrackerWrites`
reseals all content on a vice update (`updateVice` takes the `Vice`, refuses a locked one), seals every new activity,
even without triggers, and reseals an activity update only when its triggers, urge or note change, sealing the whole
`ActivityContent` again (`ViceActivity.content` with the answers changed, or after a log `cachedContent`, the
device's copy, so `zone`, `writtenAt` and `loggedVia` survive; the editor never sends a locked entry's content).
Without a key only a legacy entry's triggers may change, in plaintext (`canWrite`); anything else fails as a refused
save. A locked vice counts as `categoryStored`; `fillViceCategory` skips sealed vices. `SentWrite.fields`
holds only plaintext fields, since the envelope does not exist yet when the write is handed back. Tests override
`sealerProvider` with `test/fake_sealer.dart` (real envelope, fixed key). First-launch sealing
(`lib/crypto/plaintext_migrator.dart`) uses the same conversion: once `sealerProvider` has a key and `offlineProvider`
says online, once per uid and app version, it pages each collection with content fields from the server and seals each
document lacking `sealed`, so the next run finishes a cut-short one.

The key service (`lib/crypto/key_service.dart`; `keyServiceOverrides` in `lib/crypto/key_wiring.dart` wires it, and
`startApp` passes them to its `ProviderScope`) supplies `sealerProvider` and the three recovery-key providers, each
inert while `e2eeEnabledProvider` is false. `KeyService.resolve(uid)` yields the keychain key at once (`KeyStore`,
synchronizable, this-device fallback), then checks it against `keys/{uid}` from the server: `keyID` (16 bytes of
SHA-256 over the key, base64url), `wrapped` (the key sealed under the recovery key, 61 bytes), `createdAt`, and the
account-wide `saved` and `cardDismissed` flags; the rules let only the owner touch it and fix that field set. With no
key anywhere it makes one, saves it to the keychain, then creates the record in a transaction, so of two racing
devices the loser adopts the winner's record and asks for its recovery key. A `keyID` that differs from the keychain's
locks the journal behind `RecoveryKeyGate`'s recovery-key entry. No key here (`KeyNeedsRecovery.otherKeyHere` false)
locks it behind the gate's waiting page instead, since iCloud Keychain may deliver the key after the first look
(`key-promotion` C, Jack, 2026-11-11): rechecks keep reading the keychain and the right key opens it with nothing
typed; "Enter recovery key instead" leads to entry. The gate also holds every route while
`journalKeyPendingProvider` says no key is here and the server has not answered. Offline with no key: `KeyUnknown`, no
gate, nothing creatable; each recheck (every 5 s and on resume) reads the keychain and asks the server again.
`StoredKey.location` and `syncRefusal` (the keychain's status code alone, for a refused synced lookup or write)
reach the Recovery key page through `RecoveryKeyStatus`, which says where this device keeps the key; a this-device
key stays one. `deleteAccount` deletes the record. Device files holding journal content, findings or
Health-derived values are sealed too (`lib/crypto/sealed_files.dart`): `Caches/sealed/<uid>/`, each file through
`Sealer.sealFile` (a 4-byte length prefix, padded to a power of two from 4096; the field envelope is unchanged) with
`device-file/v1/<uid length>:<uid>/<name>` as associated data. `sealedFilesProvider` is null while nobody is signed in or no key is
loaded, and then nothing is read or written; a file that will not open is deleted and read as absent. A user's first
use deletes other users' folders; each launch deletes the plaintext `health-daily.json` of earlier builds; sign-out and deletion clear
it all. In it: `health-daily` (the Health daily store) and `samples-<random>` (one settled hours-after span each, steps over the nights Health lacks among them,
`lib/insights/health_sample_cache.dart`; random names, since spans follow use times), `last-report` (the last
Insights view with a computed report, `lib/insights/last_report_file.dart` over `report_codec.dart`; a cold open with
no view in the session shows it, updating, until the fresh one lands; raise `insightsViewFormat` with any change to
the report's types), and `places` (Places' visits and names, which nothing can read again: Caches being emptied
restarts them). The Swift-written
`Caches/health-sync.json` (anchors and changed days, no values) stays plaintext. Most of `integration_test/` pumps `e2eApp()` (`integration_test/support.dart`):
`MyApp` sealing with `e2eSealer`, a fixed-key `FakeSealer`, and the first-launch migrator off so it cannot seal a test's
legacy documents midway; legacy plaintext goes in past the rules (`createBypassingRules`). Files launching through
`startApp` (`smoke_test.dart`) seal with the real key. `storedContent` and `storedViceID` open sealed
documents with either key.

**Backup** (round 24 "A sealed backup you hold", Jack, 2026-11-16). Settings > Account > Backup (`BackupPage`,
`lib/backup/backup_page.dart`, route `/settings/backup`) saves one file through the system's save panel and restores
one into an empty account; Today's `BackupOfferCard` offers it monthly (once the recovery key is saved and a month old,
no backup or dismissal on this device in 30 days, dates per uid in shared_preferences), never a notification. Format:
`docs/backup-format.md` (`lib/backup/backup_file.dart`): magic, version, a plaintext header (creation time, source
uid, and `keys/{uid}`'s `keyID` and 61-byte `wrapped`), one `Sealer.sealFile` envelope under the journal key with
everything before it as associated data, a SHA-256 trailer; the body holds every document of `Account.ownedCollections`
as the server holds it, envelopes unopened. `makeBackup` (`lib/backup/backup_service.dart`) reads through
`Account.fetchStored` (pending writes first, server only) and opens the file again with the device's recovery key
before the save panel sees it. `backupKeyProvider` (from `keyServiceOverrides`) is null until a key is checked against
its record. Restore (`lib/backup/restore.dart`) never stores or adopts the backup's key: `planRestore` opens each
envelope with it at the original path and re-seals the fields whole under the signed-in account's key at the new path
(deterministic ids, `viceID` remapped, `ownerID` rewritten, `createdAt` kept, `updatedAt` the server's), legacy
plaintext sealed as the migrator would; `runRestore` refuses (`AccountNotEmpty`) unless every owned document is one this
backup writes, then writes vices first and activities and urges 20 a batch (the rules' 20 access calls per batch),
skipping what is there, so a cut-short run finishes on the next. A collection restore does not know refuses the file;
`test/restore_test.dart` fails when `ownedCollections` gains one. Guests are refused. The native panels are
`BackupFiles` in `ios/Runner/AppDelegate.swift` (export from a tmp folder removed on close; open in place) and
`macos/Runner/MainFlutterWindow.swift` (`files.user-selected.read-write`). `integration_test/backup_test.dart` saves and
restores on the emulators.
