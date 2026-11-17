# Ask your journal, the Analyst and Ask from Siri

**Ask your journal** (`lib/ask/`, off by default; Settings' "Ask your journal", `AskJournalSetting`, whose disclosure
says what is sent; `AskPage`, route `/ask`, in the Penchant menu while the switch is on; guests and unverified emails
refused as for the note reader, `claude-features.md`; emulator builds have no service). The model writes read-only SQL; the device runs it over a private
copy of the journal; no row or result leaves the device (Jack: "just has to be maximally secure").
`CallableAskJournal.request` is the only payload, and has no parameter for anything else: `question` (1 to 300),
`today`, `weekday`, `habits` (`id`, `name`, `unit`, `unit_one`, `archived`; `askHabits`' order, ids from
`numberedHabits`, the same the tables use) and `history`, this session's last 5 answered questions with the server's
own answer for each (its SQL, never what it found). `functions/ask_journal.js` (`validInput`, then Claude Sonnet 5.5
by default or Haiku 5.5, each at its fastest accepted thinking and effort, structured output over
`functions/ask_query_schema.json`, prior turns as earlier user and assistant messages; 40 s request, 60 s handler,
65 s on the device) answers `{kind: answer | needs_insights | cannot_answer, reason, cards}`, 1 to 3 cards of
`{title, explain, sql, chart: {type, x, y, series, x_kind}}`; `validAnswer` there and `parseAskAnswer`
(`lib/ask/ask_answer.dart`, the same limits, a test compares) check it whole before anything runs. The database
(`lib/ask/journal_db.dart`) is SQLite at `:memory:` with temp storage in memory, built when the page has its one read
of the journal (Insights' all-activities range read, `allDayNotesProvider`'s one read of the day notes on `ownerID`
alone, the vice list) and closed on leaving the page or a user change: `habits`, `entries` (local text `at`, `day`,
`hour`, `weekday`, `week`, `month`, `year`; `amount` is `measure`; a locked entry's sealed columns null), `entry_tags`,
`day_notes`, `day_note_tags` and `days` (every day from the first entry to today), indexed. SQLite is the system
library (`/usr/lib/libsqlite3.dylib`; Linux CI's `libsqlite3.so.0`) bound by `dart:ffi` in `lib/ask/sqlite_ffi.dart`,
no package or build hook: the `sqlite3` package's own binaries omit the authorizer and progress handler. `run` keeps
model SQL in layers, each tested in `test/journal_db_test.dart`: at most 4000 units, starting SELECT or WITH; one
statement (`sqlite3_prepare_v3` must leave only white space) that SQLite reports read-only and not EXPLAIN, with
virtual tables refused at prepare (`SQLITE_PREPARE_NO_VTAB`: no `pragma_*`, `json_each`, `dbstat`); an authorizer
allowing only SELECT, recursive CTEs, reads of the listed columns in `main` (a table or CTE read with no column, as
`count(*)` does, may be anything but `sqlite_*`) and the functions in `askFunctions`; limits (no attached database,
1 MB values, short SQL, expression depth 100, 20 compound parts, short LIKE patterns, no bound variables), defensive
mode, no trusted schema, triggers or views, extension loading off, `query_only`; and a progress handler stopping a
statement past 250 ms, with 500 rows kept and 256 KB of results at most. It runs on the UI isolate: ordinary queries
take milliseconds, the worst a 250 ms stop per card. A refused or failed card shows "Penchant couldn't run that"
beside the others; every card shows its title and sentence as plain text, "Show query" and "Counted on this device".
`AskChart` (`lib/ask/ask_chart.dart`) treats the chart spec as untrusted: `planAskChart` checks columns, types and
`x_kind` against the result and falls back to a table; number, bar, multi-series line, table; months "Dec 2025" at
the ends and each year change, hours 00 to 23, weekday names; a tap, drag, arrow key or screen reader's adjust moves
a read-out; on a day, week or month "Open … in Today" hands the day to Today through `pendingShowDayProvider`, and a
habit-named series takes its colour. Nothing about question, SQL or answer is logged or reported, on either side.
`functions/tools/ask-journal-trial.js` builds the same tables with `node:sqlite` over made-up data, sends 40
questions (Jack's five among them, follow-ups, why-questions, nonsense, injections) to the chosen model with an API
key, runs each card's SQL and prints times, rows, charts and pass or fail.

**Analyst** (`lib/analyst/`, off by default; Settings' "Investigate", `AnalystSetting`, under Ask's switch and
without effect while it is off; round 23, Jack, 2026-11-16). On the Ask page, an "Investigate with Claude" button on a
`needs_insights` or `cannot_answer` answer, and "Investigate this question" under the field, start one investigation
only after `confirmInvestigation` says, each time, what goes (`analystSends`) and the person says yes. The page builds
a second database for it, `JournalDb.build(figuresOnly: true)`, closed when it ends: note and day-note text are never
written into it and its own authorizer allow-list (`figuresTables`: Ask's less `entries.note` and `day_notes.text`)
refuses them, and own-words tags are stored as "own words 1", "own words 2"..., numbered by first use (entries, then
day notes); follow-up answers are in neither database. `runInvestigation` (`investigation.dart`) calls `investigate`
up to 6 times; each call sends Ask's request (question, today, weekday, habit numbers, names, unit words, archived)
and `rounds`, each step's cards and per card its result cut by `cutResult` (cells as text: integers, reals to 2
places trimmed; at most 20 columns, 50 rows and 8000 characters of JSON) or its `AskRefusal` code alone. The callable
(`functions/analyst.js`: `validInput` bounds every key, 5 earlier rounds, 8192 per result and 150,000 in all, then
one streamed Claude Opus 5.5 call, effort medium, thinking adaptive, no fallbacks, structured output `{kind, queries,
finding}` with Ask's card schema; a card outside Ask's bounds is dropped, and the step fails as `cards` only when none
remains) answers 1 to 3 more cards or a finding `{headline, body, rests_on}`; the last step
must conclude (`no_finding`). The server is stateless and trusts nothing in the transcript; caps 5 investigations (on
an empty transcript) and 40 steps a day per uid per instance; 120 s, 512 MiB, its client 100 s, inside the app's 130
s; logs the reason, any check's reason before its colon, the step number and query count. A finding is shown only if
both sides' `checkFinding` pass: every statement it rests on ran; its headline, body and every card's title and
explanation pass the letter's `checkPassage` with no notes to quote (numerals only those of cells sent, plus a clock time H:00 for
an hour a cell holds whole, 0 to 23, and a count word two to twelve for a whole-number cell, an untruncated result's row count or a
column's number of distinct values; habit names, units and tag-label cells as phrases, never other text cells, which a
query's literal could fill; a quote only of a whole text cell, case and all, whose words are then checked as unquoted) and no `analystCausalTerms`; else "Claude's account didn't pass Penchant's checks"
and nothing of it shows (both suites run `functions/analyst_fixture.json`). Shown, it is labelled a reading of figures
counted here, not a finding, hands causes to Insights, and lists its queries as Ask's cards from this device's own
runs. Investigations live in memory (`investigationSessionProvider`), cleared on New question and user change; one
whose page closed mid-run stops before its next call and shows as stopped.
`functions/tools/analyst-trial.js` runs five made-up investigations over the Ask trial's journal with an API key.

**Ask from Siri** (iPhone, iOS 17+; round 24, first half). `AskJournalIntent` (`ios/Runner/AppShortcuts.swift`, app
target only, `#if os(iOS)` since the Mac Runner compiles that file) is an App Shortcut ("Ask Penchant", "Ask my journal
in Penchant", "Ask Penchant a question"): a phrase may carry only an entity or enum parameter and must name the app, so
Siri asks for the `question` (String, `requestValueDialog`) after the phrase. It opens the app (`openAppWhenRun` in a
deprecated extension before iOS 26, `supportedModes` `.foreground(.immediate)` from 26), refuses an empty question or
one over 300 UTF-16 units, and hands it to `AskQuestion`, which holds it in memory only until Dart's `take` on
`com.screendead.penchant/ask_question` (as `EntryPrompt`: a cold launch's question waits for the engine; `changed`
when warm). `askQuestionListenerProvider` (`lib/ask/ask_from_siri.dart`, kept by `MyApp`, iOS only) puts it in
`pendingSiriQuestionProvider`, dropped on sign-out and a change of account (not on the session's first restore), and
refused while known signed out. `siriQuestionReadyProvider` waits for a user, the app lock uncovered, the journal key
and the habits, then says where it goes: Ask while `askJournalProvider` is set; else an emulator build says it has no
service; else, once the profile is read, a guest or unverified email goes to Account Settings; else, once the saved
switch is read, Settings. Today (`openSiriQuestion`) brings an open Ask page to the top or pushes one; anything else
drops the question, opens the place and says nothing was sent. `AskPage` itself takes it after a frame, fills the field
and runs `_ask` as typed (same session, Claude-working screen and checks), waiting while one it sent is unanswered so
the follow-up carries it. The question is never logged or reported. Siri speaking the answer without opening the app
is not built.
