# The whole Riverpod code-generation stack is declared with nothing to generate

**Severity:** medium

`pubspec.yaml` declares `riverpod_annotation`, `riverpod_generator`, `build_runner`, `custom_lint` and `riverpod_lint`, and `analysis_options.yaml` wires the custom_lint analyzer plugin, but there is not one riverpod annotation, generated part file or `build.yaml` anywhere in the repository — every provider is hand-written.

The declaration pulls roughly thirty extra transitive packages, including `analyzer`, `build`, `build_daemon`, `source_gen` and `dart_style`, into every `pub get` and dependency audit. No CI job invokes the tooling; the only documented entry point is the `dart run custom_lint` line in CLAUDE.md.

## Evidence

- `pubspec.yaml:44` — `riverpod_annotation: ^4.0.0`
- `pubspec.yaml:59` — `build_runner: ^2.15.1`
- `pubspec.yaml:61` — `riverpod_generator: ^4.0.0+1`
- **`grep -rn "@riverpod" --include="*.dart" .`** → `(no matches)`
- **`find . -name "*.g.dart" -not -path "./.dart_tool/*"`** → `(no matches)`
- **`find . -iname "build.yaml" -not -path "./.dart_tool/*" -not -path "*/.pub-cache/*"`** → `(no matches)`
