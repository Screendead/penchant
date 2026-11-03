import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/add_vice.dart';
import 'package:tracker/data/unit.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/manage_data.dart';
import 'package:tracker/providers/tracker_writes_provider.dart';
import 'package:tracker/providers/unarchived_vice_list_provider.dart';
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/providers/vice_activity_history_provider.dart';
import 'package:tracker/providers/vice_list_provider.dart';
import 'package:tracker/vice_activity_editor_page.dart';
import 'package:tracker/vice_activity_history_page.dart';
import 'package:tracker/widgets/record_new_activity_dialog.dart';

import 'fake_writes.dart';
import 'fakes.dart';

const String _open = 'Open';

FirebaseException _firebaseError(String code) =>
    FirebaseException(plugin: 'cloud_firestore', code: code, message: code);

Future<void> _never(Write write) => Completer<void>().future;

// Opens [page] from a host screen, so a page that pops on success can be seen
// to have closed.
Future<void> _pumpOpened(
  WidgetTester tester,
  FakeTrackerWrites writes,
  List<Override> overrides,
  Widget page, {
  bool dialog = false,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        trackerWritesProvider.overrideWithValue(writes),
        userProvider.overrideWith((ref) => Stream.value(FakeUser(ownerID))),
        ...overrides,
      ],
      child: MaterialApp(
        home: Scaffold(
          // Watches the user as main.dart does; a provider read with no
          // listener never resolves.
          body: Consumer(
            builder: (BuildContext context, WidgetRef ref, _) {
              ref.watch(userProvider);
              return TextButton(
                onPressed: () {
                  if (dialog) {
                    showDialog<void>(context: context, builder: (_) => page);
                  } else {
                    Navigator.of(
                      context,
                    ).push(MaterialPageRoute<void>(builder: (_) => page));
                  }
                },
                child: const Text(_open),
              );
            },
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text(_open));
  await tester.pumpAndSettle();
}

void main() {
  late FakeTrackerWrites writes;

  setUp(() {
    writes = FakeTrackerWrites();
  });

  group('Add Vice', () {
    Future<void> fillAndSave(WidgetTester tester) async {
      await _pumpOpened(tester, writes, const [], const AddVice());
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Vice Name'),
        'Coffee',
      );
      await tester.tap(find.byType(DropdownButtonFormField<Unit>));
      await tester.pumpAndSettle();
      await tester.tap(find.text(Unit.drink.plural).last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Save'));
      await tester.pumpAndSettle();
    }

    testWidgets('saves the vice for the signed-in user and closes', (
      WidgetTester tester,
    ) async {
      await fillAndSave(tester);

      expect(writes.writes, [
        const Write('addVice', '', <String, Object?>{
          'ownerID': ownerID,
          'name': 'Coffee',
          'unit': Unit.drink,
        }),
      ]);
      expect(find.byType(AddVice), findsNothing);
    });

    testWidgets('stays open and shows the error when the save fails', (
      WidgetTester tester,
    ) async {
      writes.respond = (_) => Future.error(_firebaseError('unavailable'));
      await fillAndSave(tester);

      expect(find.byType(AddVice), findsOneWidget);
      expect(find.text('unavailable'), findsOneWidget);
    });
  });

  group('Manage Data', () {
    final Vice active = fakeVice('coffee');
    final Vice archived = Vice(
      id: 'tea',
      name: 'tea',
      unit: Unit.values.first,
      ownerID: ownerID,
      createdAt: Timestamp.fromMillisecondsSinceEpoch(0),
      archived: true,
    );

    List<Override> overrides() => [
      viceListProvider.overrideWithValue(AsyncData([active, archived])),
      viceActivityCountProvider.overrideWith(
        (ref, String viceID) => const AsyncData(0),
      ),
    ];

    testWidgets('archives an active vice and unarchives an archived one', (
      WidgetTester tester,
    ) async {
      await _pumpOpened(tester, writes, overrides(), const ManageData());

      await tester.tap(find.byTooltip('Archive'));
      await tester.pump();
      await tester.tap(find.byTooltip('Unarchive'));
      await tester.pump();

      expect(writes.writes, [
        const Write('setViceArchived', 'coffee', <String, Object?>{
          'archived': true,
        }),
        const Write('setViceArchived', 'tea', <String, Object?>{
          'archived': false,
        }),
      ]);
    });

    testWidgets('shows the error when archiving fails', (
      WidgetTester tester,
    ) async {
      writes.respond = (_) => Future.error(_firebaseError('permission-denied'));
      await _pumpOpened(tester, writes, overrides(), const ManageData());

      await tester.tap(find.byTooltip('Archive'));
      await tester.pumpAndSettle();

      expect(find.textContaining('permission-denied'), findsOneWidget);
    });
  });

  group('the record dialog', () {
    final Vice coffee = fakeVice('coffee');

    List<Override> overrides() => [
      unarchivedViceListProvider.overrideWithValue(AsyncData([coffee])),
    ];

    final Finder dialog = find.byType(RecordNewActivityDialog);
    final Finder record = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text('Record'),
    );

    Future<void> fill(WidgetTester tester) async {
      await _pumpOpened(
        tester,
        writes,
        overrides(),
        const RecordNewActivityDialog(),
        dialog: true,
      );
      await tester.tap(find.byType(DropdownButtonFormField<Vice>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('coffee').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Quantity'),
        '2',
      );
    }

    void expectRecorded(Write write, String id) {
      expect(write.op, 'recordActivity');
      expect(write.id, id);
      expect(write.fields['ownerID'], ownerID);
      expect(write.fields['viceID'], coffee.id);
      expect(write.fields['quantity'], 2);
      expect(write.fields['createdAt'], isA<DateTime>());
    }

    testWidgets('records the activity, closes, and Undo deletes that same '
        'activity', (WidgetTester tester) async {
      await fill(tester);
      await tester.tap(record);
      await tester.pumpAndSettle();

      expect(writes.writes, hasLength(1));
      expectRecorded(writes.writes.single, 'activity-1');
      expect(dialog, findsNothing);
      expect(
        find.text(RecordNewActivityDialog.recordedMessage),
        findsOneWidget,
      );

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();

      expect(writes.writes.last, const Write('deleteActivity', 'activity-1'));
      expect(find.text('Activity removed'), findsOneWidget);
    });

    testWidgets('a second press after a failure writes the same document', (
      WidgetTester tester,
    ) async {
      writes.respond = (_) => Future.error(_firebaseError('unavailable'));
      await fill(tester);
      await tester.tap(record);
      await tester.pumpAndSettle();

      expect(dialog, findsOneWidget);
      expect(
        find.text('Error recording activity: unavailable'),
        findsOneWidget,
      );

      writes.respond = null;
      await tester.tap(record);
      await tester.pumpAndSettle();

      expect(writes.writes, hasLength(2));
      expectRecorded(writes.writes[0], 'activity-1');
      expectRecorded(writes.writes[1], 'activity-1');
      expect(dialog, findsNothing);
    });

    testWidgets('a denied write reads as a vice that no longer exists', (
      WidgetTester tester,
    ) async {
      writes.respond = (_) => Future.error(_firebaseError('permission-denied'));
      await fill(tester);
      await tester.tap(record);
      await tester.pumpAndSettle();

      expect(dialog, findsOneWidget);
      expect(find.text('That vice no longer exists'), findsOneWidget);
    });

    testWidgets('a write that outlasts the timeout closes the dialog and says '
        'it will sync', (WidgetTester tester) async {
      writes.respond = _never;
      await fill(tester);
      await tester.tap(record);
      await tester.pump();

      await tester.pump(
        RecordNewActivityDialog.writeTimeout - const Duration(seconds: 1),
      );
      expect(dialog, findsOneWidget);

      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(dialog, findsNothing);
      expect(find.text(RecordNewActivityDialog.queuedMessage), findsOneWidget);
      expectRecorded(writes.writes.single, 'activity-1');
    });

    testWidgets('an Undo that outlasts the timeout says so', (
      WidgetTester tester,
    ) async {
      await fill(tester);
      await tester.tap(record);
      await tester.pumpAndSettle();

      writes.respond = _never;
      await tester.tap(find.text('Undo'));
      await tester.pump(RecordNewActivityDialog.writeTimeout);
      await tester.pumpAndSettle();

      expect(writes.writes.last, const Write('deleteActivity', 'activity-1'));
      expect(find.text('Undo has not reached the server yet'), findsOneWidget);
    });
  });

  group('the activity editor', () {
    final Vice coffee = fakeVice('coffee');
    final DateTime at = DateTime(2026, 11, 2, 9, 30, 15);
    final ViceActivity activity = fakeActivity(coffee.id, 3, at);

    List<Override> overrides() => [
      viceListProvider.overrideWithValue(AsyncData([coffee])),
      viceActivityProvider.overrideWith(
        (ref, String activityID) => AsyncData(activity),
      ),
    ];

    Future<void> open(WidgetTester tester) => _pumpOpened(
      tester,
      writes,
      overrides(),
      ViceActivityEditorPage(viceID: coffee.id, activityID: activity.id),
    );

    final Finder editor = find.byType(ViceActivityEditorPage);

    testWidgets('saves only the edited quantity and closes', (
      WidgetTester tester,
    ) async {
      await open(tester);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Quantity'),
        '5',
      );
      await tester.tap(find.widgetWithText(TextButton, 'Save'));
      await tester.pumpAndSettle();

      expect(writes.writes, [
        Write('updateActivity', activity.id, <String, Object?>{'quantity': 5}),
      ]);
      expect(editor, findsNothing);
    });

    testWidgets('a save that outlasts ten seconds stays open and says it '
        'timed out', (WidgetTester tester) async {
      writes.respond = _never;
      await open(tester);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Quantity'),
        '5',
      );
      await tester.tap(find.widgetWithText(TextButton, 'Save'));
      await tester.pump(const Duration(seconds: 10));
      await tester.pump();

      expect(editor, findsOneWidget);
      expect(find.text('Request timed out'), findsOneWidget);
    });

    testWidgets('deletes the activity and closes', (WidgetTester tester) async {
      await open(tester);
      await tester.tap(find.byTooltip('Delete'));
      await tester.pumpAndSettle();

      expect(writes.writes, [Write('deleteActivity', activity.id)]);
      expect(editor, findsNothing);
    });

    testWidgets('stays open and shows the error when the delete fails', (
      WidgetTester tester,
    ) async {
      writes.respond = (_) => Future.error(_firebaseError('unavailable'));
      await open(tester);
      await tester.tap(find.byTooltip('Delete'));
      await tester.pumpAndSettle();

      expect(editor, findsOneWidget);
      expect(find.text('unavailable'), findsOneWidget);
    });
  });

  group('the history page', () {
    final Vice coffee = fakeVice('coffee');
    final ViceActivity activity = fakeActivity(
      coffee.id,
      3,
      DateTime(2026, 11, 2, 9, 30),
    );

    List<Override> overrides() => [
      viceListProvider.overrideWithValue(AsyncData([coffee])),
      viceActivityHistoryProvider.overrideWith(
        (ref, ViceActivityHistoryQuery query) => AsyncData([activity]),
      ),
    ];

    testWidgets('deletes a row and says so', (WidgetTester tester) async {
      await _pumpOpened(
        tester,
        writes,
        overrides(),
        ViceActivityHistoryPage(viceID: coffee.id),
      );
      await tester.tap(find.byTooltip('Delete'));
      await tester.pumpAndSettle();

      expect(writes.writes, [Write('deleteActivity', activity.id)]);
      expect(find.text('Activity deleted'), findsOneWidget);
    });

    testWidgets('shows the error when the delete fails', (
      WidgetTester tester,
    ) async {
      writes.respond = (_) => Future.error(_firebaseError('unavailable'));
      await _pumpOpened(
        tester,
        writes,
        overrides(),
        ViceActivityHistoryPage(viceID: coffee.id),
      );
      await tester.tap(find.byTooltip('Delete'));
      await tester.pumpAndSettle();

      expect(find.text('unavailable'), findsOneWidget);
      expect(find.text('Activity deleted'), findsNothing);
    });
  });
}
