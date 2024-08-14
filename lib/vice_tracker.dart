import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tracker/vice_chart.dart';

class ViceTracker extends StatefulWidget {
  const ViceTracker({super.key});

  @override
  State<ViceTracker> createState() => _ViceTrackerState();
}

class _ViceTrackerState extends State<ViceTracker> {
  final GlobalKey<ViceChartState> viceChartKey = GlobalKey<ViceChartState>();
  int selectedDataSetIndex = -1;
  final DateTime now = DateTime.now();
  late final DateTime today;

  late DateTime _selectedDate;
  DateTime get selectedDate => _selectedDate;
  set selectedDate(DateTime value) {
    _selectedDate = value;

    if (viceChartKey.currentState != null) {
      viceChartKey.currentState!.updateDate(value);
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        viceChartKey.currentState?.updateDate(value);
      });
    }
  }

  int get daysAgo => today.difference(selectedDate).inDays;

  @override
  void initState() {
    super.initState();

    today = DateTime(now.year, now.month, now.day);
    selectedDate = today;
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
                    onChanged: (DateTime? newValue) {
                      setState(() {
                        selectedDate = newValue!;
                      });
                    },
                    items: List.generate(30, (index) {
                      final date = today.subtract(Duration(days: index));
                      final formattedDate =
                          DateFormat("EEEE, MMMM d, yyyy").format(date);

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
                    onPressed: daysAgo >= 29
                        ? null
                        : () {
                            setState(() {
                              selectedDate = selectedDate
                                  .subtract(const Duration(days: 1));
                            });
                          },
                  ),
                  TextButton.icon(
                    onPressed: daysAgo == 0
                        ? null
                        : () {
                            setState(() {
                              selectedDate = today;
                            });
                          },
                    icon: const Icon(Icons.today),
                    label: const Text('Jump to Today'),
                  ),
                  IconButton(
                    icon: const Icon(Icons.arrow_forward),
                    onPressed: daysAgo <= 0
                        ? null
                        : () {
                            setState(() {
                              selectedDate =
                                  selectedDate.add(const Duration(days: 1));
                            });
                          },
                  ),
                ],
              ),
              Expanded(
                child: ViceChart(
                  key: viceChartKey,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
