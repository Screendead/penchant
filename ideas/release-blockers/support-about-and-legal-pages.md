# Build the Support, About and legal pages the listing and Settings point to

**Priority:** release blocker

## What

Publish three static pages, /privacy, /terms and /support (an FAQ and a contact address), and give Settings the
Notifications and Privacy rows it lacks. About, which already shows the version and the open-source licences, also links to the three pages. Privacy holds export, delete, the
policy, and the Health and Calendar permission switches. "Contact support" opens a mail draft pre-filled with the version and platform.

## Why

- SOURCED (repo): Settings had Notifications and Privacy rows that dead-ended on a 404; they were removed until there
  is something behind them. About already shows the version and, through `showAboutDialog`, the open-source licences.
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

**Needs Jack:** yes — Which address is the support contact, and where do the pages live (Firebase Hosting or the brand
domain)?
