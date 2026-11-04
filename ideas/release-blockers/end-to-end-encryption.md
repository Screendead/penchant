# Encrypt what each entry says on the device before it syncs, and keep the dates plaintext

**Priority:** release blocker

Why this stage (INFERENCE): by the README's own test, the app "should not reach strangers without it" if Jack wants
it at all. Moving `name` and `quantity` into a sealed field changes the type of an existing field. Every build that
predates the change then loses its whole vice list, and the migration has to run over strangers' data. Today the
only data is Jack's, and the only other client is the web site he has decided to take down (SOURCED: HANDOVER.md,
`r2-web-site`). The stage is Claude's recommendation, like the rest of this file.

## What

Each vice gets one sealed `enc` field holding its name and unit. Each activity gets one `enc` holding its quantity,
plus every later detail field (note, triggers, mood, place, time zone) from its first write. Four fields stay in
plaintext so every query, index and ownership rule keeps working: `ownerID`, `viceID`, `createdAt` and `archived`
(SOURCED: `lib/providers/*.dart`, `firestore.rules`, `firestore.indexes.json` on master). The cipher is AES-256-GCM
through CryptoKit. The key is one random 256-bit data key per user, kept in the iCloud-synced keychain plus a
this-device-only copy. A recovery key covers the case where both are lost.

The spike on branch `mockup/e2e-encryption` builds this as working code, tested against the Firestore emulator only.
Pitch page: https://claude.ai/artifact/UZp2zogfZyEL1MiursXsYt (private until Jack shares it). The links below are
pinned to commit `9b23cb9`:

