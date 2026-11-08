import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/design/dial_icons.dart';
import 'package:tracker/design/dial_theme.dart';
import 'package:tracker/design/habit_mark.dart';
import 'package:tracker/design/tokens.dart';
import 'package:tracker/formats.dart';
import 'package:tracker/providers/vice_activity_day_provider.dart';
import 'package:tracker/widgets/circle_button.dart';

// The day navigation over the dial: the day before, the date pill that opens
// the calendar, and the day after. There are no future days.
class DayPicker extends StatelessWidget {
  const DayPicker({
    super.key,
    required this.day,
    required this.today,
    required this.onSelect,
    required this.marks,
    required this.habits,
  });

  final DateTime day;
  final DateTime today;
  final ValueChanged<DateTime> onSelect;
  // For the calendar's dots: each unarchived habit and its mark.
  final List<Vice> habits;
  final Map<String, HabitMark> marks;

  static const String chooseDay = 'Choose a day';

  Future<void> _openCalendar(BuildContext context) async {
    final DateTime? picked = await showModalBottomSheet<DateTime>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (BuildContext context) => CalendarSheet(
        selected: day,
        today: today,
        habits: habits,
        marks: marks,
      ),
    );
    if (picked != null) {
      onSelect(picked);
    }
  }

  Widget _pillContent(BuildContext context, DialColors colors, DialType type) {
    final List<Widget> parts = <Widget>[
      Text(dayWord(day, today), style: type.displayM.copyWith(height: 1.2)),
      Text(
        dayPillDate(day, today),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: DialTypeScale.bodyS.copyWith(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: colors.muted,
        ),
      ),
    ];
    final Widget chevron = StrokeIcon(
      DialGlyph.down,
      size: 14,
      color: colors.muted,
    );
    if (MediaQuery.textScalerOf(context).scale(1) > 1.3) {
      return Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.center,
        spacing: 8,
        children: <Widget>[...parts, chevron],
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Flexible(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: <Widget>[
              parts[0],
              const SizedBox(width: 8),
              Flexible(child: parts[1]),
            ],
          ),
        ),
        const SizedBox(width: 8),
        chevron,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final DialColors colors = DialColors.of(context);
    final DialType type = DialType.of(context);
    final bool isToday = daysBetween(day, today) <= 0;

    return Row(
      children: <Widget>[
        CircleButton(
          icon: DialGlyph.left,
          tooltip: 'Previous day',
          onPressed: () => onSelect(addDays(day, -1)),
        ),
        const SizedBox(width: DialSpace.xs),
        Expanded(
          child: Center(
            child: Tooltip(
              message: chooseDay,
              child: DecoratedBox(
                decoration: ShapeDecoration(
                  shape: const StadiumBorder(),
                  shadows: DialShadows.card(Theme.of(context).brightness),
                ),
                child: Material(
                  color: scheme.surfaceContainerLow,
                  shape: StadiumBorder(side: BorderSide(color: colors.line)),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => _openCalendar(context),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        minHeight: DialSize.minTapTarget,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 6,
                        ),
                        // The day and the date share a baseline, as in the
                        // mock-up; at large text they wrap instead.
                        child: _DaySlide(
                          day: day,
                          child: _pillContent(context, colors, type),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: DialSpace.xs),
        CircleButton(
          icon: DialGlyph.right,
          tooltip: 'Next day',
          onPressed: isToday ? null : () => onSelect(addDays(day, 1)),
        ),
      ],
    );
  }
}

// On a day change the pill's text slides in from the side the new day lies
// on, as the mock-up's day label does; under reduce motion it just changes.
class _DaySlide extends StatefulWidget {
  const _DaySlide({required this.day, required this.child});

  final DateTime day;
  final Widget child;

  @override
  State<_DaySlide> createState() => _DaySlideState();
}

class _DaySlideState extends State<_DaySlide>
    with SingleTickerProviderStateMixin {
  static const double _travel = 18;

  late final AnimationController _in = AnimationController(
    vsync: this,
    animationBehavior: AnimationBehavior.preserve,
    duration: DialMotion.tallyRoll,
    value: 1,
  );
  double _from = 1;

  @override
  void didUpdateWidget(_DaySlide old) {
    super.didUpdateWidget(old);
    if (old.day == widget.day) {
      return;
    }
    if (MediaQuery.disableAnimationsOf(context)) {
      _in.value = 1;
      return;
    }
    _from = widget.day.isAfter(old.day) ? 1 : -1;
    _in.forward(from: 0);
  }

  @override
  void dispose() {
    _in.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _in,
    child: widget.child,
    builder: (BuildContext context, Widget? child) {
      final double k = DialMotion.enter.transform(_in.value);
      return Opacity(
        opacity: k,
        child: Transform.translate(
          offset: Offset(_from * _travel * (1 - k), 0),
          child: child,
        ),
      );
    },
  );
}

// A month of days, Monday first, with a dot under each day for each habit
// logged on it. Picking a day pops the sheet with it.
class CalendarSheet extends ConsumerStatefulWidget {
  const CalendarSheet({
    super.key,
    required this.selected,
    required this.today,
    required this.habits,
    required this.marks,
  });

  final DateTime selected;
  final DateTime today;
  final List<Vice> habits;
  final Map<String, HabitMark> marks;

  static const String footnote =
      'A dot for each habit logged that day. Tap a day to open its dial.';

  // Which of [habits] have an entry on each day of the month, by day number.
  static Map<int, List<Vice>> loggedByDay(
    List<Vice> habits,
    List<ViceActivity> activities,
  ) {
    final Map<int, Set<String>> ids = <int, Set<String>>{};
    for (final ViceActivity a in activities) {
      (ids[a.createdAt.toDate().day] ??= <String>{}).add(a.viceID);
    }
    return <int, List<Vice>>{
      for (final MapEntry<int, Set<String>>(:key, :value) in ids.entries)
        key: <Vice>[
          for (final Vice v in habits)
            if (value.contains(v.id)) v,
        ],
    };
  }

  @override
  ConsumerState<CalendarSheet> createState() => _CalendarSheetState();
}

class _CalendarSheetState extends ConsumerState<CalendarSheet> {
  late DateTime _month = DateTime(widget.selected.year, widget.selected.month);

  bool get _isCurrentMonth =>
      _month.year == widget.today.year && _month.month == widget.today.month;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final DialColors colors = DialColors.of(context);
    final DialType type = DialType.of(context);
    final List<ViceActivity> activities =
        ref.watch(viceActivityMonthProvider(_month)).value ??
        const <ViceActivity>[];
    final Map<int, List<Vice>> logged = CalendarSheet.loggedByDay(
      widget.habits,
      activities,
    );

    final int lead = DateTime(_month.year, _month.month).weekday - 1;
    final int days = DateTime(_month.year, _month.month + 1, 0).day;
    final MaterialLocalizations l10n = MaterialLocalizations.of(context);
    // Material's narrow weekdays start on Sunday.
    final List<String> weekdays = <String>[
      for (int i = 1; i <= 7; i++) l10n.narrowWeekdays[i % 7],
    ];

    Widget cell(int dayNumber) {
      final DateTime date = DateTime(_month.year, _month.month, dayNumber);
      final bool future = date.isAfter(widget.today);
      final bool selected = date == widget.selected;
      final bool isToday = date == widget.today;
      final List<Vice> dots = logged[dayNumber] ?? const <Vice>[];

      return Opacity(
        opacity: future ? 0.3 : 1,
        child: Semantics(
          button: !future,
          selected: selected,
          label:
              '${formatDay(date)}${dots.isEmpty ? '' : ', ${dots.map((Vice v) => v.name).join(', ')}'}',
          excludeSemantics: true,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: future ? null : () => Navigator.of(context).pop(date),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: DialSize.minTapTarget + 8,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  DecoratedBox(
                    decoration: ShapeDecoration(
                      color: selected ? scheme.primary : null,
                      shape: CircleBorder(
                        side: isToday && !selected
                            ? BorderSide(color: scheme.primary, width: 1.5)
                            : BorderSide.none,
                      ),
                    ),
                    child: SizedBox.square(
                      dimension: 34,
                      child: Center(
                        child: Text(
                          formatCount(dayNumber),
                          style: type.monoM.copyWith(
                            color: selected ? scheme.onPrimary : null,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 2,
                    runSpacing: 2,
                    children: <Widget>[
                      for (final Vice v in dots)
                        if (widget.marks[v.id] case final HabitMark mark)
                          DecoratedBox(
                            decoration: BoxDecoration(
                              color: colors.habitInk(mark),
                              shape: BoxShape.circle,
                            ),
                            child: const SizedBox.square(dimension: 4),
                          ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, DialSpace.xxl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              CircleButton(
                icon: DialGlyph.left,
                tooltip: 'Previous month',
                onPressed: () => setState(
                  () => _month = DateTime(_month.year, _month.month - 1),
                ),
              ),
              Expanded(
                child: Text(
                  formatMonth(_month),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge,
                ),
              ),
              CircleButton(
                icon: DialGlyph.right,
                tooltip: 'Next month',
                onPressed: _isCurrentMonth
                    ? null
                    : () => setState(
                        () => _month = DateTime(_month.year, _month.month + 1),
                      ),
              ),
            ],
          ),
          const SizedBox(height: DialSpace.s),
          ExcludeSemantics(
            child: Row(
              children: <Widget>[
                for (final String w in weekdays)
                  Expanded(
                    child: Text(
                      w,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: colors.muted,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: DialSpace.xs),
          for (int week = 0; week * 7 < lead + days; week++)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                for (int i = 0; i < 7; i++)
                  Expanded(
                    child: switch (week * 7 + i - lead + 1) {
                      final int n when n >= 1 && n <= days => cell(n),
                      _ => const SizedBox.shrink(),
                    },
                  ),
              ],
            ),
          const SizedBox(height: DialSpace.m),
          Text(
            CalendarSheet.footnote,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(color: colors.muted),
          ),
        ],
      ),
    );
  }
}
