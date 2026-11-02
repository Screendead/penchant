# Build the Support, About and legal pages the listing and Settings point to

**Priority:** release blocker

## What

Publish static pages on the existing Firebase Hosting site: /privacy, /terms and /support, with an FAQ and a contact address. In the app, build the Settings rows that currently 404. About shows the version and build, links to support, privacy and terms, and shows open-source licences via `showLicensePage`. Privacy holds export, delete and the policy. Add a "Contact support" mailto link that pre-fills the version and platform.

## Why

- SOURCED (repo): `lib/settings.dart` pushes `/settings/notifications`, `/settings/privacy` and `/settings/about`, and all three dead-end on a 404. Bundled licence text is never shown.
- SOURCED ([market scan](../market-scan.md)): hard-to-reach support is a major complaint about Reframe.
- From memory, to verify: App Store Connect requires a support URL and a privacy policy URL on the listing.

## Options

- **A.** Static pages on Firebase Hosting, plus a dedicated support mailbox.
- **B.** A hosted help-desk tool (Crisp, Zendesk). Overkill at launch.
- **C.** GitHub Issues. Unsuitable for a privacy-sensitive consumer app.

## Recommendation

Claude's recommendation, not a decision: **A.** It costs almost nothing, uses the hosting that already exists, and gives the listing its required URLs. Plan the static paths together with the missing SPA rewrite. Hosting deploys reach production, so they go through CI on merge and never from an agent's machine.

**Effort:** S

**Revenue impact:** A release prerequisite (the listing URLs). Indirectly it protects ratings and avoids refunds.

**Depends on:**
- [`four-named-routes-dead-end-at-not-found`](../../tech-debt/navigation-and-unreachable-ui/four-named-routes-dead-end-at-not-found.md)
- [`third-party-license-attribution-never-surfaced`](../../tech-debt/repo-docs-and-release-hygiene/third-party-license-attribution-never-surfaced.md)
- [`hosting-has-no-spa-rewrite`](../../tech-debt/navigation-and-unreachable-ui/hosting-has-no-spa-rewrite.md)

**Needs Jack:** yes — Which email address is the support contact, and should the Notifications row be built ([reminders](../v1-must-haves/evening-check-in-and-reminders.md)) or removed?
