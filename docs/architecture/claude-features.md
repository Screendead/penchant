# Claude features: note reader, follow-up, older notes, tag tidy, weekly words, letter, say it, working screen

**Note reader** (`lib/notes/`, off by default; Settings' "Suggest tags from notes", per device, `NoteReaderSetting`,
which says first what is sent). `noteReaderProvider` is null unless that switch is on, a user is signed in and the
build is not an emulator build. It calls the callable function `readNote` (cloud_functions) with the note's text
alone (journal text leaves the device unsealed only here and in the Letter, below), and emits each `ReadTag` (`path`, `quote`) whose path
is in the tree and whose quote is in the note. `functions/note_reader.js` asks Claude Haiku 5.5 (thinking off, effort
low, structured output over the leaf paths of `functions/note_tags.js`, a copy of the Dart tree that a test compares)
for at most 4 tags of a note of at most 2000 UTF-16 units, drops any it cannot verify, and logs counts and reason
codes only: never the uid, note, quotes or output. It signs in to Anthropic by workload identity federation, no API
key: it runs as `note-reader@screendead-vice-tracker.iam.gserviceaccount.com`, whose Google identity token the SDK
exchanges; the rule, organization, service account and workspace ids are repository variables that `functions.yml`
writes to `functions/.env.screendead-vice-tracker` at deploy (unset, it answers `failed-precondition`). Abuse is
bounded by `maxInstances: 2`, 60 reads a day per uid per instance in memory, and the workspace's spend and rate
limits in the Claude Console. `functions/tools/note-reader-trial.js` runs 12 made-up notes through the same prompt
with an API key from the environment. Only an account with a verified email may use Claude (Jack, 2026-11-15:
"Yes, refuse guests"), here and in the four features below: `claudeAllowedProvider`
(`lib/account/claude_access.dart`: the profile's `emailVerified` by `select`, and `Account.isGuest`) makes every
Claude provider null otherwise, and each Settings row is then off with "Add and verify an email address first.",
opening Account Settings. Each callable refuses a guest or an unverified email with `permission-denied`
(`verifiedCaller`, `functions/caller.js`) before its cap and any model call; since a token minted before verification
still says unverified, `callClaude` refreshes the ID token once on that answer and calls again.

**Follow-up question** (`lib/notes/follow_up*.dart`, off by default; Settings' "Ask one question about a note",
`FollowUpSetting`, under the note reader's switch and without effect while it is off). With it on, the note reader's
call sends `question: true` beside the same note, nothing more, and `readNote` returns `question: {question, quote}`
or null; `checkQuestion` (`functions/note_reader.js`) drops any question over 140 UTF-16 units, with a line break, not
ending in its one `?`, with a digit or a `DENIED_TERMS` word, or whose quote (at most 120) is not in the note, and the
device checks again (`questionIn`). One call answers tags and question, so it counts once against the cap. The panels
(`NotePanels`) add a panel after the tags, "One more, if you like", once a question has come; Skip clears the answer and saves
nothing. An answer (at most 500) is stored with its question and quote as the sealed content fields
`followUpQuestion`, `followUpQuote`, `followUpAnswer` of the entry or day note, only when typed; the entry editor and
the day note sheet show it (`SavedFollowUp`). The function logs whether a question came and its drop code before any
colon (`term:x` logs `term`). `functions/tools/follow-up-review.js` runs 40 made-up notes with an API key.

**Tag older notes** (`lib/notes/older_notes*.dart`; round 24). Settings' "Tag older notes" row, usable while the note
reader's switch is on, opens `OlderNotesPage` (`/settings/older-notes`). It reads the journal once (Insights' range
read) and offers unlocked entries with a note, newest first, leaving out (and counting) locked entries and entries
already holding 10 tags. "Read the next 20 notes" sends each note alone through `olderNoteReaderProvider` (the same
`readNote` call, no follow-up question) one at a time, at most `olderNotesDailyCap` (40) a local day on the device, under
the function's 60, so new notes can still be read. `OlderNotesRunner` (`olderNotesProvider`) runs the batch outside the
page; Stop drops the note in flight, which stays unread. Progress is the sealed kept file `older-notes`
(`keptSealedFilesProvider`): ids read or decided, tags awaiting review with their quotes, and the day's count. Each
read note is reviewed with its quotes marked and a row per tag (`shownTags`: quoted in the note as it is now, not
already on it, no more than the entry has room for); Keep ticked or Drop all per note, or every ticked tag shown after
a confirmation with the count. Saving goes through `setTriggers` (`cachedContent` or the read content,
`withAnswers`, `updateActivity`, `settle`), so the whole envelope is resealed; a save that fails at once keeps its
note for review. More notes are read only once the review list is empty.

**Tidy my tags** (`lib/notes/tag_tidy*.dart`; round 24). `TagTidyPage` (`/settings/tidy-tags`, a Settings row for a
verified account, no switch: the page shows every label before sending and sends only on the tap) gathers own-words
triggers (`ownWords`: anything not a tree path) from unlocked entries and day notes, read once (the range read and
`allDayNotesProvider`), and sends the labels alone, most used first, at most 200, each 1 to 60 units with no line break
(`sendableLabel`), to the callable `tidyTags` (`functions/tag_tidy.js`: Claude Haiku 5.5, thinking off, effort low,
structured output; 10 a day per uid per instance; 25 s request, 30 s handler, 35 s on the device; logs the reason and
counts only). It answers merges (labels into one of them) and mappings (labels onto a leaf of the tree), each label
in one suggestion at most; `CallableTagTidier.suggestionsIn` checks them again. The person accepts each; Apply says
how many entries and day notes change and that it cannot be undone in one step, then rewrites their triggers
(`tidied`: order kept, each once) through `setTriggers` and `setDayNote`, moves the picker's own-words counts
(`FreeTextTriggers.rename`), and reads the journal again. New entries typed with an old label are not mapped.
`functions/tools/tag-tidy-trial.js` runs made-up label lists with an API key.

**Weekly review in words** (`lib/insights/weekly_words.dart`, off by default; Settings' "Last week in words",
`WeeklyWordsSetting`). `WeeklyFigures.of` sends the callable `writeWeekly` the week's computed figures alone: each
habit under a placeholder ("Habit A") with its unit words, totals and counts as numerals, busiest hours, tag paths
and counts, own-words counts and Insights finding lines; never a habit name, note or entry. `functions/weekly_words.js`
(`validFigures`, then Claude Sonnet 5.5) asks for 3 to 5 sentences stating only the figures; `checkParagraph` refuses
a reply with a numeral not sent, an unknown placeholder or a number word, and the device runs the same check
(`checkParagraph` in Dart) before `restoreNames` puts the names back in by placeholder, on the device. The paragraph shows on
`WeeklyReviewPage` above the lists; each week's answer is kept in memory for the provider's life, so reopening never
calls again; nothing is stored. Cap 10 a day per uid per instance; logs the reason code only.
`functions/tools/weekly-words-trial.js` runs made-up weeks with an API key.

**Letter** (`lib/letter/`, off by default; Settings' "Letter", `LetterSetting`; `LetterPage`, route `/letter`, in the
Penchant menu while the switch is on; Jack, 2026-11-16, "Yes, build both", knowing Anthropic keeps what is sent for up
to 30 days). On request only: the person picks the last 1, 3 or 6 months, `LetterJournal` reads the period once (the
day query's activity shape; day notes by the owner's ids between the first and last day, ordered by id), and
`buildLetterPayload` (`letter_payload.dart`) builds the one request the preview shows and Send sends: each entry's local
date and time, amount and unit words, habit name, tag labels, urge in words, note and follow-up question and answer;
each day note's date, text, tags and follow-up; and figures worked out here as ASCII strings (per habit and per month
total, entries and days with use; note counts; the 10 commonest tags). Never Health, places, calendar, findings, the
uid, document ids or anything outside the period; locked entries and notes, and entries of a locked or gone habit, are
left out and counted. Over 190,000 characters the period starts later until it fits, and the preview says so. The
callable `writeLetter` (`functions/letter.js`: `validInput` rebuilds the known keys and refuses over 200,000, then one
streamed Claude Opus 5.5 call, effort medium, thinking adaptive, structured output `{sections, toTest, quotes}`, no
fallbacks) checks each section and suggestion (`checkPassage`): every double-quoted span is in a sent note, day note or
answer (or a sent label); outside quotes and sent names, units and tag labels, every numeral is one of the figures',
the period's or a label's, no count in words (`NUMBER_WORDS`) and no `LETTER_DENIED_TERMS` (the follow-up's list less
its counting words and four a description needs, plus the letter's own). A failing passage is withheld and counted
("One passage was left out"); under 3 sections in the reply or under 2 surviving, nothing is shown. The device runs the
same checks (`letter_checks.dart`; both test suites run `functions/letter_fixture.json`). `letterRunProvider` holds the
call outside the page, so a letter finished after leaving it is saved while the app stays open. Letters are the sealed
kept file `letters` (`keptSealedFilesProvider`, like the experiment plan): period, date written, counts of what was
sent, sections, suggestions and the withheld count; never the payload; not synced; deletable. "Worth testing" links to
Insights; starting an experiment from it is not built. Cap 3 a day per uid per instance; logs the reason code and the
withheld reasons up to any colon. `functions/tools/letter-review.js` writes letters for 5 made-up journals with an API
key, printing each letter, what was withheld and why, and the seconds taken.

**Say it to log and Catch up** (`lib/say_it/`, each off by default; Settings' "Say it to log" and "Catch up in words",
`EntryReadingSetting`, per device, whose disclosure says what is sent; round 24). One page, `EntryWordsPage` (routes
`/say-it`, opened from the Log fan's hub, which becomes a "Say it" button only while that switch is on, and
`/catch-up`, in the Penchant menu), in two modes: `now` (a sentence about now; yesterday and today allowed) and `days`
(1 to 7 picked days of the last 14). The person types, or on iOS taps the microphone: `ios/Runner/SpeechChannel.swift`
(`lib/say_it/speech.dart`) runs `SFSpeechRecognizer` with `requiresOnDeviceRecognition`, so the recording never leaves
the device; where the locale has no on-device model the microphone is not offered (macOS has no channel). The words fill
the field and nothing is sent until Read it. `entryRequest` is the only payload: mode, text (500 or 2000), local now,
the allowed dates with weekdays, and each unarchived, opened habit as a per-request number (`entryHabits`, never a
document id) with name and unit words. The callable `readEntries` (`functions/entry_reader.js`: `validInput`, then
Claude Haiku 5.5, thinking off, effort low, structured output whose habit and date are enums of what was sent; SDK 12 s
or 40 s inside a 50 s function and the app's 55 s) proposes `{habit, amount, date, time, note, tags}`; `checkEntries`
there and in Dart drops any entry whose habit was not sent, whose amount is not above 0 and at most 1000, whose date was
not sent, whose time is malformed or after now, whose note is not one line of the text copied exactly, or past 10 (now)
or 40 (days) entries, and drops tags not a tree leaf quoted from the text (both suites run
`functions/entry_reader_fixture.json`). Caps 60 (now) and 10 (days) a day per uid per instance; logs mode, reason and
counts only. The drafts show on the same page inside `ClaudeWorkingResult`, by day; each can change habit, amount (a
red "far above your usual" past 3× the stored typical), time (never past now) or be removed; "dropped" is said. Save
writes each through `TrackerWrites.recordActivity` with its own id and `loggedVia` `spoken` or `caughtUp` (an older
build reads an unknown name as absent, and its edit drops it); one Undo bar undoes them all. Stop drops the answer
unseen. The prompt asks for one entry per amount said, a range or rough amount at its lower number (the person can
raise it), and none for words with no number or for a container not in the habit's unit with no size given; the
review card says such words are not suggested. `functions/tools/entry-reader-trial.js` runs 21 made-up cases with an
API key, printing each one's expected reading. In Insights a `caughtUp` entry (`HabitUse.caughtUp`, false when locked)
counts on its calendar day in day totals, never moved to the evening before, and `timedUses` drops every use of that
habit on that day from the comparisons of time of day (last and first use, hours after, the hour before, one habit
after another, after an event, at a place); "What it costs" and "What sets it off" say how many were left out.
`spoken` entries keep their times.

**Claude-working screen** (`lib/claude/`). Every Claude call in flight is shown through one component. The call site
makes a `ClaudeWork` (status, optional detail, the person's own words sent as `subject`, `steps` for the analyst,
`showElapsed` for long calls), keeps it current with `say` and ends it with `finish(answered|failed|stopped)`. It calls
`showClaudeWorking(context, work, resultTag:, onStop:)` without awaiting it, from the tapped widget's context: after
`ClaudeWorking.delay` (600 ms) still running, a `ClaudeWorkingRoute` grows out of that widget's rect; once shown it
stays `minShown` (1.4 s); answered, it draws together into a plate whose `Hero` flies into the result wrapped in
`ClaudeWorkingResult` with the same tag (unique per page, e.g. `('ask', id)`), else it shrinks back to the widget. Back
hides it with the call still running; Stop calls `onStop`, which must really drop the result (`AskSession.drop`, the
investigation's stopped ids, `LetterRunner.abandon`). Status text names only what is known ("Sent your question",
"Ran 3 queries on this phone"); no progress figures. `ClaudeWorkingCard` is the same look in place, for a pending
answer on the page and for weekly review in words (it starts on open, so nothing goes fullscreen); the note reader
keeps its in-place read (an ink underline sweeping the note, chips arcing out of their quotes). Three looks share
everything else (`ClaudeWorkingLook`, `claudeWorkingLookProvider`, `lib/claude/claude_working_painters.dart`): `dial`
(the last 28 days as rings of a 24-hour face, a hand ringing each entry as it passes), `ink` (lines tracing out from
the person's words across their entries) and `lens` (a loupe over a 28-day field of hours), the default (Jack, 2026-11-16: "lens is coolest, use that"). They draw the device's own
entries (`claudeWorkingMarksProvider`, a bounded 28-day range query; nothing of it is sent). Painters repaint from a
`WorkingClock` ticker inside a `RepaintBoundary`, with no widget rebuilds per frame; under reduce motion the clock
stands still, the route fades in 150 ms and nothing schedules frames, so tests can `pumpAndSettle`. With motion on, a
pending card loops: pump fixed durations. The gallery (`ClaudeWorkingGallery`, route `/claude-working`, a Settings row)
exists only in emulator builds and plays each look over fake calls; `integration_test/claude_working_gallery_test.dart`
(through `tools/e2e-screenshots.sh`, not in `all_test.dart`) takes its stills.
