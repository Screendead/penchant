import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/data/free_text_triggers.dart';
import 'package:tracker/data/limits.dart';
import 'package:tracker/data/trigger_usage.dart';
import 'package:tracker/data/unit.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/design/dial_theme.dart';
import 'package:tracker/errors/firestore_errors.dart';
import 'package:tracker/errors/report_error.dart';
import 'package:tracker/providers/tracker_writes_provider.dart';
import 'package:tracker/providers/unarchived_vice_list_provider.dart';
import 'package:tracker/providers/vice_list_provider.dart';
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/widgets/activity_date_field.dart';
import 'package:tracker/widgets/info_box.dart';
import 'package:tracker/widgets/trigger_picker.dart';
import 'package:tracker/widgets/undo_bar.dart' as undo_bar;
import 'package:tracker/writes/log_one.dart';
import 'package:tracker/writes/rejected_writes.dart';
import 'package:tracker/writes/settle_write.dart';
import 'package:tracker/writes/tracker_writes.dart';

class RecordNewActivityDialog extends ConsumerStatefulWidget {
  const RecordNewActivityDialog({
    super.key,
    this.initialViceID,
    this.bottomClearance = 0,
  });

  // The habit chosen when the dialog opens, as from a held Log-fan wedge.
  final String? initialViceID;
  // Lifts the bar it shows over a floating button, as Today's Log button.
  final double bottomClearance;

  static const Duration undoDuration = undo_bar.undoDuration;
  static const String recordedMessage = 'Activity recorded';

  static void showRecorded(
    ScaffoldMessengerState messenger, {
    required bool synced,
    required VoidCallback onUndo,
    double bottomClearance = 0,
  }) => undo_bar.showUndoBar(
    messenger,
    TextSpan(text: synced ? recordedMessage : queuedMessage),
    onUndo: onUndo,
    bottomClearance: bottomClearance,
  );

  @override
  ConsumerState<RecordNewActivityDialog> createState() =>
      _RecordNewActivityDialogState();
}

class _RecordNewActivityDialogState
    extends ConsumerState<RecordNewActivityDialog> {
  final GlobalKey<FormState> formKey = GlobalKey<FormState>();
  Vice? selectedVice;
  final TextEditingController dateController = TextEditingController();
  final TextEditingController quantityController = TextEditingController();
  String unit = Unit.item.nameFor(0);
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

    setState(() {
      loading = true;
      error = null;
    });

    final DateTime date = ActivityDateField.format.parse(dateController.text);
    final Vice vice = selectedVice!;
    final int quantity = int.parse(quantityController.text);
    final String entry = describeActivity(
      vice.name,
      vice.unit,
      quantity,
      date,
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );

    final bool synced;

    try {
      synced = await rejected.settle(
        writes.recordActivity(
          activityID,
          ownerID: user.uid,
          viceID: vice.id,
          quantity: quantity,
          createdAt: date,
          triggers: triggers,
        ),
        'Not saved: $entry',
      );
      _countFreeText(user.uid, triggers);
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
    final double clearance = widget.bottomClearance;
    Navigator.of(context).pop();
    RecordNewActivityDialog.showRecorded(
      messenger,
      synced: synced,
      bottomClearance: clearance,
      onUndo: () => undoLog(
        messenger,
        writes,
        rejected,
        written,
        entry,
        bottomClearance: clearance,
      ),
    );
  }

  void _countFreeText(String uid, List<String> saved) {
    ref
        .read(freeTextTriggersProvider)
        .recordUses(uid, saved.where(isFreeTextTrigger))
        .catchError((Object e, StackTrace stack) {
          reportError(e, stack, context: 'while counting free-text triggers');
        });
  }

  void updateUnit(int quantity) {
    setState(() {
      unit = selectedVice == null
          ? Unit.item.nameFor(quantity)
          : selectedVice!.unit.nameFor(quantity);
    });
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<Vice>> vicesValue = ref.watch(
      unarchivedViceListProvider,
    );
    final List<Vice>? vices = vicesValue.value;

    if (vicesValue.error case final Object loadError when vices == null) {
      return AlertDialog(
        title: const Text('Record New Habit Activity'),
        icon: const Icon(Icons.addchart),
        content: InfoBox(
          message: loadErrorMessage('your habits', loadError),
          isError: true,
          onRetry: () =>
              ref.invalidate(viceListForUserProvider, asReload: true),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      );
    }

    if (vices == null) {
      return const Center(child: CircularProgressIndicator());
    }
    // Each emission brings new Vice instances, so the dropdown keys on the id;
    // a vice archived meanwhile drops out of the selection.
    if (!_initialApplied) {
      _initialApplied = true;
      selectedVice = vices
          .where((Vice v) => v.id == widget.initialViceID)
          .firstOrNull;
      if (selectedVice != null) {
        unit = selectedVice!.unit.nameFor(0);
      }
    }
    selectedVice = vices
        .where((Vice v) => v.id == selectedVice?.id)
        .firstOrNull;

    return PopScope(
      canPop: !loading,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // The scrim below stops pointers but not a screen reader.
          ExcludeSemantics(
            excluding: loading,
            child: AlertDialog(
              scrollable: true,
              title: const Text('Record New Habit Activity'),
              icon: const Icon(Icons.addchart),
              content: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      key: ValueKey<String?>(selectedVice?.id),
                      initialValue: selectedVice?.id,
                      isExpanded: true,
                      hint: const Text('Select Habit'),
                      onChanged: (String? id) {
                        final int parsedQuantity =
                            int.tryParse(quantityController.text) ?? 0;

                        setState(() {
                          selectedVice = vices.firstWhere(
                            (Vice v) => v.id == id,
                          );
                          updateUnit(parsedQuantity);
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
                      validator: (String? value) {
                        if (value == null) {
                          return 'Please select a habit';
                        }

                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    ActivityDateField(
                      controller: dateController,
                      startLive: true,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: quantityController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Quantity',
                        suffixText: unit,
                      ),
                      validator: quantityError,
                      onChanged: (String value) {
                        final int parsed = int.tryParse(value) ?? 0;
                        updateUnit(parsed);
                      },
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: TriggersField(
                        value: triggers,
                        onChanged: (List<String> picked) =>
                            setState(() => triggers = picked),
                        viceID: selectedVice?.id,
                        viceName: selectedVice?.name ?? '',
                        enabled: !loading,
                      ),
                    ),
                    if (error != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actionsAlignment: MainAxisAlignment.spaceBetween,
              actions: <Widget>[
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                  child: const Text('Cancel'),
                ),
                TextButton.icon(
                  onPressed: loading ? null : _record,
                  label: const Text('Record'),
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
          ),
          if (loading) ...[
            Positioned.fill(
              child: ColoredBox(color: DialColors.of(context).scrim),
            ),
            const Center(child: CircularProgressIndicator()),
          ],
        ],
      ),
    );
  }

  @override
  void dispose() {
    dateController.dispose();
    quantityController.dispose();
    super.dispose();
  }
}
