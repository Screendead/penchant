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

**64 issues: 0 critical, 6 high, 33 medium, 25 low.**

## Firebase Data Layer (7)

Firestore security rules, index and query shapes, the document schema contract, and project-level Firebase configuration.

- **medium** — [Activity timestamps trust the device clock, not the server](firebase-data-layer/activity-timestamps-come-from-the-device-clock.md)
- **medium** — [No dev or staging alias; every firebase command defaults to production](firebase-data-layer/every-firebase-command-targets-production.md)
- **medium** — [Legacy vices without `archived` cannot be recorded against](firebase-data-layer/vices-without-archived-never-reach-the-today-tab.md)
- **medium** — [The rules deploy job is off, and index or console drift goes unchecked](firebase-data-layer/rules-and-indexes-are-never-deployed-or-tested.md)
- **low** — [Daily totals shift depending on the device's timezone](firebase-data-layer/day-windows-use-device-local-midnight.md)
- **low** — [Legacy activities of a missing vice are fetched but unreachable](firebase-data-layer/vice-activity-relationship-is-unenforced.md)
- **low** — [The vice lists are the last list queries with no limit](firebase-data-layer/vice-lists-are-unbounded.md)

## Widget State and View Logic (11)

Riverpod provider semantics and lifecycle, resource disposal, build-phase side effects, and the chart and graph computation pipelines.

- **medium** — [Archiving a vice hides it in some screens but not others](widget-state-and-view-logic/archived-means-hidden-in-two-pickers-only.md)
- **medium** — [Signed-in users briefly see the login screen on every cold start](widget-state-and-view-logic/auth-loading-is-treated-as-signed-out.md)
- **medium** — [Form fields leak controllers and focus nodes instead of cleaning up](widget-state-and-view-logic/controllers-and-focus-nodes-are-never-disposed.md)
- **medium** — [Editing form ignores live database changes after it first loads](widget-state-and-view-logic/editor-seeds-its-controllers-during-build.md)
- **medium** — [Graph screen recomputes its entire chart pipeline on every rebuild](widget-state-and-view-logic/graph-build-method-recomputes-everything.md)
- **medium** — [Smoothing slider, caption, and math can all disagree with each other](widget-state-and-view-logic/smoothing-window-escapes-its-own-bounds.md)
- **medium** — [App left open past midnight keeps showing yesterday as today](widget-state-and-view-logic/today-is-frozen-at-widget-initialisation.md)
- **medium** — [Usage graph draws below zero and repeats or overlaps its axis labels](widget-state-and-view-logic/usage-graph-misdraws-sparse-data.md)
- **medium** — [Weekly graph's most recent point is always artificially depressed](widget-state-and-view-logic/weekly-bucketing-leaves-a-short-trailing-bucket.md)
- **low** — [Both home tabs stay active and subscribed even when hidden](widget-state-and-view-logic/both-home-tabs-stay-mounted-and-subscribed.md)
- **medium** — [Chart axis titles are not width-bounded, so long vice names can run into their neighbours](widget-state-and-view-logic/chart-axis-titles-are-not-width-bounded.md)

## Error Handling and Observability (5)

Swallowed failure states, unguarded bootstrap, inconsistent exception surfacing, and the absence of logging or telemetry.

- **high** — [A failed Firebase startup leaves the splash screen up forever](error-handling-and-observability/firebase-bootstrap-has-no-error-handling.md)
- **high** — [Data errors look exactly like loading, so screens spin forever silently](error-handling-and-observability/no-screen-inspects-asyncvalue-error-state.md)
- **medium** — [Every caught error is shown once on screen and then lost for good](error-handling-and-observability/catch-sites-render-the-error-once-and-discard-it.md)
- **medium** — [No crashes, errors, or usage are ever recorded on any platform](error-handling-and-observability/no-logging-crash-reporting-or-telemetry.md)
- **low** — [The same save error reads four different ways depending on the screen](error-handling-and-observability/firebaseexception-is-rendered-four-different-ways.md)

## Offline and Write Reliability (2)

Firestore persistence configuration, write timeouts and in-flight UI state, destructive-action safety, and connectivity feedback.

- **high** — [A change made offline that the server later refuses vanishes without a word](offline-and-write-reliability/rejected-queued-write-is-dropped-silently.md)
- **medium** — [Deleting an activity behaves differently depending on which screen you're on](offline-and-write-reliability/destructive-actions-have-inconsistent-safety.md)

## Duplication and Dead Code (9)

Copy-pasted logic, unused providers, methods and fields, commented-out code, and lint and formatting drift.

- **medium** — [Date-entry field, timer, and lock toggle are copy-pasted across two files](duplication-and-dead-code/activity-date-entry-flow-duplicated.md)
- **low** — [A copied timer runs uselessly because the editor starts in the opposite mode](duplication-and-dead-code/editor-timer-runs-for-a-mode-that-starts-disabled.md)
- **low** — [Firebase config files still carry empty CLI scaffolding](duplication-and-dead-code/firebase-config-scaffold-leftovers.md)
- **low** — [Long lines and missing const modifiers go uncaught since nothing runs dart format](duplication-and-dead-code/formatting-and-const-drift.md)
- **low** — [A row's tap and its edit button do the exact same thing, redundantly](duplication-and-dead-code/history-row-carries-two-identical-routes.md)
- **low** — [Serialization helpers are used only by tests while every write site hand-builds its own map](duplication-and-dead-code/model-tojson-and-copywith-are-never-called.md)
- **low** — [The same nullable-lookup pattern is typed out separately twice](duplication-and-dead-code/null-safe-firstwhere-idiom-copied-twice.md)
- **low** — [A custom toString reimplements the enum's built-in name getter by hand](duplication-and-dead-code/unit-tostring-reimplements-the-enum-name-getter.md)
- **low** — [An auth widget carries a dead field](duplication-and-dead-code/unused-fields-and-commented-out-code.md)

## Accessibility and Localization (7)

Screen-reader semantics, text-scale and overflow behaviour, theme colour roles, and locale-sensitive formatting and localization scaffolding.

- **medium** — [Dates always render in English regardless of device locale](accessibility-and-localization/dateformat-constructed-without-a-locale.md)
- **medium** — [App has no localization setup at all, English only](accessibility-and-localization/no-localizations-delegates-or-supported-locales.md)
- **low** — [Same date shown in four different formats across screens](accessibility-and-localization/date-patterns-differ-between-write-and-read-screens.md)
- **low** — [Day header colours are hardcoded white, not theme-derived](accessibility-and-localization/day-header-hardcodes-colors-white.md)
- **low** — [No declared app language on iOS or macOS](accessibility-and-localization/platform-shells-declare-no-language-metadata.md)
- **low** — [Relative date labels are hand-rolled English with no localization](accessibility-and-localization/relative-date-labels-are-hardcoded-english.md)
- **low** — [Pluralisation and number formatting assume English rules](accessibility-and-localization/value-rendering-is-english-and-locale-insensitive.md)

## Auth and Account Lifecycle (1)

Password reset, email verification, re-authentication, account deletion and export, and sign-out semantics.

- **medium** — [Unverified accounts work fully; nothing checks the verified flag](auth-and-account-lifecycle/no-email-verification.md)

## Dependency and Tooling Drift (7)

Version lag and resolver locks across Dart, Node and Gradle, dead or incompatible lint tooling, and unmaintained local scripts.

- **high** — [The riverpod lint plugin can never load, so it silently never runs](dependency-and-tooling-drift/custom-lint-plugin-cannot-load-riverpod-lint.md)
- **medium** — [The minimatch 11 override breaks the firebase-tools paths that call minimatch as a function](dependency-and-tooling-drift/minimatch-override-breaks-firebase-tools-glob-paths.md)
- **high** — [Unused lint tooling holds the resolved analyzer package six majors back](dependency-and-tooling-drift/unused-lint-tooling-caps-the-analyzer-package.md)
- **medium** — [Code-generation packages are installed but nothing in the app uses them](dependency-and-tooling-drift/riverpod-codegen-toolchain-declared-but-unused.md)
- **medium** — [A plain dependency upgrade can never move the Riverpod packages forward](dependency-and-tooling-drift/riverpod-family-exact-pins-block-upgrades.md)
- **low** — [Firebase plugins lag freely while test and build_runner sit stuck](dependency-and-tooling-drift/dart-dependencies-trail-pub-dev.md)
- **medium** — [Firebase stops publishing to CocoaPods in October 2026, and both Apple builds depend on it](dependency-and-tooling-drift/cocoapods-sunset-ends-firebase-ios-publishing.md)

## Platform and Delivery Config (11)

The iOS and macOS platform trees, scaffold leftovers, signing and icons.

- **high** — [macOS Firebase pods are missing from the lockfile despite being registered in code](platform-and-delivery-config/macos-tree-is-stale-and-lockfile-has-no-firebase-pods.md)
- **medium** — [The macOS build ships Firebase config registered under an iOS test bundle id](platform-and-delivery-config/macos-firebase-config-carries-the-ios-test-bundle-id.md)
- **medium** — [macOS sandbox entitlements omit outbound network access that Firebase needs](platform-and-delivery-config/macos-sandbox-grants-no-outbound-network.md)
- **medium** — [Flutter's migration metadata tracks neither shipped platform](platform-and-delivery-config/metadata-tracks-only-two-of-four-platforms.md)
- **medium** — [App name and description are still flutter-create scaffold text outside Dart code](platform-and-delivery-config/placeholder-app-identity-strings.md)
- **low** — [The client-side Firebase API key is duplicated across config files](platform-and-delivery-config/client-firebase-api-keys-committed-in-plaintext.md)
- **low** — [Unused placeholder icons and launch images from scaffolding remain in the repo](platform-and-delivery-config/dead-scaffold-assets-ship-in-every-build.md)
- **low** — [iOS Podfile forces one deployment target and relaxed includes on every pod](platform-and-delivery-config/ios-podfile-applies-blanket-pod-wide-overrides.md)
- **low** — [macOS still targets a years-unsupported OS version while iOS was upgraded](platform-and-delivery-config/macos-deployment-target-frozen-at-10-14.md)
- **low** — [iOS and macOS code-signing settings are outdated and inconsistent with each other](platform-and-delivery-config/signing-configuration-is-legacy-and-inconsistent.md)
- **medium** — [`flutter build macos --release` fails because the pods target macOS versions Xcode no longer supports](platform-and-delivery-config/macos-release-build-fails-on-pod-deployment-targets.md)

## CI and Quality Gates (1)

Test depth and what CI runs.

- **medium** — [The usage graph's weekly bucketing and smoothing are untested, and CI skips the end-to-end suite](ci-and-quality-gates/the-test-suite-is-a-single-boilerplate-smoke-test.md)

## Repo, Docs and Release Hygiene (3)

Git working state and refs, documentation that contradicts the code, and versioning, licensing and release records.

- **medium** — [A generated file is ignored on iOS but tracked on macOS](repo-docs-and-release-hygiene/generated-plugin-registrant-tracked-on-macos-only.md)
- **medium** — [The README is still the default flutter create scaffold text](repo-docs-and-release-hygiene/readme-is-the-unmodified-flutter-template.md)
- **low** — [A commented-out ignore line left the .vscode folder tracked by accident](repo-docs-and-release-hygiene/vscode-launch-json-tracked-by-template-default.md)

