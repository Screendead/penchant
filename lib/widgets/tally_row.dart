import 'package:flutter/material.dart';
import 'package:tracker/data/vice.dart';
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
  });

  final Vice vice;
  final HabitMark mark;
  // Null while the day loads.
  final int? total;
  final DateTime day;
  // [from] is the + button's centre, in global coordinates.
  final void Function(Offset from) onLog;

  static String label(Vice vice, int total) =>
      '${vice.name}, ${vice.unit.label(total)}';

  @override
  State<TallyRow> createState() => _TallyRowState();
}

class _TallyRowState extends State<TallyRow>
    with SingleTickerProviderStateMixin {
  static const Duration _flashLength = Duration(milliseconds: 700);

  late final AnimationController _flash = AnimationController(
    vsync: this,
    duration: _flashLength,
    value: 0,
  );
  bool _rising = true;

  @override
  void didUpdateWidget(TallyRow old) {
    super.didUpdateWidget(old);
    final int? before = old.total;
    final int? after = widget.total;
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
    final bool incoming = child.key == ValueKey<int?>(widget.total);
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
    final int? total = widget.total;
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
            key: ValueKey<int?>(total),
            style: type.monoM.copyWith(
              color: zero ? colors.muted : colors.habitInk(widget.mark),
            ),
          ),
        ),
        const SizedBox(width: 6),
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 58),
          child: Text(
            total == null ? '' : widget.vice.unit.nameFor(total),
            style: DialTypeScale.bodyS.copyWith(
              color: colors.muted,
              fontSize: 13.5,
            ),
          ),
        ),
      ],
    );

    return AnimatedBuilder(
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
        padding: const EdgeInsets.only(left: 10, right: 4),
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
                  child: Row(
                    children: <Widget>[
                      HabitPip(mark: widget.mark),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          widget.vice.name,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: zero ? colors.muted : null,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      totals,
                    ],
                  ),
                ),
              ),
            ),
            _PlusButton(
              label: logOneLabel(widget.vice),
              onPressed: widget.onLog,
            ),
          ],
        ),
      ),
    );
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

    return Tooltip(
      message: label,
      child: SizedBox.square(
        dimension: DialSize.minTapTarget,
        child: Material(
          type: MaterialType.transparency,
          child: InkResponse(
            radius: DialSize.minTapTarget / 2,
            onTap: () {
              final RenderBox box = context.findRenderObject()! as RenderBox;
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
                  child: Icon(Icons.add, size: 16, color: scheme.onSurface),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
