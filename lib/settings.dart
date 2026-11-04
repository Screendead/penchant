import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/account/account.dart';
import 'package:tracker/account/account_copy.dart';
import 'package:tracker/account/auth_errors.dart';
import 'package:tracker/errors/report_error.dart';
import 'package:tracker/providers/account_provider.dart';
import 'package:tracker/providers/package_info_provider.dart';

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

class Settings extends ConsumerStatefulWidget {
  const Settings({super.key});

  @override
  ConsumerState<Settings> createState() => _SettingsState();
}

class _SettingsState extends ConsumerState<Settings> {
  bool _signingOut = false;

  // MyApp also pops every page once the uid changes; this pop does not wait
  // for that event.
  Future<void> _signOut() async {
    final Account account = ref.read(accountProvider);
    final NavigatorState navigator = Navigator.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    try {
      try {
        await _whileSigningOut(account.signOut);
      } on UnsyncedEntriesException {
        if (!mounted || !await _confirmDiscard(context)) {
          return;
        }
        await _whileSigningOut(() => account.signOut(discardUnsynced: true));
      }
      navigator.popUntil((Route<dynamic> route) => route.isFirst);
    } catch (e, stack) {
      reportError(e, stack, context: 'while signing out');
      messenger.showSnackBar(
        SnackBar(content: Text(AccountCopy.signOutFailed(authErrorMessage(e)))),
      );
    }
  }

  // Waiting for unsynced entries can take seconds; the tile stays disabled
  // meanwhile so a second tap cannot start a second sign-out.
  Future<void> _whileSigningOut(Future<void> Function() signOut) async {
    setState(() => _signingOut = true);
    try {
      await signOut();
    } finally {
      if (mounted) {
        setState(() => _signingOut = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
              enabled: !_signingOut,
              trailing: _signingOut
                  ? const SizedBox.square(
                      dimension: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : null,
              onTap: _signOut,
            ),
          ],
        ),
      ),
    );
  }
}
