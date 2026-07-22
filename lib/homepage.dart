import 'package:flutter/material.dart';
import 'package:tracker/vice_tracker.dart';
import 'package:tracker/widgets/record_new_activity_button.dart';

class Homepage extends StatefulWidget {
  const Homepage({super.key});

  @override
  State<Homepage> createState() => _HomepageState();
}

class _HomepageState extends State<Homepage> {
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
              title: const Text('Manage Data'),
              leading: const Icon(Icons.list),
              onTap: () {
                Navigator.of(context).pushNamed('/manage-data');
              },
            ),
            ListTile(
              title: const Text('Settings'),
              leading: const Icon(Icons.settings),
              onTap: () {
                Navigator.of(context).pushNamed('/settings');
              },
            ),
          ],
        ),
      ),
      body: const ViceTracker(),
    );
  }
}
