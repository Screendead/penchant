import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/data/unit.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/design/dial_icons.dart';
import 'package:tracker/design/dial_theme.dart';
import 'package:tracker/design/habit_mark.dart';
import 'package:tracker/design/page_transitions.dart';
import 'package:tracker/design/tokens.dart';
import 'package:tracker/formats.dart';
import 'package:tracker/insights/after_event.dart';
import 'package:tracker/insights/after_event_copy.dart';
import 'package:tracker/insights/before_use_copy.dart';
import 'package:tracker/insights/before_use.dart';
import 'package:tracker/insights/calendar_source.dart';
import 'package:tracker/insights/daily_series.dart' show lateUseCutoffHour;
import 'package:tracker/insights/habit_follows.dart';
import 'package:tracker/insights/hours_after.dart';
import 'package:tracker/insights/insights_report.dart';
import 'package:tracker/insights/last_night.dart';
import 'package:tracker/insights/measure_shifts.dart';
import 'package:tracker/insights/payoff.dart';
import 'package:tracker/insights/payoff_copy.dart';
import 'package:tracker/insights/recovery.dart';
import 'package:tracker/insights/recovery_copy.dart';
import 'package:tracker/insights/replacement.dart';
import 'package:tracker/insights/replacement_copy.dart';
import 'package:tracker/insights/what_follows.dart';
import 'package:tracker/providers/calendar_provider.dart';
import 'package:tracker/providers/insights_provider.dart';
import 'package:tracker/providers/last_night_provider.dart';
import 'package:tracker/providers/today_provider.dart';
import 'package:tracker/providers/vice_activity_day_provider.dart';
import 'package:tracker/providers/vice_list_provider.dart';
import 'package:tracker/widgets/after_event_card.dart';
import 'package:tracker/widgets/bead_painter.dart';
import 'package:tracker/widgets/before_use_card.dart';
import 'package:tracker/widgets/habit_follows_card.dart';
import 'package:tracker/widgets/info_box.dart';
import 'package:tracker/widgets/measure_shift_card.dart';
import 'package:tracker/widgets/not_yet_box.dart';
import 'package:tracker/widgets/payoff_card.dart';
import 'package:tracker/widgets/recovery_card.dart';
import 'package:tracker/widgets/replacement_card.dart';
import 'package:tracker/weekly_review_page.dart';
import 'package:tracker/widgets/settings_card.dart';

/// What follows each habit, from the whole journal and Apple Health, worked
/// out on the device.
class InsightsPage extends ConsumerStatefulWidget {
  const InsightsPage({super.key});

  static const String route = '/insights';
  static const String title = 'Insights';
  static const String connectLabel = 'Connect Apple Health';
  static const String askAgainLabel = 'Allow new Health data';
  static const String askAgainBody =
      'Penchant can read more Health data now. Tap to allow it.';
  static const String manageLabel = 'Manage Health access';
  static const String manageBody =
      'Settings > Privacy & Security > Health > Penchant';
  static const String loadingLabel = 'Working out your insights';
  static const String noHealthData = 'No Health data to read';
  static const String noHealthDataBody =
      'Penchant found no sleep, heart or activity data. '
      'If you didn’t allow it to read Health, find Health in Settings and '
      'turn it on under Data Access & Devices > Penchant.';
  static const String noHealthDataValue = 'No data';
  static const String nothingClear = 'Nothing clear yet';
  static const String onIPhone = 'Available on iPhone';
  static const String refusedHeading = 'Not enough to say';
  static const String nothingClearBody =
      'No habit has a difference that stands out from your usual days yet.';
  static const String copyLabel = 'Copy as text';

  static const String lastNightHeading = 'Last night against your usual';
  static const String costsHeading = 'What it costs';
  static const String cuttingDownHeading = 'How cutting down is going';
  static const String setsOffHeading = 'What sets it off';

  /// The level changes' heading on the "What it costs" drill-in.
  static const String shiftsHeading = 'What else changed';
  static const String shiftsNote =
      'A measure that moved to a new level and stayed there, as after an '
      'illness or a new routine. Each habit is judged with these changes '
      'allowed for, so one isn’t pinned on a habit that happened to change '
      'at the same time.';

  /// Cards "What it costs" shows before its "more" row, which also counts
  /// the level changes behind it.
  static const int previewCards = 2;
  static const String moreCosts = 'More on what it costs';
  static String more(int n) => '$n more';

  static const String earlyTitle = 'Not enough to say yet';
  static String earlyBody(int have, int need) =>
      'Each habit needs $need days with both your journal and Apple Health. '
      'You have $have.';

  // Engines p and q (HANDOVER item 7) fill the first; until a section has a
  // finding it says what will be there, never a count nothing computes.
  static const String cuttingDownTitle = 'Nothing to show yet';
  static const String cuttingDownBody =
      'When a habit stays lower for a few weeks, this will show what moved '
      'with it: your sleep and heart against before, and any habit that rose '
      'around the same time.';
  static const String setsOffTitle = 'Nothing to show yet';
  static const String setsOffBody =
      'This will show what tends to come before each habit, such as a short '
      'night or another habit.';

  static const String calendarLabel = 'Connect Calendar';
  static const String calendarBody =
      'See which habits follow your events. Penchant reads only when each '
      'event starts and ends, on this iPhone, never writes to your calendar, '
      'and sends none of it anywhere.';
  static const String calendarOffLabel = 'Calendar';
  static const String calendarOffValue = 'Off';
  static const String calendarOffBody =
      'To see which habits follow your events, give Penchant full access to '
      'Calendars in Settings.';
  static const String calendarFailed = 'The calendar couldn’t be opened.';

  static const String copied = 'Insights copied';
  static const String foot =
      'Worked out on this device from your journal and Apple Health; '
      'Penchant sends none of it anywhere. These are patterns in your own days, '
      'not medical advice, and a pattern doesn’t show that one thing '
      'causes another.';

  static const String hoursAfterNote =
      'Heart rate in the hours after a use comes from the last '
      '$hoursAfterMaxEvents uses of each habit in the past year, against '
      'the same time after waking on nearby days. Uses you time by how you '
      'feel, such as coffee when tired, can show a change that would have '
      'come anyway.';

  static const String hoursAfterPending =
      'Still reading heart rate around your uses from Apple Health.';

