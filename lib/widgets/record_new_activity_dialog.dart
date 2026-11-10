import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/data/free_text_triggers.dart';
import 'package:tracker/data/trigger_usage.dart';
import 'package:tracker/data/unit.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/design/dial_theme.dart';
import 'package:tracker/design/dial_icons.dart';
import 'package:tracker/design/habit_mark.dart';
import 'package:tracker/design/tokens.dart';
import 'package:tracker/widgets/amount_fields.dart';
import 'package:tracker/widgets/bead_painter.dart';
import 'package:tracker/widgets/circle_button.dart';
import 'package:tracker/errors/firestore_errors.dart';
import 'package:tracker/errors/report_error.dart';
import 'package:tracker/formats.dart';
import 'package:tracker/providers/tracker_writes_provider.dart';
import 'package:tracker/providers/unarchived_vice_list_provider.dart';
import 'package:tracker/providers/vice_list_provider.dart';
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/widgets/info_box.dart';
import 'package:tracker/widgets/time_dial.dart';
import 'package:tracker/widgets/undo_bar.dart' as undo_bar;
import 'package:tracker/writes/log_one.dart';
import 'package:tracker/writes/rejected_writes.dart';
import 'package:tracker/writes/settle_write.dart';
import 'package:tracker/writes/tracker_writes.dart';

class RecordNewActivityDialog extends ConsumerStatefulWidget {
  const RecordNewActivityDialog({super.key, this.initialViceID});

  // The habit chosen when the dialog opens, as from a held Log-fan wedge.
  final String? initialViceID;

  static const Duration undoDuration = undo_bar.undoDuration;
  static const Key submitKey = ValueKey<String>('amount-sheet-submit');
  // What the primary button is called to a screen reader; its visible text
  // names the amount and time.
  static const String submitLabel = 'Record';

  // Opens the sheet over [context]'s route.
  static Future<void> show(BuildContext context, {String? initialViceID}) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => RecordNewActivityDialog(initialViceID: initialViceID),
      );
  static const String recordedMessage = 'Activity recorded';

  static void showRecorded(
    ScaffoldMessengerState messenger, {
    required bool synced,
    required VoidCallback onUndo,
  }) => undo_bar.showUndoBar(
    messenger,
    TextSpan(text: synced ? recordedMessage : queuedMessage),
    onUndo: onUndo,
  );

  @override
  ConsumerState<RecordNewActivityDialog> createState() =>
      _RecordNewActivityDialogState();
}

