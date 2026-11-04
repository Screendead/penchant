import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:tracker/data/limits.dart';
import 'package:tracker/data/unit.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/errors/firestore_errors.dart';
import 'package:tracker/errors/report_error.dart';
import 'package:tracker/providers/tracker_writes_provider.dart';
import 'package:tracker/providers/unarchived_vice_list_provider.dart';
import 'package:tracker/providers/vice_list_provider.dart';
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/widgets/info_box.dart';
import 'package:tracker/writes/rejected_writes.dart';
import 'package:tracker/writes/settle_write.dart';
import 'package:tracker/writes/tracker_writes.dart';

class RecordNewActivityDialog extends ConsumerStatefulWidget {
  static final DateFormat dateFormat = DateFormat('dd/MM/yyyy, HH:mm:ss');

  const RecordNewActivityDialog({super.key});

  static const Duration undoDuration = Duration(seconds: 8);
  static const String recordedMessage = 'Activity recorded';

  static void showRecorded(
    ScaffoldMessengerState messenger, {
    required bool synced,
    required VoidCallback onUndo,
  }) {
    // A snackbar with an action persists by default and queues every later
    // snackbar behind it, so an earlier recording's Undo would stay on screen
    // and delete the wrong activity.
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        persist: false,
        duration: undoDuration,
        content: Text(synced ? recordedMessage : queuedMessage),
        action: SnackBarAction(label: 'Undo', onPressed: onUndo),
      ),
    );
  }

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
  bool manualDate = false;
  bool loading = false;

  late Timer dateUpdaterTimer;
  // One id per dialog, so a second press writes the same document rather
  // than a duplicate. Lazy, so building the dialog needs no Firebase.
  late final String activityID = ref
      .read(trackerWritesProvider)
      .newActivityID();
  String? error;

  String get dateTime =>
      RecordNewActivityDialog.dateFormat.format(DateTime.now());

  @override
  void initState() {
    super.initState();

    dateController.text = dateTime;
    dateUpdaterTimer = Timer.periodic(Duration(seconds: 1), (Timer timer) {
      if (mounted && manualDate == false) {
        dateController.text = dateTime;
      }
    });
  }

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

    final DateTime date = RecordNewActivityDialog.dateFormat.parse(
      dateController.text,
    );
    final Vice vice = selectedVice!;
    final int quantity = int.parse(quantityController.text);
    final String entry = describeActivity(vice.name, vice.unit, quantity, date);

    final bool synced;

    try {
      synced = await settleWrite(
        writes.recordActivity(
          activityID,
          ownerID: user.uid,
          viceID: vice.id,
          quantity: quantity,
          createdAt: date,
        ),
        onRejectedLater: rejected.reporter(
          'Not saved: $entry',
          creates: activityID,
        ),
      );
    } on FirebaseException catch (e, stack) {
      reportError(e, stack, context: 'while recording an activity');
      if (mounted) {
        setState(() {
          // The rules deny a vice that was deleted after this list loaded.
          error = e.code == 'permission-denied'
              ? 'That vice no longer exists'
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
      onUndo: () => _undo(messenger, writes, rejected, written, entry),
    );
  }

  // Static so the snackbar's closure holds no reference to this State, which
  // is disposed by the time Undo can be pressed.
  static Future<void> _undo(
    ScaffoldMessengerState messenger,
    TrackerWrites writes,
    RejectedWrites rejected,
    String activityID,
    String entry,
  ) async {
    String? message;

    try {
      message =
          await settleWrite(
            writes.deleteActivity(activityID),
            onRejectedLater: rejected.reporter(
              'Not deleted: $entry',
              changes: activityID,
            ),
          )
          ? 'Activity removed'
          : queuedDeleteMessage;
    } on FirebaseException catch (e, stack) {
      reportError(e, stack, context: 'while undoing a recorded activity');
      // The banner already says the entry was not saved.
      message = rejected.createRefused(activityID)
          ? null
          : 'Could not undo. ${firestoreErrorMessage(e)}';
    }

    if (message != null && messenger.mounted) {
      messenger.showSnackBar(SnackBar(content: Text(message)));
    }
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
        title: const Text('Record New Vice Activity'),
        icon: const Icon(Icons.addchart),
        content: InfoBox(
          message: loadErrorMessage('your vices', loadError),
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
              title: const Text('Record New Vice Activity'),
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
                      hint: const Text('Select Vice'),
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
                      decoration: const InputDecoration(labelText: 'Vice'),
                      validator: (String? value) {
                        if (value == null) {
                          return 'Please select a vice';
                        }

                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: dateController,
                      readOnly: !manualDate,
                      focusNode: FocusNode(),
                      decoration: InputDecoration(
                        labelText: 'Date and Time',
                        suffixIcon: IconButton(
                          tooltip: manualDate
                              ? 'Use current date and time'
                              : 'Manually enter date and time',
                          icon: manualDate
                              ? Icon(Icons.lock_open)
                              : Icon(Icons.lock_clock),
                          onPressed: () {
                            setState(() {
                              manualDate = !manualDate;
                            });
                          },
                        ),
                      ),
                      validator: (String? value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter a date and time';
                        }

                        try {
                          RecordNewActivityDialog.dateFormat.parse(value);
                        } on FormatException {
                          return 'Please enter a valid date and time';
                        }

                        return null;
                      },
                      onTap: () async {
                        if (!manualDate) {
                          return;
                        }

                        FocusScope.of(context).requestFocus(FocusNode());

                        final DateTime? date = await showDatePicker(
                          context: context,
                          initialDate: DateTime.now(),
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                        );

                        if (date == null || !context.mounted) {
                          return;
                        }

                        final TimeOfDay? time = await showTimePicker(
                          context: context,
                          initialTime: TimeOfDay.fromDateTime(date),
                        );

                        if (time == null) {
                          return;
                        }

                        final DateTime dateTime = DateTime(
                          date.year,
                          date.month,
                          date.day,
                          time.hour,
                          time.minute,
                        );

                        dateController.text = RecordNewActivityDialog.dateFormat
                            .format(dateTime);
                      },
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
              child: Container(color: Colors.black.withValues(alpha: 0.5)),
            ),
            const Center(child: CircularProgressIndicator()),
          ],
        ],
      ),
    );
  }

  @override
  void dispose() {
    dateUpdaterTimer.cancel();
    super.dispose();
  }
}
