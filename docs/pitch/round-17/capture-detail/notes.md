# What extra detail a log can carry, and where it is asked

Already decided: new details are optional fields on an entry, and existing entries are left untouched. Not decided:
which details, and which screen asks for them.

## What exists today (read from the code)

- **One-tap log** (a tally's `+`: one tap; or the Log button then a wedge: two taps) logs 1 unit now. The Undo bar reads "Logged 1 glass of
  Wine at 21:40" and offers "What was going on?" for 8 seconds. That opens the trigger picker for the entry: usual
  chips for the habit, then seven areas (Social, Feeling, Work, Body, Routine, Place, Craving), your own words, up to
  10 per entry, Undo log and Done. The home-screen widget's entry prompt opens the same picker.
- **Amount sheet** (tap the Log button to fan out the habits, then hold a wedge): habit, amount stepper, time dial, a "What was going on?
  (optional)" chip, and a "Log 1 glass at 21:40" button. The entry editor is the same sheet over a stored entry.
- **An entry stores** habit, quantity (plus an exact decimal amount when needed), time and triggers. Triggers live
  inside the entry's encrypted envelope; the rest is plaintext.
- **What Insights reads:** each entry's habit, time and amount, beside Health, calendar, reminders and cycle data.
  Triggers are used only for counts in the weekly review. Health's State of Mind (iOS 18 and later) is already read
  as a mood measure: one value per day, the average of the moods Jack logs in Health, and only on days he logs one. So every field below is something Insights *could* use after new analysis work; none would
  change a finding on its own.
- **The trigger tree already covers "with whom" and "where":** Social has With friends, Family, Date, On my own; Place
  has Home, Bar or restaurant, Commute, Travelling, Outdoors. Feeling has Stressed, Bored, Low, Anxious, Happy and
  others.

How often Jack uses one-tap versus the sheet cannot be known without reading his live data, which is off limits. That
split decides how many entries a sheet-only field would ever reach.

## Option A: leave as is

- **What changes:** nothing.
- **What Jack sees:** today's screens (optionA.html).
- **Effort:** none.
- **Risks:** an entry logged while travelling sits on the wrong hour on Insights' timing charts, because the zone is
  not stored. Evening back-fills look identical to live logs. Neither problem gets worse over time, but the history
  that would fix them is not being collected.
- **Day to day:** one tap per log, plus an optional picker. No permission prompts.

## Option B: silent details only, with nothing asked

- **What changes:** each new entry also stores three things the app already knows:
  - the time zone it was logged in (the app already reads the zone's name for the daily reminder);
  - when it was written, which tells a live log from one filled in later;
  - how it was logged: one tap, the amount sheet, or the home-screen widget.

  Where each lives (inferred design): the zone and how it was logged go inside the entry's encrypted envelope; the
  write time is stamped by the server when the entry arrives, so it has to be plaintext and needs a rules change.

  Nothing on screen changes.
- **What Jack sees:** nothing new (optionB.html; the dashed box is only a caption on the mock-up).
- **What Insights gains:** hour-of-day and day boundaries can be put right for entries logged abroad. Back-filled times
  can be given less weight in timing analyses. Both need engine work later; the data starts building up now.
- **Effort:** S, about 1 day: three optional fields, rules changes with tests, parser defaults, and the export.
- **Risks:**
  - The zone hints at where Jack was, so it belongs in the envelope; Insights runs on the device, so sealing it costs
    nothing (inferred).
  - "When written" is a new plaintext field the rules must accept on create and refuse on change. It reveals only
    whether an entry was back-filled.
  - Older builds ignore the new fields, so nothing breaks (sourced: the parsers skip unknown keys).
- **Day to day:** no extra taps. No permission prompts.

## Option C: urge and note on the existing screens, plus option B (recommended)

- **What changes:** two optional rows appear in the amount sheet, the entry editor and the "What was going on?" picker:
  - "How strong was the urge?" as a 1 to 5 row, from Barely to Couldn't not;
  - a one-line note of up to 500 characters.

  No new step anywhere: one-tap stays one tap, and the Undo bar is unchanged. Both values go inside the entry's
  encrypted envelope next to the triggers.
- **What Jack sees:** optionC.html. The sheet grows by about two rows. The picker grows by the same two rows below the
  trigger areas.
- **Why these two and not the others:**
  - Urge is the only candidate that is both new and could be measured. Neither Health nor the trigger tree records
    how strong the pull was. Insights could later ask "is a stronger urge followed by a larger amount?" or "does a
    short night raise tomorrow's urge?" (inferred: no such analysis exists yet).
  - The note is for Jack's own record. Insights cannot use free text.
  - Mood is left out because Health's State of Mind already gives Insights a daily mood when Jack logs one, and the
    Feeling triggers (Stressed, Low, Anxious, Happy...) already record mood per entry. With whom and where are left
    out because the trigger tree already asks them. Cost waits on the separate cost-per-unit idea; duration fits only
    session-like habits, which these are not (inferred).
- **Effort:** M, about 2 to 3 days on top of option B's day:
  - the two rows in three places;
  - the fields inside the envelope;
  - showing them in the history rows and the export;
  - tests.

  Inferred: the rules cannot read sealed content, so inside the envelope only the app's validators guard them. But
  the write layer sends an edit in plaintext while the journal key has not loaded (sourced), so the rules still need
  the two fields added to their content-field lists, and the editor must refuse those edits until the key loads.
  This is a small rules change with tests.
- **Risks:**
  - **An older build drops them.** Changing an entry's triggers rebuilds the envelope from the triggers alone (sourced:
    the write layer). An older build on Jack's other device that edits an entry's triggers would therefore wipe its
    urge and note. Jack's iPhone and Mac are both updated after every merge, so an old build rarely survives (small
  risk).
  - **The envelope's size limit.** Its largest padding size is 4096 bytes. A 500-character note plus 10 full-length
    triggers comes to about 3,500 bytes in the worst ordinary case (inferred by calculation), so it fits. The
    validator must cap the encoded size so that unusual characters cannot overflow it.
  - **Fewer entries get the details.** On one-tap entries, urge and note appear only if Jack opens the picker from the
    Undo bar, the same reach triggers have today. From the amount sheet, the rows sit in the sheet itself and its
    picker shows triggers only, so nothing is asked twice.
