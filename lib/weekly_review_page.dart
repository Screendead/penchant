import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/data/unit.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/design/dial_icons.dart';
import 'package:tracker/design/dial_theme.dart';
import 'package:tracker/design/habit_mark.dart';
import 'package:tracker/design/tokens.dart';
import 'package:tracker/formats.dart';
import 'package:tracker/insights/insights_report.dart';
import 'package:tracker/insights/weekly_review.dart';
import 'package:tracker/insights/what_follows.dart';
import 'package:tracker/providers/insights_provider.dart';
import 'package:tracker/providers/vice_activity_day_provider.dart';
import 'package:tracker/providers/vice_list_provider.dart';
import 'package:tracker/providers/weekly_review_provider.dart';
import 'package:tracker/widgets/bead_painter.dart';
import 'package:tracker/widgets/info_box.dart';
import 'package:tracker/widgets/settings_card.dart';

/// Last Monday-to-Sunday week: totals against the four before, when in the
/// day, the triggers noted, and what the engine's findings did. Words stay
/// neutral (C16): a total is what was logged, never better or worse.
class WeeklyReviewPage extends ConsumerWidget {
  const WeeklyReviewPage({super.key});

  static const String route = '/insights/week';
  static const String title = 'Last week';
  static const String totalsHeading = 'Totals';
  static const String hoursHeading = 'Busiest hours';
  static const String triggersHeading = 'Most common triggers';
  static const String foundHeading = 'What the journal found';
  static const String collectingHeading = 'Still collecting';
  static const String newHeading = 'New this week';
  static const String stoppedHeading = 'No longer clear';
  static const String loading = 'Working it out…';
  static const String nothingLogged = 'Nothing logged last week';
  static const String noTriggers = 'No triggers noted last week';
  static const String noChange = 'No change from the week before';
  static const String openInsights = 'Open Insights';
  static const String needsHealth = 'Findings need Apple Health';
  static const String onIPhone =
      'Open Penchant on your iPhone, where Apple Health keeps its data.';
  static const String connectInInsights = 'Insights says how to connect it.';
  static const String failed = 'Findings couldn’t be worked out';
  static const String stoppedBody =
      'It held a week earlier; with last week’s days it no longer does.';
  static const String foot =
      'Worked out on this device from your journal. A total is what you '
      'logged, not a score.';

  static String span(ReviewWeek week) {
    final DateFormat day = DateFormat.MMMd(formatLocale);
    return '${DateFormat.EEEE(formatLocale).format(week.start)} '
        '${day.format(week.start)} to '
        '${DateFormat.EEEE(formatLocale).format(addDays(week.end, -1))} '
        '${day.format(addDays(week.end, -1))}';
  }

  static String usual(HabitWeek habit) {
    final double? usual = habit.usual;
    if (usual == null) return 'New in the last four weeks';
    final num rounded = (usual * 10).round() / 10;
    return 'Usually ${habit.vice.unit.label(rounded)} a week';
  }

  static String entries(int n) =>
      '${formatCount(n)} ${pluralWord(n, one: 'entry', other: 'entries')}';

  static String holding(int n) =>
      '${formatCount(n)} ${pluralWord(n, one: 'finding', other: 'findings')} '
      'still ${pluralWord(n, one: 'holds', other: 'hold')}.';

  static String hour(int hour, {required bool alwaysUse24HourFormat}) {
    String at(int h) => formatTime(
      DateTime(2000, 1, 1, h),
      alwaysUse24HourFormat: alwaysUse24HourFormat,
    );
    return '${at(hour)} to ${at((hour + 1) % 24)}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<WeeklyReview> review = ref.watch(weeklyReviewProvider);
    final List<Vice>? vices = ref.watch(viceListProvider).value;
    return CardPage(
      title: title,
      children: <Widget>[
        ...switch (review) {
          AsyncData(:final WeeklyReview value) when vices != null => <Widget>[
            CardFoot(span(value.week)),
            ..._journal(context, value, habitMarks(vices)),
            const CardSectionLabel(foundHeading),
            _Findings(vices: vices),
          ],
          AsyncError() => <Widget>[
            const SizedBox(height: DialSpace.l),
            InfoBox(
              message: 'Your journal couldn’t be loaded.',
              isError: true,
              onRetry: () => ref.invalidate(viceActivityRangeForUserProvider),
            ),
          ],
          _ => const <Widget>[
            DialCard(children: <Widget>[CardRow(label: loading)]),
          ],
        },
        DialCard(
          children: <Widget>[
            CardRow(
              label: openInsights,
              glyph: DialGlyph.right,
              onTap: () => Navigator.of(context).pushNamed('/insights'),
            ),
          ],
        ),
        const CardFoot(foot),
      ],
    );
  }

