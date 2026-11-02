# Remind users once a day, and let them mark a free day from the reminder

**Priority:** v1 must-have

## What

Wire the dead `/settings/notifications` row to local notifications:

- A daily check-in at a time the user chooses ("How did today go?"), with two actions: "Mark as a free day" and "Log something".
- Optional nudges that tell the user when they are close to a limit ("That's 2 of 3 today").

Reminders are off by default. Ask for notification permission only from onboarding or Settings. Never send guilt copy, and respect [discreet mode](../growth-later/app-lock-and-discreet-mode.md).

## Why

- INFERENCE: a daily check-in is the cheapest retention lever for journaling-style apps.
- It also fixes a data gap: today the app cannot tell "had nothing" from "forgot to log".
- INFERENCE: a zero-quantity activity would record a free day without changing the existing shape.

## Options

- **A.** Local notifications only (for example flutter_local_notifications). No server and no push certificates, and it works for guests.
- **B.** Server push through FCM and Cloud Functions. This needs `functions/` and raises consent questions.
- **C.** No notifications in 1.0, and remove the Settings row.

## Recommendation

Claude's recommendation, not a decision: **A, free.** Retention feeds every paywall moment, so gating reminders would cost more than it earns.

**Effort:** M

**Revenue impact:** Medium to high, through retention. More users reach the 30-day paywall moment.

**Depends on:** [quick logging](one-tap-quick-logging.md); [per-vice goals](per-vice-goals-and-limits.md); [`four-named-routes-dead-end-at-not-found`](../../tech-debt/navigation-and-unreachable-ui/four-named-routes-dead-end-at-not-found.md).

**Needs Jack:** yes — Are reminders free or Pro, and does recording a free day as a zero-quantity activity fit his data-shape rule?
