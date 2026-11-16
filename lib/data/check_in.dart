import 'package:tracker/data/activity_content.dart';

// A random check-in's answer: how strong any urge was at a moment the app
// chose at random, not one the person chose. Born sealed: `ownerID` and
// `createdAt` (the device clock at answering) stay plaintext; the rest
// exists only inside the envelope. It names no habit: the question is
// "any urge", so the answers are a baseline for urges noted at entries.

const String checkInsCollection = 'checkIns';

const String checkInStrengthField = 'strength';
const String promptedAtField = 'promptedAt';
const String answeredViaField = 'answeredVia';

/// 0 is no urge; 1 to 5 the scale an entry's urge uses.
const int minCheckIn = 0;
const int maxCheckIn = 5;

int? readCheckInStrength(Object? value) =>
    value is int && value >= minCheckIn && value <= maxCheckIn ? value : null;

/// Where the answer came from: a button on the notification, or the sheet a
/// tap on it opens.
enum CheckInVia { notification, sheet }

CheckInVia? readCheckInVia(Object? value) =>
    CheckInVia.values.where((CheckInVia v) => v.name == value).firstOrNull;

class CheckInContent {
  const CheckInContent({
    required this.strength,
    required this.promptedAt,
    this.zone,
    this.via,
  });

  /// Never throws: a missing or mistyped value reads as null.
  factory CheckInContent.read(Map<String, Object?> content) => CheckInContent(
    strength: readCheckInStrength(content[checkInStrengthField]),
    promptedAt: readWrittenAt(content[promptedAtField]),
    zone: readZone(content[zoneField]),
    via: readCheckInVia(content[answeredViaField]),
  );

  final int? strength;

  /// The random moment the notification was scheduled for, so a late answer
  /// can be told from a prompt one.
  final DateTime? promptedAt;

  /// The device's IANA time zone when answered.
  final String? zone;
  final CheckInVia? via;

  Map<String, Object?> toMap() => <String, Object?>{
    checkInStrengthField: strength,
    promptedAtField: ?promptedAt?.toUtc().millisecondsSinceEpoch,
    zoneField: ?zone,
    answeredViaField: ?via?.name,
  };
}

/// One answered check-in as Insights reads it: the local time it was
/// answered and its strength.
typedef CheckInAnswer = ({DateTime at, int strength});

/// A check-in's strength as read aloud and in the bar: the ends named, as
/// the sheet's scale names them.
String checkInLabel(int strength) => switch (strength) {
  0 => '0, no urge',
  1 => '1 of $maxCheckIn, barely',
  5 => '5 of $maxCheckIn, couldn’t not',
  _ => '$strength of $maxCheckIn',
};
