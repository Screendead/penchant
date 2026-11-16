import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/data/check_in.dart';
import 'package:tracker/design/dial_theme.dart';
import 'package:tracker/design/tokens.dart';
import 'package:tracker/formats.dart';
import 'package:tracker/reminder/check_ins.dart';
import 'package:tracker/widgets/amount_sheet_frame.dart';
import 'package:tracker/writes/answer_check_in.dart';

/// A random check-in, opened by a tap on its notification: "Any urge right
/// now?", 0 to 5, one tap answering. Names no habit, as the notification
/// does not.
class CheckInSheet extends ConsumerWidget {
  const CheckInSheet({
    super.key,
    required this.checkInID,
    required this.promptedAt,
  });

  final String checkInID;
  final DateTime promptedAt;

  static const String question = 'Any urge right now?';
  static const String lowLabel = 'None';
  static const String highLabel = 'Couldn’t not';
  static const String note =
      'For any habit. The answer is sealed in your journal; nothing else is '
      'recorded.';
  static const String notNowLabel = 'Not now';
  static const String turnOffLabel = 'Turn off check-ins';
  static const String turnedOffMessage = 'Check-ins are off';

  static Key keyFor(int strength) => ValueKey<String>('check-in-$strength');
  static const Key turnOffKey = ValueKey<String>('check-in-turn-off');

  static Future<void> show(
    BuildContext context, {
    required String checkInID,
    required DateTime promptedAt,
  }) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => CheckInSheet(checkInID: checkInID, promptedAt: promptedAt),
  );

  void _answer(BuildContext context, WidgetRef ref, int strength) {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    unawaited(
      answerCheckIn(
        ref,
        messenger,
        checkInID: checkInID,
        promptedAt: promptedAt,
        answeredAt: clock.now(),
        strength: strength,
        via: CheckInVia.sheet,
      ),
    );
  }

  Future<void> _turnOff(BuildContext context, WidgetRef ref) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    await ref.read(checkInsProvider.notifier).turnOff();
    messenger.showSnackBar(const SnackBar(content: Text(turnedOffMessage)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final DialColors colors = DialColors.of(context);
    final bool h24 = MediaQuery.alwaysUse24HourFormatOf(context);
    final TextStyle ends = DialTypeScale.bodyS.copyWith(
      color: colors.muted,
      fontSize: 12,
    );
    return AmountSheetFrame(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    question,
                    style: DialTypeScale.displayM.copyWith(fontSize: 20),
                  ),
                ),
              ),
              SheetCloseButton(onPressed: () => Navigator.of(context).pop()),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: DialSpace.m),
            child: Text(
              'Asked at ${formatTime(promptedAt, alwaysUse24HourFormat: h24)}',
              style: theme.textTheme.bodyMedium?.copyWith(color: colors.muted),
            ),
          ),
          Row(
            children: <Widget>[
              for (int n = minCheckIn; n <= maxCheckIn; n++) ...<Widget>[
                if (n > minCheckIn) const SizedBox(width: 6),
                Expanded(
                  child: _AnswerBox(
                    key: keyFor(n),
                    strength: n,
                    onTap: () => _answer(context, ref, n),
                  ),
                ),
              ],
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: DialSpace.xxs),
            child: ExcludeSemantics(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Flexible(child: Text(lowLabel, style: ends)),
                  const SizedBox(width: DialSpace.s),
                  Flexible(
                    child: Text(
                      highLabel,
                      style: ends,
                      textAlign: TextAlign.end,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: DialSpace.m),
          Text(
            note,
            style: theme.textTheme.bodySmall?.copyWith(color: colors.muted),
          ),
          const SizedBox(height: DialSpace.m),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              TextButton(
                key: turnOffKey,
                style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
                onPressed: () => unawaited(_turnOff(context, ref)),
                child: const Text(turnOffLabel),
              ),
              TextButton(
                style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text(notNowLabel),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AnswerBox extends StatelessWidget {
  const _AnswerBox({super.key, required this.strength, required this.onTap});

  final int strength;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final BorderRadius radius = BorderRadius.circular(12);
    return Semantics(
      label: checkInLabel(strength),
      button: true,
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        color: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: DialColors.of(context).line, width: 1.5),
        ),
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: SizedBox(
            height: 48,
            child: Center(
              child: Text(
                '$strength',
                style: DialTypeScale.monoM.copyWith(
                  fontSize: 16,
                  height: 1,
                  color: scheme.onSurface,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
