# The e2e record helper can lose the typed quantity

**Severity:** low

`recordActivity` in `integration_test/support.dart` types the quantity, then taps Record and waits for the dialog to
close. On a slow hosted runner the text sometimes does not reach the field: the dialog stays open with "Please enter
a quantity" and the test times out. The same test passed on the run before and on a rerun of the same commit, so a
red full-suite run can be this flake rather than the change under test.

## Evidence

- `integration_test/support.dart:414` — `await enterText(tester, 'Quantity', formatAmount(quantity));`
- Run 42414374738, attempt 1: `accessibility_test` "screen readers hear the dial, each bead and tally, and the
  graph" timed out waiting for the `AlertDialog` to vanish, with "Please enter a quantity" on screen. Attempt 2 of
  the same commit passed.
