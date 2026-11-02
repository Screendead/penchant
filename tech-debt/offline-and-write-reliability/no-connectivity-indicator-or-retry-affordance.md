# Nothing in the app observes or reports network state

**Severity:** medium

A repo-wide grep for connectivity and offline across `lib/` returns nothing, and `pubspec.yaml` declares no connectivity-detection package. No widget renders a banner, badge or snackbar for network state, no write path offers a manual retry, and no provider or model surfaces `hasPendingWrites`.

The only feedback anywhere is the per-write catch blocks that fire on an immediate `FirebaseException` or on the two ten-second timeouts.

## Evidence

- **`grep -rn "connectivity|Connectivity|offline|Offline" lib/ --include=*.dart`** → (no output — zero matches in lib/)
- `pubspec.yaml:39` — `cloud_firestore: ^6.7.1`
