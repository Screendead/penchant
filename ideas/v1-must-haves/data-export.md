# Let every user export their data as CSV and JSON

**Priority:** v1 must-have

## What

Add an "Export my data" action next to "Delete account". It reads all of the user's vices and activities and writes two files: a CSV with one row per activity (date, vice, unit, quantity) and a JSON dump. It then hands both to the share sheet.

## Why

- SOURCED (register): there is no export path.
- SOURCED ([market scan](../market-scan.md)): MyDrinkaware users complained when a redesign removed their old data presentation. Export answers the fear of lock-in.
- INFERENCE, not researched: GDPR Art. 20 portability probably applies to EU users, so putting export behind a paywall carries legal and review risk.

## Options

- **A.** Client-side CSV and JSON through a share-sheet plugin (for example share_plus). It works offline from the cache.
- **B.** A server-generated file, emailed by a Cloud Function. This depends on `functions/` (HANDOVER J2).
- **C.** A, plus CSV import from other trackers, sold as a switching tool.

## Recommendation

Claude's recommendation, not a decision: **A, free forever.** Putting your own data behind a paywall looks hostile. Paginate the read, because every query is unbounded today. Import (C) can wait until there is a paid tier to attach it to.

**Effort:** S

**Revenue impact:** Indirect: trust and retention.

**Depends on:**
- [account deletion](../release-blockers/in-app-account-deletion.md)
- [`no-account-deletion-or-data-export`](../../tech-debt/auth-and-account-lifecycle/no-account-deletion-or-data-export.md)
- [`no-query-is-bounded-or-paginated`](../../tech-debt/firebase-data-layer/no-query-is-bounded-or-paginated.md)
- [`model-parsers-cast-unconditionally`](../../tech-debt/firebase-data-layer/model-parsers-cast-unconditionally.md)

**Needs Jack:** no
