import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/vice_chart.dart';

class ViceTracker extends ConsumerStatefulWidget {
  const ViceTracker({super.key});

  static const int selectableDays = 30;

  @override
  ConsumerState<ViceTracker> createState() => _ViceTrackerState();
}

class _ViceTrackerState extends ConsumerState<ViceTracker> {
  static final DateFormat _dateFormat = DateFormat('EEEE, MMMM d, yyyy');

  DateTime selectedDay = startOfDay(DateTime.now());

  void _selectDay(DateTime day) {
    setState(() {
      selectedDay = day;
    });
  }

  @override
  Widget build(BuildContext context) {
    final DateTime today = startOfDay(DateTime.now());
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
                  Text(
                    daysAgo == 0
                        ? 'Today'
                        : daysAgo == 1
                        ? 'Yesterday'
                        : '$daysAgo days ago',
                    style: const TextStyle(color: Colors.white, fontSize: 16),
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
                  TextButton.icon(
                    onPressed: daysAgo == 0 ? null : () => _selectDay(today),
                    icon: const Icon(Icons.today),
                    label: const Text('Jump to Today'),
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
            ],
          ),
        ),
      ),
    );
  }
}
