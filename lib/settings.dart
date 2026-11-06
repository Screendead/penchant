import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/account/sign_out.dart';
import 'package:tracker/providers/account_provider.dart';
import 'package:tracker/design/dial_icons.dart';
import 'package:tracker/design/tokens.dart';
import 'package:tracker/providers/package_info_provider.dart';
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/widgets/settings_card.dart';

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
    final NavigatorState navigator = Navigator.of(context);
    if (await signOutAsking(
      context,
      ref.read(accountProvider),
      busy: _whileSigningOut,
    )) {
      navigator.popUntil((Route<dynamic> route) => route.isFirst);
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
    final String? email = ref.watch(userProvider).value?.email;
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
