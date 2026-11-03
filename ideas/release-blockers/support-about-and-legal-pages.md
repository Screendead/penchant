# Build the Support, About and legal pages the listing and Settings point to

**Priority:** release blocker

## What

Publish three static pages, /privacy, /terms and /support (an FAQ and a contact address), and build the Settings rows
that 404 today. About shows the version and build, links to the three pages, and shows open-source licences through
`showLicensePage`. Privacy holds export, delete, the policy, and the Health and Calendar permission switches. "Contact
support" opens a mail draft pre-filled with the version and platform.

## Why

- SOURCED (repo): `lib/settings.dart` pushes `/settings/notifications`, `/settings/privacy` and `/settings/about`, and
  all three dead-end on a 404. Bundled licence text is never shown.
- SOURCED ([market scan](../market-scan.md)): hard-to-reach support is a top complaint about Reframe.
- From memory, to verify: App Store Connect requires a support URL and a privacy policy URL on the listing.
- SOURCED (C6): `web/` and the hosting workflows are being deleted, so the pages need a host that is not the Flutter
  web build.

## Options

- **A.** Plain static pages on Firebase Hosting, deployed from a small `site/` folder in the repo by CI.
- **B.** Static pages on the brand's own domain (GitHub Pages or similar), outside Firebase.
- **C.** A hosted help-desk (Crisp, Zendesk). Overkill at launch.

## Recommendation

Claude's recommendation: **A** until the brand domain exists, then point the domain at the same hosting. It reuses a
host that already serves production, and the pages are three HTML files. Hosting deploys reach production, so they go
through CI on merge, never from an agent's machine.

**Effort:** S

**Revenue impact:** A release prerequisite (the listing URLs); it also protects ratings.

**Depends on:**
- [brand name](brand-name.md), for the domain
- [`four-named-routes-dead-end-at-not-found`](../../tech-debt/navigation-and-unreachable-ui/four-named-routes-dead-end-at-not-found.md)
- [`third-party-license-attribution-never-surfaced`](../../tech-debt/repo-docs-and-release-hygiene/third-party-license-attribution-never-surfaced.md)

**Needs Jack:** yes — Which address is the support contact, and where do the pages live (Firebase Hosting or the brand
domain)?
