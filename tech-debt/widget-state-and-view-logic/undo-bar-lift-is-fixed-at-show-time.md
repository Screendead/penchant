# The undo bar's lift over Log is fixed when it is shown, and applies on every page

**Severity:** low

Today lifts its undo bar over the Log button by passing a clearance that becomes the SnackBar's bottom margin. The
value is computed once, from Today's layout, when the bar is shown. The ScaffoldMessenger shows the same bar in every
root Scaffold, so a page pushed while it is up (Settings, a history, the editor) draws it 173 pt above its foot,
where no Log button is. Because the margin does not follow the layout, a tall keyboard or a short window can leave
less room than the lifted bar needs: at 874 pt it needs about 245 pt above the keyboard at the default text size, and
more at larger ones. `KeyboardInsetClamp` keeps a third of the view free, which covers it on an iPhone at the default
text size only.

A lift computed where the bar is laid out is not a small change: `ScaffoldMessenger` rebuilds every bar as a plain
`SnackBar` (`withAnimation`), so a subclass cannot read its Scaffold, and a lift drawn inside the bar's transparent
Material would absorb taps on the Log button under it.

## Evidence (at `fix/snackbar-offscreen`, 2026-11-08)

- `lib/vice_tracker.dart:48` — `static double logClearance(BuildContext context, {bool split = false}) =>`
- `lib/vice_tracker.dart:153` — `bottomClearance: ViceTracker.logClearance(context, split: _split),`
- `lib/widgets/undo_bar.dart:25` — `margin: bottomClearance == 0`
