# Let every user export their data as CSV and JSON

**Priority:** v1 must-have

## What

"Export my data" sits next to "Delete account". It reads all of the user's vices and activities, with every logged
field (time, quantity, triggers, context, notes), and writes a CSV with one row per activity plus a full JSON dump,
then hands both to the share sheet. Derived insights are not exported: they regenerate from the raw data.

## Why

- SOURCED (register): there is no export path.
- SOURCED ([market scan](../market-scan.md)): MyDrinkaware users complained when a redesign removed their old data.
  INFERENCE: a journal asks people to invest years of entries; export answers the fear of lock-in, and the
  quantified-self audience expects it.
- INFERENCE, not researched: GDPR Art. 20 portability probably applies to EU users, so a paywall on export carries
  legal and review risk.

## Options

- **A.** Client-side CSV and JSON through the share sheet. Works offline from the cache.
- **B.** A, plus CSV import from other trackers (Daylio, Bearable), sold as a switching tool.

## Recommendation

Claude's recommendation: **A, free forever**, in 1.0. Paginate the read. Import (B) waits for Pro, where it is a
switching tool for exactly the journal users the positioning targets.

**Effort:** S

**Revenue impact:** Indirect: trust and retention.

**Depends on:**
- [account deletion](../release-blockers/in-app-account-deletion.md)
- [`no-account-deletion-or-data-export`](../../tech-debt/auth-and-account-lifecycle/no-account-deletion-or-data-export.md)
- `no-query-is-bounded-or-paginated` (fixed by backend hardening: every activity list query is bounded, so an export needs its own paged read)

**Needs Jack:** no
