import 'package:flutter/material.dart';
import 'package:tracker/mockups/today_layout/fixtures.dart';
import 'package:tracker/mockups/today_layout/shared.dart';
import 'package:tracker/widgets/clean_day.dart';

/// Option B: tiles first. Each tile is a large button: tap logs the vice's
/// default quantity now and offers detail; hold opens the editor. The chart
/// and the latest entries sit below the grid.
class TilesToday extends StatelessWidget {
  const TilesToday({super.key, required this.day});

  final MockDay day;

  static const int latestShown = 3;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<MockEntry> latest = day.entries.reversed
        .take(latestShown)
        .toList();

    return MockTodayScaffold(
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          DayHeader(day: day),
          if (day.isClean)
            const CleanDay(isToday: true)
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                'Tap a tile to log it now. Hold to choose the amount or time.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.5,
              children: [
                for (final MockVice vice in day.vices)
                  _LogTile(day: day, vice: vice),
              ],
            ),
          ),
          if (!day.isClean) ...[
            const SectionLabel('The day at a glance'),
            DayChartSlot(day: day, height: day.vices.length < 3 ? 190 : 250),
            SectionLabel(
              'Latest entries',
              trailing: TextButton(
                onPressed: () {},
                child: Text('All ${day.entries.length}'),
              ),
            ),
            for (int i = 0; i < latest.length; i++)
              TimelineEntry(
                day: day,
                entry: latest[i],
                isLast: i == latest.length - 1,
              ),
          ],
        ],
      ),
    );
  }
}

class _LogTile extends StatelessWidget {
  const _LogTile({required this.day, required this.vice});

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
        key: ValueKey('tile-${vice.vice.id}'),
        onTap: () => showQuickLogSheet(context, vice),
        onLongPress: () {},
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(vice.icon, size: 20, color: colors.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      vice.name,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '$total',
                            style: theme.textTheme.headlineMedium,
                          ),
                          TextSpan(
                            text: ' ${vice.unit.nameFor(total)}',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.primaryContainer,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      child: Text(
                        '+${vice.defaultQuantity}',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: colors.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Sparkline(values: day.lastSevenDays(vice), height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
