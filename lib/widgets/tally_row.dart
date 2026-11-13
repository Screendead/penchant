import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:tracker/data/habit_line.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/design/dial_icons.dart';
import 'package:tracker/design/dial_theme.dart';
import 'package:tracker/design/habit_mark.dart';
import 'package:tracker/design/tokens.dart';
import 'package:tracker/formats.dart';
import 'package:tracker/widgets/bead_painter.dart';
import 'package:tracker/writes/log_one.dart';

// The day's habits as tiles, two across: one across at large text, where
// half the width no longer holds a name beside the +.
class TallyGrid extends StatelessWidget {
  const TallyGrid({super.key, required this.children});

  final List<Widget> children;

  static const double gap = 8;
  static const double oneColumnAbove = 1.3;

  @override
  Widget build(BuildContext context) {
    final bool oneColumn =
        MediaQuery.textScalerOf(context).scale(100) > 100 * oneColumnAbove;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (oneColumn)
          for (final (int i, Widget child) in children.indexed)
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : gap),
              child: child,
            )
        else
          for (int i = 0; i < children.length; i += 2)
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : gap),
              // Both tiles of a row are as tall as the taller.
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Expanded(child: children[i]),
                    const SizedBox(width: gap),
                    Expanded(
                      child: i + 1 < children.length
                          ? children[i + 1]
                          : const SizedBox(),
                    ),
                  ],
                ),
              ),
            ),
      ],
    );
  }
}

