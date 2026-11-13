import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/data/activity_content.dart';
import 'package:tracker/data/free_text_triggers.dart';
import 'package:tracker/data/limits.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/design/dial_theme.dart';
import 'package:tracker/design/tokens.dart';
import 'package:tracker/errors/firestore_errors.dart';
import 'package:tracker/errors/report_error.dart';
import 'package:tracker/formats.dart';
import 'package:tracker/providers/tracker_writes_provider.dart';
import 'package:tracker/providers/vice_activity_history_provider.dart';
import 'package:tracker/providers/vice_list_provider.dart';
import 'package:tracker/widgets/info_box.dart';
import 'package:tracker/widgets/amount_fields.dart';
import 'package:tracker/widgets/amount_sheet_frame.dart';
import 'package:tracker/widgets/time_dial.dart';
import 'package:tracker/widgets/urge_note_fields.dart';
import 'package:tracker/writes/delete_with_undo.dart';
import 'package:tracker/writes/rejected_writes.dart';
import 'package:tracker/writes/settle_write.dart';
import 'package:tracker/writes/what_was_going_on.dart';

class ViceActivityEditorPage extends ConsumerStatefulWidget {
  const ViceActivityEditorPage({
    super.key,
    required this.viceID,
    required this.activityID,
  });

  final String viceID;
  final String activityID;

  static const Key saveKey = ValueKey<String>('entry-editor-save');
  static const Key deleteKey = ValueKey<String>('entry-editor-delete');
  static const String saveLabel = 'Save';
  static const String deleteLabel = 'Delete';
  static const String notFoundMessage = 'Activity not found';

  // The editor as the amount sheet, so the dial stays in view behind it.
  static Route<void> route(RouteSettings settings, Widget page) =>
      ModalBottomSheetRoute<void>(
        builder: (_) => page,
        settings: settings,
        isScrollControlled: true,
        useSafeArea: true,
        barrierLabel: 'Close',
      );

  @override
  ConsumerState<ViceActivityEditorPage> createState() =>
      _ViceActivityEditorPageState();
}

class _ViceActivityEditorPageState
    extends ConsumerState<ViceActivityEditorPage> {
  final GlobalKey<FormState> formKey = GlobalKey<FormState>();
  final EntryTimeController timeController = EntryTimeController();
  final TextEditingController quantityController = TextEditingController();
  final TextEditingController noteController = TextEditingController();
  bool loading = false;
  String? error;
  // The stored values as the fields last showed them. A field still showing
  // its stored value follows the activity as it changes; once the user edits
  // it, it keeps their value.
  DateTime? storedAt;
  String storedQuantityText = '';
  String storedNoteText = '';
  ViceActivity? shown;
  // Like [editedTriggers]: the stored urge until the user picks one, and
  // then theirs (null for cleared), so [urgeEdited] tells the two apart.
  bool urgeEdited = false;
  int? editedUrge;
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
    final String noteText = activity.note ?? '';
    if (noteController.text == storedNoteText) {
      noteController.text = noteText;
    }
    storedAt = at;
    storedQuantityText = quantityText;
    storedNoteText = noteText;
  }

  @override
  void dispose() {
    timeController.dispose();
    quantityController.dispose();
    noteController.dispose();
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
    // A locked entry's content is placeholders, never to be saved.
    final ActivityContent? content = activity.locked
        ? null
        : switch (activity.content.withAnswers(
            triggers: editedTriggers ?? activity.triggers,
            urge: urgeEdited ? editedUrge : activity.urge,
            note: noteController.text == storedNoteText
                ? activity.note
                : storedNote(noteController.text),
          )) {
            final ActivityContent changed
                when changed.answersDiffer(activity.content) =>
              changed,
            _ => null,
          };

    if (createdAt == null && measure == null && content == null) {
      Navigator.of(context).pop();
      return;
    }

    if (content != null) {
      final String? refusal =
          answersTooLong(
            triggers: content.triggers,
            urge: content.urge,
            note: content.note,
          ) ??
          (ref.read(trackerWritesProvider).canWrite(content)
              ? null
              : 'Not saved. $noJournalKeyMessage');
      if (refusal != null) {
        setState(() => error = refusal);
        return;
      }
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
              content: content,
            ),
        'Change not saved: ${_describe(vice, activity)}',
      );
      if (content != null) {
        countFreeTextUses(
          freeText,
          activity.ownerID,
          content.triggers,
          already: activity.triggers,
        );
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

  Widget _message(Widget child) => AmountSheetFrame(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: SheetCloseButton(onPressed: () => Navigator.of(context).pop()),
        ),
        child,
      ],
    ),
  );

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
      return _message(
        InfoBox(
          message: loadErrorMessage('this activity', loadError),
          isError: true,
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
      return const AmountSheetFrame(
        child: SizedBox(
          height: 200,
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    final Vice? vice = viceList
        .where((Vice item) => item.id == widget.viceID)
        .firstOrNull;
    final ViceActivity? found = activityValue.hasError
        ? null
        : activityValue.value;
    // A delete leaves the local snapshot at once, long before the server
    // acknowledges it; keep the form up until this sheet pops.
    final ViceActivity? activity =
        (found != null && found.viceID == widget.viceID)
        ? found
        : (loading ? shown : null);
    shown = activity;

    if (vice == null || activity == null) {
      return _message(
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Text(
            ViceActivityEditorPage.notFoundMessage,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final ColorScheme scheme = Theme.of(context).colorScheme;
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
              child: AmountSheetFrame(
                child: Form(
                  key: formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SheetHabitHeader(
                        vice: vice,
                        onClose: loading
                            ? null
                            : () => Navigator.of(context).pop(),
                      ),
                      const SizedBox(height: 18),
                      AmountFields(
                        quantityController: quantityController,
                        unit: vice.units,
                        timeController: timeController,
                        editing: activity.id,
                        triggers: editedTriggers ?? activity.triggers,
                        onTriggersChanged: (List<String> picked) =>
                            setState(() => editedTriggers = picked),
                        viceID: vice.id,
                        viceName: vice.name,
                        urge: urgeEdited ? editedUrge : activity.urge,
                        onUrgeChanged: (int? value) => setState(() {
                          urgeEdited = true;
                          editedUrge = value;
                        }),
                        noteController: noteController,
                        answersEnabled: !activity.locked,
                        enabled: !loading,
                        quantityValidator: (String? value) =>
                            quantityError(value, unchanged: activity.measure),
                        error: error,
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          TextButton(
                            key: ViceActivityEditorPage.deleteKey,
                            style: TextButton.styleFrom(
                              foregroundColor: scheme.error,
                            ),
                            // Undo could not write a locked entry's content
                            // back.
                            onPressed: loading || activity.locked
                                ? null
                                : () => _deleteActivity(vice, activity),
                            child: const Text(
                              ViceActivityEditorPage.deleteLabel,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: FilledButton(
                              key: ViceActivityEditorPage.saveKey,
                              onPressed: loading
                                  ? null
                                  : () => _saveActivity(vice, activity),
                              child: Text(
                                ViceActivityEditorPage.saveLabel,
                                style: DialTypeScale.label.copyWith(
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          ),
                        ],
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
}
