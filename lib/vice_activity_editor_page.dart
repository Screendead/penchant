import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:tracker/data/limits.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/design/dial_theme.dart';
import 'package:tracker/errors/firestore_errors.dart';
import 'package:tracker/errors/report_error.dart';
import 'package:tracker/formats.dart';
import 'package:tracker/providers/tracker_writes_provider.dart';
import 'package:tracker/providers/vice_activity_history_provider.dart';
import 'package:tracker/providers/vice_list_provider.dart';
import 'package:tracker/widgets/activity_date_field.dart';
import 'package:tracker/widgets/info_box.dart';
import 'package:tracker/writes/delete_with_undo.dart';
import 'package:tracker/writes/rejected_writes.dart';
import 'package:tracker/writes/settle_write.dart';

class ViceActivityEditorPage extends ConsumerStatefulWidget {
  const ViceActivityEditorPage({
    super.key,
    required this.viceID,
    required this.activityID,
  });

  final String viceID;
  final String activityID;

  @override
  ConsumerState<ViceActivityEditorPage> createState() =>
      _ViceActivityEditorPageState();
}

class _ViceActivityEditorPageState
    extends ConsumerState<ViceActivityEditorPage> {
  static DateFormat get dateFormat => ActivityDateField.format;

  final GlobalKey<FormState> formKey = GlobalKey<FormState>();
  final TextEditingController dateController = TextEditingController();
  final TextEditingController quantityController = TextEditingController();
  bool loading = false;
  String? error;
  // The stored values as the fields last showed them. A field still showing
  // its stored value follows the activity as it changes; once the user edits
  // it, it keeps their value.
  String storedDateText = '';
  String storedQuantityText = '';
  ViceActivity? shown;

  @override
  void initState() {
    super.initState();
    ref.listenManual<AsyncValue<ViceActivity?>>(
      viceActivityProvider(widget.activityID),
      (_, AsyncValue<ViceActivity?> next) {
        // While this page's own write is in flight, a snapshot carries its
        // latency-compensated value, not what the server holds; following it
        // would mark a refused edit as stored.
        if (!loading) {
          _followValue(next);
        }
      },
      fireImmediately: true,
    );
  }

  void _followValue(AsyncValue<ViceActivity?> value) {
    if (value.value case final ViceActivity activity
        when activity.viceID == widget.viceID) {
      _follow(activity);
    }
  }

  // A refused write's rollback may not have reached the snapshot yet; until it
  // does, the snapshot is pending and the listener picks the rollback up.
  void _followRolledBack() {
    final AsyncValue<ViceActivity?> current = ref.read(
      viceActivityProvider(widget.activityID),
    );
    if (current.value?.pending == false) {
      _followValue(current);
    }
  }

  void _follow(ViceActivity activity) {
    final String dateText = dateFormat.format(activity.createdAt.toDate());
    final String quantityText = formatAmount(activity.measure);
    if (dateController.text == storedDateText) {
      dateController.text = dateText;
    }
    if (quantityController.text == storedQuantityText) {
      quantityController.text = quantityText;
    }
    storedDateText = dateText;
    storedQuantityText = quantityText;
  }

  @override
  void dispose() {
    dateController.dispose();
    quantityController.dispose();
    super.dispose();
  }

  String _describe(Vice vice, ViceActivity activity) => describeActivity(
    vice.name,
    vice.unit,
    activity.measure,
    activity.createdAt.toDate(),
    alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
  );

  // The bar's Undo writes the entry back, so the delete needs no confirming.
  void _deleteActivity(Vice vice, ViceActivity activity) {
    deleteWithUndo(
      ref,
      ScaffoldMessenger.of(context),
      vice,
      activity,
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
    Navigator.of(context).pop();
  }

  Future<void> _saveActivity(Vice vice, ViceActivity activity) async {
    if (!formKey.currentState!.validate()) {
      return;
    }

    // A field the user left alone may show a parser default for a legacy value
    // the rules would still accept, so only edited fields are written.
    final DateTime? createdAt = dateController.text != storedDateText
        ? dateFormat.parse(dateController.text)
        : null;
    final StoredMeasure? measure = quantityController.text != storedQuantityText
        ? storedMeasure(
            parseAmount(quantityController.text)!,
            keepAmount: activity.amount != null,
          )
        : null;

    if (createdAt == null && measure == null) {
      Navigator.of(context).pop();
      return;
    }

    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    setState(() {
      loading = true;
      error = null;
    });

    final RejectedWrites rejected = ref.read(rejectedWritesProvider.notifier);
    try {
      final bool synced = await rejected.settle(
        ref
            .read(trackerWritesProvider)
            .updateActivity(
              widget.activityID,
              quantity: measure?.quantity,
              amount: measure?.amount,
              createdAt: createdAt,
            ),
        'Change not saved: ${_describe(vice, activity)}',
      );
      if (!synced) {
        messenger.showSnackBar(const SnackBar(content: Text(queuedMessage)));
      }
      if (mounted) {
        Navigator.of(context).pop();
      }
    } on FirebaseException catch (e, stack) {
      reportError(e, stack, context: 'while updating an activity');
      if (!mounted) {
        return;
      }
      // The banner already says the entry was not saved.
      if (rejected.createRefused(widget.activityID)) {
        Navigator.of(context).pop();
        return;
      }
      setState(() {
        loading = false;
        error = 'Could not save this activity. ${firestoreErrorMessage(e)}';
      });
      _followRolledBack();
    }
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<Vice>> viceListValue = ref.watch(viceListProvider);
    final AsyncValue<ViceActivity?> activityValue = ref.watch(
      viceActivityProvider(widget.activityID),
    );
    // The rules deny reading a missing document, so a denial reads as not
    // found below.
    final Object? loadError =
        viceListValue.error ??
        switch (activityValue.error) {
          FirebaseException(code: 'permission-denied') => null,
          final Object? other => other,
        };

    if (loadError != null && !loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Edit activity')),
        body: ErrorView(
          message: loadErrorMessage('this activity', loadError),
          onRetry: () {
            ref.invalidate(viceListForUserProvider, asReload: true);
            ref.invalidate(viceActivityForUserProvider, asReload: true);
          },
        ),
      );
    }

    final List<Vice>? viceList = viceListValue.value;

    if (viceList == null ||
        (activityValue.isLoading && !activityValue.hasError)) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final Vice? vice = viceList
        .where((Vice item) => item.id == widget.viceID)
        .firstOrNull;
    final ViceActivity? found = activityValue.hasError
        ? null
        : activityValue.value;
    // A delete leaves the local snapshot at once, long before the server
    // acknowledges it; keep the form up until this page pops.
    final ViceActivity? activity =
        (found != null && found.viceID == widget.viceID)
        ? found
        : (loading ? shown : null);
    shown = activity;

    if (vice == null || activity == null) {
      return const Scaffold(body: Center(child: Text('Activity not found')));
    }

    return Stack(
      alignment: Alignment.center,
      children: [
        // The scrim below stops pointers but not a screen reader.
        ExcludeSemantics(
          excluding: loading,
          child: Scaffold(
            appBar: AppBar(
              title: Text('Edit ${vice.name} activity'),
              actions: [
                IconButton(
                  tooltip: 'Delete',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: loading
                      ? null
                      : () => _deleteActivity(vice, activity),
                ),
                TextButton(
                  onPressed: loading
                      ? null
                      : () => _saveActivity(vice, activity),
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
                      decoration: const InputDecoration(labelText: 'Habit'),
                    ),
                    const SizedBox(height: 16),
                    ActivityDateField(
                      controller: dateController,
                      startLive: false,
                      manualSeed: () => activity.createdAt.toDate(),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: quantityController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Quantity',
                        suffixText: vice.unit.nameFor(1),
                      ),
                      validator: (String? value) =>
                          quantityError(value, unchanged: activity.measure),
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
        ),
        if (loading) ...[
          Positioned.fill(
            child: ColoredBox(color: DialColors.of(context).scrim),
          ),
          const CircularProgressIndicator(),
        ],
      ],
    );
  }
}