- **Day to day:** still one tap per log (two from the Log button; three or more through the amount sheet, as today).
  Optionally, one more tap to open the picker, then a tap for the urge and
  typing for a note. No permission prompts.

## Option D: a full detail sheet after each one-tap log, plus option B

- **What changes:** the Undo bar's "What was going on?" becomes "Add details". That opens one sheet holding:
  - the triggers;
  - urge and mood before, each 1 to 5;
  - with whom (Alone, Partner, Friends, Colleagues);
  - where (Home, Work, Out, Travelling);
  - how long, in minutes;
  - cost;
  - a note.

  The amount sheet and the editor carry the same rows.
- **What Jack sees:** optionD.html, a sheet roughly twice the picker's height.
- **Effort:** L, about 5 to 7 days:
  - seven fields, five of them new kinds of input;
  - rules changes for any that stay in plaintext;
  - layout in three places;
  - the export, history and tests.
- **Risks:**
  - "With" and "Where" ask what the trigger tree already asks, so the same fact gets two records that can disagree
    (On my own as a trigger, but Friends in the With row).
  - Mood repeats Health's State of Mind.
  - Cost has no meaning until habits have a price per unit.
  - A long optional sheet tends to be skipped or filled carelessly, which would mislead Insights (inferred: general
    experience with logging apps, not measured here).
- **Day to day:** one tap per log still saves the entry. Filling in details costs a tap to open, about 5 to 8 taps
  for the rows, and typing for a note. No permission prompts.

## Recommendation: C (which includes B)

- **It costs Jack nothing per log.** No new step, and one-tap stays one tap. The only addition is two optional rows
  where he already chooses to add detail.
- **It collects what is new and could be measured.** Time zone and live-or-later fix known faults in Insights'
  timing. Urge is the one candidate that neither Health nor the trigger tree already supplies.
- **It skips the duplicates:** mood (Health already has it), with whom and where (the triggers already have them),
  and cost and duration (they wait on other work).
- **It is cheap to undo.** Every field is optional, and all but the write time are sealed. If the urge row goes unused after a month, it can be
  dropped without touching any stored entry.

If Jack wants no new rows at all, B on its own is the floor worth taking. The data it collects cannot be gathered
retroactively.
