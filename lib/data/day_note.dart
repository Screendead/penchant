import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:tracker/data/activity_triggers.dart';
import 'package:tracker/data/json_fields.dart';
import 'package:tracker/data/limits.dart';
import 'package:tracker/data/sealed.dart';

// A note about one local day: the person's own words and the triggers they
// confirmed. Born sealed: `text` and `triggers` exist only inside the
// envelope; `ownerID`, `day` and `createdAt` stay plaintext beside it.

const String dayNotesCollection = 'dayNotes';
const String dayNoteTextField = 'text';

/// The stored form of the local calendar day holding [day]: `2026-11-15`.
String dayKey(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-'
    '${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';

final RegExp dayKeyPattern = RegExp(r'^[0-9]{4}-[0-9]{2}-[0-9]{2}$');

/// One note per user per day: firestore.rules refuses a create under any
/// other id. Firebase uids hold no `_`, and the day is a fixed 10 characters.
String dayNoteID(String uid, String day) => '${uid}_$day';

/// What the envelope holds. The triggers are always present, so the stored
/// shape does not say whether the note has any.
Map<String, Object?> dayNoteContent({
  required String text,
  required List<String> triggers,
}) => <String, Object?>{
  dayNoteTextField: text.trim(),
  triggersField: writeTriggers(triggers),
};

/// Why [text] and [triggers] cannot be saved as a day note, or null. Sealed,
/// so this is their only guard.
String? dayNoteError(String text, List<String> triggers) {
  final String trimmed = text.trim();
  if (trimmed.isEmpty) {
    return 'Please write something about the day';
  }
  if (trimmed.length > maxDayNoteLength) {
    return 'Use $maxDayNoteLength characters or fewer';
  }
  return triggersError(triggers) ??
      sealedLengthError(
        utf8
            .encode(
              jsonEncode(dayNoteContent(text: trimmed, triggers: triggers)),
            )
            .length,
        tooLong: dayNoteTooLong,
      );
}

class DayNote {
  DayNote({
    required this.id,
    required this.ownerID,
    required this.day,
    required this.createdAt,
    this.text = '',
    this.triggers = const <String>[],
    this.pending = false,
    this.locked = false,
  });

  final String id;
  final String ownerID;

  /// The local calendar day asked about, as [dayKey] writes it; empty when
  /// missing or malformed.
  final String day;
  final Timestamp createdAt;
  final String text;
  final List<String> triggers;

  /// A local write the server has not acknowledged yet.
  final bool pending;

  /// The envelope would not open here, so its content must never be written
  /// back or replaced unseen.
  final bool locked;

  /// Never throws: a missing or mistyped field reads as its default, and a
  /// note without an envelope (which the rules never let in) reads as empty.
  factory DayNote.fromJson({
    required String id,
    required Map<String, dynamic> json,
    bool pending = false,
    Map<String, Object?>? opened,
  }) {
    final Object? day = json['day'];
    final Map<String, Object?> content = opened ?? const <String, Object?>{};
    final Object? text = content[dayNoteTextField];
    return DayNote(
      id: id,
      ownerID: readString(json['ownerID']),
      day: day is String && dayKeyPattern.hasMatch(day) ? day : '',
      createdAt: readTimestamp(json['createdAt'], pending: pending),
      text: text is String ? text : '',
      triggers: readTriggers(content[triggersField]),
      pending: pending,
      locked: opened == null,
    );
  }

  static Future<DayNote> open(
    DocumentSnapshot<Map<String, dynamic>> doc,
    Map<String, dynamic> json,
    SealedOpener opener,
  ) async => DayNote.fromJson(
    id: doc.id,
    json: json,
    pending: doc.metadata.hasPendingWrites,
    opened: await opener.open(dayNotesCollection, doc.id, json),
  );
}
