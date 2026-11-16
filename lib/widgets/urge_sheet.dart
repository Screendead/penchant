import 'dart:async';

import 'package:clock/clock.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/data/urge.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/design/dial_theme.dart';
import 'package:tracker/design/tokens.dart';
import 'package:tracker/errors/firestore_errors.dart';
import 'package:tracker/errors/report_error.dart';
import 'package:tracker/formats.dart';
import 'package:tracker/providers/tracker_writes_provider.dart';
import 'package:tracker/reminder/daily_nudge.dart';
import 'package:tracker/reminder/urge_check_in.dart';
import 'package:tracker/widgets/amount_sheet_frame.dart';
import 'package:tracker/widgets/pill_toggle.dart';
import 'package:tracker/widgets/record_new_activity_dialog.dart';
import 'package:tracker/widgets/undo_bar.dart';
import 'package:tracker/widgets/urge_note_fields.dart';
import 'package:tracker/writes/note_urge.dart';
import 'package:tracker/writes/rejected_writes.dart';
import 'package:tracker/writes/settle_write.dart';

// Noting an urge for one habit, or, given [urge], looking at one noted
// earlier: its strength, what happened, and Delete. Neutral throughout: the
// outcomes are three facts, none of them a win.
class UrgeSheet extends ConsumerStatefulWidget {
  const UrgeSheet({super.key, required this.vice, this.urge});

  final Vice vice;
  final Urge? urge;

  static const String newStrengthLabel = 'How strong is it?';
  static const String pastStrengthLabel = 'How strong was it?';
  static const String outcomeLabel = 'What happened?';
  static const String checkInLabel = 'Ask “Still there?” in 15 minutes';
  static const String checkInNote = 'A quiet notification that names no habit.';
  static const String doneLabel = 'Done';
  static const String deleteLabel = 'Delete';
  static const String lockedMessage =
      'This urge will not open on this device. You can still delete it.';

  static const Key doneKey = ValueKey<String>('urge-done');
  static const Key deleteKey = ValueKey<String>('urge-delete');
  static const Key checkInKey = ValueKey<String>('urge-check-in');
  static Key outcomeKey(UrgeOutcome o) => ValueKey<String>('urge-${o.name}');

  static Future<void> show(BuildContext context, Vice vice, {Urge? urge}) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => UrgeSheet(vice: vice, urge: urge),
      );

  @override
  ConsumerState<UrgeSheet> createState() => _UrgeSheetState();
}

class _UrgeSheetState extends ConsumerState<UrgeSheet> {
  late int? _strength = widget.urge?.content.strength;
  late UrgeOutcome? _outcome = widget.urge?.content.outcome;
  String? _checkInRefused;

  bool get _editing => widget.urge != null;

  Future<void> _setCheckIn(bool on) async {
    final UrgeCheckIn checkIn = ref.read(urgeCheckInProvider.notifier);
    if (!on) {
      await checkIn.turnOff();
      return;
    }
    final bool granted = await checkIn.turnOn();
    if (mounted) {
      setState(
        () => _checkInRefused = granted ? null : NudgeCopy.permissionDenied,
      );
    }
  }

  void _done() {
    final int? strength = _strength;
    if (strength == null) return;
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final NavigatorState navigator = Navigator.of(context);
    final bool h24 = MediaQuery.alwaysUse24HourFormatOf(context);
    navigator.pop();
    final Urge? urge = widget.urge;
    if (urge == null) {
      unawaited(
        noteUrge(
          ref,
          messenger,
          widget.vice,
          strength,
          alwaysUse24HourFormat: h24,
        ),
      );
      return;
    }
    final UrgeOutcome? outcome = _outcome;
    final bool answered = outcome != null && outcome != urge.content.outcome;
    if (!answered && strength == urge.content.strength) return;
    UrgeContent content = urge.content.withStrength(strength);
    if (answered) {
      content = content.answered(outcome, clock.now());
      unawaited(_withdrawCheckIn(urge.id));
    }
    unawaited(
      _save(
        messenger,
        urge,
        content,
        describeUrge(widget.vice.name, urge.at, alwaysUse24HourFormat: h24),
      ),
    );
    if (answered && outcome == UrgeOutcome.hadOne) {
      unawaited(
        RecordNewActivityDialog.show(
          navigator.context,
          initialViceID: widget.vice.id,
        ),
      );
    }
  }

  Future<void> _withdrawCheckIn(String urgeID) async {
    try {
      await ref.read(nudgeSchedulerProvider).cancelUrgeCheck(urgeID);
    } catch (e, stack) {
      reportError(e, stack, context: 'while cancelling an urge check-in');
    }
  }

  Future<void> _save(
    ScaffoldMessengerState messenger,
    Urge urge,
    UrgeContent content,
    String what,
  ) async {
    final RejectedWrites rejected = ref.read(rejectedWritesProvider.notifier);
    try {
      final bool synced = await rejected.settle(
        ref.read(trackerWritesProvider).updateUrge(urge.id, content),
        'Not saved: $what',
      );
      if (messenger.mounted) {
        showUndoBar(
          messenger,
          TextSpan(text: synced ? 'Urge saved' : queuedMessage),
        );
      }
    } on FirebaseException catch (e, stack) {
      reportError(e, stack, context: 'while saving an urge');
      if (messenger.mounted) {
        showUndoBar(
          messenger,
          TextSpan(text: 'Not saved. ${firestoreErrorMessage(e)}'),
        );
      }
    }
  }

