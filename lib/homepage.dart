import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tracker/vice_chart.dart';
import 'package:tracker/widgets/record_new_activity_button.dart';

class Homepage extends StatefulWidget {
  const Homepage({super.key});

  @override
  State<Homepage> createState() => _HomepageState();
}

class _HomepageState extends State<Homepage> {
  int selectedDataSetIndex = -1;
  final DateTime now = DateTime.now();
  late final DateTime today;
  late DateTime selectedDate;

  int get daysAgo => today.difference(selectedDate).inDays;

  @override
  void initState() {
    super.initState();

    today = DateTime(now.year, now.month, now.day);
    selectedDate = today;
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Vice Tracker'),
        actions: const <Widget>[
          RecordNewActivityButton(),
        ],
      ),
      drawer: Drawer(
        child: ListView(
          children: [
            DrawerHeader(
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
              ),
              child: Center(
                child: Text(
                  'Vice Tracker',
                  style: TextStyle(
                    color: theme.colorScheme.onPrimary,
                    fontSize: 24,
                  ),
                ),
              ),
            ),
            ListTile(
              title: const Text('Sign Out'),
              leading: const Icon(Icons.logout),
              onTap: FirebaseAuth.instance.signOut,
            ),
          ],
        ),
      ),
      body: Padding(
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
                  child: ViceChart(date: selectedDate),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
