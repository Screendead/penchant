# Read the calendar on the device to see which events come before use

**Priority:** insights (1.1, Pro)

## What

Built on iOS: `ios/Runner/CalendarChannel.swift` reads timed events' starts and ends after full access is granted
from Insights, and `lib/insights/after_event.dart` judges whether each habit is used in the hour after an event ends
more often than at the same time on nearby days clear of events. Left:

- The macOS runner's channel, so the Mac gets the same comparison: set aside while the Mac computes no Insights
  without Health.
- Events the user tags (for example "1:1s with my manager"). Built since: per-day features (time in meetings,
  events, back-to-back runs, events of 5 or more people, events over 45 minutes) in `lib/insights/calendar_days.dart`.
- "Work → Meeting" suggestions in the trigger picker when an entry follows an event; at most the entry stores the
  trigger path the user accepted.
- Calendar findings without Health: Insights computes nothing until Health has values.

## Why

- SOURCED (C15): Jack named calendar integration for meetings as a cause of use.
- SOURCED ([EventKit](https://developer.apple.com/documentation/eventkit/accessing-the-event-store)): since iOS 17 and
  macOS 14 an app asks for full or write-only access; write-only "doesn't let it read any events", and "your app can't
  request read-only access". An app with only the old `NSCalendarsUsageDescription` key is denied automatically.
  `requestAccess(to:)` is deprecated and no longer prompts
  ([reference](https://developer.apple.com/documentation/eventkit/ekeventstore/requestaccess(to:completion:))).
- SOURCED ([predicateForEvents](https://developer.apple.com/documentation/eventkit/ekeventstore/predicateforevents(withstart:end:calendars:))):
  a query spans at most four years; INFERENCE: history further back is reachable in four-year chunks, so calendar
  correlation also works on day one against the journal's past.
- SOURCED (pub.dev): [`device_calendar`](https://pub.dev/packages/device_calendar) was last published two years ago;
  [`device_calendar_plus`](https://pub.dev/packages/device_calendar_plus) is current but has no macOS support. No
  plugin found covers macOS.
- INFERENCE: the Review Guidelines have no calendar-specific clause beyond 5.1.1 and 5.1.2 (consent, purpose,
  minimisation); keeping everything on the device keeps the disclosure to one line.

## Options

- **A.** A thin Swift EventKit channel shared by the iOS and macOS runners.
- **B.** `device_calendar_plus` on iOS, and the Mac without calendar features.
- **C.** Let users mark events by hand, with no calendar read.

## Recommendation

Claude's recommendation: **A.** EventKit's read surface needed here is small (calendars, events in a range, a change
notification), and one channel serves both platforms, which C6's "fully supported" Mac needs. Ask for full access from
the insights screen with a plain explanation: what is read, that it never leaves the device, and that the app never
writes to the calendar.

**Effort:** M

**Revenue impact:** Medium to high: a distinctive Pro insight for the knowledge-worker audience (INFERENCE: of the
competitors, only Exist and Gyroscope list a calendar integration, both cloud-processed).

**Depends on:** [insights engine](insights-engine.md); [macOS target](../v1-must-haves/macos-target.md).

**Needs Jack:** no
