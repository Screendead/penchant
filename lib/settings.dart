import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/providers/package_info_provider.dart';

class Settings extends ConsumerWidget {
  const Settings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String? version = ref
        .watch(packageInfoProvider)
        .whenOrNull(
          data: (info) => 'Version ${info.version} (${info.buildNumber})',
        );
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
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
              title: const Text('About'),
              subtitle: version == null ? null : Text(version),
              leading: const Icon(Icons.info),
              onTap: () {
                showAboutDialog(context: context, applicationVersion: version);
              },
            ),
            ListTile(
              title: const Text('Sign out'),
              leading: const Icon(Icons.exit_to_app),
              // MyApp pops every page once the session ends.
              onTap: () => FirebaseAuth.instance.signOut(),
            ),
          ],
        ),
      ),
    );
  }
}
