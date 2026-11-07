// Firestore's reference types are sealed, but a mock is the only way to see
// the map TrackerWrites hands the SDK without an emulator.
// ignore_for_file: subtype_of_sealed_class

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tracker/data/limits.dart';
import 'package:tracker/data/trigger_tree.dart';
import 'package:tracker/writes/tracker_writes.dart';

class _MockFirestore extends Mock implements FirebaseFirestore {}

class _MockCollection extends Mock
    implements CollectionReference<Map<String, dynamic>> {}

class _MockDocument extends Mock
    implements DocumentReference<Map<String, dynamic>> {}

void main() {
  group('the trigger tree', () {
    test('has the seven roots Jack picked, in order', () {
      expect(triggerTree.map((TriggerNode n) => n.label), [
        'Social',
        'Feeling',
        'Work',
        'Body',
        'Routine',
        'Place',
        'Craving',
      ]);
    });

    test('every path is unique, holds no separator inside an id, and fits '
        'the stored length', () {
      final List<String> paths = triggerPaths().toList();
      expect(paths.toSet(), hasLength(paths.length));
      for (final String path in paths) {
        expect(path.length, inInclusiveRange(1, maxTriggerLength));
        expect(path.split(triggerPathSeparator), everyElement(isNotEmpty));
        expect(triggerLabels(path), isNotNull, reason: path);
      }
    });

    test('a path reads back as its labels, root first', () {
      expect(triggerLabels('work/meeting'), ['Work', 'Meeting']);
      expect(triggerLabels('feeling'), ['Feeling']);
    });

    test('free text and unknown paths are not tree nodes', () {
      expect(triggerLabels('Late train'), isNull);
      expect(triggerLabels('work/nope'), isNull);
      expect(triggerLabels(''), isNull);
    });
  });

  group('triggersError', () {
    test('accepts none, a mix of paths and free text, and the limits', () {
      expect(triggersError(<String>[]), isNull);
      expect(triggersError(<String>['work/meeting', 'Late train']), isNull);
      expect(triggersError(List<String>.filled(maxTriggers, 'x')), isNull);
      expect(triggersError(<String>['x' * maxTriggerLength]), isNull);
    });

    test('refuses what the rules deny', () {
      expect(
        triggersError(List<String>.filled(maxTriggers + 1, 'x')),
        isNotNull,
      );
      expect(triggersError(<String>['']), isNotNull);
      expect(triggersError(<String>['x' * (maxTriggerLength + 1)]), isNotNull);
    });
  });

  test('comparableValue makes a written list equal to the list read back', () {
    expect(
      comparableValue(<String>['work/meeting', 'Late train']),
      comparableValue(<dynamic>['work/meeting', 'Late train']),
    );
    expect(
      comparableValue(<String>['work']),
      isNot(comparableValue(<String>['body'])),
    );
  });

  group('TrackerWrites', () {
    late _MockDocument document;
    late TrackerWrites writes;

    setUp(() {
      final _MockFirestore firestore = _MockFirestore();
      final _MockCollection activities = _MockCollection();
      document = _MockDocument();
      when(() => firestore.collection('activities')).thenReturn(activities);
      when(() => activities.id).thenReturn('activities');
      when(() => activities.doc(any())).thenReturn(document);
      when(() => document.set(any())).thenAnswer((_) async {});
      when(() => document.update(any())).thenAnswer((_) async {});
      writes = TrackerWrites(firestore);
    });

    Map<Object?, Object?> captured(void Function() verifyCall) =>
        verify(verifyCall).captured.single as Map<Object?, Object?>;

    test('a record without triggers writes no triggers field', () {
      writes.recordActivity(
        'a',
        ownerID: 'owner',
        viceID: 'v',
        quantity: 1,
        createdAt: DateTime(2026, 11, 6),
      );
      expect(
        captured(() => document.set(captureAny())).containsKey('triggers'),
        isFalse,
      );
    });

    test('a record with triggers writes them as a list', () {
      writes.recordActivity(
        'a',
        ownerID: 'owner',
        viceID: 'v',
        quantity: 1,
        createdAt: DateTime(2026, 11, 6),
        triggers: <String>['work/meeting', 'Late train'],
      );
      expect(captured(() => document.set(captureAny()))['triggers'], [
        'work/meeting',
        'Late train',
      ]);
    });

    test('an update sets triggers only when given, and an empty list clears '
        'them', () {
      final SentWrite quantityOnly = writes.updateActivity('a', quantity: 2);
      expect(
        captured(() => document.update(captureAny())).containsKey('triggers'),
        isFalse,
      );
      expect(quantityOnly.fields.containsKey('triggers'), isFalse);

      final SentWrite cleared = writes.updateActivity(
        'a',
        triggers: <String>[],
      );
      expect(captured(() => document.update(captureAny())), {
        'triggers': <String>[],
      });
      expect(cleared.fields['triggers'], comparableValue(<String>[]));
    });
  });
}
