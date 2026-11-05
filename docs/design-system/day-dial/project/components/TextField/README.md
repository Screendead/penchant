# TextField

A pill text field with a leading icon, plus the sign-up password checklist and the inline error pill.

**Provide:** the value, a placeholder, the leading icon, and for passwords the show/hide toggle and the rules met.

- `size-pillHeight` tall, `radius-input`, `surface` with a 1px `outline` border (3:1 or better against the field and the ground), 18px left padding. A 19px `muted` icon leads.
- Value in Text 500 15.5px `text`, placeholder in Text 400 `muted`.
- Password fields end in a 38pt eye button.
- Focus: the border turns `accent` and `shadow-focus` adds a 3px halo.
- Checklist (sign-up): a `surface` card (radius 22, 1px `line`) of two columns: "8+ characters", "An upper-case letter", "A lower-case letter", "A number", "Passwords match". Each rule has an 18px circle, a 1.5px `outline` ring while unmet, that fills `clearInk` with a `surface` tick, springing in, and its label turns `muted` to `text` when met.
- Error: a `dangerContainer` pill with an 18px `danger` alert icon and `text` copy, "That email and password don't match an account." It drops in on a spring.

**Do not** show the error in red text alone or under the field. Do not draw a field's border in `line`: it is 1.2:1 and identifies nothing.
