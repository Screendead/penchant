import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/providers/today_provider.dart';
import 'package:tracker/vice_chart.dart';
import 'package:tracker/widgets/sync_status.dart';

class ViceTracker extends ConsumerStatefulWidget {
  const ViceTracker({super.key});

  static const int selectableDays = 30;

  @override
  ConsumerState<ViceTracker> createState() => _ViceTrackerState();
}

class _ViceTrackerState extends ConsumerState<ViceTracker> {
  static final DateFormat _dateFormat = ViceChart.dayFormat;
  static const String _storageID = 'ViceTracker.pinnedDay';

  // Null follows today, so the tab moves on at midnight.
  DateTime? pinnedDay;

  @override
  void initState() {
    super.initState();
    pinnedDay =
        PageStorage.maybeOf(context)?.readState(context, identifier: _storageID)
            as DateTime?;
  }

  void _selectDay(DateTime day) {
    final DateTime? pinned = day == ref.read(todayProvider) ? null : day;
    setState(() {
      pinnedDay = pinned;
    });
    PageStorage.maybeOf(
      context,
    )?.writeState(context, pinned, identifier: _storageID);
  }

  @override
  Widget build(BuildContext context) {
    final DateTime today = ref.watch(todayProvider);
    final DateTime selectedDay = pinnedDay ?? today;
    final DateTime oldestDay = addDays(
      today,
      -(ViceTracker.selectableDays - 1),
    );
    // The dropdown asserts that its value is one of its items, and the item
    // range moves forward when the build runs on a later day than selection.
    final DateTime day = selectedDay.isAfter(today)
        ? today
        : selectedDay.isBefore(oldestDay)
        ? oldestDay
        : selectedDay;
    final int daysAgo = daysBetween(day, today);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  const Icon(Icons.calendar_month, color: Colors.white),
                  Flexible(
                    child: Text(
                      daysAgo == 0
                          ? 'Today'
                          : daysAgo == 1
                          ? 'Yesterday'
                          : '$daysAgo days ago',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ),
                  const CircleAvatar(backgroundColor: Colors.white, radius: 3),
                  Flexible(
                    child: DropdownButton<DateTime>(
                      isExpanded: true,
                      value: day,
                      onChanged: (DateTime? newValue) {
                        if (newValue != null) {
                          _selectDay(newValue);
                        }
                      },
                      items: List.generate(ViceTracker.selectableDays, (index) {
                        final DateTime item = addDays(today, -index);

                        return DropdownMenuItem(
                          value: item,
                          child: Text(
                            _dateFormat.format(item),
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }),
                    ),
                  ),
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    tooltip: 'Previous day',
                    icon: const Icon(Icons.arrow_back),
                    onPressed: daysAgo >= ViceTracker.selectableDays - 1
                        ? null
                        : () => _selectDay(addDays(day, -1)),
                  ),
                  Flexible(
                    child: TextButton.icon(
                      onPressed: daysAgo == 0 ? null : () => _selectDay(today),
                      icon: const Icon(Icons.today),
                      label: const Text(
                        'Jump to Today',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Next day',
                    icon: const Icon(Icons.arrow_forward),
                    onPressed: daysAgo <= 0
                        ? null
                        : () => _selectDay(addDays(day, 1)),
                  ),
                ],
              ),
              Expanded(child: ViceChart(selectedDate: day)),
              PendingDayNote(selectedDate: day),
            ],
          ),
        ),
      ),
    );
  }
}
