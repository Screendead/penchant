# SegmentedControl

A two-to-four way switch: an ink thumb on a ground, or a quiet surface thumb inside a sheet.

**Provide:** the options, the selected one, and the change action.

- On a ground (Settings, appearance): a `surface` track with a 1px `line`, `shadow-card` and 4px padding. The selected segment is an `accent` thumb with an `onAccent` label, Text 600 13px.
- Inside a sheet (Trends range and step): a `surface2` track with 3px padding. The selected segment is a `surface` thumb with a 1px `outline` border (3:1 against the track, measured as painted over the thumb) and `shadow-tiny`, and its label turns from `muted` to `text`, Text 600 12.5px.
- Full width (sign in or create account): the inside-a-sheet style, with segments flexed equally, 12pt vertical padding and Text 600 14px.
- The thumb slides to the new segment on the standard spring.

**Do not** use it for more than four options or for actions. It only selects.
