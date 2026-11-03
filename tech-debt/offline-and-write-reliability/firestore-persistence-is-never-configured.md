# Firestore persistence and cache settings are SDK defaults nobody chose

**Severity:** medium

Outside the emulator path, `initializeFirebase` never touches `FirebaseFirestore.instance.settings`; no file sets
`persistenceEnabled`, a cache size, or any other persistence option for production builds. iOS and macOS, the only
targets, both enable disk persistence by default, so offline reads and the queued-write durability every write site
relies on rest on a default, not a decision.

Nothing records that the app depends on that default, the cache is bounded only by the SDK's own default size, and the
emulator path turns persistence off, so `tools/e2e.sh` never exercises the cached behaviour production users get.

## Evidence

- `lib/firebase_init.dart:28` — `if (!useFirebaseEmulators) {\n    await Firebase.initializeApp(\n      options: DefaultFirebaseOptions.currentPlatform,\n    );\n    return;\n  }`
- `lib/firebase_init.dart:50` — `FirebaseFirestore.instance.settings = const Settings(\n    persistenceEnabled: false,\n  );` (emulator path only)
- **`grep -rn "persistenceEnabled|cacheSizeBytes|PersistentCacheSettings" lib/`** → only `lib/firebase_init.dart:51`
