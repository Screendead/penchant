# The configured analyzer plugin is permanently incompatible with the pinned riverpod_lint

**Severity:** high

`custom_lint.log` records the analyzer plugin subsystem failing to load `riverpod_lint` with undefined-name and method-not-found errors on its plugin entrypoints. `riverpod_lint`'s own changelog states that 3.1.0 dropped the custom_lint protocol in favour of `analysis_server_plugin`, and the version the lockfile pins has no `riverpod_lint.dart` entrypoint at all, so the logged missing-file failure reproduces structurally against it.

`analysis_options.yaml` still wires the obsolete custom_lint plugin mechanism rather than the key `riverpod_lint` 3.1.0's own README documents. `dart analyze` does not execute the legacy custom_lint plugin either, so no `riverpod_lint` result exists for any file in the working tree.

## Evidence

- `custom_lint.log:582` — `Error when reading '/Users/jacklusher/.pub-cache/hosted/pub.dev/riverpod_lint-3.1.4/lib/riverpod_lint.dart': No such file or directory`
- `custom_lint.log:585` — `lib/custom_lint_client.dart:16:37: Error: Undefined name 'createPlugin'.`
- `analysis_options.yaml:13` — `plugins:\n    - custom_lint`
- `pubspec.lock:810` — `version: "3.1.0"`
- **`cat .../riverpod_lint-3.1.0/CHANGELOG.md`** → `` `riverpod_lint` is no-longer implemented using `custom_lint`, but instead `analysis_server_plugin` ``
- **`sed -n '/Installing riverpod_lint/,/Running riverpod_lint/p' .../riverpod_lint-3.1.0/README.md`** → `analyzer:\n  plugins:\n    - riverpod_lint\n\nplugins:\n  riverpod_lint: <version number>`
