# Three specific statements in CLAUDE.md are wrong about the code they describe

**Severity:** medium

It asserts every provider in `lib/providers/` is a `StreamProvider` wrapping a Firestore snapshot stream, while `vice_activities_by_vice_id_provider.dart` defines a plain `Provider` deriving from another provider's already-resolved value. It lists four files performing inline Firestore writes and omits `vice_activity_history_page.dart`, which deletes directly.

Its provider chain groups `unarchivedViceListProvider` with `viceListProvider` as feeding the day and list providers, when only the latter is watched by them and the former is a leaf read by two widgets.

## Evidence

- `CLAUDE.md:40` — `` Every provider in `lib/providers/` is a hand-written `StreamProvider` or `StreamProvider.family` wrapping a Firestore snapshot stream. ``
- `lib/providers/vice_activities_by_vice_id_provider.dart:5` — `final viceActivityListByViceIDProvider = Provider<Map<String, List<ViceActivity>>?>((ref) {`
- `lib/vice_activity_history_page.dart:85` — `await FirebaseFirestore.instance.collection('activities').doc(activity.id).delete();`
