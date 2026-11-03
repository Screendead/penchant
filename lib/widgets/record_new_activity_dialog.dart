import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:tracker/crypto/key_service.dart';
import 'package:tracker/crypto/journal_key_provider.dart';
import 'package:tracker/crypto/journal_reader.dart';
import 'package:tracker/data/limits.dart';
import 'package:tracker/data/unit.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/providers/unarchived_vice_list_provider.dart';
import 'package:tracker/providers/user_provider.dart';

class RecordNewActivityDialog extends ConsumerStatefulWidget {
  static final DateFormat dateFormat = DateFormat('dd/MM/yyyy, HH:mm:ss');

  const RecordNewActivityDialog({super.key});

  static const Duration writeTimeout = Duration(seconds: 10);
  static const Duration undoDuration = Duration(seconds: 8);
  static const String recordedMessage = 'Activity recorded';
  static const String queuedMessage =
      'Saved on this device. It will sync when you are back online.';

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
  // One reference per dialog, so a second press writes the same document
  // rather than a duplicate. Lazy, so building the dialog needs no Firebase.
  late final DocumentReference<Map<String, dynamic>> activityRef =
      FirebaseFirestore.instance.collection('activities').doc();
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
    final JournalKeyState? key = ref.read(journalKeyProvider).value;

    if (user == null || key is! KeyReady) {
      setState(() {
        error = user == null ? 'You are signed out' : 'Your journal is locked';
      });

      return;
    }

    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    setState(() {
      loading = true;
      error = null;
    });

    final DateTime date = RecordNewActivityDialog.dateFormat.parse(
      dateController.text,
    );

    bool synced = true;

    try {
      final Blob enc = await sealQuantity(
        cipher: key.cipher,
        docId: activityRef.id,
        ownerID: user.uid,
        viceID: selectedVice!.id,
        quantity: int.parse(quantityController.text),
      );
      await activityRef
          .set({
            'createdAt': date,
            'ownerID': user.uid,
            'enc': enc,
            'viceID': selectedVice!.id,
          })
          .timeout(RecordNewActivityDialog.writeTimeout);
    } on FirebaseException catch (e) {
      if (mounted) {
        setState(() {
          // The rules deny a vice that was deleted after this list loaded.
          error = e.code == 'permission-denied'
              ? 'That vice no longer exists'
              : 'Error recording activity: ${e.message}';
        });
      }

      return;
    } on TimeoutException {
      // The write stays queued in the SDK and commits once the device
      // reconnects.
      synced = false;
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

    final DocumentReference<Map<String, dynamic>> written = activityRef;
    Navigator.of(context).pop();
    RecordNewActivityDialog.showRecorded(
      messenger,
      synced: synced,
      onUndo: () => _undo(messenger, written),
    );
  }

  // Static so the snackbar's closure holds no reference to this State, which
  // is disposed by the time Undo can be pressed.
  static Future<void> _undo(
    ScaffoldMessengerState messenger,
    DocumentReference<Map<String, dynamic>> activityRef,
  ) async {
    String message;

    try {
      await activityRef.delete().timeout(RecordNewActivityDialog.writeTimeout);
      message = 'Activity removed';
    } on FirebaseException catch (e) {
      message = 'Unable to undo: ${e.message ?? e.code}';
    } on TimeoutException {
      message = 'Undo has not reached the server yet';
    }

    if (messenger.mounted) {
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
    final List<Vice>? vices = ref.watch(unarchivedViceListProvider).value;

    if (vices == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return PopScope(
      canPop: !loading,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AlertDialog(
            title: const Text('Record New Vice Activity'),
            icon: const Icon(Icons.addchart),
            content: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<Vice>(
                    initialValue: selectedVice,
                    isExpanded: true,
                    hint: const Text('Select Vice'),
                    onChanged: (Vice? value) {
                      final int parsedQuantity =
                          int.tryParse(quantityController.text) ?? 0;

                      setState(() {
                        selectedVice = value;
                        updateUnit(parsedQuantity);
                      });
                    },
                    items: vices
                        .map(
                          (Vice vice) => DropdownMenuItem<Vice>(
                            value: vice,
                            child: Text(vice.name),
                          ),
                        )
                        .toList(),
                    decoration: const InputDecoration(labelText: 'Vice'),
                    validator: (Vice? value) {
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
                    Text(error!, style: const TextStyle(color: Colors.red)),
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