  void _delete() {
    final Urge urge = widget.urge!;
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final bool h24 = MediaQuery.alwaysUse24HourFormatOf(context);
    Navigator.of(context).pop();
    unawaited(_withdrawCheckIn(urge.id));
    unawaited(
      removeUrge(
        messenger,
        ref.read(trackerWritesProvider),
        ref.read(rejectedWritesProvider.notifier),
        urge.id,
        describeUrge(widget.vice.name, urge.at, alwaysUse24HourFormat: h24),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final DialColors colors = DialColors.of(context);
    final bool h24 = MediaQuery.alwaysUse24HourFormatOf(context);
    final Urge? urge = widget.urge;
    final bool locked = urge?.locked ?? false;
    final bool checkIn = ref.watch(urgeCheckInProvider);
    final TextStyle? muted = theme.textTheme.bodyMedium?.copyWith(
      color: colors.muted,
    );

    final String when = urge == null
        ? 'Urge, now'
        : 'Urge at ${formatDayAndTime(urge.at, alwaysUse24HourFormat: h24)}';
    final DateTime? answeredAt = urge?.content.outcomeAt;

    return AmountSheetFrame(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SheetHabitHeader(
            vice: widget.vice,
            onClose: () => Navigator.of(context).pop(),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: DialSpace.m),
            child: Text(
              <String>[
                when,
                if (urge?.content.outcome case final UrgeOutcome o
                    when answeredAt != null)
                  '${outcomeWords(o)} at '
                      '${formatTime(answeredAt, alwaysUse24HourFormat: h24)}',
              ].join(' · '),
              style: muted,
            ),
          ),
          if (locked)
            Text(UrgeSheet.lockedMessage, style: theme.textTheme.bodyMedium)
          else ...<Widget>[
            UrgeField(
              value: _strength,
              label: _editing
                  ? UrgeSheet.pastStrengthLabel
                  : UrgeSheet.newStrengthLabel,
              optional: false,
              onChanged: (int? v) => setState(() => _strength = v),
            ),
            const SizedBox(height: DialSpace.m),
            if (_editing)
              _OutcomeChoice(
                value: _outcome,
                onChanged: (UrgeOutcome o) => setState(() => _outcome = o),
              )
            else ...<Widget>[
              MergeSemantics(
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            UrgeSheet.checkInLabel,
                            style: theme.textTheme.bodyLarge,
                          ),
                          Text(
                            UrgeSheet.checkInNote,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch.adaptive(
                      key: UrgeSheet.checkInKey,
                      value: checkIn,
                      onChanged: (bool on) => unawaited(_setCheckIn(on)),
                    ),
                  ],
                ),
              ),
              if (_checkInRefused case final String refused)
                Padding(
                  padding: const EdgeInsets.only(top: DialSpace.xs),
                  child: Text(
                    refused,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.error,
                    ),
                  ),
                ),
            ],
          ],
          const SizedBox(height: DialSpace.l),
          Row(
            children: <Widget>[
              if (_editing) ...<Widget>[
                TextButton(
                  key: UrgeSheet.deleteKey,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(44, 44),
                    foregroundColor: scheme.error,
                  ),
                  onPressed: _delete,
                  child: const Text(UrgeSheet.deleteLabel),
                ),
                const SizedBox(width: DialSpace.xs),
              ],
              if (!locked)
                Expanded(
                  child: FilledButton(
                    key: UrgeSheet.doneKey,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(44, 48),
                    ),
                    onPressed: _strength == null ? null : _done,
                    child: const Text(UrgeSheet.doneLabel),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OutcomeChoice extends StatelessWidget {
  const _OutcomeChoice({required this.value, required this.onChanged});

  final UrgeOutcome? value;
  final ValueChanged<UrgeOutcome> onChanged;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final DialColors colors = DialColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(bottom: DialSpace.xs),
          child: Text(
            UrgeSheet.outcomeLabel,
            style: theme.textTheme.titleSmall?.copyWith(color: colors.muted),
          ),
        ),
        Wrap(
          spacing: DialSpace.xs,
          runSpacing: DialSpace.xs,
          children: <Widget>[
            for (final UrgeOutcome o in UrgeOutcome.values)
              PillToggle(
                key: UrgeSheet.outcomeKey(o),
                selected: value == o,
                onPressed: () => onChanged(o),
                color: scheme.surfaceContainerHigh,
                selectedColor: scheme.surfaceContainerHighest,
                selectedSide: BorderSide(color: scheme.onSurface, width: 1.5),
                restForeground: scheme.onSurface,
                child: Text(outcomeWords(o)),
              ),
          ],
        ),
      ],
    );
  }
}
