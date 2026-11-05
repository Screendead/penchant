# DayPicker

The day navigation over the dial (previous, the date pill, next) and the calendar sheet the pill opens.

**Provide:** the shown day, today, and for the calendar the set of habits logged on each day of the month.

- The row is 44pt tall in the gutter: a `size-circleButton` back circle, the date pill, a forward circle.
- Forward is disabled (35%) on today. There are no future days.
- The pill shows the day word in `displayM` ("Today", "Yesterday", a weekday) and the date in Text 500 14px `muted` ("Thu 5 Nov" for today and yesterday, "3 Nov" otherwise), then a `muted` chevron.
- The calendar is a bottom sheet titled with the month in Display 700 20px, with circle buttons for the months either side (the next month is disabled past today).
- Weeks start on Monday. Day numbers are `monoM`. Today has a 1.5px `accent` ring, the selected day an `accent` fill with `onAccent` number, and future days sit at 30%.
- Under each day number, draw a 4px dot in `dataN` for each habit logged that day.
- The footnote reads "A dot for each habit logged that day. Tap a day to open its dial."

**Do not** add a week strip or a date-range picker here. Ranges belong to Trends.