  static const String updating =
      'Updating with anything new in your journal and Apple Health.';

  static const String weekSubtitle =
      'Totals, hours and triggers, and what changed';

  static String span(DateTime firstDay) =>
      'From ${formatDate(firstDay)} to today';

  @override
  ConsumerState<InsightsPage> createState() => _InsightsPageState();
}

class _InsightsPageState extends ConsumerState<InsightsPage> {
  bool _connecting = false;
  bool _connectingCalendar = false;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // Access granted in Settings shows no sheet, so coming back is the only
    // sign that Health may now have data to give.
    _lifecycle = AppLifecycleListener(
      onResume: () {
        // Access allowed in Settings shows no prompt either. Once full,
        // asking again would read the calendar and run the engine anew.
        if (ref.read(calendarAccessProvider).value != CalendarAccess.full) {
          ref.invalidate(calendarAccessProvider);
        }
        if (ref.read(healthStateProvider).value case HealthReady(
          :final values,
        ) when values.isEmpty) {
          _retryHealth();
        }
      },
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final ProviderContainer container = ProviderScope.containerOf(
      context,
      listen: false,
    );
    setState(() => _connecting = true);
    final bool shown = await connectHealth(container);
    if (!mounted) return;
    setState(() => _connecting = false);
    if (!shown) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Apple Health couldn’t be opened.')),
      );
    }
  }

  Future<void> _connectCalendar() async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final ProviderContainer container = ProviderScope.containerOf(
      context,
      listen: false,
    );
    setState(() => _connectingCalendar = true);
    final bool granted = await connectCalendar(container);
    if (!mounted) return;
    setState(() => _connectingCalendar = false);
    if (!granted &&
        await container.read(calendarAccessProvider.future) ==
            CalendarAccess.notDetermined) {
      messenger.showSnackBar(
        const SnackBar(content: Text(InsightsPage.calendarFailed)),
      );
    }
  }

  // A new read gives new values, so the engine runs again too.
  void _retryHealth() => ref.invalidate(healthStateProvider);

  void _retryJournal() => ref.invalidate(viceActivityRangeForUserProvider);

  void _retryHabits() => ref.invalidate(viceListForUserProvider);

  @override
  Widget build(BuildContext context) {
    final AsyncValue<InsightsView> view = ref.watch(insightsProvider);
    final AsyncValue<List<Vice>> habits = ref.watch(viceListProvider);
    final List<Vice>? vices = habits.value;
    // Health's state is known before the journal loads, so the card shows it.
    final HealthState? health =
        view.value?.health ?? ref.watch(healthStateProvider).value;
    final bool askAgain = ref.watch(healthAskAgainProvider).value ?? false;
    final CalendarAccess? calendar = ref.watch(calendarAccessProvider).value;

    return CardPage(
      title: InsightsPage.title,
      children: <Widget>[
        // Once Health is read with nothing to ask, its card moves to the
        // drill-in, under the findings it explains.
        if (health != null && !_healthSettled(health, askAgain))
          _HealthCard(
            state: health,
            askAgain: askAgain,
            connecting: _connecting,
            onConnect: _connect,
          ),
        if (calendar != null && calendar != CalendarAccess.full)
          _CalendarCard(
            access: calendar,
            connecting: _connectingCalendar,
            onConnect: _connectCalendar,
          ),
        ...switch (view) {
          AsyncError() => <Widget>[
            const SizedBox(height: DialSpace.l),
            InfoBox(
              message: 'Your journal couldn’t be loaded.',
              isError: true,
              onRetry: _retryJournal,
            ),
          ],
          _ when habits is AsyncError && vices == null => <Widget>[
            const SizedBox(height: DialSpace.l),
            InfoBox(
              message: 'Your habits couldn’t be loaded.',
              isError: true,
              onRetry: _retryHabits,
            ),
          ],
          AsyncData(:final InsightsView value) when vices != null => _body(
            value,
            vices,
          ),
          // Today's line opens here, so last night waits for no engine.
          _ => <Widget>[
            if (vices != null)
              _LastNightSection(vices: vices, marks: habitMarks(vices)),
            const _MessageCard(InsightsPage.loadingLabel, busy: true),
          ],
        },
        DialCard(
          children: <Widget>[
            CardRow(
              label: WeeklyReviewPage.title,
              subtitle: InsightsPage.weekSubtitle,
              glyph: DialGlyph.right,
              onTap: () =>
                  Navigator.of(context).pushNamed(WeeklyReviewPage.route),
            ),
          ],
        ),
        const CardFoot(InsightsPage.foot),
      ],
    );
  }

  List<Widget> _body(InsightsView view, List<Vice> vices) {
    switch (view.health) {
      case HealthOnIPhone():
        return const <Widget>[
          _MessageCard(
            'Insights',
            body:
                'Open Penchant on your iPhone to see what follows each '
                'habit. Apple Health keeps its data there.',
          ),
        ];
      case HealthUnsupported():
        return const <Widget>[
          _MessageCard(
            'Insights',
            body: 'Insights need Apple Health, which this device doesn’t have.',
          ),
        ];
      case HealthNotConnected():
        return const <Widget>[
          _MessageCard(
            'How it works',
            body:
                'Insights compare your sleep, heart, activity and mindfulness '
                'after days '
                'with each habit against days without it. Connect Apple '
                'Health to start.',
          ),
        ];
      case HealthLocked():
        return <Widget>[
          _MessageCard(
            'Health is locked',
            body:
                'Apple Health can’t be read while your iPhone is locked. '
                'Unlock it and try again.',
            onRetry: _retryHealth,
          ),
        ];
      case HealthFailed():
        return <Widget>[
          _MessageCard(
            'Health couldn’t be read',
            body: 'Try again in a moment.',
            onRetry: _retryHealth,
          ),
        ];
      case HealthReady():
        break;
    }
    final InsightsResult? result = view.result;
    if (result == null) {
      // HealthKit answers a refused read with no samples, so this can't tell
      // an empty Health from access that wasn't allowed.
      return <Widget>[
        _MessageCard(
          InsightsPage.noHealthData,
          body: InsightsPage.noHealthDataBody,
          onRetry: _retryHealth,
        ),
      ];
    }
    if (result is InsightsFailed) {
      return <Widget>[
        _LastNightSection(vices: vices, marks: habitMarks(vices)),
        _MessageCard(
          'Insights couldn’t be worked out',
          body: 'Try again in a moment.',
          onRetry: _retryHealth,
        ),
      ];
    }
    final _Costs costs = _Costs(result as InsightsComputed, vices);
    final List<Widget Function(double top)> costCards =
        <Widget Function(double top)>[
          for (final InsightCard card in costs.cards)
            (double top) => costs.card(card, top: top),
          for (final RecoveryCard card in costs.recovery)
            (double top) => costs.recoveryCard(card, top: top),
        ];
    final int shown = min(costCards.length, InsightsPage.previewCards);
    final int hidden = costCards.length - shown + costs.shifts.length;
    final List<Widget Function(double top)>
    cuttingDown = <Widget Function(double top)>[
      for (final PayoffCard card in costs.fallCards)
        (double top) => PayoffCardView(
          card: card,
          habit: costs.nameOf(card.habitId),
          unit: costs.unitOf(card.habitId),
          mark: costs.marks[card.habitId] ?? const HabitMark(0),
          locale: formatLocale,
          top: top,
          replacement: costs.risers[card.habitId],
          nameOf: costs.nameOf,
          unitOf: costs.unitOf,
        ),
      // A fall with nothing clear since stays a row, not a card.
      if (costs.payoffRows.isNotEmpty)
        (double top) => DialCard(
          top: top,
          children: <Widget>[
            for (final PayoffCard card in costs.payoffRows)
              CardRow(
                label: costs.nameOf(card.habitId),
                subtitle:
                    '${fallSentence(card.fall, costs.nameOf(card.habitId), formatLocale, unit: costs.unitOf(card.habitId))} '
                    '${payoffRefusal(card.refusal!)}',
              ),
          ],
        ),
      for (final ReplacementCard card in costs.replacements)
        (double top) => ReplacementCardView(
          card: card,
          nameOf: costs.nameOf,
          unitOf: costs.unitOf,
          mark: costs.marks[card.habitId] ?? const HabitMark(0),
          locale: formatLocale,
          top: top,
        ),
    ];
    return <Widget>[
      if (costs.firstDay case final DateTime first)
        CardFoot(InsightsPage.span(first)),
      if (view.updating)
        const CardFoot(InsightsPage.updating)
      else if (view.hoursPending)
        const CardFoot(InsightsPage.hoursAfterPending),
      _LastNightSection(vices: vices, marks: costs.marks),
      const CardSectionLabel(InsightsPage.costsHeading),
      if (costCards.isEmpty) costs.emptyBox(),
      for (int i = 0; i < shown; i++) costCards[i](i == 0 ? 0 : DialSpace.xs),
      // Always there: the drill-in also holds the refusals, the hours-after
      // note and, once settled, the Health card.
      DialCard(
        top: DialSpace.xs,
        children: <Widget>[
          CardRow(
            label: InsightsPage.moreCosts,
            value: hidden > 0 ? Text(InsightsPage.more(hidden)) : null,
            glyph: DialGlyph.right,
            onTap: () => Navigator.of(context).push(
              DialPageRoute<void>(builder: (_) => const InsightsCostsPage()),
            ),
          ),
        ],
      ),
      const CardSectionLabel(InsightsPage.cuttingDownHeading),
      if (cuttingDown.isEmpty)
        const NotYetBox(
          InsightsPage.cuttingDownTitle,
          body: InsightsPage.cuttingDownBody,
        ),
      for (final (int i, Widget Function(double) card) in cuttingDown.indexed)
        card(i == 0 ? 0 : DialSpace.xs),
      const CardSectionLabel(InsightsPage.setsOffHeading),
      if (costs.before.isEmpty &&
          costs.follows.isEmpty &&
          costs.calendar.isEmpty)
        const NotYetBox(
          InsightsPage.setsOffTitle,
          body: InsightsPage.setsOffBody,
        ),
      for (final (int i, BeforeUseCard card) in costs.before.indexed)
        BeforeUseCardView(
          card: card,
          habit: costs.nameOf(card.habitId),
          unit: costs.unitOf(card.habitId),
          mark: costs.marks[card.habitId] ?? const HabitMark(0),
          locale: formatLocale,
          top: i == 0 ? 0 : DialSpace.xs,
        ),
      for (final (int i, FollowsCard card) in costs.follows.indexed)
        HabitFollowsCard(
          card: card,
          nameOf: costs.nameOf,
          mark: costs.marks[card.habitId] ?? const HabitMark(0),
          top: i == 0 && costs.before.isEmpty ? 0 : DialSpace.xs,
        ),
      for (final (int i, AfterEvent finding) in costs.calendar.indexed)
        AfterEventCardView(
          finding: finding,
          habit: costs.nameOf(finding.habitId),
          mark: costs.marks[finding.habitId] ?? const HabitMark(0),
          locale: formatLocale,
          top: i == 0 && costs.before.isEmpty && costs.follows.isEmpty
              ? 0
              : DialSpace.xs,
        ),
      DialCard(
        children: <Widget>[
          CardRow(
            label: InsightsPage.copyLabel,
            subtitle: 'To the clipboard, for a note or a message',
            onTap: () => _copy(costs.text(_lastNightLines(costs.marks, vices))),
          ),
        ],
      ),
    ];
  }

  // The last-night section as the page shows it now, for the copied text.
  List<String> _lastNightLines(Map<String, HabitMark> marks, List<Vice> vices) {
    final LastNight? night = ref.read(lastNightProvider).value;
    if (night == null) return const <String>[];
    final DateTime today = ref.read(todayProvider);
    final List<ViceActivity>? journal = ref
        .read(viceActivityRangeProvider(insightsRange(today)))
        .value;
    return lastNightText(
      night,
      journal == null
          ? null
          : yesterdayLines(
              journal,
              vices,
              marks,
              today,
              alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(
                context,
              ),
            ),
    );
  }

  // Health findings reach the clipboard only from this tap; nothing else may
  // copy or send them.
  Future<void> _copy(String text) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: text));
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text(InsightsPage.copied)));
  }
}