// One habit's total for the shown day as a tile, with a + that logs one now.
// Nothing in it may be a LayoutBuilder: TallyGrid asks for its intrinsic
// height.
class TallyRow extends StatefulWidget {
  const TallyRow({
    super.key,
    required this.vice,
    required this.mark,
    required this.total,
    required this.day,
    required this.onLog,
    this.trailing,
    this.lineTotal,
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
  // What the habit's line is read against: the day's total for a day line,
  // the last 7 days' for a week line. Null shows no line, as while it loads.
  final num? lineTotal;

  static String label(Vice vice, num total) =>
      '${vice.name}, ${vice.units.label(total)}';

  // "2 of 3 a day", or "22 of 30 in 7 days" for a week line.
  static String lineText(HabitLine line, num lineTotal) =>
      '${formatCount(lineTotal)} of ${formatCount(line.amount)} '
      '${_linePeriod(line)}';

  static String _linePeriod(HabitLine line) =>
      line.period == LinePeriod.day ? 'a day' : 'in 7 days';

  // Where the bar ends: a third past the line, or the total once it is
  // further than that.
  static num lineScale(HabitLine line, num lineTotal) =>
      max(line.amount * 4 / 3, lineTotal);

  static String lineSpoken(Vice vice, HabitLine line, num lineTotal) =>
      line.period == LinePeriod.day
      ? 'your line ${line.short}'
      : '${vice.units.label(lineTotal)} in the last 7 days, your line '
            '${line.short}';

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
    final HabitLine? line = widget.vice.line;
    final num? lineTotal = line == null || total == null
        ? null
        : widget.lineTotal;

    // At large text the total shrinks before it leaves the tile.
    final Widget totals = FittedBox(
      fit: BoxFit.scaleDown,
      alignment: AlignmentDirectional.centerStart,
      child: Row(
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
              style: type.monoL.copyWith(
                color: zero ? colors.muted : colors.habitInk(widget.mark),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            total == null ? '' : widget.vice.units.nameFor(total),
            style: DialTypeScale.bodyS.copyWith(color: colors.muted),
          ),
        ],
      ),
    );

    return _TileSemantics(
      child: AnimatedBuilder(
        animation: _flash,
        builder: (BuildContext context, Widget? child) => DecoratedBox(
          decoration: BoxDecoration(
            color: Color.alphaBlend(
              hue.withValues(
                alpha:
                    0.16 *
                    (1 - Curves.easeIn.transform(_flash.value)) *
                    (_flash.isAnimating ? 1 : 0),
              ),
              theme.colorScheme.surfaceContainerLow,
            ),
            border: Border.all(color: colors.line),
            borderRadius: BorderRadius.circular(DialRadius.tile),
          ),
          child: child,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 9, 4, 9),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Semantics(
                      label: total == null
                          ? widget.vice.name
                          : lineTotal == null
                          ? TallyRow.label(widget.vice, total)
                          : '${TallyRow.label(widget.vice, total)}, '
                                '${TallyRow.lineSpoken(widget.vice, line!, lineTotal)}',
                      excludeSemantics: true,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Padding(
                                padding: const EdgeInsets.only(top: 5),
                                child: HabitPip(mark: widget.mark, dim: zero),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  widget.vice.name,
                                  style: theme.textTheme.bodyLarge?.copyWith(
                                    fontSize: 14.5,
                                    height: 20 / 14.5,
                                    color: zero ? colors.muted : null,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          totals,
                        ],
                      ),
                    ),
                  ),
                  if (widget.trailing case final Widget trailing)
                    trailing
                  else if (widget.onLog case final void Function(Offset) onLog)
                    _PlusButton(
                      label: logOneLabel(widget.vice),
                      onPressed: onLog,
                    )
                  else
                    const SizedBox(width: 8),
                ],
              ),
              if (line != null) _lineBar(line, lineTotal, hue, reduced),
            ],
          ),
        ),
      ),
    );
  }

  // Along the tile's foot, the line alone: the total it is read against in
  // words, over a track with a tick at the line. The line sits three
  // quarters along until the total passes the track's end; past the line the
  // fill runs on in the same colour.
  Widget _lineBar(HabitLine line, num? lineTotal, Color hue, bool reduced) {
    final DialColors colors = DialColors.of(context);
    final DialType type = DialType.of(context);
    final Color ink = Theme.of(context).colorScheme.onSurface;
    final num scale = TallyRow.lineScale(line, lineTotal ?? 0);
    final TextStyle words = DialTypeScale.bodyS.copyWith(
      fontSize: 12.5,
      height: 16 / 12.5,
      color: colors.muted,
    );
    final TextStyle figures = type.monoM.copyWith(
      fontSize: 12.5,
      height: 16 / 12.5,
      color: ink,
    );
    return Padding(
      padding: const EdgeInsets.only(top: 4, right: 8),
      child: ExcludeSemantics(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // While the total loads the words' space and the track still
            // show, so the tile keeps its height.
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Text.rich(
                TextSpan(
                  style: words,
                  children: <InlineSpan>[
                    if (lineTotal != null) ...<InlineSpan>[
                      TextSpan(text: formatCount(lineTotal), style: figures),
                      const TextSpan(text: ' of '),
                      TextSpan(text: formatCount(line.amount), style: figures),
                      TextSpan(text: ' ${TallyRow._linePeriod(line)}'),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 3),
            TweenAnimationBuilder<Offset>(
              tween: Tween<Offset>(
                end: Offset((lineTotal ?? 0) / scale, line.amount / scale),
              ),
              duration: reduced ? Duration.zero : DialMotion.tallyRoll,
              curve: const Cubic(0.2, 0.8, 0.2, 1),
              builder: (BuildContext context, Offset value, _) => SizedBox(
                height: 12,
                width: double.infinity,
                child: CustomPaint(
                  painter: LineBarPainter(
                    fraction: value.dx,
                    tickAt: value.dy,
                    track: colors.line,
                    fill: hue.withValues(alpha: 0.8),
                    tick: ink.withValues(alpha: 0.7),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class LineBarPainter extends CustomPainter {
  LineBarPainter({
    required this.fraction,
    required this.tickAt,
    required this.track,
    required this.fill,
    required this.tick,
  });

  final double fraction;
  final double tickAt;
  final Color track;
  final Color fill;
  final Color tick;

  @override
  void paint(Canvas canvas, Size size) {
    final double mid = size.height / 2;
    final Rect bar = Rect.fromLTWH(0, mid - 2, size.width, 4);
    const Radius round = Radius.circular(2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(bar, round),
      Paint()..color = track,
    );
    if (fraction > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, bar.top, size.width * fraction, 4),
          round,
        ),
        Paint()..color = fill,
      );
    }
    final double x = size.width * tickAt;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(x - 1, 0, 2, size.height),
        const Radius.circular(1),
      ),
      Paint()..color = tick,
    );
  }

  @override
  bool shouldRepaint(LineBarPainter old) =>
      old.fraction != fraction ||
      old.tickAt != tickAt ||
      old.track != track ||
      old.fill != fill ||
      old.tick != tick;
}

// The tile is one screen-reader stop, its name and total with the + as its
// tap.
class _TileSemantics extends SingleChildRenderObjectWidget {
  const _TileSemantics({required Widget super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderTileSemantics();
}

class _RenderTileSemantics extends RenderProxyBox {
  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    config.isSemanticBoundary = true;
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

    // 32 pt drawn in a 44 pt target.
    return SizedBox.square(
      dimension: DialSize.minTapTarget,
      child: Center(
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
                      color: scheme.surfaceContainerHigh,
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
