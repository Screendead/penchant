import 'dart:math';
import 'dart:ui' show lerpDouble;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/data/chart_scale.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/errors/firestore_errors.dart';
import 'package:tracker/formats.dart';
import 'package:tracker/providers/offline_provider.dart';
import 'package:tracker/providers/vice_activity_day_provider.dart';
import 'package:tracker/providers/unarchived_vice_list_provider.dart';
import 'package:tracker/providers/vice_list_provider.dart';
import 'package:tracker/widgets/chart_text.dart';
import 'package:tracker/widgets/clean_day.dart';
import 'package:tracker/widgets/info_box.dart';

class ViceChart extends ConsumerWidget {
  const ViceChart({super.key, required this.selectedDate});

  final DateTime selectedDate;

  static const int minimumRadarAxes = 3;
  static const int maximumRadarRings = 5;
  static const double barWidth = 48;
  static const double titleGap = 8;
  static const int barTitleLines = 2;

  static String total(Vice vice, int quantity) =>
      '${vice.name}: ${vice.unit.label(quantity)}';

  static String summary(DateTime day, List<Vice> vices, List<int> quantities) {
    final String totals = [
      for (int i = 0; i < vices.length; i++) total(vices[i], quantities[i]),
    ].join('; ');

    return 'Totals for ${formatDay(day)}. $totals';
  }

  // The outermost ring's value and the spacing between rings.
  static ({int top, int step}) radarScale(int largest) =>
      roundScale(largest, maximumRadarRings);

  static String _suffix(Vice vice, int quantity) =>
      ' (${vice.unit.label(quantity)})';

  static TextStyle _titleStyle(ThemeData theme) =>
      TextStyle(color: theme.colorScheme.secondary, fontSize: 14);

  static List<({String text, bool nameWhole})> _barTitles(
    BuildContext context,
    TextStyle style,
    double width,
    List<Vice> vices,
    List<int> quantities,
  ) {
    final double titleWidth =
        barTitleWidth(width, vices.length, barWidth) - titleGap;
    bool fits(String text) => chartLabelWraps(
      context,
      text,
      style,
      maxWidth: titleWidth,
      maxLines: barTitleLines,
    );

    return [
      for (int i = 0; i < vices.length; i++)
        if (fits('${vices[i].name}${_suffix(vices[i], quantities[i])}'))
          (
            text: '${vices[i].name}${_suffix(vices[i], quantities[i])}',
            nameWhole: true,
          )
        else
          (text: vices[i].name, nameWhole: fits(vices[i].name)),
    ];
  }

