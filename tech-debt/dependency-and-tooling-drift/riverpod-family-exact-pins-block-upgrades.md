# Each Riverpod package pins its sibling riverpod core to an exact version

**Severity:** medium

`flutter_riverpod`, `riverpod_annotation`, `riverpod_generator` and `riverpod_lint` each declare `riverpod` as an exact version rather than a range, so `flutter pub outdated` shows the upgradable and resolvable columns stuck at current for all four even though newer versions nominally satisfy this project's caret constraints.

A plain `flutter pub upgrade` can never move the family forward, and every patch release re-pins a different exact core version, so any future move requires a coordinated all-at-once bump of the whole family plus retesting.

## Evidence

- **`grep "riverpod:" .../riverpod_lint-3.1.0/pubspec.yaml`** → `riverpod: 3.1.0`
- **`grep "riverpod:" .../riverpod_generator-4.0.0+1/pubspec.yaml`** → `riverpod: 3.1.0`
- **`grep "riverpod:" .../riverpod_annotation-4.0.0/pubspec.yaml`** → `riverpod: 3.1.0`
- **`grep "riverpod:" .../flutter_riverpod-3.1.0/pubspec.yaml`** → `riverpod: 3.1.0`
- **`grep "riverpod:" .../riverpod_lint-3.1.4/pubspec.yaml`** → `riverpod: 3.3.2`
- **`flutter pub outdated`** → `flutter_riverpod *3.1.0 *3.1.0 *3.1.0 3.4.2 ... riverpod_lint *3.1.0 *3.1.0 *3.1.0 3.1.8`
