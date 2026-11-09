import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/data/free_text_triggers.dart';
import 'package:tracker/data/limits.dart';
import 'package:tracker/data/trigger_usage.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/design/dial_theme.dart';
import 'package:tracker/errors/firestore_errors.dart';
import 'package:tracker/errors/report_error.dart';
import 'package:tracker/formats.dart';
import 'package:tracker/providers/tracker_writes_provider.dart';
import 'package:tracker/providers/vice_activity_history_provider.dart';
import 'package:tracker/providers/vice_list_provider.dart';
import 'package:tracker/widgets/info_box.dart';
import 'package:tracker/widgets/amount_fields.dart';
import 'package:tracker/widgets/time_dial.dart';
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
  final GlobalKey<FormState> formKey = GlobalKey<FormState>();
  final EntryTimeController timeController = EntryTimeController();
  final TextEditingController quantityController = TextEditingController();
  bool loading = false;
  String? error;
  // The stored values as the fields last showed them. A field still showing
  // its stored value follows the activity as it changes; once the user edits
  // it, it keeps their value.
  DateTime? storedAt;
  String storedQuantityText = '';
  ViceActivity? shown;
  // Null until the user changes the triggers; until then they follow the
  // stored ones.
  List<String>? editedTriggers;

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
    final DateTime at = activity.createdAt.toDate();
    final String quantityText = formatAmount(activity.measure);
    if (timeController.at == storedAt) {
      timeController.at = at;
    }
    if (quantityController.text == storedQuantityText) {
      quantityController.text = quantityText;
    }
    storedAt = at;
    storedQuantityText = quantityText;
  }

  @override
  void dispose() {
    timeController.dispose();
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
    final DateTime? createdAt = timeController.at != storedAt
        ? timeController.value
        : null;
    final StoredMeasure? measure = quantityController.text != storedQuantityText
        ? storedMeasure(
            parseAmount(quantityController.text)!,
            keepAmount: activity.amount != null,
          )
        : null;
    final List<String>? triggers = switch (editedTriggers) {
      // A locked entry's triggers are placeholders, never to be saved.
      final List<String> picked
          when !activity.locked && !listEquals(picked, activity.triggers) =>
        picked,
      _ => null,
    };

    if (createdAt == null && measure == null && triggers == null) {
      Navigator.of(context).pop();
      return;
    }

    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    setState(() {
      loading = true;
      error = null;
    });

    final RejectedWrites rejected = ref.read(rejectedWritesProvider.notifier);
    final FreeTextTriggers freeText = ref.read(freeTextTriggersProvider);
    try {
      final bool synced = await rejected.settle(
        ref
            .read(trackerWritesProvider)
            .updateActivity(
              widget.activityID,
              quantity: measure?.quantity,
              amount: measure?.amount,
              createdAt: createdAt,
              triggers: triggers,
            ),
        'Change not saved: ${_describe(vice, activity)}',
      );
      if (triggers case final List<String> picked) {
        freeText
            .recordUses(
              activity.ownerID,
              picked.where(
                (t) => isFreeTextTrigger(t) && !activity.triggers.contains(t),
              ),
            )
            .catchError((Object e, StackTrace stack) {
              reportError(
                e,
                stack,
                context: 'while counting free-text triggers',
              );
            });
      }
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
                  // Undo could not write a locked entry's content back.
                  onPressed: loading || activity.locked
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
            body: SingleChildScrollView(
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
                    const SizedBox(height: 24),
                    AmountFields(
                      quantityController: quantityController,
                      unit: vice.unit,
                      timeController: timeController,
                      editing: activity.id,
                      triggers: editedTriggers ?? activity.triggers,
                      onTriggersChanged: (List<String> picked) =>
                          setState(() => editedTriggers = picked),
                      viceID: vice.id,
                      viceName: vice.name,
                      enabled: !loading,
                      quantityValidator: (String? value) =>
                          quantityError(value, unchanged: activity.measure),
                      error: error,
                    ),
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
