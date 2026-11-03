import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:tracker/data/limits.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/providers/tracker_writes_provider.dart';
import 'package:tracker/providers/vice_activity_history_provider.dart';
import 'package:tracker/providers/vice_list_provider.dart';

class ViceActivityEditorPage extends ConsumerStatefulWidget {
  const ViceActivityEditorPage({
    super.key,
    required this.viceID,
    required this.activityID,
  });

  final String viceID;
  final String activityID;

  static final DateFormat dateFormat = DateFormat('dd/MM/yyyy, HH:mm:ss');

  @override
  ConsumerState<ViceActivityEditorPage> createState() =>
      _ViceActivityEditorPageState();
}

class _ViceActivityEditorPageState extends ConsumerState<ViceActivityEditorPage> {
  static final DateFormat dateFormat = ViceActivityEditorPage.dateFormat;

  final GlobalKey<FormState> formKey = GlobalKey<FormState>();
  final TextEditingController dateController = TextEditingController();
  final TextEditingController quantityController = TextEditingController();
  bool manualDate = true;
  bool loading = false;
  String? error;
  Timer? dateUpdaterTimer;
  bool initialized = false;
  String initialDateText = '';
  String initialQuantityText = '';

  String get nowText => dateFormat.format(DateTime.now());

  void initializeFromActivity(ViceActivity activity) {
    if (initialized) {
      return;
    }

    initialDateText = dateFormat.format(activity.createdAt.toDate());
    initialQuantityText = activity.quantity.toString();
    dateController.text = initialDateText;
    quantityController.text = initialQuantityText;
    initialized = true;
  }

  @override
  void initState() {
    super.initState();

    dateUpdaterTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted && manualDate == false) {
        dateController.text = nowText;
      }
    });
  }

  @override
  void dispose() {
    dateUpdaterTimer?.cancel();
    dateController.dispose();
    quantityController.dispose();
    super.dispose();
  }

  Future<void> _deleteActivity() async {
    try {
      await ref.read(trackerWritesProvider).deleteActivity(widget.activityID);
      if (mounted) {
        Navigator.of(context).pop();
      }
    } on FirebaseException catch (e) {
      if (mounted) {
        setState(() {
          error = e.message ?? 'Unable to delete activity';
        });
      }
    }
  }

  Future<void> _saveActivity() async {
    if (!formKey.currentState!.validate()) {
      return;
    }

    // A field the user left alone may show a parser default for a legacy value
    // the rules would still accept, so only edited fields are written.
    final Map<String, Object> changes = <String, Object>{
      if (dateController.text != initialDateText)
        'createdAt': dateFormat.parse(dateController.text),
      if (quantityController.text != initialQuantityText)
        'quantity': int.parse(quantityController.text),
    };

    if (changes.isEmpty) {
      Navigator.of(context).pop();
      return;
    }

    setState(() {
      loading = true;
      error = null;
    });

    try {
      await ref
          .read(trackerWritesProvider)
          .updateActivity(
            widget.activityID,
            quantity: changes['quantity'] as int?,
            createdAt: changes['createdAt'] as DateTime?,
          )
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () => Future.error(TimeoutException(null)),
          );

      if (mounted) {
        Navigator.of(context).pop();
      }
    } on FirebaseException catch (e) {
      setState(() {
        error = 'Error updating activity: ${e.message}';
      });
    } on TimeoutException {
      setState(() {
        error = 'Request timed out';
      });
    } finally {
      if (mounted) {
        setState(() {
          loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<Vice>? viceList = ref.watch(viceListProvider).value;
    final List<ViceActivity>? activityList =
        ref.watch(viceActivityHistoryProvider(widget.viceID)).value;

    if (viceList == null || activityList == null) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    final Vice? vice = viceList.where((Vice item) => item.id == widget.viceID).isEmpty
        ? null
        : viceList.firstWhere((Vice item) => item.id == widget.viceID);
    final ViceActivity? activity = activityList.where((ViceActivity item) => item.id == widget.activityID).isEmpty
        ? null
        : activityList.firstWhere((ViceActivity item) => item.id == widget.activityID);

    if (vice == null || activity == null) {
      return const Scaffold(
        body: Center(
          child: Text('Activity not found'),
        ),
      );
    }

    initializeFromActivity(activity);

    return Stack(
      alignment: Alignment.center,
      children: [
        Scaffold(
          appBar: AppBar(
            title: Text('Edit ${vice.name} activity'),
            actions: [
              IconButton(
                tooltip: 'Delete',
                icon: const Icon(Icons.delete_outline),
                onPressed: loading ? null : _deleteActivity,
              ),
              TextButton(
                onPressed: loading ? null : _saveActivity,
                child: const Text('Save'),
              ),
            ],
          ),
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    initialValue: vice.name,
                    readOnly: true,
                    decoration: const InputDecoration(
                      labelText: 'Vice',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: dateController,
                    readOnly: !manualDate,
                    decoration: InputDecoration(
                      labelText: 'Date and Time',
                      suffixIcon: IconButton(
                        tooltip: manualDate
                            ? 'Use current date and time'
                            : 'Manually enter date and time',
                        icon: manualDate
                            ? const Icon(Icons.lock_open)
                            : const Icon(Icons.lock_clock),
                        onPressed: () {
                          setState(() {
                            manualDate = !manualDate;
                            if (manualDate) {
                              dateController.text = dateFormat
                                  .format(activity.createdAt.toDate());
                            } else {
                              dateController.text = nowText;
                            }
                          });
                        },
                      ),
                    ),
                    validator: (String? value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter a date and time';
                      }

                      try {
                        dateFormat.parse(value);
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

                      final DateTime firstDate = DateTime(2000);
                      final DateTime lastDate = DateTime(2100);
                      final DateTime stored = activity.createdAt.toDate();
                      // The picker asserts its initial date is in range; an
                      // unreadable legacy date reads as the epoch.
                      final DateTime? date = await showDatePicker(
                        context: context,
                        initialDate: stored.isBefore(firstDate)
                            ? firstDate
                            : stored.isAfter(lastDate)
                            ? lastDate
                            : stored,
                        firstDate: firstDate,
                        lastDate: lastDate,
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

                      dateController.text = dateFormat.format(dateTime);
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: quantityController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Quantity',
                      suffixText: vice.unit.nameFor(1),
                    ),
                    validator: (String? value) =>
                        quantityError(value, unchanged: activity.quantity),
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
          ),
        ),
        if (loading) ...[
          Positioned.fill(
            child: Container(
              color: Colors.black.withValues(alpha: 0.5),
            ),
          ),
          const CircularProgressIndicator(),
        ],
      ],
    );
  }
}