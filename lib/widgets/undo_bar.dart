import 'package:flutter/material.dart';
import 'package:tracker/design/tokens.dart';

const Duration undoDuration = DialMotion.undoWindow;
const Duration noticeDuration = Duration(seconds: 3);

const TextStyle undoBarBold = TextStyle(fontWeight: FontWeight.w600);

// The bar that confirms a change, with Undo for eight seconds when it can be
// undone. A new bar replaces the last rather than queueing behind it: an
// earlier bar's Undo left on screen would undo the wrong change.
// [bottomClearance] lifts it over a floating button below it.
void showUndoBar(
  ScaffoldMessengerState messenger,
  InlineSpan message, {
  VoidCallback? onUndo,
  double bottomClearance = 0,
}) {
  messenger.clearSnackBars();
  messenger.showSnackBar(
    SnackBar(
      persist: false,
      behavior: SnackBarBehavior.floating,
      duration: onUndo == null ? noticeDuration : undoDuration,
      margin: bottomClearance == 0
          ? null
          : EdgeInsets.fromLTRB(
              DialSpace.m,
              0,
              DialSpace.m,
              DialSpace.m + bottomClearance,
            ),
      padding: EdgeInsets.fromLTRB(18, 6, onUndo == null ? 18 : 6, 6),
      content: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: DialSize.minTapTarget),
        child: Row(
          children: <Widget>[
            Expanded(child: Text.rich(message)),
            if (onUndo != null) ...<Widget>[
              const SizedBox(width: 10),
              _UndoButton(
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

class _UndoButton extends StatefulWidget {
  const _UndoButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  State<_UndoButton> createState() => _UndoButtonState();
}

class _UndoButtonState extends State<_UndoButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _countdown = AnimationController(
    vsync: this,
    animationBehavior: AnimationBehavior.preserve,
    duration: undoDuration,
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
        bar.actionTextColor ?? Theme.of(context).colorScheme.onInverseSurface;

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
