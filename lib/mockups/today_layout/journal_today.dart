import 'dart:math';

import 'package:flutter/material.dart';
import 'package:tracker/mockups/today_layout/fixtures.dart';
import 'package:tracker/mockups/today_layout/shared.dart';
import 'package:tracker/widgets/clean_day.dart';

/// Option A: the day as a journal page. A strip of compact tiles (tap logs,
/// hold opens the editor), the day chart, then the timeline of entries.
class JournalToday extends StatelessWidget {
  const JournalToday({super.key, required this.day});

  final MockDay day;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return MockTodayScaffold(
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          DayHeader(day: day),
          _TileStrip(day: day),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
            child: Text(
              'Tap to log one now · hold for amount or time',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          if (day.isClean)
            const Padding(
              padding: EdgeInsets.only(top: 24),
              child: CleanDay(isToday: true),
            )
          else ...[
            const SectionLabel('The day at a glance'),
            DayChartSlot(day: day, height: day.vices.length < 3 ? 200 : 260),
            SectionLabel(
              'Entries',
              trailing: Text(
                '${day.entries.length}',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Timeline(day: day),
          ],
        ],
      ),
    );
  }
}

class _TileStrip extends StatelessWidget {
  const _TileStrip({required this.day});

  final MockDay day;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        const double gap = 8;
        const double side = 16;
        final int n = day.vices.length;
        final double fill =
            (constraints.maxWidth - 2 * side - gap * (n - 1)) / n;
        final double width = max(fill, 148);

        return SizedBox(
          height: 108,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: side),
            itemCount: n,
            separatorBuilder: (_, _) => const SizedBox(width: gap),
            itemBuilder: (BuildContext context, int i) => SizedBox(
              width: width,
              child: _CompactTile(day: day, vice: day.vices[i]),
            ),
          ),
        );
      },
    );
  }
}

class _CompactTile extends StatelessWidget {
  const _CompactTile({required this.day, required this.vice});

  final MockDay day;
  final MockVice vice;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final int total = day.total(vice);

    return Card.filled(
      margin: EdgeInsets.zero,
      color: colors.surfaceContainerHigh,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => showQuickLogSheet(context, vice),
        onLongPress: () {},
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(vice.icon, size: 16, color: colors.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      vice.name,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.add_circle_outline,
                    size: 18,
                    color: colors.primary,
                  ),
                ],
              ),
              const Spacer(),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: '$total', style: theme.textTheme.titleLarge),
                    TextSpan(
                      text: ' ${vice.unit.nameFor(total)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Sparkline(values: day.lastSevenDays(vice), height: 18),
            ],
          ),
        ),
      ),
    );
  }
}
