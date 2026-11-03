import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/account/account.dart';
import 'package:tracker/account/account_copy.dart';
import 'package:tracker/account/auth_errors.dart';
import 'package:tracker/providers/account_provider.dart';
import 'package:tracker/providers/package_info_provider.dart';

// Routes pushed above the root outlive the session, so the stack is cleared
// back to the root, which shows sign-in once the user is null.
Future<void> signOut(BuildContext context, WidgetRef ref) async {
  final Account account = ref.read(accountProvider);
  final NavigatorState navigator = Navigator.of(context);
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
  try {
    try {
      await account.signOut();
    } on UnsyncedEntriesException {
      if (!context.mounted || !await _confirmDiscard(context)) {
        return;
      }
      await account.signOut(discardUnsynced: true);
    }
    navigator.popUntil((Route<dynamic> route) => route.isFirst);
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(content: Text(AccountCopy.signOutFailed(authErrorMessage(e)))),
    );
  }
}

Future<bool> _confirmDiscard(BuildContext context) async {
  final bool? discard = await showDialog<bool>(
    context: context,
    builder: (BuildContext context) => AlertDialog(
      title: const Text(AccountCopy.signOutUnsyncedTitle),
      content: const Text(AccountCopy.signOutUnsyncedBody),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text(AccountCopy.cancel),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text(AccountCopy.signOutAnyway),
        ),
      ],
    ),
  );
  return discard ?? false;
}

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
              subtitle: version == null ? null : Text(version),
              leading: const Icon(Icons.info),
              onTap: () {
                showAboutDialog(context: context, applicationVersion: version);
              },
            ),
            ListTile(
              title: const Text('Sign out'),
              leading: const Icon(Icons.exit_to_app),
              onTap: () => signOut(context, ref),
            ),
          ],
        ),
      ),
    );
  }
}
