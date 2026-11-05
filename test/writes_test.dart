import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/vice_form.dart';
import 'package:tracker/data/unit.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/errors/firestore_errors.dart';
import 'package:tracker/manage_data.dart';
import 'package:tracker/providers/tracker_writes_provider.dart';
import 'package:tracker/providers/unarchived_vice_list_provider.dart';
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/providers/vice_activity_history_provider.dart';
import 'package:tracker/providers/vice_list_provider.dart';
import 'package:tracker/vice_activity_editor_page.dart';
import 'package:tracker/vice_activity_history_page.dart';
import 'package:tracker/widgets/record_new_activity_dialog.dart';
import 'package:tracker/widgets/rejected_writes_banner.dart';
import 'package:tracker/writes/rejected_writes.dart';
import 'package:tracker/writes/settle_write.dart';

import 'fake_writes.dart';
import 'fakes.dart';

const String _open = 'Open';

FirebaseException _firebaseError(String code) =>
    FirebaseException(plugin: 'cloud_firestore', code: code, message: code);

final String _offline = firestoreErrorMessage(_firebaseError('unavailable'));

Future<void> _never(Write write) => Completer<void>().future;

// Holds every write past the timeout, then lets the test refuse it.
class _LateRefusal {
  final Completer<void> _write = Completer<void>();

  Future<void> respond(Write write) => _write.future;

  Future<void> refuse(
    WidgetTester tester, [
    String code = 'permission-denied',
  ]) async {
    _write.completeError(_firebaseError(code));
    await tester.pumpAndSettle();
  }
}

// Holds each write until the test refuses that one, by its op.
class _RefuseEach {
  final Map<String, Completer<void>> _writes = <String, Completer<void>>{};

  Future<void> respond(Write write) =>
      _writes.putIfAbsent(write.op, Completer<void>.new).future;

  Future<void> refuse(WidgetTester tester, String op) async {
    _writes[op]!.completeError(_firebaseError('permission-denied'));
    await tester.pumpAndSettle();
  }
}

Finder _rejected(String what) => find.descendant(
  of: find.byType(RejectedWritesBanner),
  matching: find.textContaining(what),
);

