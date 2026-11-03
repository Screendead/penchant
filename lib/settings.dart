import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class Settings extends StatefulWidget {
  const Settings({super.key});

  @override
  State<Settings> createState() => _SettingsState();
}

class _SettingsState extends State<Settings> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: <Widget>[
            ListTile(
              title: const Text('Account'),
              leading: const Icon(Icons.account_circle),
              onTap: () {
                Navigator.of(context).pushNamed('/settings/account');
              },
            ),
            ListTile(
              title: const Text('Recovery key'),
              leading: const Icon(Icons.key),
              onTap: () {
                Navigator.of(context).pushNamed('/settings/recovery-key');
              },
            ),
            ListTile(
              title: const Text('Notifications'),
              leading: const Icon(Icons.notifications),
              onTap: () {
                Navigator.of(context).pushNamed('/settings/notifications');
              },
            ),
            ListTile(
              title: const Text('Privacy'),
              leading: const Icon(Icons.privacy_tip),
              onTap: () {
                Navigator.of(context).pushNamed('/settings/privacy');
              },
            ),
            ListTile(
              title: const Text('About'),
              leading: const Icon(Icons.info),
              onTap: () {
                Navigator.of(context).pushNamed('/settings/about');
              },
            ),
            ListTile(
              title: const Text('Sign out'),
              leading: const Icon(Icons.exit_to_app),
              onTap: () {
                FirebaseAuth.instance.signOut();
                Navigator.of(context).pop();
              },
            ),
          ],
        ),
      ),
    );
  }
}