// Read with values and nothing new to ask: the card only says so.
bool _healthSettled(HealthState state, bool askAgain) =>
    !askAgain && state is HealthReady && state.values.isNotEmpty;

/// "What it costs" in full: every card, the habits with nothing clear and
/// why, and the Health card once it has nothing to ask.
class InsightsCostsPage extends ConsumerWidget {
  const InsightsCostsPage({super.key});

  static const String lede =
      'What follows each habit in your sleep, heart, activity and mindfulness';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final InsightsView? view = ref.watch(insightsProvider).value;
    final List<Vice>? vices = ref.watch(viceListProvider).value;
    final bool askAgain = ref.watch(healthAskAgainProvider).value ?? false;
    final InsightsResult? result = view?.result;
    return CardPage(
      title: InsightsPage.costsHeading,
      children: <Widget>[
        const CardFoot(lede),
        if (view != null && result is InsightsComputed && vices != null)
          ..._body(_Costs(result, vices), view)
        else
          const _MessageCard(InsightsPage.loadingLabel, busy: true),
        if (view?.health case final HealthState health
            when _healthSettled(health, askAgain))
          _HealthCard(state: health, askAgain: false),
        const CardFoot(InsightsPage.foot),
      ],
    );
  }

  List<Widget> _body(_Costs costs, InsightsView view) => <Widget>[
    if (view.updating)
      const CardFoot(InsightsPage.updating)
    else if (view.hoursPending)
      const CardFoot(InsightsPage.hoursAfterPending)
    else if (costs.report.hoursAfterChecks > 0)
      const CardFoot(InsightsPage.hoursAfterNote),
    if (costs.cards.isEmpty && costs.recovery.isEmpty)
      Padding(
        padding: const EdgeInsets.only(top: DialSpace.l),
        child: costs.emptyBox(),
      ),
    for (final (int i, InsightCard card) in costs.cards.indexed)
      costs.card(card, top: i == 0 ? DialSpace.l : DialSpace.xs),
    for (final (int i, RecoveryCard card) in costs.recovery.indexed)
      costs.recoveryCard(
        card,
        top: i == 0 && costs.cards.isEmpty ? DialSpace.l : DialSpace.xs,
      ),
    if (costs.refused.isNotEmpty) ...<Widget>[
      const CardSectionLabel(InsightsPage.refusedHeading),
      DialCard(
        top: 0,
        children: <Widget>[
          for (final HabitRefusal r in costs.refused)
            CardRow(
              label: costs.nameOf(r.habitId),
              subtitle: refusalReason(
                r,
                costs.nameOf,
                floors: costs.report.floors,
              ),
            ),
        ],
      ),
    ],
    if (costs.shifts.isNotEmpty)
      const CardSectionLabel(InsightsPage.shiftsHeading),
    for (final (int i, MeasureShift shift) in costs.shifts.indexed)
      MeasureShiftCard(
        shift: shift,
        nameOf: costs.nameOf,
        locale: formatLocale,
        top: i == 0 ? 0 : DialSpace.xs,
      ),
    if (costs.shifts.isNotEmpty) const CardFoot(InsightsPage.shiftsNote),
  ];
}