// Opens [page] from a host screen, so a page that pops on success can be seen
// to have closed.
Future<void> _pumpOpened(
  WidgetTester tester,
  FakeTrackerWrites writes,
  List<Override> overrides,
  Widget page, {
  bool dialog = false,
  Stream<User?>? users,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        trackerWritesProvider.overrideWithValue(writes),
        userProvider.overrideWith(
          (ref) => users ?? Stream.value(FakeUser(ownerID)),
        ),
        ...overrides,
      ],
      child: MaterialApp(
        builder: rejectedWritesBuilder,
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

  group('Add Habit', () {
    Future<void> fillAndSave(WidgetTester tester) async {
      await _pumpOpened(tester, writes, const [], const ViceForm());
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Habit Name'),
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
      expect(find.byType(ViceForm), findsNothing);
    });

    testWidgets('a save in flight disables Save, and one that outlasts the '
        'timeout closes and says it will sync', (WidgetTester tester) async {
      writes.respond = _never;
      await _pumpOpened(tester, writes, const [], const ViceForm());
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Habit Name'),
        'Coffee',
      );
      await tester.tap(find.byType(DropdownButtonFormField<Unit>));
      await tester.pumpAndSettle();
      await tester.tap(find.text(Unit.drink.plural).last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Save'));
      await tester.pump();

      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Save'))
            .onPressed,
        isNull,
      );

      await tester.pump(writeTimeout);
      await tester.pumpAndSettle();

      expect(writes.writes, hasLength(1));
      expect(find.byType(ViceForm), findsNothing);
      expect(find.text(queuedMessage), findsOneWidget);
    });

    testWidgets('stays open and shows the error when the save fails', (
      WidgetTester tester,
    ) async {
      writes.respond = (_) => Future.error(_firebaseError('unavailable'));
      await fillAndSave(tester);

      expect(find.byType(ViceForm), findsOneWidget);
      expect(find.text('Not saved. $_offline'), findsOneWidget);
    });
  });

  group('Edit Habit', () {
    final Vice legacy = Vice(
      id: 'coffee',
      name: 'x' * 61,
      unit: Unit.drink,
      ownerID: ownerID,
      createdAt: Timestamp.fromMillisecondsSinceEpoch(0),
      archived: false,
    );

    Future<void> open(WidgetTester tester) => _pumpOpened(tester, writes, [
      viceListProvider.overrideWith((ref) => AsyncData([legacy])),
    ], const EditVice(viceID: 'coffee'));

    Future<void> pickUnit(WidgetTester tester, Unit unit) async {
      await tester.tap(find.byType(DropdownButtonFormField<Unit>));
      await tester.pumpAndSettle();
      await tester.tap(find.text(unit.plural).last);
      await tester.pumpAndSettle();
    }

    Future<void> save(WidgetTester tester) async {
      await tester.tap(find.widgetWithText(TextButton, 'Save'));
      await tester.pumpAndSettle();
    }

    testWidgets('opens filled with the vice', (WidgetTester tester) async {
      await open(tester);

      expect(find.text('Edit Habit'), findsOneWidget);
      expect(find.text('x' * 61), findsOneWidget);
      expect(find.text(Unit.drink.plural), findsOneWidget);
    });

    testWidgets('writes only a changed unit, keeping a legacy name as it is', (
      WidgetTester tester,
    ) async {
      await open(tester);
      await pickUnit(tester, Unit.hour);
      await save(tester);

      expect(writes.writes, [
        const Write('updateVice', 'coffee', <String, Object?>{
          'unit': Unit.hour,
        }),
      ]);
      expect(find.byType(EditVice), findsNothing);
    });

    testWidgets('writes only a changed name', (WidgetTester tester) async {
      await open(tester);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Habit Name'),
        'Espresso',
      );
      await save(tester);

      expect(writes.writes, [
        const Write('updateVice', 'coffee', <String, Object?>{
          'name': 'Espresso',
        }),
      ]);
    });

    testWidgets('writes nothing when nothing changed, and closes', (
      WidgetTester tester,
    ) async {
      await open(tester);
      await save(tester);

      expect(writes.writes, isEmpty);
      expect(find.byType(EditVice), findsNothing);
    });

    testWidgets('an edit that outlasts the timeout closes and says it will '
        'sync', (WidgetTester tester) async {
      writes.respond = _never;
      await open(tester);
      await pickUnit(tester, Unit.hour);
      await tester.tap(find.widgetWithText(TextButton, 'Save'));
      await tester.pump();

      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Save'))
            .onPressed,
        isNull,
      );

      await tester.pump(writeTimeout);
      await tester.pumpAndSettle();

      expect(writes.writes, hasLength(1));
      expect(find.byType(EditVice), findsNothing);
      expect(find.text(queuedMessage), findsOneWidget);
    });

    group('when another device edits the vice while the form is open', () {
      final Vice coffee = Vice(
        id: 'coffee',
        name: 'Coffee',
        unit: Unit.drink,
        ownerID: ownerID,
        createdAt: Timestamp.fromMillisecondsSinceEpoch(0),
        archived: false,
      );
      final Vice renamed = Vice(
        id: 'coffee',
        name: 'Espresso',
        unit: Unit.hour,
        ownerID: ownerID,
        createdAt: Timestamp.fromMillisecondsSinceEpoch(0),
        archived: false,
      );

      Future<void> openThenRename(WidgetTester tester) async {
        final StreamController<List<Vice>> vices =
            StreamController<List<Vice>>();
        addTearDown(() => unawaited(vices.close()));
        vices.add([coffee]);
        await _pumpOpened(tester, writes, [
          viceListForUserProvider.overrideWith(
            (ref, String uid) => vices.stream,
          ),
        ], const EditVice(viceID: 'coffee'));
        vices.add([renamed]);
        await tester.pumpAndSettle();
      }

      testWidgets('an untouched save writes nothing', (
        WidgetTester tester,
      ) async {
        await openThenRename(tester);
        await save(tester);

        expect(writes.writes, isEmpty);
      });

      testWidgets('a save writes only what this form changed', (
        WidgetTester tester,
      ) async {
        await openThenRename(tester);
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Habit Name'),
          'Latte',
        );
        await save(tester);

        expect(writes.writes, [
          const Write('updateVice', 'coffee', <String, Object?>{
            'name': 'Latte',
          }),
        ]);
      });
    });

    testWidgets('stays open and shows the error when the save fails', (
      WidgetTester tester,
    ) async {
      writes.respond = (_) => Future.error(_firebaseError('unavailable'));
      await open(tester);
      await pickUnit(tester, Unit.hour);
      await save(tester);

      expect(find.byType(EditVice), findsOneWidget);
      expect(find.text('Not saved. $_offline'), findsOneWidget);
    });

    testWidgets('says so when the vice is gone', (WidgetTester tester) async {
      await _pumpOpened(tester, writes, [
        viceListProvider.overrideWith((ref) => AsyncData(<Vice>[])),
      ], const EditVice(viceID: 'coffee'));

      expect(find.text('Habit not found'), findsOneWidget);
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
        (ref, String viceID) =>
            const AsyncData((count: 0, source: CountSource.server)),
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

    testWidgets('an archive in flight disables that row, and one that '
        'outlasts the timeout says it will sync', (WidgetTester tester) async {
      writes.respond = _never;
      await _pumpOpened(tester, writes, overrides(), const ManageData());

      await tester.tap(find.byTooltip('Archive'));
      await tester.pump();

      expect(writes.writes, hasLength(1));
      expect(
        tester
            .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.archive))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<IconButton>(
              find.widgetWithIcon(IconButton, Icons.unarchive),
            )
            .onPressed,
        isNotNull,
      );

      await tester.pump(writeTimeout);
      await tester.pumpAndSettle();

      expect(find.text(queuedMessage), findsOneWidget);
    });

    testWidgets('counts from the server online, says when a count comes '
        'from this device offline or because the server did not count, and '
        'says when there is none', (WidgetTester tester) async {
      final Vice water = fakeVice('water');
      final Vice beer = fakeVice('beer');
      final Map<String, AsyncValue<ActivityCount>> counts =
          <String, AsyncValue<ActivityCount>>{
            active.id: const AsyncData((count: 1, source: CountSource.server)),
            archived.id: const AsyncData((
              count: 3,
              source: CountSource.deviceOffline,
            )),
            beer.id: const AsyncData((
              count: 2,
              source: CountSource.deviceServerFailed,
            )),
            water.id: AsyncError<ActivityCount>(
              _firebaseError('unavailable'),
              StackTrace.empty,
            ),
          };
      await _pumpOpened(tester, writes, [
        viceListProvider.overrideWithValue(
          AsyncData([active, archived, beer, water]),
        ),
        viceActivityCountProvider.overrideWith(
          (ref, String viceID) => counts[viceID]!,
        ),
      ], const ManageData());

      expect(find.text('1 activity'), findsOneWidget);
      expect(
        find.text(
          '${ManageData.archivedLabel}, 3 activities on this device (offline)',
        ),
        findsOneWidget,
      );
      expect(
        find.text('2 activities on this device (server count unavailable)'),
        findsOneWidget,
      );
      expect(find.text(ManageData.countUnavailable), findsOneWidget);
    });

    testWidgets('shows the error when archiving fails', (
      WidgetTester tester,
    ) async {
      writes.respond = (_) => Future.error(_firebaseError('permission-denied'));
      await _pumpOpened(tester, writes, overrides(), const ManageData());

      await tester.tap(find.byTooltip('Archive'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Could not archive coffee. '
          '${firestoreErrorMessage(_firebaseError('permission-denied'))}',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('permission-denied'), findsNothing);
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
      await tester.tap(find.byType(DropdownButtonFormField<String>));
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
      expect(find.text('Not recorded. $_offline'), findsOneWidget);

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
      expect(find.text('That habit no longer exists'), findsOneWidget);
    });

    testWidgets('a write that outlasts the timeout closes the dialog and says '
        'it will sync', (WidgetTester tester) async {
      writes.respond = _never;
      await fill(tester);
      await tester.tap(record);
      await tester.pump();

      await tester.pump(writeTimeout - const Duration(seconds: 1));
      expect(dialog, findsOneWidget);

      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(dialog, findsNothing);
      expect(find.text(queuedMessage), findsOneWidget);
      expectRecorded(writes.writes.single, 'activity-1');
    });

    testWidgets('while saving, a screen reader cannot reach the form', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      writes.respond = _never;
      await fill(tester);
      expect(find.semantics.byLabel('Record'), findsOneWidget);

      await tester.tap(record);
      await tester.pump();

      expect(find.semantics.byLabel('Record'), findsNothing);
      expect(find.semantics.byLabel('Quantity'), findsNothing);
      await tester.pump(writeTimeout);
      await tester.pumpAndSettle();
      semantics.dispose();
    });

    testWidgets('an Undo that outlasts the timeout says it will sync', (
      WidgetTester tester,
    ) async {
      await fill(tester);
      await tester.tap(record);
      await tester.pumpAndSettle();

      writes.respond = _never;
      await tester.tap(find.text('Undo'));
      await tester.pump(writeTimeout);
      await tester.pumpAndSettle();

      expect(writes.writes.last, const Write('deleteActivity', 'activity-1'));
      expect(find.text(queuedDeleteMessage), findsOneWidget);
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

    testWidgets('a save that outlasts the timeout closes and says it will '
        'sync', (WidgetTester tester) async {
      writes.respond = _never;
      await open(tester);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Quantity'),
        '5',
      );
      await tester.tap(find.widgetWithText(TextButton, 'Save'));
      await tester.pump(writeTimeout - const Duration(seconds: 1));
      expect(editor, findsOneWidget);

      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(editor, findsNothing);
      expect(find.text(queuedMessage), findsOneWidget);
      expect(find.text('Request timed out'), findsNothing);
    });

    testWidgets('a delete in flight disables both actions, and one that '
        'outlasts the timeout closes and says it will sync', (
      WidgetTester tester,
    ) async {
      writes.respond = _never;
      await open(tester);
      await tester.tap(find.byTooltip('Delete'));
      await tester.pump();

      expect(
        tester
            .widget<IconButton>(
              find.widgetWithIcon(IconButton, Icons.delete_outline),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Save'))
            .onPressed,
        isNull,
      );

      await tester.pump(writeTimeout);
      await tester.pumpAndSettle();

      expect(writes.writes, [Write('deleteActivity', activity.id)]);
      expect(editor, findsNothing);
      expect(find.text(queuedDeleteMessage), findsOneWidget);
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
      expect(
        find.text('Could not delete this activity. $_offline'),
        findsOneWidget,
      );
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

    testWidgets('a delete in flight disables its button, and one that '
        'outlasts the timeout says it will sync', (WidgetTester tester) async {
      writes.respond = _never;
      await _pumpOpened(
        tester,
        writes,
        overrides(),
        ViceActivityHistoryPage(viceID: coffee.id),
      );
      await tester.tap(find.byTooltip('Delete'));
      await tester.pump();

      expect(writes.writes, [Write('deleteActivity', activity.id)]);
      expect(
        tester
            .widget<IconButton>(
              find.widgetWithIcon(IconButton, Icons.delete_outline),
            )
            .onPressed,
        isNull,
      );

      await tester.pump(writeTimeout);
      await tester.pumpAndSettle();

      expect(find.text(queuedDeleteMessage), findsOneWidget);
      expect(find.text('Activity deleted'), findsNothing);
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

      expect(
        find.text('Could not delete this activity. $_offline'),
        findsOneWidget,
      );
      expect(find.text('Activity deleted'), findsNothing);
    });
  });

  group('settleWrite', () {
    test('a write acknowledged in time settles true', () async {
      final List<FirebaseException> late = <FirebaseException>[];
      expect(
        await settleWrite(Future<void>.value(), onRejectedLater: late.add),
        isTrue,
      );
      expect(late, isEmpty);
    });

    testWidgets(
      'a write whose future carries a value still times out to false',
      (WidgetTester tester) async {
        final Completer<DocumentReference<Map<String, dynamic>>> write =
            Completer<DocumentReference<Map<String, dynamic>>>();
        bool? settled;
        unawaited(
          settleWrite(
            write.future,
            onRejectedLater: (_) {},
          ).then((bool value) => settled = value),
        );

        await tester.pump(writeTimeout);
        expect(settled, isFalse);
      },
    );

    test(
      'a refusal before the timeout throws and is not reported later',
      () async {
        final List<FirebaseException> late = <FirebaseException>[];
        await expectLater(
          settleWrite(
            Future<void>.error(_firebaseError('permission-denied')),
            onRejectedLater: late.add,
          ),
          throwsA(isA<FirebaseException>()),
        );
        await Future<void>.delayed(Duration.zero);
        expect(late, isEmpty);
      },
    );

    testWidgets('a refusal after the timeout settles false, then is reported', (
      WidgetTester tester,
    ) async {
      final List<FirebaseException> late = <FirebaseException>[];
      final Completer<void> write = Completer<void>();
      bool? settled;
      unawaited(
        settleWrite(
          write.future,
          onRejectedLater: late.add,
        ).then((bool value) => settled = value),
      );

      await tester.pump(writeTimeout);
      expect(settled, isFalse);
      expect(late, isEmpty);

      write.completeError(_firebaseError('permission-denied'));
      await tester.pump();
      expect(late.single.code, 'permission-denied');
    });
  });

  group('a change the server refuses after the timeout', () {
    // Called inside each test: a Completer made in setUp lives outside the
    // test's fake-async zone, so the test's pumps never deliver its error.
    _LateRefusal holdWrites() {
      final _LateRefusal refusal = _LateRefusal();
      writes.respond = refusal.respond;
      return refusal;
    }

    Future<void> waitOutTimeout(WidgetTester tester) async {
      await tester.pump(writeTimeout);
      await tester.pumpAndSettle();
    }

    // Records 2 coffee through the dialog and waits until it calls the entry
    // queued.
    Future<void> recordQueued(WidgetTester tester) async {
      await _pumpOpened(
        tester,
        writes,
        [
          unarchivedViceListProvider.overrideWithValue(
            AsyncData([fakeVice('coffee')]),
          ),
        ],
        const RecordNewActivityDialog(),
        dialog: true,
      );
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('coffee').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Quantity'),
        '2',
      );
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Record'),
        ),
      );
      await tester.pump();
      await waitOutTimeout(tester);
    }

    testWidgets('a recorded activity is named in a banner until dismissed', (
      WidgetTester tester,
    ) async {
      final _LateRefusal refusal = holdWrites();
      await recordQueued(tester);

      expect(find.text(queuedMessage), findsOneWidget);
      expect(find.byType(RejectedWritesBanner), findsOneWidget);
      expect(_rejected('Not saved'), findsNothing);

      await refusal.refuse(tester);

      expect(_rejected('Not saved: coffee, 2 items, '), findsOneWidget);
      expect(_rejected('The server refused this change.'), findsOneWidget);

      await tester.tap(find.text(RejectedWritesBanner.dismissLabel));
      await tester.pumpAndSettle();

      expect(_rejected('Not saved'), findsNothing);
    });

    testWidgets('an Undo of a recording the server refuses is not called '
        'not deleted', (WidgetTester tester) async {
      final _LateRefusal refusal = holdWrites();
      await recordQueued(tester);
      await tester.tap(find.text('Undo'));
      await waitOutTimeout(tester);
      expect(find.text(queuedDeleteMessage), findsOneWidget);

      // Both queued writes are refused, the create first, as the SDK sends
      // them: the delete finds no document.
      await refusal.refuse(tester);

      expect(writes.writes.last, const Write('deleteActivity', 'activity-1'));
      expect(_rejected('Not saved: coffee, 2 items, '), findsOneWidget);
      expect(_rejected('Not deleted'), findsNothing);
    });

    testWidgets('an Undo refused before its own timeout, after the recording '
        'was refused, does not say the Undo failed', (
      WidgetTester tester,
    ) async {
      final _RefuseEach refusals = _RefuseEach();
      writes.respond = refusals.respond;
      await recordQueued(tester);
      await tester.tap(find.text('Undo'));
      await tester.pump();

      await refusals.refuse(tester, 'recordActivity');
      await refusals.refuse(tester, 'deleteActivity');

      expect(_rejected('Not saved: coffee, 2 items, '), findsOneWidget);
      expect(_rejected('Not deleted'), findsNothing);
      expect(find.textContaining('Unable to undo'), findsNothing);
    });

    testWidgets('a history delete refused before its own timeout, after the '
        'entry\'s create was refused, shows no error', (
      WidgetTester tester,
    ) async {
      final _RefuseEach refusals = _RefuseEach();
      writes.respond = refusals.respond;
      final Vice coffee = fakeVice('coffee');
      final ViceActivity activity = fakeActivity(
        coffee.id,
        1,
        DateTime(2026, 11, 2, 9, 30),
      );
      await _pumpOpened(tester, writes, [
        viceListProvider.overrideWithValue(AsyncData([coffee])),
        viceActivityHistoryProvider.overrideWith(
          (ref, ViceActivityHistoryQuery query) => AsyncData([activity]),
        ),
      ], ViceActivityHistoryPage(viceID: coffee.id));
      await tester.tap(find.byTooltip('Delete'));
      await tester.pump();

      ProviderScope.containerOf(
            tester.element(find.byType(ViceActivityHistoryPage)),
          )
          .read(rejectedWritesProvider.notifier)
          .reporter('Not saved: coffee', creates: activity.id)(
        _firebaseError('permission-denied'),
      );
      await refusals.refuse(tester, 'deleteActivity');

      expect(_rejected('Not saved: coffee'), findsOneWidget);
      expect(_rejected('Not deleted'), findsNothing);
      expect(find.text('permission-denied'), findsNothing);
    });

    testWidgets('an edit refused before its own timeout, after the entry\'s '
        'create was refused, closes without an error', (
      WidgetTester tester,
    ) async {
      final _RefuseEach refusals = _RefuseEach();
      writes.respond = refusals.respond;
      final Vice coffee = fakeVice('coffee');
      final ViceActivity activity = fakeActivity(
        coffee.id,
        3,
        DateTime(2026, 11, 2, 9, 30),
      );
      await _pumpOpened(
        tester,
        writes,
        [
          viceListProvider.overrideWithValue(AsyncData([coffee])),
          viceActivityProvider.overrideWith(
            (ref, String activityID) => AsyncData(activity),
          ),
        ],
        ViceActivityEditorPage(viceID: coffee.id, activityID: activity.id),
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Quantity'),
        '5',
      );
      await tester.tap(find.widgetWithText(TextButton, 'Save'));
      await tester.pump();

      ProviderScope.containerOf(
            tester.element(find.byType(ViceActivityEditorPage)),
          )
          .read(rejectedWritesProvider.notifier)
          .reporter('Not saved: coffee', creates: activity.id)(
        _firebaseError('permission-denied'),
      );
      await refusals.refuse(tester, 'updateActivity');

      expect(find.byType(ViceActivityEditorPage), findsNothing);
      expect(_rejected('Not saved: coffee'), findsOneWidget);
      expect(_rejected('Change not saved'), findsNothing);
    });

    testWidgets('an edit names the entry it was made to', (
      WidgetTester tester,
    ) async {
      final _LateRefusal refusal = holdWrites();
      final Vice coffee = fakeVice('coffee');
      final ViceActivity activity = fakeActivity(
        coffee.id,
        3,
        DateTime(2026, 11, 2, 9, 30),
      );
      await _pumpOpened(
        tester,
        writes,
        [
          viceListProvider.overrideWithValue(AsyncData([coffee])),
          viceActivityProvider.overrideWith(
            (ref, String activityID) => AsyncData(activity),
          ),
        ],
        ViceActivityEditorPage(viceID: coffee.id, activityID: activity.id),
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Quantity'),
        '5',
      );
      await tester.tap(find.widgetWithText(TextButton, 'Save'));
      await tester.pump();
      await waitOutTimeout(tester);
      await refusal.refuse(tester, 'unavailable');

      expect(
        _rejected(
          'Change not saved: coffee, 3 items, Mon, Nov 2, 2026 9:30\u202fAM',
        ),
        findsOneWidget,
      );
      expect(
        _rejected('The server refused this change: unavailable'),
        findsOneWidget,
      );
    });

    testWidgets('a delete from the history page is named', (
      WidgetTester tester,
    ) async {
      final _LateRefusal refusal = holdWrites();
      final Vice coffee = fakeVice('coffee');
      final ViceActivity activity = fakeActivity(
        coffee.id,
        1,
        DateTime(2026, 11, 2, 9, 30),
      );
      await _pumpOpened(tester, writes, [
        viceListProvider.overrideWithValue(AsyncData([coffee])),
        viceActivityHistoryProvider.overrideWith(
          (ref, ViceActivityHistoryQuery query) => AsyncData([activity]),
        ),
      ], ViceActivityHistoryPage(viceID: coffee.id));
      final Finder navigatorScope = find.byWidgetPredicate(
        (Widget widget) =>
            widget is FocusScope && widget.debugLabel == 'Navigator Scope',
      );
      final State scope = tester.state(navigatorScope);
      await tester.tap(find.byTooltip('Delete'));
      await tester.pump();
      await waitOutTimeout(tester);
      await refusal.refuse(tester);

      expect(
        _rejected('Not deleted: coffee, 1 item, Mon, Nov 2, 2026 9:30\u202fAM'),
        findsOneWidget,
      );
      expect(find.byType(ViceActivityHistoryPage), findsOneWidget);
      expect(tester.state(navigatorScope), same(scope));
    });

    testWidgets('a new vice is named', (WidgetTester tester) async {
      final _LateRefusal refusal = holdWrites();
      await _pumpOpened(tester, writes, const [], const ViceForm());
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Habit Name'),
        'Coffee',
      );
      await tester.tap(find.byType(DropdownButtonFormField<Unit>));
      await tester.pumpAndSettle();
      await tester.tap(find.text(Unit.drink.plural).last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Save'));
      await tester.pump();
      await waitOutTimeout(tester);
      await refusal.refuse(tester);

      expect(_rejected('Not saved: the habit Coffee'), findsOneWidget);
    });

    testWidgets('archiving is named', (WidgetTester tester) async {
      final _LateRefusal refusal = holdWrites();
      await _pumpOpened(tester, writes, [
        viceListProvider.overrideWithValue(AsyncData([fakeVice('coffee')])),
        viceActivityCountProvider.overrideWith(
          (ref, String viceID) =>
              const AsyncData((count: 0, source: CountSource.server)),
        ),
      ], const ManageData());
      await tester.tap(find.byTooltip('Archive'));
      await tester.pump();
      await waitOutTimeout(tester);
      await refusal.refuse(tester);

      expect(_rejected('Not archived: coffee'), findsOneWidget);
    });

    testWidgets('a refusal that arrives after sign-out is not shown', (
      WidgetTester tester,
    ) async {
      final _LateRefusal refusal = holdWrites();
      final StreamController<User?> users = StreamController<User?>();
      addTearDown(() => unawaited(users.close()));
      users.add(FakeUser(ownerID));
      await _pumpOpened(tester, writes, users: users.stream, [
        viceListProvider.overrideWithValue(AsyncData([fakeVice('coffee')])),
        viceActivityCountProvider.overrideWith(
          (ref, String viceID) =>
              const AsyncData((count: 0, source: CountSource.server)),
        ),
      ], const ManageData());
      await tester.tap(find.byTooltip('Archive'));
      await tester.pump();
      await waitOutTimeout(tester);

      users.add(null);
      await tester.pump();
      await refusal.refuse(tester);

      expect(find.byType(RejectedWritesBanner), findsOneWidget);
      expect(_rejected('Not archived'), findsNothing);
    });
  });

  group('rejectedWritesProvider', () {
    Future<ProviderContainer> signedIn() async {
      final ProviderContainer container = ProviderContainer(
        overrides: [
          userProvider.overrideWith((ref) => Stream.value(FakeUser(ownerID))),
        ],
      );
      addTearDown(container.dispose);
      container.listen(userProvider, (_, _) {});
      await container.read(userProvider.future);
      return container;
    }

    List<String> shown(ProviderContainer container) => [
      for (final RejectedWrite item in container.read(rejectedWritesProvider))
        item.what,
    ];

    final FirebaseException denied = _firebaseError('permission-denied');

    test('drops a change to a document whose create was refused, even once '
        'that line is dismissed', () async {
      final ProviderContainer container = await signedIn();
      final RejectedWrites rejected = container.read(
        rejectedWritesProvider.notifier,
      );
      rejected.reporter('Not saved: a', creates: 'a')(denied);
      rejected.dismiss(container.read(rejectedWritesProvider).single);
      rejected.reporter('Change not saved: a', changes: 'a')(denied);
      rejected.reporter('Not deleted: a', changes: 'a')(denied);

      expect(shown(container), isEmpty);
    });

    test('a refused create removes a refusal already shown for a change to '
        'that document', () async {
      final ProviderContainer container = await signedIn();
      final RejectedWrites rejected = container.read(
        rejectedWritesProvider.notifier,
      );
      rejected.reporter('Not deleted: a', changes: 'a')(denied);
      rejected.reporter('Not deleted: b', changes: 'b')(denied);
      rejected.reporter('Not saved: a', creates: 'a')(denied);

      expect(shown(container), ['Not deleted: b', 'Not saved: a']);
    });
  });
}