  List<Widget> _journal(
    BuildContext context,
    WeeklyReview review,
    Map<String, HabitMark> marks,
  ) {
    final bool h24 = MediaQuery.alwaysUse24HourFormatOf(context);
    final List<HourCount> hours = review.busiest(3);
    final List<TriggerCount> triggers = review.triggers.take(5).toList();
    return <Widget>[
      const CardSectionLabel(totalsHeading),
      DialCard(
        top: 0,
        children: <Widget>[
          if (review.habits.isEmpty) const CardRow(label: nothingLogged),
          for (final HabitWeek habit in review.habits)
            _HabitWeekRow(
              habit: habit,
              mark: marks[habit.vice.id] ?? const HabitMark(0),
            ),
        ],
      ),
      const CardSectionLabel(hoursHeading),
      DialCard(
        top: 0,
        children: <Widget>[
          if (hours.isEmpty) const CardRow(label: nothingLogged),
          for (final HourCount h in hours)
            CardRow(
              label: hour(h.hour, alwaysUse24HourFormat: h24),
              value: Text(entries(h.entries)),
            ),
        ],
      ),
      const CardSectionLabel(triggersHeading),
      DialCard(
        top: 0,
        children: <Widget>[
          if (triggers.isEmpty) const CardRow(label: noTriggers),
          for (final TriggerCount t in triggers)
            CardRow(label: t.label, value: Text(entries(t.entries))),
        ],
      ),
    ];
  }
}

class _HabitWeekRow extends StatelessWidget {
  const _HabitWeekRow({required this.habit, required this.mark});

