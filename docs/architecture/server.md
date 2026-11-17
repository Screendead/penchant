# Server side (Cloud Functions)

**Server side.** Two scheduled functions in `functions/index.js`, and the callables `readNote` (Note reader,
Follow-up question), `writeWeekly` (Weekly review in words), `askJournal` (Ask your journal), `investigate` (Analyst),
`writeLetter` (Letter), `tidyTags` (Tidy my tags) and `readEntries` (Say it to log, Catch up), each requiring
sign-in and a verified, non-guest account (`permission-denied`), answering `failed-precondition` until the Anthropic federation is set, with its own `DailyCap`, and sharing
`maxInstances: 2`, 15 s, 256 MiB and the `note-reader@` service account (`writeLetter`: 220 s and 512 MiB, its client a
200 s timeout, inside the app's 240 s). `monthlySummaries` (03:00 UTC on the 1st;
`r8-bead-size`) writes `summaries/{uid}` for every user owning a vice: `{computedAt, windowDays: 90, vices: {viceID:
{typical, count}}}`, the median positive quantity of their last 90 days of activities and the entries it covers
(`functions/summary.js`, same median as `typicalQuantity` in `lib/data/dial_layout.dart`). It reads only `viceID` and
`quantity`, never a name or unit, which `r2-e2ee` seals; amounts and times stay plaintext for it (Sealed fields, `sealing-and-backup.md`).
Per user, one paged query on the existing (`ownerID`, `createdAt` desc) index, capped at 20,000 entries; writes go in
batches of 400; it deletes the summary of any uid owning no vice (a deleted account keeps its summary until the next
run). Rules let the owner read `summaries/{uid}` and nobody write it; the Admin SDK bypasses them. `habitSummaryProvider`
(`lib/providers/habit_summary_provider.dart`) follows the provider chain; `storedTypicalsProvider` gives Today's and
Trends' `DayDial` each habit's typical, or none while loading, failed or never written. `dailyOrphanCleanup` (04:30
UTC, `functions/cleanup.js`) finds the Firestore documents of guest Auth users that Firebase's anonymous-account
clean-up deleted after 30 days; it runs dry while `DELETE_ORPHANED_DATA` is false (HANDOVER.md).
