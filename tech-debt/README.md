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

**12 issues: 0 critical, 0 high, 1 medium, 11 low.**
**12 issues: 0 critical, 0 high, 1 medium, 11 low.**

## Firebase Data Layer (5)

Firestore security rules, index and query shapes, the document schema contract, and project-level Firebase configuration.

- **medium** — [The rules still accept a vice's name and unit, and an activity's triggers, in plaintext](firebase-data-layer/plaintext-creates-are-still-accepted.md)
- **low** — [A sealed entry can be moved in time or rolled back without the client noticing](firebase-data-layer/sealed-blobs-bind-neither-time-nor-state.md)
- **low** — [The sealing migrator fails a whole batch on one oversized legacy name and tracks completion per device](firebase-data-layer/sealing-migrator-edge-cases.md)
- **low** — [Nothing checks the rules and index files against the live project](firebase-data-layer/rules-and-indexes-are-never-deployed-or-tested.md)
- **low** — [Legacy activities of a missing vice appear on no screen](firebase-data-layer/vice-activity-relationship-is-unenforced.md)

## Widget State and View Logic (1)

Riverpod provider semantics and lifecycle, resource disposal, build-phase side effects, and the chart and graph computation pipelines.

- **low** — [The undo bar's lift over Log is fixed when it is shown, and applies on every page](widget-state-and-view-logic/undo-bar-lift-is-fixed-at-show-time.md)

## Error Handling and Observability (0)

Swallowed failure states, unguarded bootstrap, inconsistent exception surfacing, and the absence of logging or telemetry.


## Offline and Write Reliability (2)

Firestore persistence configuration, write timeouts and in-flight UI state, destructive-action safety, and connectivity feedback.

- **low** — [A dense hour's arc does not show which of its entries are unsynced](offline-and-write-reliability/dense-hour-arc-shows-no-pending-entries.md)
- **low** — [A late Undo made offline from a widget reaches the server only when Penchant next starts](offline-and-write-reliability/late-undo-offline-waits-for-the-app.md)

## Accessibility and Localization (1)

Screen-reader semantics, text-scale and overflow behaviour, theme colour roles, and locale-sensitive formatting and localization scaffolding.

- **low** — [English only: every UI string is a literal, with no translation pipeline](accessibility-and-localization/no-localizations-delegates-or-supported-locales.md)

## Auth and Account Lifecycle (1)

Password reset, email verification, re-authentication, account deletion and export, and sign-out semantics.

- **low** — [The recovery key is copied with a plain clipboard write](auth-and-account-lifecycle/recovery-key-copy-reaches-universal-clipboard.md)

## Dependency and Tooling Drift (0)

Version lag and resolver locks across Dart, Node and Gradle, dead or incompatible lint tooling, and unmaintained local scripts.


## Platform and Delivery Config (2)

The iOS and macOS platform trees, scaffold leftovers, signing and icons.

- **low** — [A Mac launch nobody asked to bring forward still takes focus](platform-and-delivery-config/background-launches-take-focus-on-the-mac.md)
- **low** — [Mac widget logs wait for the app when the menu bar helper is not running](platform-and-delivery-config/mac-widget-logs-need-the-helper.md)

## CI and Quality Gates (0)

Test depth and what CI runs.


## Repo, Docs and Release Hygiene (0)

Git working state and refs, documentation that contradicts the code, and versioning, licensing and release records.


