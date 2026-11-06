import 'package:flutter/material.dart';
import 'package:tracker/vice_tracker.dart';
import 'package:tracker/widgets/sync_status.dart';

class Homepage extends StatefulWidget {
  const Homepage({super.key});

  @override
  State<Homepage> createState() => _HomepageState();
}

class _HomepageState extends State<Homepage> {
  // Today's day and the Trends selection outlive their widgets here, as when
  // a load error replaces them. It lives and dies with the signed-in session.
  final PageStorageBucket tabState = PageStorageBucket();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Penchant')),
      drawer: Drawer(
        child: ListView(
          children: [
            DrawerHeader(
              decoration: BoxDecoration(color: theme.colorScheme.primary),
              child: Center(
                child: Text(
                  'Penchant',
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
                Navigator.of(context)
                  ..pop()
                  ..pushNamed('/manage-data');
              },
            ),
            ListTile(
              title: const Text('Settings'),
              leading: const Icon(Icons.settings),
              onTap: () {
                Navigator.of(context)
                  ..pop()
                  ..pushNamed('/settings');
              },
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          const OfflineBanner(),
          Expanded(
            child: PageStorage(bucket: tabState, child: const ViceTracker()),
          ),
        ],
      ),
    );
  }
}
