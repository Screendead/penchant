import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/activity_content.dart';
import 'package:tracker/data/day_note.dart';
import 'package:tracker/data/limits.dart';
import 'package:tracker/notes/follow_up.dart';

import 'fake_sealer.dart';

// firestore.rules bounds `sealed` to 4125 bytes; the device checks are the
// only guard on what goes in, so whatever they let through must seal within
// it, and the largest answers must be refused on the device.
const int _rulesMaxSealed = 4125;

String _fill(String unit, int length) => unit * length;

FollowUp _followUp(String unit) => FollowUp(
  question: '${_fill(unit, maxFollowUpQuestionLength - 1)}?',
  quote: _fill(unit, maxFollowUpQuoteLength),
  answer: _fill(unit, maxFollowUpAnswerLength),
);

List<String> _triggers(String unit) => <String>[
  for (int i = 0; i < maxTriggers; i++) _fill(unit, maxTriggerLength),
];

Future<int> _sealedBytes(Map<String, Object?> content) async {
  final Uint8List sealed = await FakeSealer().seal(
    content,
    context: 'dayNotes/u_2026-11-15',
  );
  return sealed.length;
}

void main() {
  // ASCII, two-byte, three-byte and JSON-escaped (6 bytes a unit) text.
  const List<String> units = <String>['a', 'é', '€', '\u0001'];

  group('day note at every maximum', () {
    for (final String unit in units) {
      test('U+${unit.codeUnitAt(0).toRadixString(16)}: refused on the device '
          'or sealed within the rules', () async {
        final String text = _fill(unit, maxDayNoteLength);
        final List<String> triggers = _triggers(unit);
        final FollowUp followUp = _followUp(unit);
        final String? error = dayNoteError(text, triggers, followUp: followUp);
        if (unit == 'a') {
          expect(error, isNull);
        } else {
          expect(error, dayNoteTooLong);
        }
        if (error == null) {
          final int bytes = await _sealedBytes(
            dayNoteContent(text: text, triggers: triggers, followUp: followUp),
          );
          expect(bytes, lessThanOrEqualTo(_rulesMaxSealed));
        }
      });
    }

    test(
      'the longest text the device accepts seals within the rules',
      () async {
        for (final String unit in units) {
          final List<String> triggers = _triggers(unit);
          final FollowUp followUp = _followUp(unit);
          int length = maxDayNoteLength;
          while (length > 0 &&
              dayNoteError(_fill(unit, length), triggers, followUp: followUp) !=
                  null) {
            length--;
          }
          if (length == 0) continue;
          final int bytes = await _sealedBytes(
            dayNoteContent(
              text: _fill(unit, length),
              triggers: triggers,
              followUp: followUp,
            ),
          );
          expect(bytes, lessThanOrEqualTo(_rulesMaxSealed), reason: unit);
        }
      },
    );
  });

  group('entry content at every maximum', () {
    for (final String unit in units) {
      test('U+${unit.codeUnitAt(0).toRadixString(16)}: refused on the device '
          'or sealed within the rules', () async {
        final String note = _fill(unit, maxNoteLength);
        final List<String> triggers = _triggers(unit);
        final FollowUp followUp = _followUp(unit);
        final String? error = answersTooLong(
          triggers: triggers,
          urge: 5,
          note: note,
          followUp: followUp,
        );
        if (unit == 'a') expect(error, isNull);
        if (unit == '\u0001') expect(error, isNotNull);
        if (error == null) {
          final int bytes = await _sealedBytes(
            ActivityContent(
              triggers: triggers,
              urge: 5,
              note: note,
              followUp: followUp,
              zone: 'America/Argentina/ComodRivadavia',
              writtenAt: DateTime.utc(9999),
              loggedVia: longestLoggedVia,
            ).toMap(),
          );
          expect(bytes, lessThanOrEqualTo(_rulesMaxSealed));
        }
      });
    }
  });
}
