import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/data/activity_content.dart';
import 'package:tracker/data/limits.dart';
import 'package:tracker/design/tokens.dart';
import 'package:tracker/notes/follow_up.dart';
import 'package:tracker/widgets/note_panels.dart';
import 'package:tracker/widgets/trigger_picker.dart';
import 'package:tracker/widgets/urge_note_fields.dart';

/// What the panels close with on Done.
typedef WhatWasGoingOnPick = ({
  List<String> triggers,
  int? urge,
  String? note,
  FollowUp? followUp,
});

/// Opens the panels after a log of [viceID]: a note, the tags (read from the
/// note when a [NoteReader] is there, else picked by hand), the follow-up
/// question when the reader asked one, and the urge.
/// Returns null when dismissed without Done. With [onUndoLog] every panel
/// offers Undo log, which closes it with null and calls that. With [at], the
/// entry's time, the tags panel offers what the calendar suggests.
Future<WhatWasGoingOnPick?> showWhatWasGoingOn(
  BuildContext context, {
  required String viceID,
  required String viceName,
  List<String> initial = const <String>[],
  DateTime? at,
  VoidCallback? onUndoLog,
}) => showModalBottomSheet<WhatWasGoingOnPick>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (BuildContext context) => TriggerSources(
    viceID: viceID,
    at: at,
    builder: (BuildContext context, TriggerOffers offers) =>
        WhatWasGoingOnSheet(
          viceName: viceName,
          offers: offers,
          initial: initial,
          onDone: (WhatWasGoingOnPick pick) => Navigator.of(context).pop(pick),
          onUndoLog: onUndoLog == null
              ? null
              : () {
                  Navigator.of(context).pop();
                  onUndoLog();
                },
        ),
  ),
);

/// Three panels moved only by Back and Next, each with Done, and a fourth
/// after the tags when the reader asks a follow-up question.
class WhatWasGoingOnSheet extends ConsumerStatefulWidget {
  const WhatWasGoingOnSheet({
    super.key,
    required this.viceName,
    required this.onDone,
    this.offers = (
      usual: const <String>[],
      promoted: const <String>[],
      suggested: const <String>[],
    ),
    this.initial = const <String>[],
    this.onUndoLog,
  });

  final String viceName;
  final TriggerOffers offers;
  final List<String> initial;
  final ValueChanged<WhatWasGoingOnPick> onDone;
  final VoidCallback? onUndoLog;

  static const int panels = 3;
  static const Key nextKey = NotePanels.nextKey;
  static const Key backKey = NotePanels.backKey;
  static const Key doneKey = NotePanels.doneKey;
  static const Key flyingKey = NotePanels.flyingKey;
  static const String noteTitle = NotePanels.noteTitle;
  static const String readsHint = NotePanels.readsHint;
  static const String tagsTitle = NotePanels.tagsTitle;
  static const String handTitle = NotePanels.handTitle;
  static const String readingLine = NotePanels.readingLine;
  static const String readLine = NotePanels.readLine;
  static const String noneReadLine = NotePanels.noneReadLine;
  static const String failedLine = NotePanels.failedLine;
  static const Duration readTimeout = NotePanels.readTimeout;
  static const Key answerKey = NotePanels.answerKey;
  static const Key skipKey = NotePanels.skipKey;
  static const String followUpTitle = NotePanels.followUpTitle;

  @override
  ConsumerState<WhatWasGoingOnSheet> createState() =>
      _WhatWasGoingOnSheetState();
}

class _WhatWasGoingOnSheetState extends NotePanelsState<WhatWasGoingOnSheet> {
  int? urge;

  @override
  String get title => 'What was going on?';

  @override
  int get basePanelCount => WhatWasGoingOnSheet.panels;

  @override
  List<String> get initial => widget.initial;

  @override
  String get viceName => widget.viceName;

  @override
  TriggerOffers get offers => widget.offers;

  @override
  Widget? footerLeading(BuildContext context) => switch (widget.onUndoLog) {
    final VoidCallback undo => UndoLogButton(onPressed: undo),
    null => null,
  };

  @override
  void done() {
    final String? text = storedNote(note.text);
    final FollowUp? answered = followUp;
    final String? tooLong =
        noteError(text) ??
        answersTooLong(
          triggers: selected,
          urge: urge,
          note: text,
          followUp: answered,
        );
    if (tooLong != null) {
      setState(() => error = tooLong);
      return;
    }
    stopReading();
    widget.onDone((
      triggers: List<String>.of(selected),
      urge: urge,
      note: text,
      followUp: answered,
    ));
  }

  @override
  Widget build(BuildContext context) => buildPanels(context);

  @override
  Widget sheetPanel(BuildContext context, int index) => switch (index) {
    0 => notePanel(
      context,
      NoteField(controller: note, label: WhatWasGoingOnSheet.noteTitle),
    ),
    1 => tagsPanel(context),
    _ => ListView(
      padding: const EdgeInsets.all(DialSpace.m),
      children: <Widget>[
        UrgeField(
          value: urge,
          onChanged: (int? value) => setState(() => urge = value),
        ),
      ],
    ),
  };
}
