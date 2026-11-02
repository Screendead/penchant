# No Firestore settings are configured, so cache and queued-write behaviour diverge by platform

**Severity:** high

`main.dart` initializes Firebase and never touches `FirebaseFirestore.instance.settings`; no file sets `persistenceEnabled`, a cache size, or any persistence option. Firestore enables disk persistence by default on mobile and desktop and leaves it off on web, so the same provider code behaves differently per target: a listener started offline on mobile can emit a cached result immediately, while on web it has nothing to emit until a server round trip succeeds and the screen sits on its spinner.

The same default governs write durability. A write made offline is held in the SDK mutation queue, and that queue survives a process restart only where persistence is on, so closing or reloading a web tab with a pending write from any of the eight write sites discards it with nothing shown and nothing recorded. No code branches on platform to account for either difference.

## Evidence

- `lib/main.dart:19` — `await Firebase.initializeApp(\n    options: DefaultFirebaseOptions.currentPlatform,\n  );`
- **`grep -rn "persistenceEnabled|enablePersistence|cacheSettings|PersistentCacheSettings" lib/ --include=*.dart`** → (no output — zero matches in lib/)
- `pubspec.yaml:39` — `cloud_firestore: ^6.7.1`
- `lib/widgets/record_new_activity_dialog.dart:251` — `await activityRef.set({`
