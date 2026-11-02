# Five specific statements in CLAUDE.md are wrong about the code they describe

**Severity:** medium

It asserts every provider in `lib/providers/` is a `StreamProvider` wrapping a Firestore snapshot stream, while `vice_activities_by_vice_id_provider.dart` defines a plain `Provider` deriving from another provider's already-resolved value. It lists four files performing inline Firestore writes and omits `vice_activity_history_page.dart`, which deletes directly.

Its provider chain groups `unarchivedViceListProvider` with `viceListProvider` as feeding the day and list providers, when only the latter is watched by them and the former is a leaf read by two widgets. It calls `functions/src/index.ts` entirely commented-out scaffolding when two live import statements sit above the commented block. It labels the release web build as what CI builds when only the merge workflow passes that flag.

## Evidence

- `CLAUDE.md:40` — `` Every provider in `lib/providers/` is a hand-written `StreamProvider` or `StreamProvider.family` wrapping a Firestore snapshot stream. ``
- `lib/providers/vice_activities_by_vice_id_provider.dart:5` — `final viceActivityListByViceIDProvider = Provider<Map<String, List<ViceActivity>>?>((ref) {`
- `lib/vice_activity_history_page.dart:85` — `await FirebaseFirestore.instance.collection('activities').doc(activity.id).delete();`
- `functions/src/index.ts:10` — `import {onRequest} from "firebase-functions/v2/https"; import * as logger from "firebase-functions/logger";`
- `CLAUDE.md:14` — `flutter build web --release      # what CI builds and deploys`
- `.github/workflows/firebase-hosting-pull-request.yml:24` — `run: flutter build web`
