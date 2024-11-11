import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:tracker/data/unit.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/providers/unarchived_vice_list_provider.dart';

class RecordNewActivityDialog extends ConsumerStatefulWidget {
  static final DateFormat dateFormat = DateFormat('dd/MM/yyyy, HH:mm:ss');

  const RecordNewActivityDialog({
    super.key,
    required this.context,
  });

  final BuildContext context;

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
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    return Stack(
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
                  value: selectedVice,
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
                  decoration: const InputDecoration(
                    labelText: 'Vice',
                  ),
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

                    dateController.text =
                        RecordNewActivityDialog.dateFormat.format(dateTime);
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
                  validator: (String? value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter a quantity';
                    }

                    if (int.tryParse(value) == null) {
                      return 'Please enter a valid number';
                    }

                    return null;
                  },
                  onChanged: (String value) {
                    final int parsed = int.tryParse(value) ?? 0;
                    updateUnit(parsed);
                  },
                ),
                if (error != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    error!,
                    style: const TextStyle(
                      color: Colors.red,
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
              onPressed: () async {
                if (formKey.currentState!.validate()) {
                  final DateTime date = DateFormat('dd/MM/yyyy, HH:mm')
                      .parse(dateController.text);

                  try {
                    await FirebaseFirestore.instance
                        .collection('activities')
                        .add({
                      'createdAt': date,
                      'ownerID': FirebaseAuth.instance.currentUser!.uid,
                      'quantity': int.parse(quantityController.text),
                      'viceID': selectedVice!.id,
                    }).timeout(
                      const Duration(seconds: 10),
                      onTimeout: () => Future.error(
                        TimeoutException('Request timed out'),
                      ),
                    );
                  } on FirebaseException catch (e) {
                    setState(() {
                      error = 'Error recording activity: ${e.message}';
                    });

                    return;
                  } on TimeoutException {
                    setState(() {
                      error = 'Request timed out';
                    });

                    return;
                  } finally {
                    if (widget.context.mounted) {
                      setState(() {
                        loading = false;
                      });
                    }
                  }

                  if (widget.context.mounted) {
                    Navigator.of(widget.context).pop();
                  }
                }
              },
              label: const Text('Record'),
              icon: const Icon(Icons.add),
            ),
          ],
        ),
        if (loading) ...[
          Expanded(
            child: Container(
              color: Colors.black.withOpacity(0.5),
            ),
          ),
          const CircularProgressIndicator(),
        ],
      ],
    );
  }

  @override
  void dispose() {
    dateUpdaterTimer.cancel();
    super.dispose();
  }
}
