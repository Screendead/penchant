import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
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
  static const double titleGap = 8;
  static const double radarTitleOffset = 0.2;

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

  // A radar axis at zero collapses into the centre, so a day with fewer
  // than three used vices reads as broken spokes; it gets bars instead.
  static bool drawsRadar(List<int> quantities) =>
      quantities.where((int quantity) => quantity > 0).length >=
      minimumRadarAxes;

  static String _suffix(Vice vice, int quantity) =>
      ' (${vice.unit.label(quantity)})';

  static TextStyle _titleStyle(ThemeData theme) =>
      TextStyle(color: theme.colorScheme.secondary, fontSize: 14);

  // fl_chart draws each radar title up to a full line beyond its rings
  // (0.96 of the half side plus the title's height), outside the chart's box.
  static EdgeInsets _radarInset(BuildContext context, TextStyle style) =>
      EdgeInsets.all(chartLabelSize(context, 'Ag', style).height);

  static List<({String text, bool nameWhole})> _radarTitles(
    BuildContext context,
    TextStyle style,
    Size size,
    List<Vice> vices,
    List<int> quantities, {
    required bool withAmounts,
  }) {
    final double titleWidth =
        radarTitleWidth(size, vices.length, radarTitleOffset) - titleGap;

    return [
      for (int i = 0; i < vices.length; i++)
        fitChartLabel(
          context,
          name: vices[i].name,
          suffix: withAmounts ? _suffix(vices[i], quantities[i]) : '',
          style: style,
          maxWidth: titleWidth,
        ),
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

    return Semantics(
      container: true,
      label: summary(selectedDate, vices, quantities),
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: !drawsRadar(quantities)
            ? DayBars(vices: vices, quantities: quantities)
            : LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  // Decided on the whole area: the key's height would
                  // otherwise change the radar's size, and with it whether
                  // the titles fit.
                  final List<({String text, bool nameWhole})> titles =
                      _radarTitles(
                        context,
                        titleStyle,
                        _radarInset(
                          context,
                          titleStyle,
                        ).deflateSize(constraints.biggest),
                        vices,
                        quantities,
                        withAmounts: true,
                      );
                  final bool amountsShown = [
                    for (int i = 0; i < vices.length; i++)
                      titles[i].text ==
                          '${vices[i].name}${_suffix(vices[i], quantities[i])}',
                  ].every((bool shown) => shown);
                  // With the amounts in the key, the titles need only name
                  // the axes.
                  final Widget chart = _radar(
                    context,
                    theme,
                    vices,
                    quantities,
                    withAmounts: amountsShown,
                  );
                  if (amountsShown) {
                    return chart;
                  }

                  // A chart under four title lines tall cannot be read.
                  final double minimumChart =
                      4 * chartLabelSize(context, 'Ag', titleStyle).height;
                  return Column(
                    children: [
                      Expanded(
                        child: LayoutBuilder(
                          builder:
                              (BuildContext context, BoxConstraints space) =>
                                  space.maxHeight < minimumChart
                                  ? const SizedBox.shrink()
                                  : chart,
                        ),
                      ),
                      _key(
                        titleStyle,
                        constraints.maxHeight,
                        vices,
                        quantities,
                      ),
                    ],
                  );
                },
              ),
      ),
    );
  }

  Widget _radar(
    BuildContext context,
    ThemeData theme,
    List<Vice> vices,
    List<int> quantities, {
    required bool withAmounts,
  }) {
    final ({int top, int step}) scale = radarScale(quantities.reduce(max));

    final RadarDataSet dataSet = RadarDataSet(
      fillColor: theme.colorScheme.primary.withValues(alpha: 0.2),
      borderColor: theme.colorScheme.primary,
      entryRadius: 6,
      dataEntries: [
        for (final int quantity in quantities)
          RadarEntry(value: quantity.toDouble()),
      ],
      borderWidth: 2,
    );
    // fl_chart puts the smallest entry of all data sets at the centre and the
    // largest on the outer ring, so this invisible set pins them to 0 and to
    // a round top value.
    final RadarDataSet scaleSet = RadarDataSet(
      fillColor: Colors.transparent,
      borderColor: Colors.transparent,
      borderWidth: 0,
      entryRadius: 0,
      dataEntries: [
        RadarEntry(value: scale.top.toDouble()),
        for (int i = 1; i < quantities.length; i++) const RadarEntry(value: 0),
      ],
    );

    final TextStyle titleStyle = _titleStyle(theme);

    return Padding(
      padding: _radarInset(context, titleStyle),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final List<({String text, bool nameWhole})> titles = _radarTitles(
            context,
            titleStyle,
            constraints.biggest,
            vices,
            quantities,
            withAmounts: withAmounts,
          );

          return RadarChart(
            RadarChartData(
              dataSets: [dataSet, scaleSet],
              isMinValueAtCenter: true,
              borderData: FlBorderData(show: false),
              radarBorderData: BorderSide(
                color: theme.colorScheme.tertiary.withValues(alpha: 0.5),
              ),
              radarShape: RadarShape.polygon,
              titlePositionPercentageOffset: radarTitleOffset,
              titleTextStyle: titleStyle,
              getTitle: (int index, double angle) {
                final double correctionFactor = angle > 90 && angle < 270
                    ? 180
                    : 0;

                return RadarChartTitle(
                  text: titles[index].text,
                  angle: angle + correctionFactor,
                );
              },
              tickCount: scale.top ~/ scale.step,
              // fl_chart scales the titles by the device text size, not the ticks.
              // fl_chart prints every ring's value with a decimal place,
              // the centre's "0.0" included; the titles carry the amounts.
              ticksTextStyle: const TextStyle(
                color: Colors.transparent,
                fontSize: 1,
              ),
              tickBorderData: BorderSide(
                color: theme.colorScheme.tertiary.withValues(alpha: 0.5),
              ),
              gridBorderData: BorderSide(
                color: theme.colorScheme.tertiary,
                width: 1,
              ),
            ),
            duration: const Duration(milliseconds: 600),
            curve: Curves.fastOutSlowIn,
          );
        },
      ),
    );
  }
}