- **Code:**
  - [`lib/crypto/`](https://github.com/Screendead/tracker/tree/9b23cb96a0df094feb9cf308f2e27618f285397c/lib/crypto):
    the cipher, recovery key, keychain store, key service, provider, reader, migrator and native-AES guard.
  - [`lib/journal_key/`](https://github.com/Screendead/tracker/tree/9b23cb96a0df094feb9cf308f2e27618f285397c/lib/journal_key):
    the key screens and `JournalGate`.
  - The data path: [`lib/data/vice.dart`](https://github.com/Screendead/tracker/blob/9b23cb96a0df094feb9cf308f2e27618f285397c/lib/data/vice.dart),
    [`vice_activity.dart`](https://github.com/Screendead/tracker/blob/9b23cb96a0df094feb9cf308f2e27618f285397c/lib/data/vice_activity.dart),
    [`add_vice.dart`](https://github.com/Screendead/tracker/blob/9b23cb96a0df094feb9cf308f2e27618f285397c/lib/add_vice.dart),
    [`record_new_activity_dialog.dart`](https://github.com/Screendead/tracker/blob/9b23cb96a0df094feb9cf308f2e27618f285397c/lib/widgets/record_new_activity_dialog.dart),
    [`vice_activity_editor_page.dart`](https://github.com/Screendead/tracker/blob/9b23cb96a0df094feb9cf308f2e27618f285397c/lib/vice_activity_editor_page.dart).
- **Rules R1** (the dual-shape phase) and indexes:
  [`firestore.rules`](https://github.com/Screendead/tracker/blob/9b23cb96a0df094feb9cf308f2e27618f285397c/firestore.rules),
  [`firestore.indexes.json`](https://github.com/Screendead/tracker/blob/9b23cb96a0df094feb9cf308f2e27618f285397c/firestore.indexes.json).
- **Tests:**
  - [`tests/firestore-rules/e2ee.test.js`](https://github.com/Screendead/tracker/blob/9b23cb96a0df094feb9cf308f2e27618f285397c/tests/firestore-rules/e2ee.test.js)
    and [`bytes-probe.test.js`](https://github.com/Screendead/tracker/blob/9b23cb96a0df094feb9cf308f2e27618f285397c/tests/firestore-rules/bytes-probe.test.js).
  - [`test/crypto/`](https://github.com/Screendead/tracker/tree/9b23cb96a0df094feb9cf308f2e27618f285397c/test/crypto).
- **Tools:**
  - [`tools/e2ee-metadata-view.js`](https://github.com/Screendead/tracker/blob/9b23cb96a0df094feb9cf308f2e27618f285397c/tools/e2ee-metadata-view.js):
    what someone with console access still sees. Sample output:
    [`metadata-view.txt`](https://github.com/Screendead/tracker/blob/9b23cb96a0df094feb9cf308f2e27618f285397c/docs/pitch/mockups/e2e-encryption/metadata-view.txt).
  - [`tools/bench/`](https://github.com/Screendead/tracker/tree/9b23cb96a0df094feb9cf308f2e27618f285397c/tools/bench).
- **Screens:** rendered by
  [`test/mockups/e2e_encryption_test.dart`](https://github.com/Screendead/tracker/blob/9b23cb96a0df094feb9cf308f2e27618f285397c/test/mockups/e2e_encryption_test.dart)
  at iPhone size:
  - Offering the recovery key, in the two candidate timings:
    [on Today after a week](https://github.com/Screendead/tracker/blob/9b23cb96a0df094feb9cf308f2e27618f285397c/docs/pitch/mockups/e2e-encryption/a-today-deferred-card.png),
    [at sign-up](https://github.com/Screendead/tracker/blob/9b23cb96a0df094feb9cf308f2e27618f285397c/docs/pitch/mockups/e2e-encryption/b-signup-recovery-step.png).
  - Saving and checking it:
    [save sheet](https://github.com/Screendead/tracker/blob/9b23cb96a0df094feb9cf308f2e27618f285397c/docs/pitch/mockups/e2e-encryption/save-sheet.png),
    [confirm a group](https://github.com/Screendead/tracker/blob/9b23cb96a0df094feb9cf308f2e27618f285397c/docs/pitch/mockups/e2e-encryption/confirm-group.png),
    [wrong group](https://github.com/Screendead/tracker/blob/9b23cb96a0df094feb9cf308f2e27618f285397c/docs/pitch/mockups/e2e-encryption/confirm-group-wrong.png),
    [Settings > Recovery key](https://github.com/Screendead/tracker/blob/9b23cb96a0df094feb9cf308f2e27618f285397c/docs/pitch/mockups/e2e-encryption/settings-recovery-key.png).
  - A new or lost device:
    [opening the journal](https://github.com/Screendead/tracker/blob/9b23cb96a0df094feb9cf308f2e27618f285397c/docs/pitch/mockups/e2e-encryption/opening-journal.png),
    [enter the key](https://github.com/Screendead/tracker/blob/9b23cb96a0df094feb9cf308f2e27618f285397c/docs/pitch/mockups/e2e-encryption/enter-key.png),
    [a typo located](https://github.com/Screendead/tracker/blob/9b23cb96a0df094feb9cf308f2e27618f285397c/docs/pitch/mockups/e2e-encryption/enter-key-typo.png),
    [a valid key for another journal](https://github.com/Screendead/tracker/blob/9b23cb96a0df094feb9cf308f2e27618f285397c/docs/pitch/mockups/e2e-encryption/enter-key-wrong-journal.png),
    [Start a new journal](https://github.com/Screendead/tracker/blob/9b23cb96a0df094feb9cf308f2e27618f285397c/docs/pitch/mockups/e2e-encryption/start-new-journal.png).

What the spike shows, re-run on this branch on 2026-11-03 (SOURCED: local runs):

- The rules suite passes 115/115: the 72 existing tests unchanged, 41 for R1, and 2 that probe whether a Blob passes
  `is bytes`.
- `flutter test` passes 91 tests, with 1 skipped (the benchmark).
- `flutter analyze --fatal-infos --fatal-warnings` is clean, once `tools/bench/` is excluded from analysis.
- The screens match their goldens.

What it does not show: nothing ran on iOS. The simulator, `tools/e2e.sh` and the iPhones were held by other agents.

## Why

**Jack asked for it:** "would be good to have e2e encryption for the app's data in Firebase. it could be sensitive."
His steer: "you only need to encrypt the actual names/quantities of vices surely, dates aren't that big of a deal?"

**On "send the encrypted field to the db as a filter/sort":**

- Equality filters do work on ciphertext, if the encryption is deterministic (INFERENCE).
- Sorts and ranges don't. Firestore sorts bytes in byte order, so the order of ciphertexts means nothing (SOURCED:
  [data types](https://firebase.google.com/docs/firestore/manage-data/data-types)).
- Order-preserving schemes, which do allow sorting, leak the plaintext. Naveed, Kamara and Wright recovered most
  patients' encrypted hospital attributes from them (SOURCED, secondary:
  [Microsoft Research](https://www.microsoft.com/en-us/research/publication/inference-attacks-property-preserving-encrypted-databases/)).
- Under Jack's scope none of this is needed. No query filters or sorts on name, unit or quantity (SOURCED:
  `lib/providers/*.dart`). Ordinary authenticated encryption is enough, and his read on the cost is right.

**On dates:**

- Dates are the main thing left exposed. Plaintext `createdAt` grouped by `viceID` gives anyone with console access a
  per-vice histogram by hour and weekday. The spike's metadata view draws one for a sealed journal: one vice twice
  every morning, one on weekdays in working hours, one on Friday to Sunday evenings (SOURCED: `metadata-view.txt`).
  Anyone who knows the app's audience can guess what each vice is (INFERENCE).
- Sealing `createdAt` inside each entry would not hide a live log. Firestore stamps its own `createTime` and
  `updateTime` on every document (SOURCED:
  [REST documents](https://firebase.google.com/docs/firestore/reference/rest/v1/projects.databases.documents)).
  That holds only for live logs: a backfilled or edited entry has a `createdAt` that differs from `createTime`, and
  the migrator bumps `updateTime` on every legacy document (INFERENCE). Hiding timing takes O3 below.

**The upside:**

- Firebase offers no end-to-end encryption. It encrypts at rest with keys Google holds, and "Firestore does not know
  if your data has already been encrypted client-side" (SOURCED:
  [server-side encryption](https://docs.cloud.google.com/firestore/docs/server-side-encryption)).
- CMEK only changes who holds the at-rest key. It works only on a new database, and the project owner still reads
  plaintext (SOURCED: [CMEK](https://docs.cloud.google.com/firestore/docs/cmek)).
- Day One, the closest analogue, encrypts new journals end to end by default and leads its listing with it (SOURCED:
  [guide](https://dayoneapp.com/guides/security/end-to-end-encryption/),
  [App Store](https://apps.apple.com/us/app/day-one-journal-private-diary/id1044867788)).
- Stardust went from #119 to #1 on a promise of end-to-end encryption. TechCrunch then found the promise was false
  (SOURCED: [TechCrunch](https://techcrunch.com/2022/06/27/stardust-period-tracker-phone-number)). So the claim sells,
  and journalists check it.

**GDPR:**

- Years of alcohol or drug logs next to Apple Health correlations are likely Art. 9 health data (INFERENCE from the
  Art. 29 Working Party summaries, e.g.
  [Hunton](https://www.hunton.com/privacy-and-cybersecurity-law-blog/article-29-working-party-clarifies-scope-health-data-processed-lifestyle-wellbeing-apps)).
- Encryption relieves only the duty to tell data subjects about a breach, and only for data made unintelligible
  (SOURCED: [Art. 34(3)(a)](https://gdpr-info.eu/art-34-gdpr/)).
- Under O1 the email, uid and exact per-vice timestamps stay readable, so a breach can still be high-risk. The duty
  to notify the supervisory authority (Art. 33) is not waived at all (INFERENCE).

**Timing:** after 1.0 the cost rises every month, as O2 shows.

## Options

- **O0. No end-to-end encryption; say exactly what is true.** Firestore encrypts at rest with Google's keys, and
  insights, Health and Calendar stay on the device.
  - Cost: Jack, Google, the CI service account and anyone who breaches the project can read every name, amount and,
    later, note. The app gives up the differentiator. Adding encryption later costs more (see O2).
  - Risk: low for engineering. High for reputation, in a category where Mozilla flagged 19 of 32 mental-health apps
    (SOURCED: [Mozilla](https://www.mozillafoundation.org/en/blog/shady-mental-health-apps-inch-toward-privacy-and-security-improvements-but-many-still-siphon-personal-data/)).
    It also goes against Jack's stated aim.
  - Effort: S, copy only (INFERENCE).
- **O1. Seal the content before 1.0 (Jack's scope), with a synced keychain key and a recovery key.** As in What, and
  as built in the spike.
  - Corrections to the design as first pitched (SOURCED: package source and worktree code, unless tagged):
    - cryptography_flutter routes inputs under 2,000 bytes to pure Dart by default, which is every blob this app
      writes. It also falls back to Dart silently when the plugin is missing (`flutter_cipher.dart`,
      `defaultChannelPolicy`). An override is required.
      [`native_aes.dart`](https://github.com/Screendead/tracker/blob/9b23cb96a0df094feb9cf308f2e27618f285397c/lib/crypto/native_aes.dart)
      sends every length to CryptoKit and refuses the fallback.
    - On Apple, only AES-GCM, ChaCha20 and the curve primitives run natively. PBKDF2 (`BackgroundPbkdf2` is Dart in
      an isolate), HKDF and HMAC are pure Dart (`flutter_pbkdf2.dart`, `flutter_hmac.dart`).
    - C14 survives: `ownsVice()` still runs on sealed creates.
    - The migrator adds a fourth composite index, activities `(ownerID, createdAt desc)`.
  - Cost:
    - C12 (quantity ≥ 1), C13 (names of 1 to 60) and the unit list stop being server checks. They live only in
      `lib/data/limits.dart`, and the rules check only the blob's type and exact padded length. A modified client can
      corrupt only its own data (INFERENCE).
    - The claim narrows to "we can see when you log, not what". Apple makes the same caveat for its metadata under
      Advanced Data Protection (SOURCED: [Apple](https://support.apple.com/en-us/102651)).
    - Jack can no longer read his own data in the console.
    - Three new dependencies: cryptography, cryptography_flutter and flutter_secure_storage.
    - A new `keys/{uid}` collection.
  - Risk:
    - A second data key minted while ciphertext exists means silent data loss. The rules can't stop it: the owner may
      delete `keys/{uid}` and create another. Only the client invariant, tested on fakes, prevents it.
    - The data is lost if every device, the keychain, the recovery key and any export are all lost. No vendor
      publishes a loss rate (INFERENCE from the research).
    - If the app reaches a device before R1 is in production, every write is denied.
    - Crash logs that carry decrypted names would make the claim false.
  - Effort: L for the 1.0 core, XL with an iPhone-to-Mac QR handoff (INFERENCE).
- **O2. The same, deferred to 1.1 with Pro.** 1.0 would have to ship parsers that already read both shapes.
  - Cost:
    - The migration runs over strangers' data.
    - 1.0 plaintext stays in Google's deletion pipeline for up to about 180 days (SOURCED:
      [deletion](https://docs.cloud.google.com/docs/security/deletion)) and in the PITR window (SOURCED:
      [PITR](https://firebase.google.com/docs/firestore/pitr)).
    - Notes, triggers and place get written in plaintext first.
    - Users who never update keep writing plaintext, so the strict rules (R2) can't land.
    - 1.0 launches without the claim.
  - Risk: higher than O1, because client versions in the field are mixed (INFERENCE).
  - Effort: L+, spread over two releases (INFERENCE).
- **O3. A sealed vault that hides timing too.** Per-user encrypted segments hold an operation log. Writes flush at
  random times in each 6-hour window, with cover chunks. Every query becomes an in-memory filter.
  - Cost:
    - It goes against Jack's steer on dates.
    - An entry reaches the Mac up to 6 hours late, and a device lost before a flush loses its pending entries.
    - The rules can validate nothing.
    - It replaces the documented data shape, so it needs Jack's explicit yes under the hard rule.
    - Auth token refresh still shows when the app is open (SOURCED:
      [sessions](https://firebase.google.com/docs/auth/admin/manage-sessions)).
  - Risk: highest. The sync engine is homemade, and a merge bug loses data the server can't repair (INFERENCE).
  - Effort: XL, about twice O1 (INFERENCE).

## Recommendation

Claude's recommendation, not a decision: **O1, before 1.0.** It fits Jack's steer, keeps every query and composite
index, and the server learns when, never what. Build order (INFERENCE):

1. **After** the parser defaults, the shared write layer, bounded queries (every provider moves to `asyncMap` with a
   decrypt per document), the bundle-ID lock, and the macOS target at 11 or later.
2. **Before** the granular-logging and trigger fields, so those are sealed from their first write.
3. **Rollout:** R1 rules and the fourth index go live in production first. Then the build that reads both shapes and
   migrates on first launch. Then R2, which refuses plaintext, once Jack's devices have migrated.

Reasons for the choices inside O1:

- **AES-GCM through CryptoKit rather than XChaCha:** to stay in the export row that asks for no documents (SOURCED:
  [Apple's table](https://developer.apple.com/help/app-store-connect/reference/app-information/export-compliance-documentation-for-encryption/)).
  The case is weaker than it looks: the Firestore SDK already bundles BoringSSL (SOURCED: `ios/Podfile.lock`), and the
  questionnaire's wording is sourced only from a forum. Confirm before TestFlight.
- **A recovery key used directly as an AES-128 wrapping key, with no key derivation:** every primitive then stays
  native.
- **A recovery key Settings can show again:** in the Tuta study only 63.3% of users knew they could view theirs
  again (SOURCED: [USENIX 2024](https://www.usenix.org/system/files/usenixsecurity24-holtervennhoff.pdf)).
- **No passphrase and no account-password key:** Firebase receives the password at every sign-in, an email reset
  loses the key, and guests and Sign in with Apple users have no password (SOURCED:
  [REST auth](https://firebase.google.com/docs/reference/rest/auth),
  [email handler](https://firebase.google.com/docs/auth/custom-email-handler)).

**Sub-decisions inside O1** (one recommendation each; the pitch page has the screens and alternatives):

1. **When to first offer the recovery key.**
   - Recommended: a card on Today after a week, plus Settings at any time.
   - Alternatives: a step at sign-up with Later, or mandatory before the first log.
2. **How to store `enc`.**
   - Recommended: as a Blob. The rules check exact byte sizes 93, 285, 1053 and 4125.
   - Alternative: a base64 string, at lengths 124, 380, 1404 and 5500.
   - Caveat: `is bytes` passes on the emulator (SOURCED: `bytes-probe.test.js`), but the
     [rules-language page](https://firebase.google.com/docs/rules/rules-language) doesn't list it. A one-document
     check in the beta project comes first.
3. **Padding for vices.**
   - Recommended: pad every vice to at least 256 bytes, so most names leave the same 285-byte blob.
   - The gap: about 35 control characters or unpaired surrogates in a 60-unit name reach 1053, because JSON escapes
     each one to 6 bytes, and `limits.dart` rejects neither (SOURCED: jsonEncode sizes). Rejecting those characters
     in names closes the gap (INFERENCE).
4. **The recovery key's format.**
   - Recommended: 32 characters with a 32-bit checksum, which locates a typo.
   - Alternative: 27 characters with a mod-37 check, which detects a typo but can't say where.
5. **Who may delete `keys/{uid}`.**
   - Recommended: the owner, which "Start a new journal" and account deletion need.
   - Alternative: also add a keyId guard on every sealed write.
   - The guard is cheaper than first pitched. Repeated reads of one document "may be cached, and cached calls do not
     count towards the limits" (SOURCED:
     [rules conditions](https://firebase.google.com/docs/firestore/security/rules-conditions)), and billing is one
     read per dependent document per request (SOURCED: [pricing](https://firebase.google.com/docs/firestore/pricing)).
   - On the emulator, 200-write batches pass with the guard (SOURCED: a reviewer's emulator run, not in the branch's tests). That production behaves the same
     is INFERENCE.
6. **Two keychain copies or one.**
   - Recommended: two, a synced copy and a this-device-only copy, but only once a device check shows the local copy
     survives iCloud Keychain being switched off.
7. **The iPhone-to-Mac QR handoff.**
   - Recommended: ship it with the Mac, since a Mac on another Apple ID is the Mac's own failure mode.
   - Alternatives: defer it, or never ship it.
   - It is the one piece that needs a non-native primitive (HKDF) and a homemade protocol.
8. **Accept that C12 and C13 become checks in the app only.** This partly undoes decided calls.
9. **Accept the visible metadata and the claim's wording:** "What you log is encrypted on your device before it
   syncs; we can't read it. We can see when you log."
10. **Add `keys/{uid}`**, which folds into `r2-data-model`.
11. **Legacy plaintext from production users who never install 1.0:** Jack counts it in the console (Claude can't,
    by the hard rule), then decides whether to delete it.
12. **Before TestFlight:**
    - Export compliance and `ITSAppUsesNonExemptEncryption`, which nothing sets today (SOURCED: grep of `ios/` and
      `macos/`).
    - The App Privacy wording: timestamps are still collected.
    - Under `r2-crash`, a scrubbing rule so that decrypted text never leaves the device.

**Open findings from review, to fix if O1 is picked** (SOURCED: worktree code, unless tagged):

- **Deployment:**
  - The fourth index must be in production before any device migrates, or the migrator's query fails.
  - The fourth index doesn't cover the createdAt-ascending history queries (INFERENCE from
    [index overview](https://firebase.google.com/docs/firestore/query-data/index-overview)).
- **macOS:**
  - The Runner has no `DEVELOPMENT_TEAM`, and neither entitlements file has `keychain-access-groups` or
    `network.client`.
  - flutter_secure_storage's README says writes can appear to succeed without being written when the
    `keychain-access-groups` entitlement is missing.
  - So iPhone-to-Mac key sync can't work as configured. This lands in queue item 1.
- **Integrity:**
  - The AAD binds the collection, document, owner and vice, but not `createdAt`, `archived` or a version. Someone
    with database access can move an entry in time, flip `archived`, or roll `enc` back to an earlier valid blob, and
    the client can't tell (INFERENCE).
  - A new recovery key re-wraps the same data key, so it does not revoke a leaked one. The only key rotation is
    "Start a new journal".
- **Key handling:**
  - `SecureKeyStore.read()` prefers the synced copy. If that copy holds a stale key while the local copy is right,
    the app asks for the recovery key and offers "Start a new journal" (INFERENCE).
  - The recovery key is copied with a plain `Clipboard.setData`, which can reach Universal Clipboard (INFERENCE).
  - Locking the app with biometrics needs a separate per-device copy of the key: flutter_secure_storage drops sync
    when access-control flags are set (SOURCED: plugin Swift).
  - A bundle-ID rename orphans the keychain items unless the old access group is listed first. That is unverified:
    Apple's page didn't load for the reviewer.
- **Migrator:**
  - It skips documents that lack `createdAt`.
  - A legacy name whose JSON is over 4,094 bytes fails its whole 200-document batch on every launch.
  - Its done flag is per device, and R1 still accepts plaintext creates.
  - R2 (sealed-only rules) is not written yet.
- **Contradiction to settle:** the research says both "keep a local plaintext copy" and "the cache holds only
  ciphertext". Recommended: ciphertext only, with export as the backup that needs no key. That also shrinks what the
  on-device cache holds between sign-outs (sign-out now clears it) to metadata (INFERENCE).
- **Untested:**
  - The end-to-end run on iOS: sign up, log, wipe the keychain, unlock with the recovery key, convert legacy
    documents.
  - Decrypt time on an iPhone. On this Mac, opening 2,000 entries over the platform channel took 209 to 219 ms. That
    is about 100 µs a call, almost all of it channel overhead (SOURCED: two runs).
  - Keychain sync between two signed devices.

**Effort:** L, or XL with the QR handoff (INFERENCE).

**Revenue impact:** A conditional differentiator. Verified end-to-end sync looks rare among vice trackers
(INFERENCE; the category wasn't surveyed systematically). It is worth something only if the claim is literally true
(SOURCED: the Stardust precedent above).

**Depends on:**
- [`model-parsers-cast-unconditionally`](../../tech-debt/firebase-data-layer/model-parsers-cast-unconditionally.md)
- `no-query-is-bounded-or-paginated` (fixed by backend hardening)
- [`writes-bypass-providers-with-inline-firestore-calls`](../../tech-debt/widget-state-and-view-logic/writes-bypass-providers-with-inline-firestore-calls.md)
- [`macos-deployment-target-frozen-at-10-14`](../../tech-debt/platform-and-delivery-config/macos-deployment-target-frozen-at-10-14.md)
  and [`macos-sandbox-grants-no-outbound-network`](../../tech-debt/platform-and-delivery-config/macos-sandbox-grants-no-outbound-network.md)
- Ideas: [name and bundle ID](name-and-bundle-id.md), [backend hardening](backend-hardening.md),
  account deletion (built in `lib/account/`; it must delete the key too),
  [privacy policy](privacy-policy-and-labels.md), data export (built in `lib/account/`; export becomes the
  only backup that needs no key), [crash reporting](../v1-must-haves/crash-reporting-and-analytics.md),
  [macOS target](../v1-must-haves/macos-target.md),
  [granular logging](../insights/granular-logging-and-data-model.md),
  [app lock](../growth-later/app-lock-and-discreet-mode.md).
- Jack's to-dos: enable `DEPLOY_FIRESTORE_RULES`, or deploy R1 by hand, and take the web site down.

**Needs Jack:** yes. Should 1.0 seal what each entry says (O1, recommended), wait until 1.1 (O2), seal nothing (O0),
or also hide timing (O3)? Does he accept C12 and C13 as app-only checks and the visible "when"? Which of the
sub-decisions above does he pick?
