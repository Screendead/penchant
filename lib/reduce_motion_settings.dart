import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/design/tokens.dart';
import 'package:tracker/providers/reduce_motion_provider.dart';
import 'package:tracker/widgets/dial_segments.dart';
import 'package:tracker/widgets/settings_card.dart';

/// Settings › Reduce motion: the same segmented control as Appearance.
class ReduceMotionSettings extends ConsumerWidget {
  const ReduceMotionSettings({super.key});

  static const String route = '/settings/reduce-motion';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CardPage(
      title: 'Reduce motion',
      children: <Widget>[
        const SizedBox(height: DialSpace.l),
        DialSegments<MotionPreference>(
          choices: MotionPreference.values,
          selected: ref.watch(reduceMotionProvider),
          label: motionLabel,
          onChanged: ref.read(reduceMotionProvider.notifier).choose,
        ),
        const CardFoot(
          'Follow system uses your device’s Reduce Motion setting. Reduce '
          'swaps travel and sweeps for short fades. Full keeps the dial, the '
          'log fan, the tallies, the Undo timer and page changes moving even '
          'if the system asks for less; sheets, dialogs and small fades still '
          'follow the system. Saved on this device only.',
        ),
      ],
    );
  }
}
