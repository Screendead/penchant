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

**11 issues: 0 critical, 0 high, 5 medium, 6 low.**

## Firebase Data Layer (5)

Firestore security rules, index and query shapes, the document schema contract, and project-level Firebase configuration.

- **medium** — [Activity timestamps trust the device clock, not the server](firebase-data-layer/activity-timestamps-come-from-the-device-clock.md)
- **medium** — [The main checkout's active Firebase project is production; no staging project](firebase-data-layer/every-firebase-command-targets-production.md)
- **low** — [Nothing checks the rules and index files against the live project](firebase-data-layer/rules-and-indexes-are-never-deployed-or-tested.md)
- **low** — [Legacy activities of a missing vice appear on no screen](firebase-data-layer/vice-activity-relationship-is-unenforced.md)
- **low** — [The vice lists are the last list queries with no limit](firebase-data-layer/vice-lists-are-unbounded.md)

## Widget State and View Logic (0)

Riverpod provider semantics and lifecycle, resource disposal, build-phase side effects, and the chart and graph computation pipelines.

## Error Handling and Observability (1)

Swallowed failure states, unguarded bootstrap, inconsistent exception surfacing, and the absence of logging or telemetry.

- **medium** — [Errors reach only the device log; no crash report or usage data leaves the device](error-handling-and-observability/no-logging-crash-reporting-or-telemetry.md)

## Offline and Write Reliability (0)

Firestore persistence configuration, write timeouts and in-flight UI state, destructive-action safety, and connectivity feedback.


## Accessibility and Localization (1)

Screen-reader semantics, text-scale and overflow behaviour, theme colour roles, and locale-sensitive formatting and localization scaffolding.

- **low** — [English only: every UI string is a literal, with no translation pipeline](accessibility-and-localization/no-localizations-delegates-or-supported-locales.md)

## Auth and Account Lifecycle (1)

Password reset, email verification, re-authentication, account deletion and export, and sign-out semantics.

- **medium** — [Unverified accounts work fully; nothing checks the verified flag](auth-and-account-lifecycle/no-email-verification.md)

## Dependency and Tooling Drift (0)

Version lag and resolver locks across Dart, Node and Gradle, dead or incompatible lint tooling, and unmaintained local scripts.


## Platform and Delivery Config (1)

The iOS and macOS platform trees, scaffold leftovers, signing and icons.

- **low** — [The client-side Firebase API key is duplicated across config files](platform-and-delivery-config/client-firebase-api-keys-committed-in-plaintext.md)

## CI and Quality Gates (1)

Test depth and what CI runs.

- **low** — [Three template tests still run and check nothing about the app](ci-and-quality-gates/template-tests-check-nothing.md)

## Repo, Docs and Release Hygiene (1)

Git working state and refs, documentation that contradicts the code, and versioning, licensing and release records.

- **medium** — [A generated file is ignored on iOS but tracked on macOS](repo-docs-and-release-hygiene/generated-plugin-registrant-tracked-on-macos-only.md)