// The report as both "What it costs" views show it: the habits the page
// knows, by name, unit and mark.
class _Costs {
  _Costs(InsightsComputed computed, List<Vice> vices)
    : report = computed.report,
      marks = habitMarks(vices),
      _names = <String, String>{for (final Vice v in vices) v.id: v.name},
      _units = <String, Unit>{for (final Vice v in vices) v.id: v.unit} {
    cards = insightCards(<HabitFinding>[
      for (final HabitFinding f in report.findings)
        if (_names.containsKey(f.habitId)) f,
    ], floors: report.floors);
    follows = followsCards(<HabitFollows>[
      for (final HabitFollows f in report.follows)
        if (_names.containsKey(f.leadId) && _names.containsKey(f.followerId)) f,
    ]);
    refused = <HabitRefusal>[
      for (final HabitRefusal r in report.refused)
        if (_names.containsKey(r.habitId)) r,
    ]..sort((a, b) => nameOf(a.habitId).compareTo(nameOf(b.habitId)));
    before = beforeUseCards(<BeforeUse>[
      for (final BeforeUse b in report.beforeUse)
        if (_names.containsKey(b.habitId)) b,
    ], floors: report.floors);
    final ({Map<(String, String), Recovery> joined, List<Recovery> rest})
    split = joinRecovery(cards, <Recovery>[
      for (final Recovery r in report.recovery)
        if (_names.containsKey(r.habitId)) r,
    ]);
    joined = split.joined;
    recovery = recoveryCards(split.rest);
    final List<PayoffCard> payoffs = payoffCards(<Payoff>[
      for (final Payoff p in report.payoffs)
        if (_names.containsKey(p.habitId)) p,
    ], floors: report.floors);
    final Map<String, DateTime> fellOn = <String, DateTime>{
      for (final PayoffCard p in payoffs) p.habitId: p.fall.day,
    };
    // A rise joins the payoff card stating the same fall, so the fall is
    // said once.
    final List<ReplacementCard> rises = replacementCards(<Replacement>[
      for (final Replacement r in report.replacements)
        if (_names.containsKey(r.habitId) && _names.containsKey(r.riserId)) r,
    ]);
    risers = <String, ReplacementCard>{
      for (final ReplacementCard r in rises)
        if (fellOn[r.habitId] == r.fall.day) r.habitId: r,
    };
    replacements = <ReplacementCard>[
      for (final ReplacementCard r in rises)
        if (!risers.containsKey(r.habitId)) r,
    ];
    fallCards = <PayoffCard>[
      for (final PayoffCard p in payoffs)
        if (p.findings.isNotEmpty || risers.containsKey(p.habitId)) p,
    ];
    payoffRows = <PayoffCard>[
      for (final PayoffCard p in payoffs)
        if (p.findings.isEmpty && !risers.containsKey(p.habitId)) p,
    ];
    calendar = afterEventCards(<AfterEvent>[
      for (final AfterEvent a in report.afterEvent)
        if (_names.containsKey(a.habitId)) a,
    ]);
    shifts = <MeasureShift>[
      for (final MeasureShift s in report.shifts)
        MeasureShift(
          metricId: s.metricId,
          shift: s.shift,
          found: s.found,
          habits: <HabitChange>[
            for (final HabitChange c in s.habits)
              if (_names.containsKey(c.habitId)) c,
          ],
        ),
    ];
    // A legacy entry of a vice that is gone would date the span from a habit
    // the page doesn't show.
    firstDay = insightsFirstDay(computed.firstDays, _names.containsKey);
  }

