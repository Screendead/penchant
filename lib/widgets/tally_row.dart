import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/design/dial_icons.dart';
import 'package:tracker/design/dial_theme.dart';
import 'package:tracker/design/habit_mark.dart';
import 'package:tracker/design/tokens.dart';
import 'package:tracker/formats.dart';
import 'package:tracker/widgets/bead_painter.dart';
import 'package:tracker/writes/log_one.dart';

// One habit's total for the shown day, with a + that logs one now.
class TallyRow extends StatefulWidget {
  const TallyRow({
    super.key,
    required this.vice,
    required this.mark,
    required this.total,
    required this.day,
    required this.onLog,
    this.trailing,
  });

  final Vice vice;
  final HabitMark mark;
  // Null while the day loads.
  final num? total;
  final DateTime day;
  // [from] is the + button's centre, in global coordinates. Null shows no +.
  final void Function(Offset from)? onLog;
  // Shown in place of the + while set.
  final Widget? trailing;

  static String label(Vice vice, num total) =>
      '${vice.name}, ${vice.units.label(total)}';

  @override
  State<TallyRow> createState() => _TallyRowState();
}

class _TallyRowState extends State<TallyRow>
    with SingleTickerProviderStateMixin {
  static const Duration _flashLength = Duration(milliseconds: 700);

  late final AnimationController _flash = AnimationController(
    vsync: this,
    animationBehavior: AnimationBehavior.preserve,
    duration: _flashLength,
    value: 0,
  );
  bool _rising = true;

  @override
  void didUpdateWidget(TallyRow old) {
    super.didUpdateWidget(old);
    final num? before = old.total;
    final num? after = widget.total;
    if (before != null && after != null && before != after) {
      _rising = after > before;
      if (old.day == widget.day && after > before) {
        _flash.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    _flash.dispose();
    super.dispose();
  }

  Widget _roll(Widget child, Animation<double> animation, bool reduced) {
    if (reduced) {
      return FadeTransition(opacity: animation, child: child);
    }
    final bool incoming = child.key == ValueKey<num?>(widget.total);
    final double from = (_rising ? 1 : -1) * (incoming ? 1 : -1);
    return ClipRect(
      child: SlideTransition(
        position: Tween<Offset>(
          begin: Offset(0, from),
          end: Offset.zero,
        ).animate(animation),
        child: FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final DialColors colors = DialColors.of(context);
    final DialType type = DialType.of(context);
    final ThemeData theme = Theme.of(context);
    final bool reduced = MediaQuery.disableAnimationsOf(context);
    final num? total = widget.total;
    final bool zero = total == 0;
    final Color hue = colors.habit(widget.mark);

    final Widget totals = Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: <Widget>[
        AnimatedSwitcher(
          duration: reduced ? DialMotion.reducedFade : DialMotion.tallyRoll,
          switchInCurve: const Cubic(0.2, 0.8, 0.2, 1),
          switchOutCurve: const Cubic(0.2, 0.8, 0.2, 1),
          transitionBuilder: (Widget child, Animation<double> a) =>
              _roll(child, a, reduced),
          child: Text(
            total == null ? '' : formatCount(total),
            key: ValueKey<num?>(total),
            style: type.monoM.copyWith(
              color: zero ? colors.muted : colors.habitInk(widget.mark),
            ),
          ),
        ),
        const SizedBox(width: 6),
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 58),
          child: Text(
            total == null ? '' : widget.vice.units.nameFor(total),
            style: DialTypeScale.bodyS.copyWith(
              color: colors.muted,
              fontSize: 13.5,
            ),
          ),
        ),
      ],
    );

    return _TallSemantics(
      child: AnimatedBuilder(
        animation: _flash,
        builder: (BuildContext context, Widget? child) => DecoratedBox(
          decoration: BoxDecoration(
            color: hue.withValues(
              alpha:
                  0.16 *
                  (1 - Curves.easeIn.transform(_flash.value)) *
                  (_flash.isAnimating ? 1 : 0),
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          child: child,
        ),
        child: Padding(
          padding: const EdgeInsets.only(left: 10),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: DialSize.tallyRow),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Semantics(
                    label: total == null
                        ? widget.vice.name
                        : TallyRow.label(widget.vice, total),
                    excludeSemantics: true,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: LayoutBuilder(
                        builder: (BuildContext context, BoxConstraints box) =>
                            Row(
                              children: <Widget>[
                                HabitPip(mark: widget.mark, dim: zero),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    widget.vice.name,
                                    style: theme.textTheme.bodyLarge?.copyWith(
                                      fontSize: 15.5,
                                      color: zero ? colors.muted : null,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                // At large text the total shrinks before it
                                // crowds the name out.
                                ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxWidth: box.maxWidth * 0.55,
                                  ),
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: AlignmentDirectional.centerEnd,
                                    child: totals,
                                  ),
                                ),
                              ],
                            ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                if (widget.trailing case final Widget trailing)
                  trailing
                else if (widget.onLog case final void Function(Offset) onLog)
                  _PlusButton(label: logOneLabel(widget.vice), onPressed: onLog)
                else
                  const SizedBox(width: DialSize.minTapTarget),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// The row is one screen-reader stop, its name and total with the + as its
// tap. The row is 38 pt, so the stop's frame is stretched to 44 pt about its
// middle, overlapping its neighbours' by 3 pt, as the +'s ink does.
class _TallSemantics extends SingleChildRenderObjectWidget {
  const _TallSemantics({required Widget super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderTallSemantics();
}

class _RenderTallSemantics extends RenderProxyBox {
  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    config.isSemanticBoundary = true;
  }

  @override
  Rect get semanticBounds {
    final double extra = max(0, DialSize.minTapTarget - size.height) / 2;
    return Rect.fromLTRB(0, -extra, size.width, size.height + extra);
  }
}

class _PlusButton extends StatelessWidget {
  const _PlusButton({required this.label, required this.onPressed});

  final String label;
  final void Function(Offset from) onPressed;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final DialColors colors = DialColors.of(context);

    // 32 pt drawn in a 38 pt row, as the mock-up has it. The ink is 44 pt
    // square, but hit testing stops at the row's bounds, so a touch lands on
    // a 44 x 38 target; the rows' targets meet with no gap between them.
    return SizedBox(
      width: DialSize.minTapTarget,
      height: DialSize.tallyRow,
      child: OverflowBox(
        maxHeight: DialSize.minTapTarget,
        child: Tooltip(
          message: label,
          child: SizedBox.square(
            dimension: DialSize.minTapTarget,
            child: Material(
              type: MaterialType.transparency,
              child: InkResponse(
                radius: DialSize.minTapTarget / 2,
                onTap: () {
                  final RenderBox box =
                      context.findRenderObject()! as RenderBox;
                  onPressed(box.localToGlobal(box.size.center(Offset.zero)));
                },
                child: Center(
                  child: DecoratedBox(
                    decoration: ShapeDecoration(
                      color: scheme.surfaceContainerLow,
                      shape: CircleBorder(side: BorderSide(color: colors.line)),
                    ),
                    child: SizedBox.square(
                      dimension: DialSize.tallyPlus,
                      child: Center(
                        child: StrokeIcon(
                          DialGlyph.plus,
                          size: 16,
                          color: scheme.onSurface,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
