# Tech-debt register

An exhaustive catalogue of this repository's technical debt as of 2026-08-11. Each subdirectory is one class of debt;
each file inside is one issue: what it is, what it costs, and the evidence, never a prescription for the fix, which is
the PR's to design. The register burns down by deletion: when an issue is fixed or stops being true, the PR deletes its
file and its line below (and a directory it empties). When this directory is gone the debt is gone.

`tools/tech-debt-recount.py` recomputes the counts, drops lines whose file is gone, keeps both sides of a merge
conflict in this file, and fails if a report file has no line (`--check` exits 1 if a rewrite would change the file).
It resolves paths from its own location, so run the copy inside the worktree you are changing.

Severity: **critical**: broken right now, or a real security or data-integrity exposure. **high**: actively costs
correctness or velocity, or breaks the next routine action. **medium**: drift, friction, or risk that compounds.
**low**: clutter.

Evidence line numbers refer to the working tree at `master` on 2026-11-04 (refreshed after waves A and B); citations
drift as code moves.

**8 issues: 0 critical, 0 high, 0 medium, 8 low.**

## Firebase Data Layer (2)

Firestore security rules, index and query shapes, the document schema contract, and project-level Firebase configuration.

- **low** — [A sealed entry can be moved in time or rolled back without the client noticing](firebase-data-layer/sealed-blobs-bind-neither-time-nor-state.md)
- **low** — [Nothing checks the rules and index files against the live project](firebase-data-layer/rules-and-indexes-are-never-deployed-or-tested.md)

## Widget State and View Logic (1)

Riverpod provider semantics and lifecycle, resource disposal, build-phase side effects, and the chart and graph computation pipelines.

- **low** — [The undo bar's lift over Log is fixed when it is shown, and applies on every page](widget-state-and-view-logic/undo-bar-lift-is-fixed-at-show-time.md)

## Error Handling and Observability (0)

Swallowed failure states, unguarded bootstrap, inconsistent exception surfacing, and the absence of logging or telemetry.


## Offline and Write Reliability (1)

Firestore persistence configuration, write timeouts and in-flight UI state, destructive-action safety, and connectivity feedback.

- **low** — [A dense hour's arc does not show which of its entries are unsynced](offline-and-write-reliability/dense-hour-arc-shows-no-pending-entries.md)

## Accessibility and Localization (1)

Screen-reader semantics, text-scale and overflow behaviour, theme colour roles, and locale-sensitive formatting and localization scaffolding.

- **low** — [English only: every UI string is a literal, with no translation pipeline](accessibility-and-localization/no-localizations-delegates-or-supported-locales.md)

## Auth and Account Lifecycle (0)

Password reset, email verification, re-authentication, account deletion and export, and sign-out semantics.


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