  final InsightsReport report;
  final Map<String, HabitMark> marks;
  final Map<String, String> _names;
  final Map<String, Unit> _units;
  late final List<InsightCard> cards;
  late final List<HabitRefusal> refused;
  late final List<BeforeUseCard> before;
  late final List<RecoveryCard> recovery;

  /// Recovery joined to the line in the amount on its habit and measure.
  late final Map<(String, String), Recovery> joined;

  Recovery? recoveryOf(HabitFinding f) =>
      f.kind == InsightKind.doseLine ? joined[(f.habitId, f.metricId)] : null;

  /// Falls shown as cards, in order, and the rest as rows after them.
  late final List<PayoffCard> fallCards;
  late final List<PayoffCard> payoffRows;

  /// Rises by the habit that fell, joined to its payoff card.
  late final Map<String, ReplacementCard> risers;

  /// Rises with no payoff card for the same fall, each a card of its own.
  late final List<ReplacementCard> replacements;
  late final List<AfterEvent> calendar;
  late final List<FollowsCard> follows;
  late final List<MeasureShift> shifts;
  late final DateTime? firstDay;

  String nameOf(String id) => _names[id] ?? 'a removed habit';
  Unit unitOf(String id) => _units[id] ?? Unit.fallback;

  Widget card(InsightCard card, {required double top}) => _FindingCard(
    card: card,
    habit: nameOf(card.habitId),
    unit: unitOf(card.habitId),
    mark: marks[card.habitId] ?? const HabitMark(0),
    locale: formatLocale,
    top: top,
    recoveryOf: recoveryOf,
  );

  Widget recoveryCard(RecoveryCard card, {required double top}) =>
      RecoveryCardView(
        card: card,
        habit: nameOf(card.habitId),
        unit: unitOf(card.habitId),
        mark: marks[card.habitId] ?? const HabitMark(0),
        locale: formatLocale,
        top: top,
      );

  // With no card: every habit still short of the days a comparison needs
  // says how far the furthest along has come; otherwise nothing is clear.
  ({String title, String body, double? progress}) emptyCopy() {
    const InsightGates gates = InsightGates();
    final bool early =
        refused.isNotEmpty &&
        refused.every(
          (HabitRefusal r) =>
              r.reason == RefusalReason.tooFewDays &&
              r.usableDays < gates.minDays,
        );
    if (!early) {
      return (
        title: InsightsPage.nothingClear,
        body: InsightsPage.nothingClearBody,
        progress: null,
      );
    }
    final int have = refused.map((HabitRefusal r) => r.usableDays).reduce(max);
    return (
      title: InsightsPage.earlyTitle,
      body: InsightsPage.earlyBody(have, gates.minDays),
      progress: have / gates.minDays,
    );
  }

  Widget emptyBox() {
    final ({String title, String body, double? progress}) copy = emptyCopy();
    return NotYetBox(copy.title, body: copy.body, progress: copy.progress);
  }

  String text(List<String> lastNight) {
    final ({String title, String body, double? progress}) empty = emptyCopy();
    return insightsText(
      cards: cards,
      refused: refused,
      floors: report.floors,
      firstDay: firstDay,
      nameOf: nameOf,
      unitOf: unitOf,
      locale: formatLocale,
      lastNight: lastNight,
      emptyTitle: empty.title,
      emptyBody: empty.body,
      recoveryOf: recoveryOf,
      recovery: <List<String>>[
        for (final RecoveryCard card in recovery)
          recoveryText(
            card,
            nameOf(card.habitId),
            formatLocale,
            unit: unitOf(card.habitId),
          ),
      ],
      cuttingDown: <List<String>>[
        for (final PayoffCard card in <PayoffCard>[...fallCards, ...payoffRows])
          <String>[
            ...payoffText(
              card,
              nameOf(card.habitId),
              formatLocale,
              unit: unitOf(card.habitId),
            ),
            if (risers[card.habitId] case final ReplacementCard rise)
              ...replacementRiserText(rise, nameOf, unitOf, formatLocale),
          ],
        for (final ReplacementCard card in replacements)
          replacementText(card, nameOf, unitOf, formatLocale),
      ],
      setsOff: <List<String>>[
        for (final BeforeUseCard card in before)
          beforeUseText(
            card,
            nameOf(card.habitId),
            formatLocale,
            unit: unitOf(card.habitId),
          ),
        for (final FollowsCard card in follows) followsText(card, nameOf),
        for (final AfterEvent a in calendar)
          afterEventText(a, nameOf(a.habitId), formatLocale),
      ],
      shifts: <List<String>>[
        for (final MeasureShift s in shifts)
          measureShiftText(s, formatDate(s.shift.at), nameOf, formatLocale),
      ],
    );
  }
}

