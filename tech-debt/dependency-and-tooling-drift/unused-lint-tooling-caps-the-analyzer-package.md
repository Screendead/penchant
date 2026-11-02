# riverpod_lint and riverpod_generator hold the analyzer package six majors behind

**Severity:** high

Both dev dependencies declare an upper bound of `analyzer` below 9.0.0 in their own pubspecs. That forces the project's resolved `analyzer` — the version the codegen and lint packages compile against — to stay on 8.4.0 while pub.dev's latest is 14.1.0.

The constraint comes entirely from tooling that has no code to act on.

## Evidence

- `pubspec.lock:28` — `analyzer:\n    dependency: transitive`
- **`grep -A6 "^dependencies:" .../riverpod_lint-3.1.0/pubspec.yaml`** → `analyzer: ">=7.0.0 <9.0.0"`
- **`grep -A6 "^dependencies:" .../riverpod_generator-4.0.0+1/pubspec.yaml`** → `analyzer: ">=7.0.0 <9.0.0"`
- **`flutter pub outdated`** → `analyzer *8.4.0 *8.4.0 *8.4.0 14.1.0`