  Widget _key(
    TextStyle style,
    double maxHeight,
    List<Vice> vices,
    List<int> quantities,
  ) => ConstrainedBox(
    constraints: BoxConstraints(maxHeight: maxHeight),
    child: SingleChildScrollView(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 16,
        runSpacing: 4,
        children: [
          for (int i = 0; i < vices.length; i++)
            Text(
              total(vices[i], quantities[i]),
              textAlign: TextAlign.center,
              style: style,
            ),
        ],
      ),
    ),
  );

  Widget _bars(
    BuildContext context,
    ThemeData theme,
    List<({String text, bool nameWhole})> titles,
    List<int> quantities,
  ) {
    final TextStyle titleStyle = _titleStyle(theme);
    final double lineHeight = chartLabelSize(context, 'Ag', titleStyle).height;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double titleWidth =
            barTitleWidth(constraints.maxWidth, titles.length, barWidth) -
            titleGap;

        return BarChart(
          BarChartData(
            alignment: BarChartAlignment.spaceEvenly,
            minY: 0,
            maxY: quantities.reduce(max) * 1.15,
            gridData: const FlGridData(show: false),
            borderData: FlBorderData(show: false),
            barTouchData: BarTouchData(enabled: false),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(),
              leftTitles: const AxisTitles(),
              rightTitles: const AxisTitles(),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: max(48, barTitleLines * lineHeight + 8),
                  getTitlesWidget: (double value, TitleMeta meta) {
                    return SideTitleWidget(
                      meta: meta,
                      child: SizedBox(
                        width: titleWidth,
                        child: Text(
                          titles[value.toInt()].text,
                          maxLines: barTitleLines,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: titleStyle,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            barGroups: [
              for (int i = 0; i < quantities.length; i++)
                BarChartGroupData(
                  x: i,
                  barRods: [
                    BarChartRodData(
                      toY: quantities[i].toDouble(),
                      width: barWidth,
                      color: theme.colorScheme.primary,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(6),
                      ),
                    ),
                  ],
                ),
            ],
          ),
          duration: const Duration(milliseconds: 600),
          curve: Curves.fastOutSlowIn,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<Vice>> vicesValue = ref.watch(
      unarchivedViceListProvider,
    );
    final AsyncValue<List<ViceActivity>> activitiesValue = ref.watch(
      viceActivityDayProvider(selectedDate),
    );

    final List<Vice>? vices = vicesValue.value;

    // With no vices there is nothing to chart, whatever the day's query did.
    if (!vicesValue.hasError && vices != null && vices.isEmpty) {
      return const InfoBox(
        message: 'No vices yet. Add one from Manage Data in the menu.',
      );
    }

    if (vicesValue.error ?? activitiesValue.error case final Object error) {
      return InfoBox(
        message: loadErrorMessage('this day', error),
        isError: true,
        onRetry: () {
          ref.invalidate(viceListForUserProvider, asReload: true);
          ref.invalidate(viceActivityDayForUserProvider, asReload: true);
        },
      );
    }

    final List<ViceActivity>? activityList = activitiesValue.value;

    if (vices == null || activityList == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final Map<String, int> quantityByViceID = {
      for (final Vice vice in vices) vice.id: 0,
    };

    for (final ViceActivity activity in activityList) {
      final int? quantity = quantityByViceID[activity.viceID];
      if (quantity != null) {
        quantityByViceID[activity.viceID] = quantity + activity.quantity;
      }
    }

    if (quantityByViceID.values.every((int quantity) => quantity == 0)) {
      return CleanDay(
        isToday: daysBetween(selectedDate, startOfDay(DateTime.now())) == 0,
        offline: ref.watch(offlineProvider).value ?? false,
      );
    }

    final ThemeData theme = Theme.of(context);
    final List<int> quantities = [
      for (final Vice vice in vices) quantityByViceID[vice.id]!,
    ];

    final TextStyle titleStyle = _titleStyle(theme);
    // fl_chart asserts that a radar data set has at least three entries.
    final bool asBars = vices.length < minimumRadarAxes;

    return Semantics(
      container: true,
      label: summary(selectedDate, vices, quantities),
      excludeSemantics: true,
      child: Padding(
        // The radar's side labels need the width more than a margin does.
        padding: asBars
            ? const EdgeInsets.all(16)
            : const EdgeInsets.symmetric(vertical: 16),
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final List<({String text, bool nameWhole})>? barTitles = asBars
                ? _barTitles(
                    context,
                    titleStyle,
                    constraints.maxWidth,
                    vices,
                    quantities,
                  )
                : null;
            final Widget chart = barTitles != null
                ? _bars(context, theme, barTitles, quantities)
                : ViceRadar(vices: vices, quantities: quantities);
            // Decided on the whole area: the key's height would otherwise
            // change the radar's size, and with it whether the names fit.
            final bool namesWhole =
                barTitles?.every(
                  (({String text, bool nameWhole}) t) => t.nameWhole,
                ) ??
                ViceRadar.layOut(
                  context,
                  constraints.biggest,
                  vices,
                  quantities,
                ).namesWhole;
            if (namesWhole) {
              return chart;
            }

            // A chart under four title lines tall cannot be read.
            final double minimumChart =
                4 * chartLabelSize(context, 'Ag', titleStyle).height;
            return Column(
              children: [
                Expanded(
                  child: LayoutBuilder(
                    builder: (BuildContext context, BoxConstraints space) =>
                        space.maxHeight < minimumChart
                        ? const SizedBox.shrink()
                        : chart,
                  ),
                ),
                _key(titleStyle, constraints.maxHeight, vices, quantities),
              ],
            );
          },
        ),
      ),
    );
  }
}

typedef RadarLabel = ({Rect box, double maxWidth, TextAlign align, int lines});

typedef RadarLayout = ({
  Offset centre,
  double radius,
  List<RadarLabel> labels,
  bool namesWhole,
});

// One axis per vice, drawn here rather than by fl_chart: fl_chart cannot give
// zero its own point on each axis, colour points one by one, or lay titles out
// level, and it prints every ring's value.
class ViceRadar extends StatelessWidget {
  const ViceRadar({super.key, required this.vices, required this.quantities});

  final List<Vice> vices;
  final List<int> quantities;

  // Zero sits on a small ring rather than at the centre, so that each axis
  // keeps its own point and a day with two vices used still has an area.
  static const double zeroRing = 0.16;
  static const double labelGap = 14;
  static const double minimumRadius = 48;
  static const int nameLines = 2;

  ({int top, int step}) get scale =>
      ViceChart.radarScale(quantities.reduce(max));

  String amount(int i) => vices[i].unit.label(quantities[i]);

  // Each axis's name and amount as one string.
  List<String> get titles => [
    for (int i = 0; i < vices.length; i++) '${vices[i].name} (${amount(i)})',
  ];

  static const TextStyle _nameStyle = TextStyle(fontSize: 14, height: 1.2);
  static const TextStyle _amountStyle = TextStyle(
    fontSize: 14,
    height: 1.2,
    fontWeight: FontWeight.w600,
  );

  static Offset _direction(int index, int axes) {
    final double angle = 2 * pi * index / axes;
    return Offset(sin(angle), -cos(angle));
  }

  static TextPainter _measure(
    BuildContext context,
    String text,
    TextStyle style, {
    required double maxWidth,
    required int maxLines,
  }) => TextPainter(
    text: TextSpan(
      text: text,
      style: DefaultTextStyle.of(context).style.merge(style),
    ),
    textDirection: TextDirection.ltr,
    textScaler: MediaQuery.textScalerOf(context),
    textWidthBasis: TextWidthBasis.longestLine,
    maxLines: maxLines,
    ellipsis: '…',
  )..layout(maxWidth: maxWidth);

  static bool _wordsFit(BuildContext context, String name, double maxWidth) =>
      name.split(RegExp(r'\s+')).every((String word) {
        final TextPainter painter = _measure(
          context,
          word,
          _nameStyle,
          maxWidth: double.infinity,
          maxLines: 1,
        );
        final bool fits = painter.width <= maxWidth;
        painter.dispose();
        return fits;
      });

  // Labels sit level just beyond each axis's end, pushed outward by their own
  // size so none crosses the rings. The radius is the largest at which every
  // label fits the area whole without touching another; when none does, the
  // names are cut to one line and the caller shows a key.
  static RadarLayout layOut(
    BuildContext context,
    Size size,
    List<Vice> vices,
    List<int> quantities,
  ) {
    final int axes = vices.length;
    final Offset centre = size.center(Offset.zero);

    List<RadarLabel>? attempt(double radius, {required bool whole}) {
      final List<RadarLabel> labels = [];
      for (int i = 0; i < axes; i++) {
        final Offset u = _direction(i, axes);
        final Offset anchor = centre + u * (radius + labelGap);
        // A point short of the edge: a laid-out line can be a fraction
        // wider than measured.
        double maxWidth =
            -1 +
            min(
              size.width,
              min(
                u.dx < 1 ? 2 * anchor.dx / (1 - u.dx) : double.infinity,
                u.dx > -1
                    ? 2 * (size.width - anchor.dx) / (1 + u.dx)
                    : double.infinity,
              ),
            );
        if (!whole) {
          maxWidth = min(maxWidth, 2 * (radius + labelGap) * sin(pi / axes));
        }
        if (maxWidth < 1) {
          return null;
        }

        final int lines = whole ? nameLines : 1;
        final TextPainter name = _measure(
          context,
          vices[i].name,
          _nameStyle,
          maxWidth: maxWidth,
          maxLines: lines,
        );
        final TextPainter total = _measure(
          context,
          vices[i].unit.label(quantities[i]),
          _amountStyle,
          maxWidth: maxWidth,
          maxLines: 1,
        );
        final bool nameFits =
            !name.didExceedMaxLines &&
            _wordsFit(context, vices[i].name, maxWidth);
        final Size box = Size(
          max(name.width, total.width),
          name.height + total.height,
        );
        name.dispose();
        total.dispose();
        if (whole && !nameFits) {
          return null;
        }

        final Rect rect = Rect.fromCenter(
          center: anchor + Offset(u.dx * box.width / 2, u.dy * box.height / 2),
          width: box.width,
          height: box.height,
        );
        if (rect.top < 0 || rect.bottom > size.height) {
          return null;
        }
        labels.add((
          box: rect,
          maxWidth: maxWidth,
          align: u.dx > 0.2
              ? TextAlign.left
              : u.dx < -0.2
              ? TextAlign.right
              : TextAlign.center,
          lines: lines,
        ));
      }
      for (int i = 0; i < labels.length; i++) {
        for (int j = i + 1; j < labels.length; j++) {
          if (labels[i].box.overlaps(labels[j].box.inflate(2))) {
            return null;
          }
        }
      }
      return labels;
    }

    RadarLayout? largest() {
      double low = minimumRadius;
      double high = size.shortestSide / 2;
      List<RadarLabel>? best = attempt(low, whole: true);
      if (best == null) {
        return null;
      }
      while (high - low > 1) {
        final double mid = (low + high) / 2;
        final List<RadarLabel>? labels = attempt(mid, whole: true);
        if (labels != null) {
          low = mid;
          best = labels;
        } else {
          high = mid;
        }
      }
      return (centre: centre, radius: low, labels: best!, namesWhole: true);
    }

    // Cut names fit beside more neighbours as the ring grows, so the largest
    // radius that keeps the labels on the area is the one to look for.
    RadarLayout? cut() {
      for (double r = size.shortestSide / 2; r >= minimumRadius; r -= 2) {
        final List<RadarLabel>? labels = attempt(r, whole: false);
        if (labels != null) {
          return (centre: centre, radius: r, labels: labels, namesWhole: false);
        }
      }
      return null;
    }

    return largest() ??
        cut() ??
        (
          centre: centre,
          radius: max(0, min(minimumRadius, size.shortestSide / 2)),
          labels: const <RadarLabel>[],
          namesWhole: false,
        );
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colours = Theme.of(context).colorScheme;
    final ({int top, int step}) scale = this.scale;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final RadarLayout layout = layOut(
          context,
          constraints.biggest,
          vices,
          quantities,
        );

        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: TweenAnimationBuilder<_Reach>(
                tween: _ReachTween(
                  end: _Reach([for (final int q in quantities) q / scale.top]),
                ),
                duration: const Duration(milliseconds: 600),
                curve: Curves.fastOutSlowIn,
                builder: (BuildContext context, _Reach reach, Widget? _) =>
                    CustomPaint(
                      painter: _RadarPainter(
                        centre: layout.centre,
                        radius: layout.radius,
                        rings: scale.top ~/ scale.step,
                        reach: reach.values,
                        used: [for (final int q in quantities) q > 0],
                        colours: colours,
                      ),
                    ),
              ),
            ),
            for (int i = 0; i < layout.labels.length; i++)
              _label(layout.labels[i], i, colours),
          ],
        );
      },
    );
  }

  Widget _label(RadarLabel label, int i, ColorScheme colours) {
    final bool used = quantities[i] > 0;

    return Positioned(
      left: switch (label.align) {
        TextAlign.left => label.box.left,
        TextAlign.right => label.box.right - label.maxWidth,
        _ => label.box.center.dx - label.maxWidth / 2,
      },
      top: label.box.top,
      width: label.maxWidth,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: switch (label.align) {
          TextAlign.left => CrossAxisAlignment.start,
          TextAlign.right => CrossAxisAlignment.end,
          _ => CrossAxisAlignment.center,
        },
        children: [
          Text(
            vices[i].name,
            maxLines: label.lines,
            overflow: TextOverflow.ellipsis,
            textAlign: label.align,
            textWidthBasis: TextWidthBasis.longestLine,
            style: _nameStyle.copyWith(
              color: used ? colours.onSurface : colours.onSurfaceVariant,
            ),
          ),
          Text(
            amount(i),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: label.align,
            style: _amountStyle.copyWith(
              color: used
                  ? colours.primary
                  : colours.onSurfaceVariant.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }
}

// Each axis's distance out from the zero ring, as a fraction of the way to
// the outer ring.
class _Reach {
  const _Reach(this.values);

  final List<double> values;

  @override
  bool operator ==(Object other) =>
      other is _Reach && listEquals(other.values, values);

  @override
  int get hashCode => Object.hashAll(values);
}

class _ReachTween extends Tween<_Reach> {
  _ReachTween({required super.end});

  @override
  _Reach lerp(double t) {
    final _Reach from = begin ?? end!;
    if (from.values.length != end!.values.length) {
      return end!;
    }
    return _Reach([
      for (int i = 0; i < end!.values.length; i++)
        lerpDouble(from.values[i], end!.values[i], t)!,
    ]);
  }
}

class _RadarPainter extends CustomPainter {
  _RadarPainter({
    required this.centre,
    required this.radius,
    required this.rings,
    required this.reach,
    required this.used,
    required this.colours,
  });

  final Offset centre;
  final double radius;
  final int rings;
  final List<double> reach;
  final List<bool> used;
  final ColorScheme colours;

  double get _zero => radius * ViceRadar.zeroRing;

  Offset _point(int i, double fraction) =>
      centre +
      ViceRadar._direction(i, reach.length) *
          (_zero + (radius - _zero) * fraction);

  Path _polygon(List<double> fractions) {
    final Path path = Path();
    for (int i = 0; i < fractions.length; i++) {
      final Offset p = _point(i, fractions[i]);
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    return path..close();
  }

  Path _ring(double fraction) =>
      _polygon(List<double>.filled(reach.length, fraction));

  @override
  void paint(Canvas canvas, Size size) {
    final Paint grid = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = colours.outlineVariant;

    for (int i = 0; i < reach.length; i++) {
      canvas.drawLine(_point(i, 0), _point(i, 1), grid);
    }
    for (int k = 1; k < rings; k++) {
      canvas.drawPath(_ring(k / rings), grid);
    }
    canvas
      ..drawPath(
        _ring(1),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = colours.outline,
      )
      ..drawPath(_ring(0), Paint()..color = colours.surfaceContainerHighest)
      ..drawPath(_ring(0), grid);

    final Path shape = _polygon(reach);
    canvas
      ..drawPath(
        shape,
        Paint()..color = colours.primary.withValues(alpha: 0.35),
      )
      ..drawPath(
        shape,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeJoin = StrokeJoin.round
          ..color = colours.primary,
      );

    for (int i = 0; i < reach.length; i++) {
      final Offset p = _point(i, reach[i]);
      if (used[i]) {
        canvas
          ..drawCircle(p, 7, Paint()..color = colours.surface)
          ..drawCircle(p, 5, Paint()..color = colours.primary);
      } else {
        canvas
          ..drawCircle(p, 4, Paint()..color = colours.surface)
          ..drawCircle(
            p,
            4,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5
              ..color = colours.onSurfaceVariant.withValues(alpha: 0.8),
          );
      }
    }
  }

  @override
  bool shouldRepaint(_RadarPainter old) =>
      old.centre != centre ||
      old.radius != radius ||
      old.rings != rings ||
      !listEquals(old.reach, reach) ||
      !listEquals(old.used, used) ||
      old.colours != colours;
}