/// The page as it shows it, in plain text: last night's rows ([lastNight],
/// from [lastNightText]), then the findings and refusals.
String insightsText({
  required List<InsightCard> cards,
  required List<HabitRefusal> refused,
  Map<String, double> floors = const <String, double>{},
  required DateTime? firstDay,
  required String Function(String habitId) nameOf,
  Unit Function(String habitId) unitOf = _anyUnit,
  required String locale,
  List<String> lastNight = const <String>[],
  String emptyTitle = InsightsPage.nothingClear,
  String emptyBody = InsightsPage.nothingClearBody,
  Recovery? Function(HabitFinding line) recoveryOf = _noRecovery,
  List<List<String>> recovery = const <List<String>>[],
  List<List<String>> cuttingDown = const <List<String>>[],
  List<List<String>> setsOff = const <List<String>>[],
  List<List<String>> shifts = const <List<String>>[],
}) {
  final StringBuffer out = StringBuffer(InsightsPage.title);
  if (firstDay != null) out.write('\n${InsightsPage.span(firstDay)}');
  if (lastNight.isNotEmpty) {
    out.write('\n\n${InsightsPage.lastNightHeading}');
    for (final String line in lastNight) {
      out.write('\n$line');
    }
  }
  out.write('\n\n${InsightsPage.costsHeading}\n');
  if (cards.isEmpty && recovery.isEmpty) {
    out.write('$emptyTitle: $emptyBody\n');
  }
  for (final InsightCard card in cards) {
    final HabitFinding f = card.headline;
    final String habit = nameOf(f.habitId);
    final Unit unit = unitOf(f.habitId);
    final String? bedtime = bedtimeLine(f, locale, unit: unit);
    final Recovery? after = recoveryOf(f);
    out
      ..write('\n$habit · ${card.family.label}\n')
      ..write(
        after == null
            ? '${findingSentence(f, habit, locale, unit: unit)}\n'
            : '${recoveryJoinedSentence(f, after, habit, locale, unit: unit)}\n',
      )
      ..write(bedtime == null ? '' : '$bedtime\n')
      ..write('${findingRange(f, locale)}\n')
      ..write('${findingBasis(f, habit, locale: locale, unit: unit)}\n');
    if (findingEvidence(f) case final String evidence) {
      out.write('$evidence\n');
    }
    if (after != null) {
      out
        ..write('${recoveryRange(after, locale, joined: true)}\n')
        ..write(
          '${recoveryJoinedBasis(f, after, locale: locale, unit: unit)}\n',
        );
    }
    for (final HabitFinding other in card.others) {
      out.write(switch (recoveryOf(other)) {
        final Recovery r =>
          '${recoveryJoinedLine(other, r, locale, unit: unit)}\n',
        null => '${findingLine(other, locale, unit: unit)}\n',
      });
    }
  }
  for (final List<String> card in recovery) {
    out.write('\n${card.join('\n')}\n');
  }
  if (refused.isNotEmpty) {
    out.write('\n${InsightsPage.refusedHeading}\n');
    for (final HabitRefusal r in refused) {
      out.write(
        '${nameOf(r.habitId)}: ${refusalReason(r, nameOf, floors: floors)}\n',
      );
    }
  }
  if (shifts.isNotEmpty) {
    out.write('\n${InsightsPage.shiftsHeading}\n');
    for (final List<String> card in shifts) {
      out.write('\n${card.join('\n')}\n');
    }
    out.write('\n${InsightsPage.shiftsNote}\n');
  }
  if (cuttingDown.isNotEmpty) {
    out.write('\n${InsightsPage.cuttingDownHeading}\n');
    for (final List<String> card in cuttingDown) {
      out.write('\n${card.join('\n')}\n');
    }
  }
  if (setsOff.isNotEmpty) {
    out.write('\n${InsightsPage.setsOffHeading}\n');
    for (final List<String> card in setsOff) {
      out.write('\n${card.join('\n')}\n');
    }
  }
  out.write('\n${InsightsPage.foot}\n');
  return out.toString();
}

Unit _anyUnit(String _) => Unit.fallback;

Recovery? _noRecovery(HabitFinding _) => null;

class _HealthCard extends StatelessWidget {
  const _HealthCard({
    required this.state,
    required this.askAgain,
    this.connecting = false,
    this.onConnect,
  });

  final HealthState? state;

  /// Connected before the app read a type it reads now.
  final bool askAgain;
  final bool connecting;

  /// Shows the Health sheet; null where no state offers it.
  final VoidCallback? onConnect;

  @override
  Widget build(BuildContext context) {
    CardRow sheetRow(String label, String subtitle) => CardRow(
      label: label,
      subtitle: subtitle,
      enabled: !connecting,
      glyph: connecting ? null : DialGlyph.right,
      trailing: connecting
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : null,
      onTap: onConnect,
    );
    final Widget row = switch (state) {
      HealthNotConnected() => sheetRow(
        InsightsPage.connectLabel,
        'Sleep, heart and activity totals, read on this iPhone only',
      ),
      HealthReady() when askAgain => sheetRow(
        InsightsPage.askAgainLabel,
        InsightsPage.askAgainBody,
      ),
      HealthOnIPhone() => const CardRow(
        label: 'Apple Health',
        subtitle: 'Health data stays on your iPhone',
        value: Text(InsightsPage.onIPhone),
      ),
      HealthUnsupported() => const CardRow(
        label: 'Apple Health',
        value: Text('Not on this device'),
      ),
      null => const CardRow(label: 'Apple Health'),
      HealthReady(:final values) when values.isEmpty => const CardRow(
        label: 'Apple Health',
        subtitle: 'Nothing shared, or access not allowed',
        value: Text(InsightsPage.noHealthDataValue),
      ),
      _ => const CardRow(
        label: 'Apple Health',
        subtitle: 'Read on this iPhone only',
        value: Text('Connected'),
      ),
    };
    return DialCard(
      children: <Widget>[
        row,
        // A type refused on the sheet is never asked again; only Settings
        // changes it. An empty Health already says so below the card.
        if (state case HealthReady(:final values) when values.isNotEmpty)
          const CardRow(
            label: InsightsPage.manageLabel,
            subtitle: InsightsPage.manageBody,
          ),
      ],
    );
  }
}

/// Asks for calendar access, or says where to allow it once refused.
class _CalendarCard extends StatelessWidget {
  const _CalendarCard({
    required this.access,
    required this.connecting,
    required this.onConnect,
  });

  final CalendarAccess access;
  final bool connecting;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) => DialCard(
    children: <Widget>[
      if (access == CalendarAccess.notDetermined)
        CardRow(
          label: InsightsPage.calendarLabel,
          subtitle: InsightsPage.calendarBody,
          enabled: !connecting,
          glyph: connecting ? null : DialGlyph.right,
          trailing: connecting
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : null,
          onTap: onConnect,
        )
      else
        const CardRow(
          label: InsightsPage.calendarOffLabel,
          subtitle: InsightsPage.calendarOffBody,
          value: Text(InsightsPage.calendarOffValue),
        ),
    ],
  );
}

class _MessageCard extends StatelessWidget {
  const _MessageCard(this.title, {this.body, this.busy = false, this.onRetry});

