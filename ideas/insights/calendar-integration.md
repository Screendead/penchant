# Read the calendar on the device to see which events come before use

**Priority:** insights (1.1, Pro)

## What

With full calendar access, the [insights engine](insights-engine.md) reads past and upcoming events and derives
features per entry and per day: minutes in meetings that day, the number of events, whether an event ended within the
hour or two before an entry, back-to-back blocks, events with many attendees, and events the user tags (for example
"1:1s with my manager"). It answers "you log coffee within an hour after 64% of meetings longer than 45 minutes" and
feeds "Work → Meeting" suggestions to the [trigger picker](trigger-tagging.md) when an entry follows an event.

Event titles, attendees and notes are read on the device and never stored outside it. At most, the entry stores the
trigger path the user accepted.

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

**Depends on:** [insights engine](insights-engine.md); [trigger tagging](trigger-tagging.md); [macOS target](../v1-must-haves/macos-target.md).

**Needs Jack:** no
