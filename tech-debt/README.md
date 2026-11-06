# Tech-debt register

An exhaustive catalogue of this repository's technical debt as of 2026-08-11. Each
subdirectory is one class of debt; each file inside is one issue — what it is, what it
costs, and the evidence, never a prescription for how to fix it. The register burns
down by deletion: when an issue stops being true its file goes, when a directory
empties it goes too, and when this directory is gone the debt is gone.

Severity: **critical** — broken right now, or a real security or data-integrity
exposure. **high** — actively costs correctness or velocity, or breaks the next
routine action. **medium** — drift, friction, or risk that compounds. **low** —
clutter.

Evidence line numbers refer to the working tree at `master` on 2026-11-04 (refreshed after waves A and B);
citations drift as code moves.

**19 issues: 0 critical, 0 high, 8 medium, 11 low.**

## Firebase Data Layer (5)

Firestore security rules, index and query shapes, the document schema contract, and project-level Firebase configuration.

- **medium** — [Activity timestamps trust the device clock, not the server](firebase-data-layer/activity-timestamps-come-from-the-device-clock.md)
- **medium** — [The main checkout's active Firebase project is production; no staging project](firebase-data-layer/every-firebase-command-targets-production.md)
- **low** — [Nothing checks the index file against the queries or the live project](firebase-data-layer/rules-and-indexes-are-never-deployed-or-tested.md)
- **low** — [Legacy activities of a missing vice appear on no screen](firebase-data-layer/vice-activity-relationship-is-unenforced.md)
- **low** — [The vice lists are the last list queries with no limit](firebase-data-layer/vice-lists-are-unbounded.md)

## Widget State and View Logic (1)

Riverpod provider semantics and lifecycle, resource disposal, build-phase side effects, and the chart and graph computation pipelines.
- **low** — [The oldest weekly bucket is a short remainder, summed like a full week](widget-state-and-view-logic/oldest-weekly-bucket-holds-the-remainder.md)

## Error Handling and Observability (1)

Swallowed failure states, unguarded bootstrap, inconsistent exception surfacing, and the absence of logging or telemetry.

- **medium** — [Errors reach only the device log; no crash report or usage data leaves the device](error-handling-and-observability/no-logging-crash-reporting-or-telemetry.md)

## Offline and Write Reliability (1)

Firestore persistence configuration, write timeouts and in-flight UI state, destructive-action safety, and connectivity feedback.

- **medium** — [Deleting an activity behaves differently depending on which screen you're on](offline-and-write-reliability/destructive-actions-have-inconsistent-safety.md)

## Accessibility and Localization (2)

Screen-reader semantics, text-scale and overflow behaviour, theme colour roles, and locale-sensitive formatting and localization scaffolding.

- **low** — [English only: every UI string is a literal, with no translation pipeline](accessibility-and-localization/no-localizations-delegates-or-supported-locales.md)
- **low** — [The usage graph sizes its date labels from one sample date](accessibility-and-localization/date-axis-sizes-labels-from-one-sample-month.md)

## Auth and Account Lifecycle (1)

Password reset, email verification, re-authentication, account deletion and export, and sign-out semantics.

- **medium** — [Unverified accounts work fully; nothing checks the verified flag](auth-and-account-lifecycle/no-email-verification.md)

## Dependency and Tooling Drift (1)

Version lag and resolver locks across Dart, Node and Gradle, dead or incompatible lint tooling, and unmaintained local scripts.

- **medium** — [Firebase stops publishing to CocoaPods in October 2026, and both Apple builds depend on it](dependency-and-tooling-drift/cocoapods-sunset-ends-firebase-ios-publishing.md)

## Platform and Delivery Config (5)

The iOS and macOS platform trees, scaffold leftovers, signing and icons.

- **low** — [The client-side Firebase API key is duplicated across config files](platform-and-delivery-config/client-firebase-api-keys-committed-in-plaintext.md)
- **low** — [Legacy iOS icons the generator recreates, and a 1x1 launch image placeholder](platform-and-delivery-config/dead-scaffold-assets-ship-in-every-build.md)
- **low** — [iOS Podfile relaxes modular includes on every pod, and forces the deployment target](platform-and-delivery-config/ios-podfile-applies-blanket-pod-wide-overrides.md)
- **low** — [Both platforms hardcode a development team, and macOS mixes provisioning styles](platform-and-delivery-config/signing-configuration-is-legacy-and-inconsistent.md)
- **medium** — [`flutter build macos --release` fails in Flutter's framework unpack step](platform-and-delivery-config/macos-release-build-fails-in-flutter-unpack.md)

## CI and Quality Gates (1)

Test depth and what CI runs.

- **low** — [Three template tests still run and check nothing about the app](ci-and-quality-gates/template-tests-check-nothing.md)

## Repo, Docs and Release Hygiene (1)

Git working state and refs, documentation that contradicts the code, and versioning, licensing and release records.

- **medium** — [A generated file is ignored on iOS but tracked on macOS](repo-docs-and-release-hygiene/generated-plugin-registrant-tracked-on-macos-only.md)