  final String title;
  final String? body;
  final bool busy;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final DialColors colors = DialColors.of(context);
    final bool still = MediaQuery.disableAnimationsOf(context);
    return DialCard(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          child: Semantics(
            liveRegion: busy,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        title,
                        style: DialTypeScale.bodyL.copyWith(
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurface,
                        ),
                      ),
                    ),
                    if (busy && !still)
                      const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                  ],
                ),
                if (body != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      body!,
                      style: DialTypeScale.body.copyWith(color: colors.muted),
                    ),
                  ),
                if (onRetry != null)
                  Padding(
                    padding: const EdgeInsets.only(top: DialSpace.xs),
                    child: TextButton(
                      onPressed: onRetry,
                      child: const Text('Try again'),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _FindingCard extends StatelessWidget {
  const _FindingCard({
    required this.card,
    required this.habit,
    required this.unit,
    required this.mark,
    required this.locale,
    required this.top,
    this.recoveryOf = _noRecovery,
  });

  final InsightCard card;
  final String habit;
  final Unit unit;
  final HabitMark mark;
  final String locale;
  final double top;
  final Recovery? Function(HabitFinding line) recoveryOf;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final DialColors colors = DialColors.of(context);
    final HabitFinding finding = card.headline;
    final TextStyle small = DialTypeScale.bodyS.copyWith(color: colors.muted);
    final String? bedtime = bedtimeLine(finding, locale, unit: unit);
    final Recovery? after = recoveryOf(finding);
    return DialCard(
      top: top,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  HabitPip(mark: mark),
                  const SizedBox(width: DialSpace.xs),
                  Expanded(
                    child: Text(
                      '$habit · ${card.family.label}',
                      style: DialTypeScale.label.copyWith(color: colors.muted),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                after == null
                    ? findingSentence(finding, habit, locale, unit: unit)
                    : recoveryJoinedSentence(
                        finding,
                        after,
                        habit,
                        locale,
                        unit: unit,
                      ),
                style: DialTypeScale.bodyL.copyWith(color: scheme.onSurface),
              ),
              if (bedtime != null) ...<Widget>[
                const SizedBox(height: DialSpace.xs),
                Text(
                  bedtime,
                  style: DialTypeScale.bodyS.copyWith(color: scheme.onSurface),
                ),
              ],
              const SizedBox(height: DialSpace.s),
              ExcludeSemantics(
                child: SizedBox(
                  height: 14,
                  width: double.infinity,
                  child: CustomPaint(
                    painter: _RangePainter(
                      finding: finding,
                      ink: scheme.onSurface,
                      surface: scheme.surfaceContainerLow,
                      zero: colors.spoke,
                      track: colors.line,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: DialSpace.xs),
              Text(findingRange(finding, locale), style: small),
              Text(
                findingBasis(finding, habit, locale: locale, unit: unit),
                style: small,
              ),
              if (findingEvidence(finding) case final String evidence)
                Text(evidence, style: small),
              if (after != null) ...<Widget>[
                Text(recoveryRange(after, locale, joined: true), style: small),
                Text(
                  recoveryJoinedBasis(
                    finding,
                    after,
                    locale: locale,
                    unit: unit,
                  ),
                  style: small,
                ),
              ],
              if (card.others.isNotEmpty) const SizedBox(height: DialSpace.s),
              for (final HabitFinding other in card.others)
                Text(
                  switch (recoveryOf(other)) {
                    final Recovery r => recoveryJoinedLine(
                      other,
                      r,
                      locale,
                      unit: unit,
                    ),
                    null => findingLine(other, locale, unit: unit),
                  },
                  style: DialTypeScale.bodyS.copyWith(color: scheme.onSurface),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// The range as a bar beside a zero tick, on a track scaled so both fit with
// room either side. The words above carry the numbers; this only shows how far
// the range sits from zero.
class _RangePainter extends CustomPainter {
  _RangePainter({
    required this.finding,
    required this.ink,
    required this.surface,
    required this.zero,
    required this.track,
  });

  final HabitFinding finding;
  final Color ink;
  final Color surface;
  final Color zero;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final double low = finding.interval.low, high = finding.interval.high;
    final double reach = <double>[
      low.abs(),
      high.abs(),
    ].reduce((a, b) => a > b ? a : b);
    if (reach == 0) return;
    double x(double v) => size.width / 2 + v / reach * (size.width / 2 - 6);
    final double mid = size.height / 2;
    canvas
      ..drawLine(
        Offset(0, mid),
        Offset(size.width, mid),
        Paint()
          ..color = track
          ..strokeWidth = 2,
      )
      ..drawLine(
        Offset(x(0), 0),
        Offset(x(0), size.height),
        Paint()
          ..color = zero
          ..strokeWidth = 2,
      )
      ..drawLine(
        Offset(x(low), mid),
        Offset(x(high), mid),
        Paint()
          ..color = ink
          ..strokeWidth = 6
          ..strokeCap = StrokeCap.round,
      )
      ..drawCircle(Offset(x(finding.effect), mid), 6, Paint()..color = ink)
      ..drawCircle(Offset(x(finding.effect), mid), 3, Paint()..color = surface);
  }

  @override
  bool shouldRepaint(_RangePainter old) =>
      old.finding != finding ||
      old.ink != ink ||
      old.surface != surface ||
      old.zero != zero ||
      old.track != track;
}

/// The full last-night check, at the top of Insights: sleeping heart rate,
/// HRV and time asleep against the nights before, and what was logged the
/// day before. Today's line is its first row. Nothing while Health is read.
class _LastNightSection extends ConsumerWidget {
  const _LastNightSection({required this.vices, required this.marks});

  final List<Vice> vices;
  final Map<String, HabitMark> marks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final LastNight? night = ref.watch(lastNightProvider).value;
    if (night == null) return const SizedBox.shrink();
    final DateTime today = ref.watch(todayProvider);
    // The page's own journal read, so this costs no query of its own; no
    // "nothing logged" before it answers.
    final List<ViceActivity>? journal = ref
        .watch(viceActivityRangeProvider(insightsRange(today)))
        .value;
    final List<Widget> rows = <Widget>[
      for (final NightRow row in nightRows(night))
        _NightRow(label: row.label, value: row.value, note: row.note),
      if (journal != null)
        for (final YesterdayLine line in yesterdayLines(
          journal,
          vices,
          marks,
          today,
          alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
        ))
          _YesterdayRow(mark: line.mark, text: line.text),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const CardSectionLabel(InsightsPage.lastNightHeading),
        DialCard(top: 0, inset: 0, children: rows),
      ],
    );
  }
}

/// One measure's row: its label, each number with its unit ("6 h 50 m" is
/// two) and the note against the usual.
typedef NightRow = ({String label, List<(String, String)> value, String note});

/// The rows of the last-night check, in the order shown.
List<NightRow> nightRows(LastNight night) => <NightRow>[
  if (night.sleepingHeartRate case final NightCompare c)
    (
      label: 'Sleeping heart rate',
      value: <(String, String)>[('${c.shownValue}', 'bpm')],
      note: lastNightHeartNote(c),
    ),
  if (night.heartRateVariability case final NightCompare c)
    (
      label: 'HRV',
      value: <(String, String)>[('${c.shownValue}', 'ms')],
      note: lastNightHrvNote(c),
    ),
  if (night.asleep case final NightCompare c)
    (
      label: 'Sleep',
      value: <(String, String)>[
        ('${c.shownValue ~/ 60}', 'h'),
        ('${c.shownValue % 60}', 'm'),
      ],
      note: lastNightSleepNote(c),
    ),
];

/// "Yesterday: Wine 3 drinks, last at 22:05", with the habit's mark; or the
/// one line saying nothing was logged.
typedef YesterdayLine = ({HabitMark? mark, String text});

/// What was logged the day before, as the engine keys it: a use before
/// 05:00 counts to the evening before, so last night's drinks after midnight
/// are yesterday's. Habits in creation order; archived ones left out.
List<YesterdayLine> yesterdayLines(
  List<ViceActivity> journal,
  List<Vice> vices,
  Map<String, HabitMark> marks,
  DateTime today, {
  required bool alwaysUse24HourFormat,
}) {
  final DateTime from = addDays(
    today,
    -1,
  ).add(const Duration(hours: lateUseCutoffHour));
  final DateTime to = today.add(const Duration(hours: lateUseCutoffHour));
  final Map<String, ({num total, DateTime last})> used =
      <String, ({num total, DateTime last})>{};
  for (final ViceActivity a in journal) {
    final DateTime at = a.createdAt.toDate();
    if (at.isBefore(from) || !at.isBefore(to)) continue;
    final ({num total, DateTime last})? had = used[a.viceID];
    used[a.viceID] = (
      total: (had?.total ?? 0) + a.measure,
      last: had == null || at.isAfter(had.last) ? at : had.last,
    );
  }
  final List<Vice> shown = <Vice>[
    for (final Vice v in vices)
      if (!v.archived && used.containsKey(v.id)) v,
  ]..sort((a, b) => marks[a.id]!.creationIndex - marks[b.id]!.creationIndex);
  if (shown.isEmpty) {
    return const <YesterdayLine>[
      (mark: null, text: 'Nothing logged yesterday'),
    ];
  }
  return <YesterdayLine>[
    for (final Vice v in shown)
      (
        mark: marks[v.id],
        text:
            'Yesterday: ${v.name} ${v.unit.label(used[v.id]!.total)}, '
            'last at ${formatTime(used[v.id]!.last, alwaysUse24HourFormat: alwaysUse24HourFormat)}',
      ),
  ];
}

/// The check as text, one row a line: "Sleeping heart rate: 57 bpm, usual
/// 54 · 3 above". [yesterday] is null while the journal has not answered.
List<String> lastNightText(
  LastNight night,
  List<YesterdayLine>? yesterday,
) => <String>[
  for (final NightRow row in nightRows(night))
    '${row.label}: '
        '${row.value.map(((String, String) v) => '${v.$1} ${v.$2}').join(' ')}'
        ', ${row.note}',
  if (yesterday != null)
    for (final YesterdayLine line in yesterday) line.text,
];

/// "usual 54 · 3 above", "usual 54 · in your usual range".
String lastNightHeartNote(NightCompare c) =>
    'usual ${c.shownUsual} · ${switch (c.side) {
      NightSide.above => '${c.shownBy} above',
      NightSide.below => '${c.shownBy} below',
      NightSide.usual => 'in your usual range',
    }}';

/// "usual range 45–51 · below"; a range whose ends round to one number is
/// "usual 48".
String lastNightHrvNote(NightCompare c) {
  final int low = c.low.round();
  final int high = c.high.round();
  final String usual = low == high ? 'usual $low' : 'usual range $low–$high';
  return '$usual · ${switch (c.side) {
    NightSide.above => 'above',
    NightSide.below => 'below',
    NightSide.usual => low == high ? 'in your usual range' : 'within it',
  }}';
}

/// "usual 7 h 15 m · 25 min under".
String lastNightSleepNote(NightCompare c) =>
    'usual ${formatSleep(c.usual)} · ${switch (c.side) {
      NightSide.above => '${c.shownBy} min over',
      NightSide.below => '${c.shownBy} min under',
      NightSide.usual => 'in your usual range',
    }}';

