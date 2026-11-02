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

Evidence line numbers refer to the working tree on 2026-08-11, which included roughly
1,400 uncommitted lines across twelve paths; citations into those files will drift as
that work lands.

**155 issues: 5 critical, 33 high, 74 medium, 43 low.**

## Firebase Data Layer (17)

Firestore security rules, index and query shapes, the document schema contract, and project-level Firebase configuration.

- **critical** — [Every activity delete is silently denied by the security rules](firebase-data-layer/activity-deletes-permitted-by-no-rule.md)
- **critical** — [A user can overwrite and reassign another account's document](firebase-data-layer/write-rules-authorize-on-the-post-write-owner.md)
- **high** — [Saving a vice throws internally and stalls the list a round trip](firebase-data-layer/model-parsers-cast-unconditionally.md)
- **high** — [Documented seed command produces data that crashes the app](firebase-data-layer/seed-script-writes-documents-that-crash-the-parser.md)
- **high** — [Main chart's query has no matching index in the repo](firebase-data-layer/unarchived-vices-query-has-no-matching-index.md)
- **high** — [Security rules never check field types or required fields](firebase-data-layer/writes-carry-no-field-or-type-validation.md)
- **medium** — [Activity timestamps trust the device clock, not the server](firebase-data-layer/activity-timestamps-come-from-the-device-clock.md)
- **medium** — [Unused providers would fail instantly if ever wired up](firebase-data-layer/dead-providers-query-an-unindexed-shape.md)
- **medium** — [No dev or staging project; every command hits production](firebase-data-layer/every-firebase-command-targets-production.md)
- **medium** — [Every list screen streams unbounded data with no limit](firebase-data-layer/no-query-is-bounded-or-paginated.md)
- **medium** — [Security rules and indexes can silently drift from production](firebase-data-layer/rules-and-indexes-are-never-deployed-or-tested.md)
- **medium** — [Rules wrapper leaks permissions to any future nested collection](firebase-data-layer/rules-nested-in-an-unused-recursive-wildcard.md)
- **medium** — [Vice count growth will eventually break the main chart](firebase-data-layer/wherein-filter-is-unbounded-and-includes-archived.md)
- **low** — [Auth check works by accident, not by the condition written](firebase-data-layer/auth-guard-dereferences-a-null-request-auth.md)
- **low** — [Daily totals shift depending on the device's timezone](firebase-data-layer/day-windows-use-device-local-midnight.md)
- **low** — [Unused Firebase Storage rules still deploy on every release](firebase-data-layer/storage-rules-configured-for-an-unused-product.md)
- **low** — [An activity's vice link is never validated anywhere](firebase-data-layer/vice-activity-relationship-is-unenforced.md)

## Widget State and View Logic (20)

Riverpod provider semantics and lifecycle, resource disposal, build-phase side effects, and the chart and graph computation pipelines.

- **high** — [Date navigation can permanently freeze the day picker with no error shown](widget-state-and-view-logic/date-navigation-awaits-a-future-that-never-completes.md)
- **high** — [A new account with zero vices sees an endless loading spinner](widget-state-and-view-logic/empty-stream-shortcircuit-reads-as-permanent-loading.md)
- **high** — [Signing out can briefly show the previous user's private data](widget-state-and-view-logic/provider-value-carries-the-previous-users-data.md)
- **high** — [Every database write is hand-copied inline instead of shared code](widget-state-and-view-logic/writes-bypass-providers-with-inline-firestore-calls.md)
- **medium** — [Archiving a vice hides it in some screens but not others](widget-state-and-view-logic/archived-means-hidden-in-two-pickers-only.md)
- **medium** — [Signed-in users briefly see the login screen on every cold start](widget-state-and-view-logic/auth-loading-is-treated-as-signed-out.md)
- **medium** — [Chart can crash mid-paint when two vice lists fall out of sync](widget-state-and-view-logic/axis-titles-resolve-against-a-different-provider.md)
- **medium** — [Form fields leak controllers and focus nodes instead of cleaning up](widget-state-and-view-logic/controllers-and-focus-nodes-are-never-disposed.md)
- **medium** — [Dialog holds onto another screen's context across async gaps](widget-state-and-view-logic/dialog-stores-a-foreign-buildcontext.md)
- **medium** — [Editing form ignores live database changes after it first loads](widget-state-and-view-logic/editor-seeds-its-controllers-during-build.md)
- **medium** — [Graph screen recomputes its entire chart pipeline on every rebuild](widget-state-and-view-logic/graph-build-method-recomputes-everything.md)
- **medium** — [Browsing history can leave up to 30 live database listeners open](widget-state-and-view-logic/no-provider-is-autodispose.md)
- **medium** — [Two vices sharing a name merge into one chart axis silently](widget-state-and-view-logic/radar-data-is-keyed-by-vice-name.md)
- **medium** — [Recording an activity can crash if the session ends mid-dialog](widget-state-and-view-logic/record-dialog-reads-auth-directly-with-a-bang.md)
- **medium** — [Chart title callback watches a provider outside Flutter's build phase](widget-state-and-view-logic/ref-watch-runs-inside-a-chart-paint-callback.md)
- **medium** — [Smoothing slider, caption, and math can all disagree with each other](widget-state-and-view-logic/smoothing-window-escapes-its-own-bounds.md)
- **medium** — [App left open past midnight keeps showing yesterday as today](widget-state-and-view-logic/today-is-frozen-at-widget-initialisation.md)
- **medium** — [Weekly graph's most recent point is always artificially depressed](widget-state-and-view-logic/weekly-bucketing-leaves-a-short-trailing-bucket.md)
- **low** — [Both home tabs stay active and subscribed even when hidden](widget-state-and-view-logic/both-home-tabs-stay-mounted-and-subscribed.md)
- **low** — [Same calendar day can spawn duplicate database listeners](widget-state-and-view-logic/day-provider-family-key-is-not-normalised.md)

## Navigation and Unreachable UI (8)

Routes that dead-end, screens and empty states that cannot be reached or escaped, and routing configuration.

- **high** — [Editing a vice, and three Settings rows, all dead-end on a 404 page](navigation-and-unreachable-ui/four-named-routes-dead-end-at-not-found.md)
- **medium** — [Every ordinary zero-activity day now looks like an error](navigation-and-unreachable-ui/a-zero-activity-day-renders-as-an-error.md)
- **medium** — [No activities yet hides the add-vice button and close action](navigation-and-unreachable-ui/manage-data-hides-everything-when-activities-are-empty.md)
- **medium** — [Signing out leaves a stuck spinner screen floating over sign-in](navigation-and-unreachable-ui/routes-are-generated-without-consulting-auth-state.md)
- **low** — [Every screen, including the error page, opens as a modal](navigation-and-unreachable-ui/every-route-is-a-fullscreen-dialog.md)
- **low** — [Deep links would 404 on Firebase Hosting if paths were ever used](navigation-and-unreachable-ui/hosting-has-no-spa-rewrite.md)
- **low** — [A bad link can strand a web user on a dead-end error page](navigation-and-unreachable-ui/not-found-offers-only-an-inert-back-action.md)
- **low** — [The record-activity button vanishes while viewing the graph tab](navigation-and-unreachable-ui/record-action-disappears-on-the-graph-tab.md)

## Error Handling and Observability (7)

Swallowed failure states, unguarded bootstrap, inconsistent exception surfacing, and the absence of logging or telemetry.

- **high** — [A failed Firebase startup leaves a blank screen or stuck splash forever](error-handling-and-observability/firebase-bootstrap-has-no-error-handling.md)
- **high** — [Data errors look exactly like loading, so screens spin forever silently](error-handling-and-observability/no-screen-inspects-asyncvalue-error-state.md)
- **high** — [Sign-up errors like taken emails never reach the user at all](error-handling-and-observability/registration-failures-are-unhandled.md)
- **medium** — [One screen silences a safety lint instead of checking the widget is still alive](error-handling-and-observability/async-buildcontext-lint-suppressed-instead-of-guarded.md)
- **medium** — [Every caught error is shown once on screen and then lost for good](error-handling-and-observability/catch-sites-render-the-error-once-and-discard-it.md)
- **medium** — [Inconsistent error display, and one path can crash the Save button itself](error-handling-and-observability/firebaseexception-is-rendered-four-different-ways.md)
- **medium** — [No crashes, errors, or usage are ever recorded on any platform](error-handling-and-observability/no-logging-crash-reporting-or-telemetry.md)

## Offline and Write Reliability (9)

Firestore persistence configuration, write timeouts and in-flight UI state, destructive-action safety, and connectivity feedback.

- **high** — [Offline caching and write durability silently differ between web and mobile](offline-and-write-reliability/firestore-persistence-is-never-configured.md)
- **high** — [Loading scrim blocks touch but not screen readers; Record button unguarded](offline-and-write-reliability/loading-overlay-does-not-block-input.md)
- **high** — [App can't tell a stale offline cache from a confirmed empty result](offline-and-write-reliability/no-read-path-inspects-snapshotmetadata.md)
- **high** — [A timeout error can be followed by the write succeeding anyway, twice](offline-and-write-reliability/the-timeout-abandons-the-await-not-the-write.md)
- **high** — [Delete buttons can hang offline with no timeout and no visible feedback](offline-and-write-reliability/three-delete-paths-have-no-timeout-or-pending-state.md)
- **medium** — [Add and archive buttons can be pressed repeatedly while offline](offline-and-write-reliability/add-vice-and-archive-writes-have-no-timeout.md)
- **medium** — [Deleting an activity behaves differently depending on which screen you're on](offline-and-write-reliability/destructive-actions-have-inconsistent-safety.md)
- **medium** — [No banner, badge, or retry button ever tells the user they're offline](offline-and-write-reliability/no-connectivity-indicator-or-retry-affordance.md)
- **medium** — [Tapping outside the record dialog mid-write misdirects both success and failure](offline-and-write-reliability/record-dialog-barrier-is-dismissible-mid-write.md)

## Duplication and Dead Code (13)

Copy-pasted logic, unused providers, methods and fields, commented-out code, and lint and formatting drift.

- **medium** — [Date-entry field, timer, and lock toggle are copy-pasted across two files](duplication-and-dead-code/activity-date-entry-flow-duplicated.md)
- **medium** — [A provider has zero callers while another screen re-derives its grouping manually](duplication-and-dead-code/orphaned-vice-activities-by-vice-id-provider.md)
- **low** — [Two cosmetic lint warnings make flutter analyze exit with a failure code](duplication-and-dead-code/analyzer-info-lints-leave-the-gate-red.md)
- **low** — [A copied timer runs uselessly because the editor starts in the opposite mode](duplication-and-dead-code/editor-timer-runs-for-a-mode-that-starts-disabled.md)
- **low** — [Email validation is defined three separate times, two identically, one different](duplication-and-dead-code/email-validation-regex-declared-three-times.md)
- **low** — [Firebase config files still carry empty CLI scaffolding and missing newlines](duplication-and-dead-code/firebase-config-scaffold-leftovers.md)
- **low** — [Formatting drift and missing const modifiers go uncaught since nothing runs dart format](duplication-and-dead-code/formatting-and-const-drift.md)
- **low** — [A row's tap and its edit button do the exact same thing, redundantly](duplication-and-dead-code/history-row-carries-two-identical-routes.md)
- **low** — [Serialization helpers exist but every write site hand-builds its own map instead](duplication-and-dead-code/model-tojson-and-copywith-are-never-called.md)
- **low** — [The same nullable-lookup pattern is typed out separately three times](duplication-and-dead-code/null-safe-firstwhere-idiom-copied-three-times.md)
- **low** — [One query builder orders its clauses backwards compared to seven siblings](duplication-and-dead-code/query-clause-order-differs-between-providers.md)
- **low** — [A custom toString reimplements the enum's built-in name getter by hand](duplication-and-dead-code/unit-tostring-reimplements-the-enum-name-getter.md)
- **low** — [Auth widgets carry dead fields and a chart file keeps a stale commented-out line](duplication-and-dead-code/unused-fields-and-commented-out-code.md)

## Accessibility and Localization (17)

Screen-reader semantics, text-scale and overflow behaviour, theme colour roles, and locale-sensitive formatting and localization scaffolding.

- **high** — [Neither chart exposes any data to screen readers](accessibility-and-localization/charts-carry-no-screen-reader-semantics.md)
- **high** — [Main logging dialog can overflow at larger text sizes](accessibility-and-localization/record-dialog-content-cannot-scroll.md)
- **medium** — [Dates always render in English regardless of device locale](accessibility-and-localization/dateformat-constructed-without-a-locale.md)
- **medium** — [Date navigation row can overflow at larger text sizes](accessibility-and-localization/day-selector-row-overflows-at-large-text-scale.md)
- **medium** — [Two mismatched reds represent the same error concept](accessibility-and-localization/error-red-is-hardcoded-instead-of-the-theme-role.md)
- **medium** — [Graph's two lines are indistinguishable by colour or label](accessibility-and-localization/graph-series-distinguished-only-by-opacity.md)
- **medium** — [Some icon buttons have no accessible name at all](accessibility-and-localization/icon-button-tooltip-coverage-is-inconsistent.md)
- **medium** — [Chart axis labels clip when text size is increased](accessibility-and-localization/line-chart-axis-labels-clip-at-large-text-scale.md)
- **medium** — [App has no localization setup at all, English only](accessibility-and-localization/no-localizations-delegates-or-supported-locales.md)
- **medium** — [Radar chart text ignores accessibility text-size settings](accessibility-and-localization/radar-chart-text-ignores-system-text-scale.md)
- **medium** — [Tap-to-dismiss-keyboard handler goes stale after focus moves](accessibility-and-localization/root-gesturedetector-unfocus-handler-is-stale.md)
- **low** — [Same date shown in four different formats across screens](accessibility-and-localization/date-patterns-differ-between-write-and-read-screens.md)
- **low** — [Day header colours are hardcoded white, not theme-derived](accessibility-and-localization/day-header-hardcodes-colors-white.md)
- **low** — [Empty-data messages look identical to real error messages](accessibility-and-localization/neutral-empty-states-use-the-error-colour.md)
- **low** — [No declared app language on iOS, macOS, or the web shell](accessibility-and-localization/platform-shells-declare-no-language-metadata.md)
- **low** — [Relative date labels are hand-rolled English with no localization](accessibility-and-localization/relative-date-labels-are-hardcoded-english.md)
- **low** — [Pluralisation and number formatting assume English rules](accessibility-and-localization/value-rendering-is-english-and-locale-insensitive.md)

## Auth and Account Lifecycle (7)

Password reset, email verification, re-authentication, account deletion and export, and sign-out semantics.

- **high** — [No forgot-password link or recovery path anywhere in the app](auth-and-account-lifecycle/no-password-reset-path.md)
- **high** — [Profile save can fail on stale login yet still change display name silently](auth-and-account-lifecycle/profile-update-never-reauthenticates.md)
- **medium** — [Raw Firebase error text shown to users can reveal registered emails](auth-and-account-lifecycle/auth-errors-are-surfaced-verbatim.md)
- **medium** — [No account deletion or data export; deleted accounts leave orphaned data forever](auth-and-account-lifecycle/no-account-deletion-or-data-export.md)
- **medium** — [New accounts work immediately with an unverified, unconfirmed email](auth-and-account-lifecycle/no-email-verification.md)
- **medium** — [Sign-out failures go unhandled while navigation proceeds immediately regardless](auth-and-account-lifecycle/sign-out-is-neither-awaited-nor-guarded.md)
- **medium** — [Signed-out user's synced data stays cached on the device](auth-and-account-lifecycle/sign-out-leaves-firestore-cache-on-device.md)

## Dependency and Tooling Drift (11)

Version lag and resolver locks across Dart, Node and Gradle, dead or incompatible lint tooling, and unmaintained local scripts.

- **critical** — [Any Android build from this checkout fails before app code compiles](dependency-and-tooling-drift/android-gradle-pins-below-flutters-failure-floor.md)
- **high** — [The riverpod lint plugin can never load, so it silently never runs](dependency-and-tooling-drift/custom-lint-plugin-cannot-load-riverpod-lint.md)
- **high** — [Cloud Functions target a Node version that is already end of life](dependency-and-tooling-drift/functions-dependencies-frozen-on-an-eol-runtime.md)
- **high** — [Unused lint tooling holds the resolved analyzer package six majors back](dependency-and-tooling-drift/unused-lint-tooling-caps-the-analyzer-package.md)
- **medium** — [Functions lint stack is versions behind and on a config format ESLint 9 drops](dependency-and-tooling-drift/functions-lint-toolchain-on-legacy-config.md)
- **medium** — [Code-generation packages are installed but nothing in the app uses them](dependency-and-tooling-drift/riverpod-codegen-toolchain-declared-but-unused.md)
- **medium** — [A plain dependency upgrade can never move the Riverpod packages forward](dependency-and-tooling-drift/riverpod-family-exact-pins-block-upgrades.md)
- **low** — [The admin script's dependencies have not changed since the day they were added](dependency-and-tooling-drift/admin-dependencies-never-revisited.md)
- **low** — [Firebase plugins lag freely while test and build_runner sit stuck](dependency-and-tooling-drift/dart-dependencies-trail-pub-dev.md)
- **low** — [A testing package is installed even though the functions have no tests](dependency-and-tooling-drift/firebase-functions-test-is-unused.md)
- **low** — [The seed script hardcodes a real user's ID and cannot run on a fresh clone](dependency-and-tooling-drift/seed-script-is-a-hardcoded-one-off.md)

## Platform and Delivery Config (24)

The iOS, macOS, Android and web platform trees, scaffold leftovers, signing and icons, and web hosting and PWA delivery.

- **high** — [macOS Firebase pods are missing from the lockfile despite being registered in code](platform-and-delivery-config/macos-tree-is-stale-and-lockfile-has-no-firebase-pods.md)
- **high** — [No cache or security headers, and no service worker to bound stale builds](platform-and-delivery-config/no-hosting-headers-and-no-service-worker.md)
- **high** — [Android release builds are signed with the debug key, unusable for the Play Store](platform-and-delivery-config/release-builds-are-signed-with-the-debug-keystore.md)
- **medium** — [Android, iOS, and macOS trees exist but only web is ever built or documented](platform-and-delivery-config/android-is-maintained-in-name-only.md)
- **medium** — [A failed bootstrap script leaves users on a blank page with no error](platform-and-delivery-config/blank-page-when-the-bootstrap-script-fails.md)
- **medium** — [A committed Android config file is never read and names the wrong package](platform-and-delivery-config/google-services-json-unused-and-mismatched.md)
- **medium** — [Web hosting has no predeploy build step, unlike the functions deploy config](platform-and-delivery-config/hosting-public-directory-has-no-predeploy-build.md)
- **medium** — [The installable PWA has no offline fallback since no service worker exists](platform-and-delivery-config/installable-pwa-with-no-offline-shell.md)
- **medium** — [The macOS build ships Firebase config registered under an iOS test bundle id](platform-and-delivery-config/macos-firebase-config-carries-the-ios-test-bundle-id.md)
- **medium** — [macOS sandbox entitlements omit outbound network access that Firebase needs](platform-and-delivery-config/macos-sandbox-grants-no-outbound-network.md)
- **medium** — [PWA manifest colors use Dart's byte order, rendering as near-transparent to spec](platform-and-delivery-config/manifest-colors-use-dart-argb-order.md)
- **medium** — [Flutter's migration metadata tracks only two of the four shipped platforms](platform-and-delivery-config/metadata-tracks-only-two-of-four-platforms.md)
- **medium** — [The Android icon has no adaptive variant, so modern launchers render it flat](platform-and-delivery-config/no-adaptive-icon-for-api-26.md)
- **medium** — [Login and register pages have no CSP or frame protection headers](platform-and-delivery-config/no-csp-or-frame-protection-for-in-page-auth.md)
- **medium** — [App name and description are still flutter-create scaffold text outside Dart code](platform-and-delivery-config/placeholder-app-identity-strings.md)
- **low** — [Android Gradle config keeps outdated Jetifier and build-dir settings from scaffolding](platform-and-delivery-config/android-gradle-template-drift.md)
- **low** — [Android's fallback version numbers do not match pubspec's version format](platform-and-delivery-config/android-version-fallback-diverges-from-pubspec.md)
- **low** — [Client-side Firebase API keys are duplicated across platform config files](platform-and-delivery-config/client-firebase-api-keys-committed-in-plaintext.md)
- **low** — [Unused placeholder icons and launch images from scaffolding remain in the repo](platform-and-delivery-config/dead-scaffold-assets-ship-in-every-build.md)
- **low** — [iOS Podfile forces one deployment target and relaxed includes on every pod](platform-and-delivery-config/ios-podfile-applies-blanket-pod-wide-overrides.md)
- **low** — [macOS still targets a years-unsupported OS version while iOS was upgraded](platform-and-delivery-config/macos-deployment-target-frozen-at-10-14.md)
- **low** — [Maskable PWA icons are identical to plain icons, so adaptive masks crop the art](platform-and-delivery-config/maskable-icons-are-byte-identical-copies.md)
- **low** — [iOS and macOS code-signing settings are outdated and inconsistent with each other](platform-and-delivery-config/signing-configuration-is-legacy-and-inconsistent.md)
- **low** — [The web page keeps an obsolete IE meta tag and has no no-JavaScript fallback](platform-and-delivery-config/web-index-html-retains-obsolete-template-markup.md)

## CI and Quality Gates (5)

Test depth, the failing and unchecked functions build, fork coverage, and unverified build state.

- **critical** — [Cloud Functions cannot build, so any functions deploy fails before it starts](ci-and-quality-gates/functions-build-fails-so-any-deploy-aborts.md)
- **high** — [The only tests in the app check a hardcoded string against itself](ci-and-quality-gates/the-test-suite-is-a-single-boilerplate-smoke-test.md)
- **high** — [A logged compile failure was never re-verified after the code changed](ci-and-quality-gates/the-upgrade-left-a-failing-build-and-unverified-tree.md)
- **medium** — [No CI step ever touches the Cloud Functions code at all](ci-and-quality-gates/functions-directory-has-no-ci-coverage.md)
- **low** — [Fork-based pull requests never get a preview deploy](ci-and-quality-gates/fork-pull-requests-get-no-preview.md)

## Repo, Docs and Release Hygiene (17)

Git working state and refs, documentation that contradicts the code, and versioning, licensing and release records.

- **critical** — [Four finished features exist only on one machine, invisible to git diff or stash](repo-docs-and-release-hygiene/feature-work-exists-only-in-one-working-tree.md)
- **high** — [The onboarding doc describes code that was never committed anywhere](repo-docs-and-release-hygiene/claude-md-documents-uncommitted-state.md)
- **high** — [No LICENSE file exists, yet one manifest claims a license anyway](repo-docs-and-release-hygiene/no-license-file-anywhere.md)
- **high** — [New feature work is piling onto a branch already merged and closed](repo-docs-and-release-hygiene/the-work-sits-on-a-branch-already-merged-upstream.md)
- **high** — [Every production build reports version 1.0.0 with no tags to trace it](repo-docs-and-release-hygiene/version-never-incremented-and-no-tags.md)
- **medium** — [Five factual claims in the guidance doc do not match the actual code](repo-docs-and-release-hygiene/claude-md-claims-contradicted-by-the-code.md)
- **medium** — [A generated file is ignored on two platforms but tracked on a third](repo-docs-and-release-hygiene/generated-plugin-registrant-tracked-on-macos-only.md)
- **medium** — [The only records of failing quality gates are gitignored, unseen](repo-docs-and-release-hygiene/gitignored-logs-hid-the-failing-gates.md)
- **medium** — [Local master is three commits behind what CI actually deploys](repo-docs-and-release-hygiene/local-master-is-three-commits-behind.md)
- **medium** — [A full tracked macOS platform target is mentioned nowhere in docs](repo-docs-and-release-hygiene/macos-platform-is-undocumented.md)
- **medium** — [Seven already-merged branches and one unmergeable branch were never deleted](repo-docs-and-release-hygiene/merged-and-obsolete-refs-were-never-pruned.md)
- **medium** — [Two years of shipped changes have no changelog record at all](repo-docs-and-release-hygiene/no-changelog-or-release-notes.md)
- **medium** — [The README is still the default flutter create scaffold text](repo-docs-and-release-hygiene/readme-is-the-unmodified-flutter-template.md)
- **medium** — [Bundled third-party license text ships in the app but no screen shows it](repo-docs-and-release-hygiene/third-party-license-attribution-never-surfaced.md)
- **medium** — [Two git stashes, one over a year old, are stale and unusable](repo-docs-and-release-hygiene/two-stale-stashes.md)
- **low** — [Six gigabytes of ignored build and IDE clutter sit at the repo root](repo-docs-and-release-hygiene/stray-local-build-and-ide-artifacts.md)
- **low** — [A commented-out ignore line left the .vscode folder tracked by accident](repo-docs-and-release-hygiene/vscode-launch-json-tracked-by-template-default.md)

