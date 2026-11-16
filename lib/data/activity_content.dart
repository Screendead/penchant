import 'dart:convert';

import 'package:tracker/data/activity_triggers.dart';
import 'package:tracker/data/habit_strength.dart';
import 'package:tracker/data/limits.dart';
import 'package:tracker/notes/follow_up.dart';

// An activity's sealed content: everything inside its envelope. Only
// TrackerWrites writes it and only ViceActivity.fromJson reads it, through
// here. Every field but the triggers is optional and absent on entries
// written before it existed; a missing or mistyped value reads as absent.

const String urgeField = 'urge';
const String noteField = 'note';
const String zoneField = 'zone';
const String writtenAtField = 'writtenAt';
const String loggedViaField = 'loggedVia';
const String abvField = 'abv';
const String caffeineMgField = 'caffeineMg';

/// How an entry was logged: a one-tap log (a tally's `+`, a Log-fan wedge),
/// the amount sheet, the home-screen widget, Say it to log ([spoken], typed
/// or said), or Catch up ([caughtUp], recalled later, so its time is rougher
/// than a live one's). Stored by name; a build that predates a name reads it
/// as absent.
enum LoggedVia { oneTap, sheet, widget, spoken, caughtUp }

/// The longest stored name, for the envelope's bound.
final LoggedVia longestLoggedVia = LoggedVia.values.reduce(
  (LoggedVia a, LoggedVia b) => b.name.length > a.name.length ? b : a,
);

class ActivityContent {
  const ActivityContent({
    this.triggers = const <String>[],
    this.urge,
    this.note,
    this.zone,
    this.writtenAt,
    this.loggedVia,
    this.followUp,
    this.abv,
    this.caffeineMg,
  });

  /// Reads opened (or legacy plaintext) content; never throws.
  factory ActivityContent.read(Map<String, Object?> content) => ActivityContent(
    triggers: readTriggers(content[triggersField]),
    urge: readUrge(content[urgeField]),
    note: readNote(content[noteField]),
    zone: readZone(content[zoneField]),
    writtenAt: readWrittenAt(content[writtenAtField]),
    loggedVia: readLoggedVia(content[loggedViaField]),
    followUp: FollowUp.read(content),
    abv: readAbv(content[abvField]),
    caffeineMg: readCaffeineMg(content[caffeineMgField]),
  );

  final List<String> triggers;

  /// How strong the urge was, 1 (barely) to 5 (couldn't not).
  final int? urge;

  /// One line of the user's own words.
  final String? note;

  /// The IANA time zone the device was in when the entry was logged.
  final String? zone;

  /// The device clock when the entry was first written, so a live log can be
  /// told from one filled in later. The device clock, not the server's: a
  /// queued offline write would otherwise carry its sync time.
  final DateTime? writtenAt;

  final LoggedVia? loggedVia;

  /// The follow-up question about the note and the answer typed to it.
  final FollowUp? followUp;

  /// This entry's own strength, which wins over its habit's: percent alcohol
  /// by volume, or caffeine in mg per serving.
  final double? abv;
  final double? caffeineMg;

  /// The map sealed in the envelope. The triggers are always present, so the
  /// stored shape does not say whether the entry has any; the rest only when
  /// known.
  Map<String, Object?> toMap() => <String, Object?>{
    triggersField: writeTriggers(triggers),
    urgeField: ?urge,
    noteField: ?note,
    zoneField: ?zone,
    writtenAtField: ?writtenAt?.toUtc().millisecondsSinceEpoch,
    loggedViaField: ?loggedVia?.name,
    ...?followUp?.toMap(),
    abvField: ?abv,
    caffeineMgField: ?caffeineMg,
  };

  /// The bytes of JSON the envelope pads, which Sealer.bucketFor bounds.
  int get sealedLength => utf8.encode(jsonEncode(toMap())).length;

  /// The answers changed; the follow-up stays, as do the silent fields.
  ActivityContent withAnswers({
    required List<String> triggers,
    required int? urge,
    required String? note,
  }) => ActivityContent(
    triggers: triggers,
    urge: urge,
    note: note,
    zone: zone,
    writtenAt: writtenAt,
    loggedVia: loggedVia,
    followUp: followUp,
    abv: abv,
    caffeineMg: caffeineMg,
  );

  /// The entry's own strength changed; null for either clears it.
  ActivityContent withStrength({
    required double? abv,
    required double? caffeineMg,
  }) => ActivityContent(
    triggers: triggers,
    urge: urge,
    note: note,
    zone: zone,
    writtenAt: writtenAt,
    loggedVia: loggedVia,
    followUp: followUp,
    abv: abv,
    caffeineMg: caffeineMg,
  );

  ActivityContent withFollowUp(FollowUp? followUp) => ActivityContent(
    triggers: triggers,
    urge: urge,
    note: note,
    zone: zone,
    writtenAt: writtenAt,
    loggedVia: loggedVia,
    followUp: followUp,
    abv: abv,
    caffeineMg: caffeineMg,
  );

  /// Whether only triggers are set, as on an entry from before the rest
  /// existed: the one content a write without the journal key may carry.
  bool get triggersAlone =>
      urge == null &&
      note == null &&
      zone == null &&
      writtenAt == null &&
      loggedVia == null &&
      followUp == null &&
      abv == null &&
      caffeineMg == null;

  /// Whether the answers the user can change differ from [other]'s.
  bool answersDiffer(ActivityContent other) =>
      urge != other.urge ||
      note != other.note ||
      followUp != other.followUp ||
      abv != other.abv ||
      caffeineMg != other.caffeineMg ||
      triggers.length != other.triggers.length ||
      Iterable<int>.generate(
        triggers.length,
      ).any((int i) => triggers[i] != other.triggers[i]);
}

int? readUrge(Object? value) =>
    value is int && value >= minUrge && value <= maxUrge ? value : null;

String? readNote(Object? value) =>
    value is String && value.isNotEmpty ? value : null;

String? readZone(Object? value) =>
    value is String && value.isNotEmpty ? value : null;

DateTime? readWrittenAt(Object? value) => value is int
    ? DateTime.fromMillisecondsSinceEpoch(value, isUtc: true).toLocal()
    : null;

LoggedVia? readLoggedVia(Object? value) =>
    LoggedVia.values.where((LoggedVia v) => v.name == value).firstOrNull;

/// Why [triggers], [urge], [note] and [followUp] would not fit one envelope beside the
/// longest zone, write time, source and own strength an entry can carry, or
/// null.
String? answersTooLong({
  required List<String> triggers,
  required int? urge,
  required String? note,
  FollowUp? followUp,
}) =>
    followUp?.error ??
    sealedLengthError(
      ActivityContent(
        triggers: triggers,
        urge: urge,
        note: note,
        followUp: followUp,
        zone: _longestZone,
        writtenAt: DateTime.utc(9999),
        loggedVia: longestLoggedVia,
        abv: _longestStrength,
        caffeineMg: _longestStrength,
      ).sealedLength,
    );

// A strength is kept to two decimal places (roundStrength) under its bound,
// so none is written longer than this.
const double _longestStrength = 1999.99;

// Longer than any IANA zone name (the longest is 32 characters).
final String _longestZone = 'x' * 64;
