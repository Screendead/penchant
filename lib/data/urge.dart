import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:tracker/data/activity_content.dart';
import 'package:tracker/data/json_fields.dart';
import 'package:tracker/data/sealed.dart';
import 'package:tracker/data/usage_series.dart';

// An urge that need not have become an entry: when it came, for which habit,
// how strong, and what happened. Born sealed: `ownerID`, `viceID` and
// `createdAt` stay plaintext for the queries; everything else exists only
// inside the envelope. A record, never a score: nothing counts urges passed.

const String urgesCollection = 'urges';

const String strengthField = 'strength';
const String outcomeField = 'outcome';
const String outcomeAtField = 'outcomeAt';

/// What the person said happened, from the check-in or the urge sheet.
enum UrgeOutcome { passed, stillThere, hadOne }

String outcomeWords(UrgeOutcome outcome) => switch (outcome) {
  UrgeOutcome.passed => 'Passed',
  UrgeOutcome.stillThere => 'Still there',
  UrgeOutcome.hadOne => 'Had one',
};

UrgeOutcome? readOutcome(Object? value) => value is String
    ? UrgeOutcome.values.where((UrgeOutcome o) => o.name == value).firstOrNull
    : null;

/// The sealed content. The outcome and its time are present together or not
/// at all.
class UrgeContent {
  const UrgeContent({
    required this.strength,
    this.zone,
    this.outcome,
    this.outcomeAt,
  });

  factory UrgeContent.read(Map<String, Object?> content) {
    final UrgeOutcome? outcome = readOutcome(content[outcomeField]);
    final DateTime? at = readWrittenAt(content[outcomeAtField]);
    return UrgeContent(
      strength: readUrge(content[strengthField]),
      zone: readZone(content[zoneField]),
      outcome: at == null ? null : outcome,
      outcomeAt: outcome == null ? null : at,
    );
  }

  /// 1 (barely) to 5 (couldn't not), the scale an entry's urge uses; null
  /// only for content that will not parse.
  final int? strength;

  /// The device's IANA time zone when the urge was noted.
  final String? zone;
  final UrgeOutcome? outcome;

  /// The device clock when the outcome was given.
  final DateTime? outcomeAt;

  UrgeContent answered(UrgeOutcome outcome, DateTime at) => UrgeContent(
    strength: strength,
    zone: zone,
    outcome: outcome,
    outcomeAt: at,
  );

  UrgeContent withStrength(int strength) => UrgeContent(
    strength: strength,
    zone: zone,
    outcome: outcome,
    outcomeAt: outcomeAt,
  );

  Map<String, Object?> toMap() => <String, Object?>{
    strengthField: strength,
    zoneField: ?zone,
    if (outcome != null && outcomeAt != null) ...<String, Object?>{
      outcomeField: outcome!.name,
      outcomeAtField: outcomeAt!.toUtc().millisecondsSinceEpoch,
    },
  };
}

class Urge {
  Urge({
    required this.id,
    required this.ownerID,
    required this.viceID,
    required this.createdAt,
    this.content = const UrgeContent(strength: null),
    this.pending = false,
    this.locked = false,
  });

  /// Never throws: a missing or mistyped field reads as its default.
  factory Urge.fromJson({
    required String id,
    required Map<String, dynamic> json,
    bool pending = false,
    Map<String, Object?>? opened,
  }) => Urge(
    id: id,
    ownerID: readString(json['ownerID']),
    viceID: readString(json['viceID']),
    createdAt: readTimestamp(json['createdAt'], pending: pending),
    content: opened == null
        ? const UrgeContent(strength: null)
        : UrgeContent.read(opened),
    pending: pending,
    locked: opened == null,
  );

  static Future<Urge> open(
    DocumentSnapshot<Map<String, dynamic>> doc,
    Map<String, dynamic> json,
    SealedOpener opener,
  ) async => Urge.fromJson(
    id: doc.id,
    json: json,
    pending: doc.metadata.hasPendingWrites,
    opened: await opener.open(urgesCollection, doc.id, json),
  );

  final String id;
  final String ownerID;
  final String viceID;

  /// The device clock when the urge was noted, as an entry's `createdAt`.
  final Timestamp createdAt;
  final UrgeContent content;

  /// A local write the server has not acknowledged yet.
  final bool pending;

  /// The envelope would not open here, so it must never be written back.
  final bool locked;

  DateTime get at => createdAt.toDate();
}

/// Where each urge in [range] sits on the Trends chart's x axis: bucket i's
/// point is at i, and its time spans i - 0.5 to i + 0.5, so an urge at noon
/// sits on its day's point. Never added to any total.
List<double> urgeChartPositions(UsageRange range, Iterable<Urge> urges) {
  final List<double> xs = <double>[];
  final int ms = range.stepDays * Duration.millisecondsPerDay;
  for (final Urge urge in urges) {
    final DateTime at = urge.at;
    final int? bucket = range.bucketOf(at);
    if (bucket == null) continue;
    final DateTime start = range.bucketStart(bucket);
    final double into = (at.difference(start).inMilliseconds / ms)
        .clamp(0, 1)
        .toDouble();
    xs.add(bucket - 0.5 + into);
  }
  return xs..sort();
}

/// How many urges each bucket of [range] holds.
List<int> urgeCounts(UsageRange range, Iterable<Urge> urges) {
  final List<int> counts = List<int>.filled(range.bucketCount, 0);
  for (final Urge urge in urges) {
    final int? bucket = range.bucketOf(urge.at);
    if (bucket != null) counts[bucket]++;
  }
  return counts;
}

String urgesWord(int n) => n == 1 ? 'urge' : 'urges';
