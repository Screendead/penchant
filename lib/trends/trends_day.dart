import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/design/dial_icons.dart';
import 'package:tracker/design/dial_theme.dart';
import 'package:tracker/design/habit_mark.dart';
import 'package:tracker/design/tokens.dart';
import 'package:tracker/errors/firestore_errors.dart';
import 'package:tracker/formats.dart';
import 'package:tracker/providers/habit_summary_provider.dart';
import 'package:tracker/providers/offline_provider.dart';
import 'package:tracker/providers/vice_activity_day_provider.dart';
import 'package:tracker/widgets/circle_button.dart';
import 'package:tracker/widgets/day_dial.dart';
import 'package:tracker/widgets/info_box.dart';
import 'package:tracker/widgets/tally_row.dart';

// One day opened from the Trends chart: its dial and tallies, read only, with
// a way back to the chart. Archived habits count here, since it is history.
class TrendsDay extends ConsumerWidget {
  const TrendsDay({
    super.key,
    required this.day,
    required this.today,
    required this.vice,
    required this.habits,
    required this.marks,
    required this.onBack,
    this.backFocus,
  });

  final DateTime day;
  final DateTime today;
  // The habit the chart showed, named in the subtitle.
  final Vice vice;
  // Every habit, in chip order.
  final List<Vice> habits;
  final Map<String, HabitMark> marks;
  final VoidCallback onBack;
  final FocusNode? backFocus;

  static const String backLabel = 'Back to Trends';

  static String title(DateTime day, DateTime today) =>
      daysBetween(day, today) == 0
      ? 'Today'
      : DateFormat.MMMEd(formatLocale).format(day);

  static String subtitle(int entries, Vice vice, num total) =>
      '${formatCount(entries)} ${pluralWord(entries, one: 'entry', other: 'entries')}'
      ' · ${vice.name} ${vice.unit.label(total)}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final DialType type = DialType.of(context);
    final DialColors colors = DialColors.of(context);
    final ThemeData theme = Theme.of(context);
    final AsyncValue<List<ViceActivity>> value = ref.watch(
      viceActivityDayProvider(day),
    );
    final bool offline = ref.watch(offlineProvider).value ?? false;
    final Map<String, double> storedTypicals = ref.watch(
      storedTypicalsProvider,
    );
    HabitMark markOf(Vice v) => marks[v.id] ?? const HabitMark(0);

    final Map<String, Vice> byID = <String, Vice>{
      for (final Vice v in habits) v.id: v,
    };
    final List<ViceActivity>? activities = value.hasError ? null : value.value;
    final List<DialEntry>? entries = activities == null
        ? null
        : <DialEntry>[
            for (final ViceActivity a in activities)
              if (byID[a.viceID] case final Vice v)
                DialEntry(
                  id: a.id,
                  vice: v,
                  mark: markOf(v),
                  quantity: a.measure,
                  at: a.createdAt.toDate(),
                  pending: a.pending,
                ),
          ];
    final Map<String, num> totals = <String, num>{};
    for (final DialEntry e in entries ?? const <DialEntry>[]) {
      totals[e.vice.id] = (totals[e.vice.id] ?? 0) + e.quantity;
    }
    final List<Vice> shown = <Vice>[
      for (final Vice v in habits)
        if (!v.archived || totals.containsKey(v.id)) v,
    ];

    final Widget header = Row(
      children: <Widget>[
        CircleButton(
          icon: DialGlyph.left,
          tooltip: backLabel,
          focusNode: backFocus,
          onPressed: onBack,
        ),
        const SizedBox(width: DialSpace.s),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Semantics(
                header: true,
                child: Text(title(day, today), style: type.displayL),
              ),
              if (entries != null)
                Text(
                  subtitle(entries.length, vice, totals[vice.id] ?? 0),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.muted,
                  ),
                ),
            ],
          ),
        ),
      ],
    );

    if (value.error case final Object error) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          header,
          const SizedBox(height: DialSpace.l),
          InfoBox(
            message: loadErrorMessage('this day', error),
            isError: true,
            onRetry: () =>
                ref.invalidate(viceActivityDayForUserProvider, asReload: true),
          ),
        ],
      );
    }

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double side = min(300, constraints.maxWidth);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            header,
            const SizedBox(height: DialSpace.s),
            Center(
              child: SizedBox.square(
                dimension: side,
                // On the sheet the disc is recessed and the hub raised, the
                // reverse of Today on the ground.
                child: Theme(
                  data: theme.copyWith(
                    colorScheme: theme.colorScheme.copyWith(
                      surfaceContainerLow: colors.surface2,
                      surface: theme.colorScheme.surfaceContainerLow,
                    ),
                  ),
                  child: DayDial(
                    day: day,
                    today: today,
                    entries: entries,
                    storedTypicals: storedTypicals,
                    semanticsLabel: entries == null
                        ? null
                        : DayDial.summary(
                            day,
                            today,
                            shown,
                            <num>[
                              for (final Vice v in shown) totals[v.id] ?? 0,
                            ],
                            <DateTime>[for (final DialEntry e in entries) e.at],
                            alwaysUse24HourFormat:
                                MediaQuery.alwaysUse24HourFormatOf(context),
                          ),
                    offline: offline,
                    onBeadTap: (DialEntry entry) =>
                        Navigator.of(context).pushNamed(
                          '/vices/${entry.vice.id}/activities/${entry.id}',
                        ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: DialSpace.s),
            for (final Vice v in shown)
              TallyRow(
                key: ValueKey<String>('trends-tally-${v.id}'),
                vice: v,
                mark: markOf(v),
                total: entries == null ? null : totals[v.id] ?? 0,
                day: day,
                onLog: null,
              ),
          ],
        );
      },
    );
  }
}
