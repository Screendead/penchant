import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:tracker/data/limits.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/errors/firestore_errors.dart';
import 'package:tracker/errors/report_error.dart';
import 'package:tracker/providers/tracker_writes_provider.dart';
import 'package:tracker/providers/vice_activity_history_provider.dart';
import 'package:tracker/providers/vice_list_provider.dart';
import 'package:tracker/widgets/activity_date_field.dart';
import 'package:tracker/widgets/info_box.dart';
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
  static final DateFormat dateFormat = ActivityDateField.format;

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
        if (next.value case final ViceActivity activity
            when activity.viceID == widget.viceID) {
          _follow(activity);
        }
      },
      fireImmediately: true,
    );
  }

  void _follow(ViceActivity activity) {
    final String dateText = dateFormat.format(activity.createdAt.toDate());
    final String quantityText = activity.quantity.toString();
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

  Future<void> _deleteActivity() async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    setState(() {
      loading = true;
      error = null;
    });

    try {
      final bool synced = await settleWrite(
        ref.read(trackerWritesProvider).deleteActivity(widget.activityID),
      );
      if (!synced) {
        messenger.showSnackBar(
          const SnackBar(content: Text(queuedDeleteMessage)),
        );
      }
      if (mounted) {
        Navigator.of(context).pop();
      }
    } on FirebaseException catch (e, stack) {
      reportError(e, stack, context: 'while deleting an activity');
      if (mounted) {
        setState(() {
          loading = false;
          error = 'Could not delete this activity. ${firestoreErrorMessage(e)}';
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
      if (dateController.text != storedDateText)
        'createdAt': dateFormat.parse(dateController.text),
      if (quantityController.text != storedQuantityText)
        'quantity': int.parse(quantityController.text),
    };

    if (changes.isEmpty) {
      Navigator.of(context).pop();
      return;
    }

    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    setState(() {
      loading = true;
      error = null;
    });

    try {
      final bool synced = await settleWrite(
        ref
            .read(trackerWritesProvider)
            .updateActivity(
              widget.activityID,
              quantity: changes['quantity'] as int?,
              createdAt: changes['createdAt'] as DateTime?,
            ),
      );
      if (!synced) {
        messenger.showSnackBar(const SnackBar(content: Text(queuedMessage)));
      }
      if (mounted) {
        Navigator.of(context).pop();
      }
    } on FirebaseException catch (e, stack) {
      reportError(e, stack, context: 'while updating an activity');
      if (mounted) {
        setState(() {
          loading = false;
          error = 'Could not save this activity. ${firestoreErrorMessage(e)}';
        });
      }
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

    final Vice? vice =
        viceList.where((Vice item) => item.id == widget.viceID).isEmpty
        ? null
        : viceList.firstWhere((Vice item) => item.id == widget.viceID);
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
                      decoration: const InputDecoration(labelText: 'Vice'),
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
        ),
        if (loading) ...[
          Positioned.fill(
            child: Container(color: Colors.black.withValues(alpha: 0.5)),
          ),
          const CircularProgressIndicator(),
        ],
      ],
    );
  }
}
