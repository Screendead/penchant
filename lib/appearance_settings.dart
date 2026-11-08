import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/design/tokens.dart';
import 'package:tracker/providers/appearance_provider.dart';
import 'package:tracker/widgets/dial_segments.dart';
import 'package:tracker/widgets/settings_card.dart';

/// Settings › Appearance: the design system's segmented control on a ground.
class AppearanceSettings extends ConsumerWidget {
  const AppearanceSettings({super.key});

  static const String route = '/settings/appearance';
  static const List<ThemeMode> choices = <ThemeMode>[
    ThemeMode.system,
    ThemeMode.light,
    ThemeMode.dark,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeMode mode = ref.watch(appearanceProvider);
    return CardPage(
      title: 'Appearance',
      children: <Widget>[
        const SizedBox(height: DialSpace.l),
        DialSegments<ThemeMode>(
          choices: choices,
          selected: mode,
          label: appearanceLabel,
          onChanged: ref.read(appearanceProvider.notifier).choose,
        ),
        const CardFoot(
          'Match system follows your phone’s light or dark setting. '
          'Saved on this device only.',
        ),
      ],
    );
  }
}
