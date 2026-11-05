# Button

The app's buttons: one ink primary per screen, tonal and danger pills, 40pt circles, and underlined text links.

**Provide:** a label (or an icon and an accessible label for a circle), the action, and its disabled or busy state.

- Primary: `size-pillHeight` tall, full width, `accent` fill, `onAccent` label in Text 600 16px. Numbers in a label are Mono ("Log 2 drinks at 18:30").
  - Disabled: `surface2` with a `muted` label.
  - Busy: a 22px spinner in `onAccent`, with the label removed.
- Tonal: 46pt, `surface2`, Text 600 15px, optional 18px leading icon. Danger tonal is `danger` on `dangerContainer`.
- Circle: `size-circleButton`, `surface` with a 1px `line` and `shadow-card`, 20px icon in `text`. Inside a sheet's header the close circle is 36pt `surface2` with no border or shadow. Disabled is 35%.
- Link: `text`, Text 600 14px, underlined 3px below in `muted` ("Forgot password?").
- Secondary pill: 44pt, `surface` with a 1px `outline` border, Text 600 14px ("Show older").
- Pressed: scale 0.98 (wide) or 0.92 (circle). Focus: a 2px solid `accent` outline at 2px offset.

**Do not** colour a button with a habit, put two primaries on one screen, or use a filled danger button. Danger is always tonal.
