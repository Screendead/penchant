# Fidelity renders

Today, rendered by the app and by the Day Dial mock-up in the same states, side by side.

1. The mock-up: from a checkout of `master`, for each state and theme,
   `node tools/fidelity/mockshot.mjs <checkout>/docs/pitch/mockups/ui-overhaul/day-dial/index.html <root>/mock/mock-<state>-<theme>.png "<query>" 3500 [js]`.
   The busy day is `only=1&theme=<theme>`, the menu adds `&state=menu`, the fan is frame 3 with `state=fan`. The
   sweep is the busy day's query with `"$(cat tools/fidelity/sweep-frame.js)"` as `[js]`, half way round the sweep
   into the day before. It needs Google Chrome and Node 22.
2. The app: `flutter test test/fidelity_render_test.dart --dart-define=RENDER_DIR=<root>/app`. It pins the
   mock-up's clock (21:10, Thu 5 Nov 2026), its data (the busy, sparse and record days, and its generator for the
   rest) and en_GB dates, on a 390 x 844 pt phone at 3x, and prints each block's rect for the busy light shot.
3. `python3 tools/fidelity/pair.py <root> "App, <branch>" <out>` writes `<root>/<out>/<state>-<theme>.png`, mock-up
   left.

The top 47 pt differ by construction: the mock-up draws its own status bar and Dynamic Island.

The onboarding has no Day Dial mock-up; it is compared with the stills it was picked from
(tag `archive/mockup/onboarding-presets`, `docs/pitch/mockups/onboarding-presets/plain-*.png`, Material-styled, dark only):
`flutter test test/fidelity_onboarding_render_test.dart --dart-define=RENDER_DIR=<root>/app`, each still copied to
`<root>/mock/mock-<step>-<theme>.png` for both themes, then `pair.py`. The pairs are `fidelity/onboarding-*.png`.

Sign-in, sign-up, Settings and Account Settings: `flutter test test/fidelity_account_render_test.dart
--dart-define=RENDER_DIR=<root>/app`. The mock-up has no Account Settings screen, so `fidelity/account-*.png` is the
app alone.

The amount sheet: `flutter test test/fidelity_amount_sheet_render_test.dart --dart-define=RENDER_DIR=<root>/app`, the
mock-up with `"only=3&theme=<theme>&state=amount"` saved as `<root>/mock/mock-amount-sheet-new-<theme>.png`, then
`pair.py`. The pairs are `fidelity/amount-sheet-new-*.png`; `fidelity/amount-sheet-edit-*.png` is the editor alone,
since the mock-up shows editing only through the same sheet.