// One row per vice: its name and amount, and a bar scaled to the day's
// largest amount, so an unused vice keeps its place as an empty track.
class DayBars extends StatelessWidget {
  const DayBars({super.key, required this.vices, required this.quantities});

  final List<Vice> vices;
  final List<int> quantities;

  static const double trackHeight = 12;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;
    final int largest = quantities.reduce(max);

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) =>
          SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (int i = 0; i < vices.length; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: _row(
                        colors,
                        text,
                        vices[i],
                        quantities[i],
                        largest,
                      ),
                    ),
                ],
              ),
            ),
          ),
    );
  }

  Widget _row(
    ColorScheme colors,
    TextTheme text,
    Vice vice,
    int quantity,
    int largest,
  ) {
    final bool used = quantity > 0;
    final Color ink = used ? colors.onSurface : colors.onSurfaceVariant;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // At large text the amount moves under the name rather than
        // squeezing it.
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.end,
          spacing: 12,
          children: [
            Text(vice.name, style: text.titleMedium?.copyWith(color: ink)),
            Text(
              vice.unit.label(quantity),
              style: text.titleMedium?.copyWith(
                color: used ? ink : colors.outline,
                fontWeight: used ? FontWeight.w600 : FontWeight.w400,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(trackHeight / 2),
          child: Container(
            height: trackHeight,
            color: colors.surfaceContainerHighest,
            alignment: Alignment.centerLeft,
            child: AnimatedFractionallySizedBox(
              duration: const Duration(milliseconds: 600),
              curve: Curves.fastOutSlowIn,
              widthFactor: quantity / largest,
              heightFactor: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.primary,
                  borderRadius: BorderRadius.circular(trackHeight / 2),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
