import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:tracker/providers/vice_activity_day_provider.dart';
import 'package:tracker/vice_chart.dart';

class ViceTracker extends ConsumerStatefulWidget {
  const ViceTracker({super.key});

  @override
  ConsumerState<ViceTracker> createState() => _ViceTrackerState();
}

class _ViceTrackerState extends ConsumerState<ViceTracker> {
  final DateTime now = DateTime.now();
  late final DateTime today;

  late DateTime _selectedDate;
  DateTime get selectedDate => _selectedDate;
  set selectedDate(DateTime value) {
    _selectedDate = value;
  }

  int get daysAgo => today.difference(selectedDate).inDays;
  bool loadingDate = false;

  @override
  void initState() {
    super.initState();

    today = DateTime(now.year, now.month, now.day);
    selectedDate = today;
  }

  Future<void> _selectDate(DateTime nextDate) async {
    if (loadingDate || nextDate == selectedDate) {
      return;
    }

    setState(() {
      loadingDate = true;
    });

    try {
      await ref.read(viceActivityDayProvider(nextDate).future);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Unable to load that day: $error'),
          ),
        );
        setState(() {
          loadingDate = false;
        });
      }

      return;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      selectedDate = nextDate;
      loadingDate = false;
    });
  }

  @override
  Widget build(BuildContext context) {
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
                  const Icon(
                    Icons.calendar_month,
                    color: Colors.white,
                  ),
                  Text(
                    daysAgo == 0
                        ? 'Today'
                        : daysAgo == 1
                            ? 'Yesterday'
                            : '$daysAgo days ago',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                    ),
                  ),
                  const CircleAvatar(
                    backgroundColor: Colors.white,
                    radius: 3,
                  ),
                  DropdownButton<DateTime>(
                    value: selectedDate,
                    onChanged: loadingDate
                        ? null
                        : (DateTime? newValue) {
                            if (newValue != null) {
                              _selectDate(newValue);
                            }
                          },
                    items: List.generate(30, (index) {
                      final date = today.subtract(Duration(days: index));
                      final formattedDate =
                          DateFormat('EEEE, MMMM d, yyyy').format(date);

                      return DropdownMenuItem(
                        value: date,
                        child: Text(formattedDate),
                      );
                    }),
                  ),
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: daysAgo >= 29 || loadingDate
                        ? null
                        : () {
                            _selectDate(
                              selectedDate.subtract(const Duration(days: 1)),
                            );
                          },
                  ),
                  TextButton.icon(
                    onPressed: daysAgo == 0 || loadingDate
                        ? null
                        : () {
                            _selectDate(today);
                          },
                    icon: const Icon(Icons.today),
                    label: const Text('Jump to Today'),
                  ),
                  IconButton(
                    icon: const Icon(Icons.arrow_forward),
                    onPressed: daysAgo <= 0 || loadingDate
                        ? null
                        : () {
                            _selectDate(
                              selectedDate.add(const Duration(days: 1)),
                            );
                          },
                  ),
                ],
              ),
              Expanded(
                child: ViceChart(
                  selectedDate: selectedDate,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}