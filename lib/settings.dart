import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/account/account.dart';
import 'package:tracker/account/account_copy.dart';
import 'package:tracker/account/auth_errors.dart';
import 'package:tracker/errors/report_error.dart';
import 'package:tracker/providers/account_provider.dart';
import 'package:tracker/design/dial_icons.dart';
import 'package:tracker/design/tokens.dart';
import 'package:tracker/providers/package_info_provider.dart';
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/widgets/settings_card.dart';

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

// Nothing signs a guest back in, so signing out erases their journal rather
// than leave it on the server under a uid nothing can reach.
Future<bool> _confirmGuestSignOut(BuildContext context) async {
  final bool? leave = await showDialog<bool>(
    context: context,
    builder: (BuildContext context) => AlertDialog(
      title: const Text(AccountCopy.guestSignOutTitle),
      content: const Text(AccountCopy.guestSignOutBody),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text(AccountCopy.cancel),
        ),
        TextButton(
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.error,
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text(AccountCopy.guestSignOutAction),
        ),
      ],
    ),
  );
  return leave ?? false;
}

class Settings extends ConsumerStatefulWidget {
  const Settings({super.key});

  @override
  ConsumerState<Settings> createState() => _SettingsState();
}

class _SettingsState extends ConsumerState<Settings> {
  bool _signingOut = false;

  Future<void> _signOut() async {
    final Account account = ref.read(accountProvider);
    final NavigatorState navigator = Navigator.of(context);
    final ModalRoute<dynamic>? route = ModalRoute.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    try {
      if (account.isGuest) {
        await _eraseGuest(account, navigator, route, messenger);
        return;
      }
      try {
        await _whileSigningOut(account.signOut);
      } on UnsyncedEntriesException {
        if (!mounted || !await _confirmDiscard(context)) {
          return;
        }
        await _whileSigningOut(() => account.signOut(discardUnsynced: true));
      }
      _popToHome(navigator, route);
    } catch (e, stack) {
      reportError(e, stack, context: 'while signing out');
      messenger.showSnackBar(
        SnackBar(content: Text(AccountCopy.signOutFailed(authErrorMessage(e)))),
      );
    }
  }

  // Deleting the guest's Auth user signs it out. A failure leaves it signed in,
  // so whatever remains stays reachable for another try.
  Future<void> _eraseGuest(
    Account account,
    NavigatorState navigator,
    ModalRoute<dynamic>? route,
    ScaffoldMessengerState messenger,
  ) async {
    if (!await _confirmGuestSignOut(context) || !mounted) {
      return;
    }
    try {
      await _whileSigningOut(account.deleteAccount);
    } on DeletionIncompleteException catch (e, stack) {
      reportError(e.cause, stack, context: 'while erasing a guest journal');
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            AccountCopy.guestSignOutIncomplete(authErrorMessage(e.cause)),
          ),
        ),
      );
      return;
    } catch (e, stack) {
      reportError(e, stack, context: 'while erasing a guest journal');
      messenger.showSnackBar(
        SnackBar(
          content: Text(AccountCopy.guestSignOutFailed(authErrorMessage(e))),
        ),
      );
      return;
    }
    _popToHome(navigator, route);
    messenger.showSnackBar(
      const SnackBar(content: Text(AccountCopy.guestErased)),
    );
  }

  // MyApp pops every page once the uid changes, which is usually before the
  // sign-out returns (it clears the cache after Auth signs out). A pop after
  // that would close whatever the sign-in screen has opened since, such as
  // the reset-password dialog.
  void _popToHome(NavigatorState navigator, ModalRoute<dynamic>? route) {
    if (route?.isActive ?? false) {
      navigator.popUntil((Route<dynamic> r) => r.isFirst);
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
        .whenOrNull(data: (info) => '${info.version} (${info.buildNumber})');
    // The profile stream, since linking a guest or changing the address
    // leaves the auth-state User as it was.
    final String? email = ref.watch(
      userProfileProvider.select(
        (AsyncValue<User?> user) => (user.value?.isAnonymous ?? false)
            ? AccountCopy.guest
            : user.value?.email,
      ),
    );
    return CardPage(
      title: 'Settings',
      children: <Widget>[
        DialCard(
          children: <Widget>[
            CardRow(
              label: 'Account',
              value: email == null || email.isEmpty
                  ? null
                  : Text(email, overflow: TextOverflow.ellipsis),
              glyph: DialGlyph.right,
              onTap: () {
                Navigator.of(context).pushNamed('/settings/account');
              },
            ),
          ],
        ),
        const CardSectionLabel('App'),
        DialCard(
          top: 0,
          children: <Widget>[
            const CardRow(label: 'Appearance', value: Text('Match system')),
            CardRow(
              label: 'About',
              value: version == null
                  ? null
                  : Text(
                      version,
                      style: const TextStyle(
                        fontFamily: DialFonts.mono,
                        fontFeatures: DialFonts.tabular,
                      ),
                    ),
              glyph: DialGlyph.right,
              onTap: () {
                showAboutDialog(
                  context: context,
                  applicationVersion: version == null
                      ? null
                      : 'Version $version',
                );
              },
            ),
          ],
        ),
        DialCard(
          top: DialSpace.xl,
          children: <Widget>[
            CardRow(
              label: 'Sign out',
              danger: true,
              enabled: !_signingOut,
              trailing: _signingOut
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : null,
              onTap: _signOut,
            ),
          ],
        ),
        const CardFoot(
          'Your journal is private to your account. Nothing is shared.',
        ),
      ],
    );
  }
}
