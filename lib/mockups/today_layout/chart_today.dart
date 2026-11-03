import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tracker/mockups/today_layout/fixtures.dart';
import 'package:tracker/mockups/today_layout/shared.dart';
import 'package:tracker/widgets/clean_day.dart';
import 'package:tracker/widgets/record_new_activity_button.dart';

/// Option C: today's screen as shipped (day picker, then the chart), with the
/// timeline of entries added below. Logging stays in the Record dialog.
class ChartToday extends StatelessWidget {
  const ChartToday({super.key, required this.day});

  final MockDay day;

  static final DateFormat _dateFormat = DateFormat('EEEE, MMMM d, yyyy');

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return MockTodayScaffold(
      actions: const [RecordNewActivityButton()],
      body: ListView(
        padding: const EdgeInsets.fromLTRB(0, 8, 0, 24),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                const Icon(Icons.calendar_month),
                const SizedBox(width: 8),
                Text('Today', style: theme.textTheme.titleMedium),
                const SizedBox(width: 8),
                const CircleAvatar(radius: 3),
                const SizedBox(width: 8),
                Flexible(
                  child: DropdownButton<int>(
                    isExpanded: true,
                    value: 0,
                    onChanged: (_) {},
                    items: [
                      DropdownMenuItem(
                        value: 0,
                        child: Text(
                          _dateFormat.format(day.date),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                tooltip: 'Previous day',
                icon: const Icon(Icons.arrow_back),
                onPressed: () {},
              ),
              TextButton.icon(
                onPressed: null,
                icon: const Icon(Icons.today),
                label: const Text('Jump to Today'),
              ),
              const IconButton(
                tooltip: 'Next day',
                icon: Icon(Icons.arrow_forward),
                onPressed: null,
              ),
            ],
          ),
          if (day.isClean)
            const SizedBox(height: 360, child: CleanDay(isToday: true))
          else ...[
            DayChartSlot(day: day, height: day.vices.length < 3 ? 300 : 340),
            SectionLabel(
              'Entries',
              trailing: Text(
                '${day.entries.length}',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Timeline(day: day, newestFirst: true),
          ],
        ],
      ),
    );
  }
}