/// Minutes as "6 h 50 m".
String formatSleep(double minutes) {
  final int whole = minutes.round();
  return '${whole ~/ 60} h ${whole % 60} m';
}

class _NightRow extends StatelessWidget {
  const _NightRow({
    required this.label,
    required this.value,
    required this.note,
  });

  final String label;

  /// Each number with its unit: "6 h 50 m" is two.
  final List<(String, String)> value;
  final String note;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final DialColors colors = DialColors.of(context);
    final DialType type = DialType.of(context);
    final TextStyle small = DialTypeScale.bodyS.copyWith(color: colors.muted);
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: <Widget>[
                Expanded(
                  child: Text(
                    label,
                    style: DialTypeScale.body.copyWith(color: scheme.onSurface),
                  ),
                ),
                Text.rich(
                  TextSpan(
                    children: <InlineSpan>[
                      for (final (int i, (String number, String unit))
                          in value.indexed) ...<InlineSpan>[
                        TextSpan(text: number, style: type.monoM),
                        TextSpan(
                          text: i == value.length - 1 ? ' $unit' : ' $unit ',
                          style: small,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(note, style: small),
          ],
        ),
      ),
    );
  }
}

class _YesterdayRow extends StatelessWidget {
  const _YesterdayRow({required this.text, this.mark});

  final String text;
  final HabitMark? mark;

  @override
  Widget build(BuildContext context) {
    final DialColors colors = DialColors.of(context);
    final HabitMark? mark = this.mark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
      child: Row(
        children: <Widget>[
          if (mark != null) ...<Widget>[
            HabitPip(mark: mark),
            const SizedBox(width: DialSpace.xs),
          ],
          Expanded(
            child: Text(
              text,
              style: DialTypeScale.bodyS.copyWith(color: colors.muted),
            ),
          ),
        ],
      ),
    );
  }
}
