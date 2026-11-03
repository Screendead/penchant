import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:tracker/mockups/today_layout/fixtures.dart';
import 'package:tracker/providers/unarchived_vice_list_provider.dart';
import 'package:tracker/providers/vice_activity_day_provider.dart';
import 'package:tracker/vice_chart.dart';

final DateFormat _time = DateFormat('HH:mm');
final DateFormat _longDate = DateFormat('EEEE, d MMMM');

/// The shipped day chart (C2: bars below three vices, radar from three) fed
/// the mock day through the providers it reads in the app.
class DayChartSlot extends StatelessWidget {
  const DayChartSlot({super.key, required this.day, required this.height});

  final MockDay day;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: ProviderScope(
        overrides: [
          unarchivedViceListProvider.overrideWith(
            (ref) => Stream.value([for (final v in day.vices) v.vice]),
          ),
          viceActivityDayProvider.overrideWith(
            (ref, DateTime _) => Stream.value(day.activities),
          ),
        ],
        child: ViceChart(selectedDate: day.date),
      ),
    );
  }
}

class MockTodayScaffold extends StatelessWidget {
  const MockTodayScaffold({
    super.key,
    required this.body,
    this.actions = const [],
  });

  final Widget body;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const Icon(Icons.menu),
        title: const Text('Today'),
        actions: actions,
      ),
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: 0,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.today_outlined),
            selectedIcon: Icon(Icons.today),
            label: 'Today',
          ),
          NavigationDestination(
            icon: Icon(Icons.show_chart_outlined),
            selectedIcon: Icon(Icons.show_chart),
            label: 'Trends',
          ),
        ],
      ),
    );
  }
}

/// Date with previous and next; the day also changes by swiping the page.
class DayHeader extends StatelessWidget {
  const DayHeader({super.key, required this.day});

  final MockDay day;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Row(
      children: [
        IconButton(
          tooltip: 'Previous day',
          onPressed: () {},
          icon: const Icon(Icons.chevron_left),
        ),
        Expanded(
          child: Column(
            children: [
              Text(
                _longDate.format(day.date),
                style: theme.textTheme.titleMedium,
              ),
              Text(
                'Today',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const IconButton(
          tooltip: 'Next day',
          onPressed: null,
          icon: Icon(Icons.chevron_right),
        ),
      ],
    );
  }
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Seven days ending today; today's point is filled.
class Sparkline extends StatelessWidget {
  const Sparkline({super.key, required this.values, this.height = 24});

  final List<int> values;
  final double height;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;

    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _SparklinePainter(
          values: values,
          line: colors.primary,
          baseline: colors.outlineVariant,
        ),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter({
    required this.values,
    required this.line,
    required this.baseline,
  });

  final List<int> values;
  final Color line;
  final Color baseline;

  @override
  void paint(Canvas canvas, Size size) {
    const double dot = 3;
    final double top = dot;
    final double bottom = size.height - dot;
    final int peak = max(values.reduce(max), 1);
    final double step = (size.width - 2 * dot) / (values.length - 1);
    Offset point(int i) =>
        Offset(dot + i * step, bottom - (bottom - top) * values[i] / peak);

    canvas.drawLine(
      Offset(0, bottom),
      Offset(size.width, bottom),
      Paint()
        ..color = baseline
        ..strokeWidth = 1,
    );

    final Path path = Path()..moveTo(point(0).dx, point(0).dy);
    for (int i = 1; i < values.length; i++) {
      path.lineTo(point(i).dx, point(i).dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = line.withValues(alpha: 0.7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawCircle(point(values.length - 1), dot, Paint()..color = line);
  }

  @override
  bool shouldRepaint(_SparklinePainter old) => old.values != values;
}

class TimelineEntry extends StatelessWidget {
  const TimelineEntry({
    super.key,
    required this.day,
    required this.entry,
    this.isLast = false,
  });

  final MockDay day;
  final MockEntry entry;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;

    return InkWell(
      onTap: () {},
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 44,
                child: Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    _time.format(day.at(entry)),
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: colors.onSurfaceVariant,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: 32,
                child: Column(
                  children: [
                    const SizedBox(height: 6),
                    CircleAvatar(
                      radius: 12,
                      backgroundColor: colors.secondaryContainer,
                      child: Icon(
                        entry.vice.icon,
                        size: 14,
                        color: colors.onSecondaryContainer,
                      ),
                    ),
                    if (!isLast)
                      Expanded(
                        child: Container(
                          width: 1.5,
                          color: colors.outlineVariant,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: entry.vice.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            TextSpan(
                              text:
                                  '  ${entry.vice.unit.label(entry.quantity)}',
                              style: TextStyle(color: colors.onSurfaceVariant),
                            ),
                          ],
                        ),
                        style: theme.textTheme.bodyLarge,
                      ),
                      if (entry.triggers.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final String t in entry.triggers)
                              TriggerChip(t),
                          ],
                        ),
                      ],
                      if (entry.note case final String note) ...[
                        const SizedBox(height: 6),
                        Text(
                          note,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colors.onSurfaceVariant,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class TriggerChip extends StatelessWidget {
  const TriggerChip(this.label, {super.key, this.selected = false});

  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: selected
            ? colors.secondaryContainer
            : colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
        border: selected ? null : Border.all(color: colors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: selected
                ? colors.onSecondaryContainer
                : colors.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class Timeline extends StatelessWidget {
  const Timeline({super.key, required this.day, this.newestFirst = false});

  final MockDay day;
  final bool newestFirst;

  @override
  Widget build(BuildContext context) {
    final List<MockEntry> entries = newestFirst
        ? day.entries.reversed.toList()
        : day.entries;

    return Column(
      children: [
        for (int i = 0; i < entries.length; i++)
          TimelineEntry(
            day: day,
            entry: entries[i],
            isLast: i == entries.length - 1,
          ),
      ],
    );
  }
}

/// What a tap on a tile does: the entry is already saved; the sheet only
/// offers detail and the 8-second undo (C4).
Future<void> showQuickLogSheet(BuildContext context, MockVice vice) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (BuildContext context) => QuickLogSheet(vice: vice),
  );
}

class QuickLogSheet extends StatelessWidget {
  const QuickLogSheet({super.key, required this.vice});

  final MockVice vice;

  static const List<String> triggers = [
    'Social',
    'Work',
    'Stress',
    'Bored',
    'Tired',
    'After a meal',
    'Morning routine',
  ];

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: colors.secondaryContainer,
                child: Icon(vice.icon, color: colors.onSecondaryContainer),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${vice.name} · ${vice.unit.label(vice.defaultQuantity)}',
                      style: theme.textTheme.titleMedium,
                    ),
                    Text(
                      'Logged at 21:32',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(onPressed: () {}, child: const Text('Undo')),
            ],
          ),
          const SizedBox(height: 20),
          Text('What was going on?', style: theme.textTheme.titleSmall),
          Text(
            'Optional. You can add this later from the timeline.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final String t in triggers)
                FilterChip(
                  label: Text(t),
                  selected: t == 'Social',
                  onSelected: (_) {},
                ),
              ActionChip(
                avatar: const Icon(Icons.add, size: 18),
                label: const Text('Other'),
                onPressed: () {},
              ),
            ],
          ),
          const SizedBox(height: 16),
          const TextField(
            decoration: InputDecoration(
              hintText: 'Add a note',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              TextButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.tune),
                label: const Text('Amount or time'),
              ),
              const Spacer(),
              FilledButton(onPressed: () {}, child: const Text('Done')),
            ],
          ),
        ],
      ),
    );
  }
}
