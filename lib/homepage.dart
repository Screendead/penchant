import 'package:flutter/material.dart';
import 'package:tracker/usage_graph_view.dart';
import 'package:tracker/vice_tracker.dart';
import 'package:tracker/widgets/record_new_activity_button.dart';
import 'package:tracker/widgets/sync_status.dart';

class Homepage extends StatefulWidget {
  const Homepage({super.key});

  @override
  State<Homepage> createState() => _HomepageState();
}

class _HomepageState extends State<Homepage> {
  int selectedTabIndex = 0;
  // Only the visible tab is built, so each tab keeps its selections here
  // across a switch. It lives and dies with the signed-in session.
  final PageStorageBucket tabState = PageStorageBucket();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(selectedTabIndex == 0 ? 'Vice Tracker' : 'Usage Graph'),
        actions: const <Widget>[RecordNewActivityButton()],
      ),
      drawer: Drawer(
        child: ListView(
          children: [
            DrawerHeader(
              decoration: BoxDecoration(color: theme.colorScheme.primary),
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
            child: PageStorage(
              bucket: tabState,
              child: selectedTabIndex == 0
                  ? const ViceTracker()
                  : const UsageGraphView(),
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedTabIndex,
        onDestinationSelected: (int index) {
          setState(() {
            selectedTabIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.today_outlined),
            selectedIcon: Icon(Icons.today),
            label: 'Today',
          ),
          NavigationDestination(
            icon: Icon(Icons.show_chart_outlined),
            selectedIcon: Icon(Icons.show_chart),
            label: 'Graph',
          ),
        ],
      ),
    );
  }
}