  final HabitWeek habit;
  final HabitMark mark;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final DialColors colors = DialColors.of(context);
    final Unit unit = habit.vice.unit;
    final String usual = WeeklyReviewPage.usual(habit);
    final String total = unit.label(habit.total);
    return MergeSemantics(
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          child: Row(
            children: <Widget>[
              HabitPip(mark: mark),
              const SizedBox(width: DialSpace.s),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      habit.vice.name,
                      style: DialTypeScale.bodyL.copyWith(
                        fontWeight: FontWeight.w500,
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      usual,
                      style: DialTypeScale.bodyS.copyWith(color: colors.muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: DialSpace.s),
              ExcludeSemantics(
                child: _WeekBars(
                  weeks: habit.weeks,
                  week: colors.data[mark.slot],
                  earlier: colors.line,
                ),
              ),
              const SizedBox(width: DialSpace.s),
              Text(
                total,
                style: DialTypeScale.bodyL.copyWith(
                  fontFamily: DialFonts.mono,
                  fontFeatures: DialFonts.tabular,
                  color: scheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// The five weeks side by side, the reviewed one last in the habit's colour.
class _WeekBars extends StatelessWidget {
  const _WeekBars({
    required this.weeks,
    required this.week,
    required this.earlier,
  });

  static const double height = 22;

  final List<num> weeks;
  final Color week;
  final Color earlier;

  @override
  Widget build(BuildContext context) {
    final num most = weeks.fold<num>(0, max);
    return SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          for (final (int i, num w) in weeks.indexed)
            Padding(
              padding: EdgeInsets.only(left: i == 0 ? 0 : 2),
              child: Container(
                width: 5,
                height: most == 0 ? 2 : max(2, height * w / most),
                decoration: BoxDecoration(
                  color: i == weeks.length - 1 ? week : earlier,
                  borderRadius: BorderRadius.circular(1.5),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Findings extends ConsumerWidget {
  const _Findings({required this.vices});

  final List<Vice> vices;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Map<String, String> names = <String, String>{
      for (final Vice v in vices) v.id: v.name,
    };
    final Map<String, Unit> units = <String, Unit>{
      for (final Vice v in vices) v.id: v.unit,
    };
    final Map<String, HabitMark> marks = habitMarks(vices);
    final WeeklyInsights? insights = ref.watch(weeklyInsightsProvider).value;
    void retry() => ref.invalidate(healthStateProvider);
    void insightsPage() => Navigator.of(context).pushNamed('/insights');
    String nameOf(String id) => names[id] ?? 'a removed habit';
    switch (insights) {
      case null:
        return const DialCard(
          top: 0,
          children: <Widget>[CardRow(label: WeeklyReviewPage.loading)],
        );
      case WeeklyInsightsUnavailable(:final HealthState health):
        return DialCard(
          top: 0,
          children: <Widget>[
            CardRow(
              label: WeeklyReviewPage.needsHealth,
              subtitle: health is HealthOnIPhone
                  ? WeeklyReviewPage.onIPhone
                  : WeeklyReviewPage.connectInInsights,
              glyph: health is HealthOnIPhone ? null : DialGlyph.right,
              onTap: health is HealthOnIPhone ? null : insightsPage,
            ),
          ],
        );
      case WeeklyInsightsFailed():
        return DialCard(
          top: 0,
          children: <Widget>[
            CardRow(
              label: WeeklyReviewPage.failed,
              subtitle: 'Try again in a moment.',
              onTap: retry,
            ),
          ],
        );
      case WeeklyInsightsComputed(
        :final InsightChanges changes,
        :final List<HabitRefusal> collecting,
        :final Map<String, double> floors,
      ):
        bool known(InsightCard c) => names.containsKey(c.habitId);
        final List<InsightCard> started = changes.started.where(known).toList();
        final List<InsightCard> stopped = changes.stopped.where(known).toList();
        final int holding = changes.holding.where(known).length;
        final List<HabitRefusal> waiting = <HabitRefusal>[
          for (final HabitRefusal r in collecting)
            if (names.containsKey(r.habitId)) r,
        ];
        Widget card(InsightCard c, String body) => _FindingRow(
          heading: '${nameOf(c.habitId)} · ${c.family.label}',
          body: body,
          mark: marks[c.habitId] ?? const HabitMark(0),
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (started.isEmpty && stopped.isEmpty)
              DialCard(
                top: 0,
                children: <Widget>[
                  CardRow(
                    label: WeeklyReviewPage.noChange,
                    subtitle: holding > 0
                        ? WeeklyReviewPage.holding(holding)
                        : null,
                  ),
                ],
              ),
            if (started.isNotEmpty) ...<Widget>[
              const _SubLabel(WeeklyReviewPage.newHeading),
              DialCard(
                top: 0,
                children: <Widget>[
                  for (final InsightCard c in started)
                    card(
                      c,
                      findingSentence(
                        c.headline,
                        nameOf(c.habitId),
                        formatLocale,
                        unit: units[c.habitId] ?? Unit.fallback,
                      ),
                    ),
                ],
              ),
            ],
            if (stopped.isNotEmpty) ...<Widget>[
              const _SubLabel(WeeklyReviewPage.stoppedHeading),
              DialCard(
                top: 0,
                children: <Widget>[
                  for (final InsightCard c in stopped)
                    card(c, WeeklyReviewPage.stoppedBody),
                ],
              ),
            ],
            if ((started.isNotEmpty || stopped.isNotEmpty) && holding > 0)
              CardFoot(WeeklyReviewPage.holding(holding)),
            if (waiting.isNotEmpty) ...<Widget>[
              const CardSectionLabel(WeeklyReviewPage.collectingHeading),
              DialCard(
                top: 0,
                children: <Widget>[
                  for (final HabitRefusal r in waiting)
                    CardRow(
                      label: nameOf(r.habitId),
                      subtitle: refusalReason(r, nameOf, floors: floors),
                    ),
                ],
              ),
            ],
          ],
        );
    }
  }
}

class _SubLabel extends StatelessWidget {
  const _SubLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(18, DialSpace.s, 18, DialSpace.xs),
    child: Text(
      text,
      style: DialTypeScale.label.copyWith(color: DialColors.of(context).muted),
    ),
  );
}

class _FindingRow extends StatelessWidget {
  const _FindingRow({
    required this.heading,
    required this.body,
    required this.mark,
  });

  final String heading;
  final String body;
  final HabitMark mark;

  @override
  Widget build(BuildContext context) {
    final DialColors colors = DialColors.of(context);
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                HabitPip(mark: mark),
                const SizedBox(width: DialSpace.xs),
                Expanded(
                  child: Text(
                    heading,
                    style: DialTypeScale.label.copyWith(color: colors.muted),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              body,
              style: DialTypeScale.bodyL.copyWith(
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
