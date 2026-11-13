import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/activity_content.dart';
import 'package:tracker/data/limits.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

void main() {
  test('an entry from before the new fields reads them all as absent', () {
    final ActivityContent legacy = ActivityContent.read(<String, Object?>{
      'triggers': <Object?>['social'],
    });
    expect(legacy.triggers, <String>['social']);
    expect(legacy.urge, isNull);
    expect(legacy.note, isNull);
    expect(legacy.zone, isNull);
    expect(legacy.writtenAt, isNull);
    expect(legacy.loggedVia, isNull);
    expect(legacy.triggersAlone, isTrue);
  });

  test('mistyped or out-of-range values read as absent, never throw', () {
    final ActivityContent odd = ActivityContent.read(<String, Object?>{
      'triggers': 'social',
      'urge': 6,
      'note': 7,
      'zone': '',
      'writtenAt': '2026-01-01',
      'loggedVia': 'telepathy',
    });
    expect(odd.triggers, isEmpty);
    expect(odd.urge, isNull);
    expect(odd.note, isNull);
    expect(odd.zone, isNull);
    expect(odd.writtenAt, isNull);
    expect(odd.loggedVia, isNull);
    expect(ActivityContent.read(<String, Object?>{'urge': 0}).urge, isNull);
    expect(ActivityContent.read(<String, Object?>{'urge': 2.0}).urge, isNull);
  });

  test('the stored map round-trips and omits what is absent', () {
    final ActivityContent content = ActivityContent(
      triggers: const <String>['work/meeting'],
      urge: 5,
      note: 'Deadline',
      zone: 'America/New_York',
      writtenAt: DateTime.utc(2026, 11, 13, 21, 40),
      loggedVia: LoggedVia.widget,
    );
    final ActivityContent back = ActivityContent.read(content.toMap());
    expect(back.toMap(), content.toMap());
    expect(back.writtenAt!.isAtSameMomentAs(content.writtenAt!), isTrue);
    expect(const ActivityContent().toMap(), <String, Object?>{
      'triggers': <String>[],
    });
  });

  test('a parsed entry carries its content, and a locked one none', () {
    final ViceActivity entry = ViceActivity.fromJson(
      id: 'a',
      json: <String, dynamic>{
        'viceID': 'wine',
        'quantity': 1,
        'ownerID': 'owner',
        'createdAt': Timestamp.fromMillisecondsSinceEpoch(0),
        'sealed': Blob(Uint8List(40)),
      },
      opened: <String, Object?>{
        'triggers': <Object?>[],
        'urge': 3,
        'note': 'Home',
        'loggedVia': 'oneTap',
      },
    );
    expect(entry.urge, 3);
    expect(entry.note, 'Home');
    expect(entry.loggedVia, LoggedVia.oneTap);
    expect(entry.content.toMap(), <String, Object?>{
      'triggers': <String>[],
      'urge': 3,
      'note': 'Home',
      'loggedVia': 'oneTap',
    });

    final ViceActivity locked = ViceActivity.fromJson(
      id: 'a',
      json: <String, dynamic>{
        'viceID': 'wine',
        'quantity': 1,
        'ownerID': 'owner',
        'createdAt': Timestamp.fromMillisecondsSinceEpoch(0),
        'sealed': Blob(Uint8List(40)),
      },
    );
    expect(locked.locked, isTrue);
    expect(locked.urge, isNull);
    expect(locked.note, isNull);
  });

  test('answers differ only by triggers, urge or note', () {
    final ActivityContent stored = ActivityContent(
      triggers: const <String>['social'],
      zone: 'Europe/London',
      writtenAt: DateTime.utc(2026),
    );
    expect(
      stored
          .withAnswers(triggers: <String>['social'], urge: null, note: null)
          .answersDiffer(stored),
      isFalse,
    );
    final ActivityContent answered = stored.withAnswers(
      triggers: <String>['social'],
      urge: 2,
      note: null,
    );
    expect(answered.answersDiffer(stored), isTrue);
    expect(answered.zone, 'Europe/London');
    expect(answered.writtenAt, DateTime.utc(2026));
  });

  test('a note is one line of at most $maxNoteLength code units', () {
    expect(noteError(null), isNull);
    expect(noteError('x' * maxNoteLength), isNull);
    expect(noteError('x' * (maxNoteLength + 1)), isNotNull);
    expect(noteError('two\nlines'), isNotNull);
  });

  test('a full note and ten full triggers fit one envelope; escaped '
      'characters that would overflow it are refused', () {
    final List<String> triggers = List<String>.generate(
      maxTriggers,
      (int i) => '$i${'y' * (maxTriggerLength - 1)}',
    );
    expect(
      answersTooLong(
        triggers: triggers,
        urge: maxUrge,
        note: 'é' * maxNoteLength,
      ),
      isNull,
    );
    // Each control character is six bytes of JSON.
    expect(
      answersTooLong(
        triggers: List<String>.filled(maxTriggers, '\u0001' * maxTriggerLength),
        urge: null,
        note: '\u0001' * maxNoteLength,
      ),
      isNotNull,
    );
  });
}
