import 'dart:math';

import 'package:flutter/material.dart';
import 'package:tracker/design/tokens.dart';

const Duration undoDuration = DialMotion.undoWindow;
const Duration noticeDuration = Duration(seconds: 3);

const TextStyle undoBarBold = TextStyle(fontWeight: FontWeight.w600);

// The bar that confirms a change, with Undo for eight seconds when it can be
// undone. A new bar replaces the last rather than queueing behind it: an
// earlier bar's Undo left on screen would undo the wrong change. [action],
// under the message, is a second step on the same change; it closes the bar.
void showUndoBar(
  ScaffoldMessengerState messenger,
  InlineSpan message, {
  VoidCallback? onUndo,
  ({String label, VoidCallback onPressed})? action,
}) {
  messenger.clearSnackBars();
  messenger.showSnackBar(
    SnackBar(
      persist: false,
      behavior: SnackBarBehavior.floating,
      duration: onUndo == null && action == null
          ? noticeDuration
          : undoDuration,
      padding: EdgeInsets.fromLTRB(18, 6, onUndo == null ? 18 : 6, 6),
      content: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: DialSize.minTapTarget),
        child: Row(
          children: <Widget>[
            Expanded(
              child: action == null
                  ? Text.rich(message)
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text.rich(message),
                        ),
                        _BarAction(
                          label: action.label,
                          onPressed: () {
                            messenger.hideCurrentSnackBar();
                            action.onPressed();
                          },
                        ),
                      ],
                    ),
            ),
            if (onUndo != null) ...<Widget>[
              const SizedBox(width: 10),
              UndoCountdownButton(
                window: undoDuration,
                onPressed: () {
                  messenger.hideCurrentSnackBar();
                  onUndo();
                },
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

// A text button in the snack bar's action colour, as tall as a tap target.
class _BarAction extends StatelessWidget {
  const _BarAction({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final Color ink =
        Theme.of(context).snackBarTheme.actionTextColor ??
        Theme.of(context).colorScheme.onInverseSurface;

    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: ink,
        minimumSize: const Size(DialSize.minTapTarget, DialSize.minTapTarget),
        padding: EdgeInsets.zero,
        alignment: AlignmentDirectional.centerStart,
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
      child: Text(label),
    );
  }
}

/// Undo, with a ring that empties over [window]. [ink] defaults to the
/// snack bar's action colour.
class UndoCountdownButton extends StatefulWidget {
  const UndoCountdownButton({
    super.key,
    required this.window,
    required this.onPressed,
    this.ink,
  });

  final Duration window;
  final VoidCallback onPressed;
  final Color? ink;

  @override
  State<UndoCountdownButton> createState() => _UndoCountdownButtonState();
}

class _UndoCountdownButtonState extends State<UndoCountdownButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _countdown = AnimationController(
    vsync: this,
    animationBehavior: AnimationBehavior.preserve,
    duration: widget.window,
  )..forward();

  @override
  void dispose() {
    _countdown.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final SnackBarThemeData bar = Theme.of(context).snackBarTheme;
    final Color ink =
        widget.ink ??
        bar.actionTextColor ??
        Theme.of(context).colorScheme.onInverseSurface;

    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: widget.onPressed,
        customBorder: const StadiumBorder(),
        child: Ink(
          height: DialSize.minTapTarget,
          padding: const EdgeInsets.fromLTRB(10, 0, 14, 0),
          decoration: ShapeDecoration(
            shape: const StadiumBorder(),
            color: ink.withValues(alpha: 0.14),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ExcludeSemantics(
                child: SizedBox.square(
                  dimension: 20,
                  child: AnimatedBuilder(
                    animation: _countdown,
                    builder: (BuildContext context, _) =>
                        CircularProgressIndicator(
                          value: 1 - _countdown.value,
                          strokeWidth: 2.2,
                          color: ink,
                          backgroundColor: ink.withValues(alpha: 0.3),
                        ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Undo',
                style: TextStyle(
                  color: ink,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Sits in a Scaffold's floating-action-button slot, so that Scaffold alone
// lays its floating bars [height] higher, re-measured on every layout. It
// takes no taps, so the button it clears stays usable.
class SnackBarLift extends StatelessWidget {
  const SnackBarLift({super.key, required this.height});

  final double Function(BuildContext context, double width) height;

  static const FloatingActionButtonLocation location = _LiftLocation();

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (BuildContext context, BoxConstraints constraints) =>
        IgnorePointer(
          child: SizedBox(
            width: 1,
            height: height(context, constraints.maxWidth),
          ),
        ),
  );
}

class _LiftLocation extends FloatingActionButtonLocation {
  const _LiftLocation();

  // Measured from where an unlifted floating bar would sit, and never above
  // half of it, so a tall keyboard leaves the bar on screen.
  @override
  Offset getOffset(ScaffoldPrelayoutGeometry g) {
    final double base = min(
      g.contentBottom,
      g.scaffoldSize.height - g.minViewPadding.bottom,
    );
    return Offset(0, max(base - g.floatingActionButtonSize.height, base / 2));
  }
}