class _RecordNewActivityDialogState
    extends ConsumerState<RecordNewActivityDialog> {
  final GlobalKey<FormState> formKey = GlobalKey<FormState>();
  Vice? selectedVice;
  final EntryTimeController timeController = EntryTimeController();
  final TextEditingController quantityController = TextEditingController(
    text: formatAmount(defaultQuantity),
  );
  List<String> triggers = const <String>[];
  bool loading = false;
  bool _initialApplied = false;

  // One id per dialog, so a second press writes the same document rather
  // than a duplicate. Lazy, so building the dialog needs no Firebase.
  late final String activityID = ref
      .read(trackerWritesProvider)
      .newActivityID();
  String? error;

  Future<void> _record() async {
    if (!formKey.currentState!.validate()) {
      return;
    }

    final User? user = ref.read(userProvider).value;

    if (user == null) {
      setState(() {
        error = 'You are signed out';
      });

      return;
    }

    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final TrackerWrites writes = ref.read(trackerWritesProvider);
    final RejectedWrites rejected = ref.read(rejectedWritesProvider.notifier);
    // The sheet stays open with what was typed, to save once the key loads.
    if (!writes.canCreate) {
      setState(() {
        error = 'Not recorded. $noJournalKeyMessage';
      });
      return;
    }

    setState(() {
      loading = true;
      error = null;
    });

    final DateTime date = timeController.value;
    final Vice vice = selectedVice!;
    final num typed = parseAmount(quantityController.text)!;
    final StoredMeasure measure = storedMeasure(typed);
    final String entry = describeActivity(
      vice.name,
      vice.unit,
      typed,
      date,
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );

    final FreeTextTriggers freeText = ref.read(freeTextTriggersProvider);
    final bool synced;

    try {
      synced = await rejected.settle(
        writes.recordActivity(
          activityID,
          ownerID: user.uid,
          viceID: vice.id,
          quantity: measure.quantity,
          amount: measure.amount,
          createdAt: date,
          triggers: triggers,
        ),
        'Not saved: $entry',
      );
      _countFreeText(freeText, user.uid, triggers);
    } on FirebaseException catch (e, stack) {
      reportError(e, stack, context: 'while recording an activity');
      if (mounted) {
        setState(() {
          // The rules deny a vice that was deleted after this list loaded.
          error = e.code == 'permission-denied'
              ? 'That habit no longer exists'
              : 'Not recorded. ${firestoreErrorMessage(e)}';
        });
      }

      return;
    } finally {
      if (mounted) {
        setState(() {
          loading = false;
        });
      }
    }

    if (!mounted) {
      return;
    }

    final String written = activityID;
    Navigator.of(context).pop();
    RecordNewActivityDialog.showRecorded(
      messenger,
      synced: synced,
      onUndo: () => undoLog(messenger, writes, rejected, written, entry),
    );
  }

  // Runs after the save, when this dialog may be gone, so it takes no ref.
  void _countFreeText(FreeTextTriggers store, String uid, List<String> saved) {
    store.recordUses(uid, saved.where(isFreeTextTrigger)).catchError((
      Object e,
      StackTrace stack,
    ) {
      reportError(e, stack, context: 'while counting free-text triggers');
    });
  }

  // The button's label in runs; the numbers in a run marked true set in Mono.
  List<(String, bool)> _submitLabel(Vice? vice) {
    final num typed = parseAmount(quantityController.text) ?? 0;
    final DateTime at = timeController.value;
    final List<(String, bool)> runs = vice == null
        ? <(String, bool)>[('Record', false)]
        : <(String, bool)>[
            ('Log ', false),
            (formatCount(typed), true),
            (' ${vice.unit.nameFor(typed)}', false),
          ];
    return <(String, bool)>[
      ...runs,
      (' at ', false),
      (
        formatTime(
          at,
          alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
        ),
        true,
      ),
    ];
  }

  Widget _header(BuildContext context, List<Vice> vices, Vice? chosen) {
    final List<Vice> all = ref.watch(viceListProvider).value ?? vices;
    final Widget close = CircleButton(
      flat: true,
      icon: DialGlyph.close,
      tooltip: 'Close',
      onPressed: loading ? null : () => Navigator.of(context).pop(),
    );
    if (widget.initialViceID != null && chosen != null) {
      final HabitMark? mark = habitMarks(all)[chosen.id];
      return Row(
        children: [
          if (mark != null) ...[
            HabitPip(mark: mark, size: 12),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Text(
              chosen.name,
              style: DialTypeScale.displayM.copyWith(fontSize: 20),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          close,
        ],
      );
    }
    return Row(
      children: [
        Expanded(
          child: DropdownButtonFormField<String>(
            key: ValueKey<String?>(chosen?.id),
            initialValue: chosen?.id,
            isExpanded: true,
            hint: const Text('Select Habit'),
            onChanged: (String? id) {
              setState(() {
                selectedVice = vices.firstWhere((Vice v) => v.id == id);
              });
            },
            items: vices
                .map(
                  (Vice vice) => DropdownMenuItem<String>(
                    value: vice.id,
                    child: Text(vice.name),
                  ),
                )
                .toList(),
            decoration: const InputDecoration(labelText: 'Habit'),
            validator: (String? value) =>
                value == null ? 'Please select a habit' : null,
          ),
        ),
        const SizedBox(width: 10),
        close,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<Vice>> vicesValue = ref.watch(
      unarchivedViceListProvider,
    );
    final List<Vice>? vices = vicesValue.value;

    if (vicesValue.error case final Object loadError when vices == null) {
      return _SheetFrame(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InfoBox(
              message: loadErrorMessage('your habits', loadError),
              isError: true,
              onRetry: () =>
                  ref.invalidate(viceListForUserProvider, asReload: true),
            ),
            const SizedBox(height: 14),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
          ],
        ),
      );
    }

    if (vices == null) {
      return const _SheetFrame(
        child: SizedBox(
          height: 200,
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    // Each emission brings new Vice instances, so the dropdown keys on the id;
    // a vice archived meanwhile drops out of the selection.
    if (!_initialApplied) {
      _initialApplied = true;
      selectedVice = vices
          .where((Vice v) => v.id == widget.initialViceID)
          .firstOrNull;
    }
    selectedVice = vices
        .where((Vice v) => v.id == selectedVice?.id)
        .firstOrNull;
    final Vice? chosen = selectedVice;

    return PopScope(
      canPop: !loading,
      // A drag on the sheet would close it mid-save; this one wins the drag.
      child: GestureDetector(
        onVerticalDragUpdate: loading ? (_) {} : null,
        child: Stack(
          children: [
            // The scrim below stops pointers but not a screen reader.
            ExcludeSemantics(
              excluding: loading,
              child: _SheetFrame(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _header(context, vices, chosen),
                      const SizedBox(height: 18),
                      AmountFields(
                        quantityController: quantityController,
                        unit: chosen?.unit ?? Unit.item,
                        timeController: timeController,
                        triggers: triggers,
                        onTriggersChanged: (List<String> picked) =>
                            setState(() => triggers = picked),
                        viceID: chosen?.id,
                        viceName: chosen?.name ?? '',
                        enabled: !loading,
                        error: error,
                      ),
                      const SizedBox(height: 14),
                      ListenableBuilder(
                        listenable: Listenable.merge(<Listenable>[
                          quantityController,
                          timeController,
                        ]),
                        builder: (BuildContext context, _) {
                          final List<(String, bool)> runs = _submitLabel(
                            chosen,
                          );
                          return Semantics(
                            label: RecordNewActivityDialog.submitLabel,
                            hint: runs.map(((String, bool) r) => r.$1).join(),
                            excludeSemantics: true,
                            button: true,
                            enabled: !loading,
                            onTap: loading ? null : _record,
                            child: FilledButton(
                              key: RecordNewActivityDialog.submitKey,
                              onPressed: loading ? null : _record,
                              child: Text.rich(
                                TextSpan(
                                  children: <InlineSpan>[
                                    for (final (String text, bool mono) in runs)
                                      TextSpan(
                                        text: text,
                                        style: mono
                                            ? DialTypeScale.monoM.copyWith(
                                                fontSize: 17,
                                                height: 1,
                                              )
                                            : null,
                                      ),
                                  ],
                                ),
                                style: DialTypeScale.label.copyWith(
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (loading) ...[
              Positioned.fill(
                child: ColoredBox(color: DialColors.of(context).scrim),
              ),
              const Positioned.fill(
                child: Center(child: CircularProgressIndicator()),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    timeController.dispose();
    quantityController.dispose();
    super.dispose();
  }
}

// The sheet's padding, its grab bar, and room for the keyboard.
class _SheetFrame extends StatelessWidget {
  const _SheetFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final Color ink = Theme.of(context).colorScheme.onSurface;
    // Its own Material, so it also renders outside a sheet's.
    return Material(
      type: MaterialType.transparency,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          22,
          12,
          22,
          // Clear of the home indicator, as the mock-up's sheet is, or of
          // the keyboard while it is up (the padding drops to 0 then).
          math.max(
            MediaQuery.viewInsetsOf(context).bottom + 22,
            math.max(MediaQuery.paddingOf(context).bottom, 22),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 5,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: ink.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            child,
          ],
        ),
      ),
    );
  }
}
