import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/deleted_habit_page.dart';
import 'package:tracker/formats.dart';
import 'package:tracker/main.dart';
import 'package:tracker/manage_data.dart';
import 'package:tracker/providers/deleted_habit_provider.dart';
import 'package:tracker/providers/tracker_writes_provider.dart';
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/providers/vice_activity_history_provider.dart';
import 'package:tracker/providers/vice_list_provider.dart';
import 'package:tracker/widgets/rejected_writes_banner.dart';

import 'fake_writes.dart';
import 'fakes.dart';

void main() {
  final Vice coffee = fakeVice('coffee');
  final Vice tea = fakeVice('tea', archived: true);
  final DateTime now = DateTime.now();
  final List<ViceActivity> orphans = <ViceActivity>[
    fakeActivity('gone', 2, now.subtract(const Duration(minutes: 5))),
    fakeActivity('gone', 1, now.subtract(const Duration(days: 1, hours: 1))),
    fakeActivity(
      'foreign',
      3,
      now.subtract(const Duration(days: 3)),
      triggers: <String>['work/meeting'],
    ),
  ];

  late FakeTrackerWrites writes;

  setUp(() => writes = FakeTrackerWrites());

  Future<void> pump(
    WidgetTester tester, {
    required String route,
    List<Vice>? vices,
    ActivityCount total = (count: 9, source: CountSource.server),
    Map<String, ActivityCount> counts = const <String, ActivityCount>{
      'coffee': (count: 4, source: CountSource.server),
      'tea': (count: 2, source: CountSource.server),
    },
    AsyncValue<List<ViceActivity>>? entries,
    List<Override> extra = const <Override>[],
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          trackerWritesProvider.overrideWithValue(writes),
          memoryJournal(),
          userProvider.overrideWith((ref) => Stream.value(FakeUser(ownerID))),
          viceListProvider.overrideWithValue(
            AsyncData<List<Vice>>(vices ?? <Vice>[coffee, tea]),
          ),
          activityTotalCountProvider.overrideWithValue(
            AsyncData<ActivityCount>(total),
          ),
          viceActivityCountProvider.overrideWith(
            (ref, String viceID) => AsyncData<ActivityCount>(counts[viceID]!),
          ),
          deletedHabitActivitiesProvider.overrideWithValue(
            entries ?? AsyncData<List<ViceActivity>>(orphans),
          ),
          ...extra,
        ],
        child: MaterialApp(
          builder: rejectedWritesBuilder,
          initialRoute: route,
          onGenerateRoute: generateRoute,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('Habits row', () {
    testWidgets('shows the count left after every habit\'s own', (
      WidgetTester tester,
    ) async {
      await pump(tester, route: '/manage-data');
      expect(find.text(DeletedHabitPage.title), findsOne);
      expect(find.text('3 entries · ${ManageData.deletedHabitNote}'), findsOne);
      expect(
        tester
            .getSize(
              find.ancestor(
                of: find.text(DeletedHabitPage.title),
                matching: find.byType(InkWell),
              ),
            )
            .height,
        greaterThanOrEqualTo(44),
      );

      await tester.tap(find.text(DeletedHabitPage.title));
      await tester.pumpAndSettle();
      expect(find.byType(DeletedHabitPage), findsOne);
    });

    testWidgets('is absent when the counts add up', (
      WidgetTester tester,
    ) async {
      await pump(
        tester,
        route: '/manage-data',
        total: (count: 6, source: CountSource.server),
      );
      expect(find.text(DeletedHabitPage.title), findsNothing);
    });

    testWidgets('is absent while any count is the device\'s', (
      WidgetTester tester,
    ) async {
      await pump(
        tester,
        route: '/manage-data',
        counts: const <String, ActivityCount>{
          'coffee': (count: 4, source: CountSource.deviceOffline),
          'tea': (count: 2, source: CountSource.server),
        },
      );
      expect(find.text(DeletedHabitPage.title), findsNothing);
    });

    testWidgets('shows with no habits left at all', (
      WidgetTester tester,
    ) async {
      await pump(tester, route: '/manage-data', vices: <Vice>[]);
      expect(find.text('9 entries · ${ManageData.deletedHabitNote}'), findsOne);
    });
  });

  group('Deleted habit page', () {
    testWidgets('lists the entries newest first by day', (
      WidgetTester tester,
    ) async {
      await pump(tester, route: DeletedHabitPage.route);
      expect(find.text('3 entries'), findsOne);
      expect(find.text('Today'), findsOne);
      expect(find.text('Yesterday'), findsOne);
      expect(find.byTooltip(DeletedHabitPage.deleteEntry), findsNWidgets(3));
      for (final Element button
          in find.byTooltip(DeletedHabitPage.deleteEntry).evaluate()) {
        expect(
          tester.getSize(find.byWidget(button.widget)).width,
          greaterThanOrEqualTo(44),
        );
      }
    });

    testWidgets('deletes one entry after confirming it on the page', (
      WidgetTester tester,
    ) async {
      await pump(tester, route: DeletedHabitPage.route);
      await tester.tap(find.byTooltip(DeletedHabitPage.deleteEntry).first);
      await tester.pumpAndSettle();
      expect(find.text(DeletedHabitPage.confirmOne), findsOne);
      expect(writes.writes, isEmpty);

      await tester.tap(find.text(DeletedHabitPage.cancel));
      await tester.pumpAndSettle();
      expect(find.text(DeletedHabitPage.confirmOne), findsNothing);
      expect(writes.writes, isEmpty);

      await tester.tap(find.byTooltip(DeletedHabitPage.deleteEntry).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text(DeletedHabitPage.delete));
      await tester.pumpAndSettle();
      expect(writes.writes, <Write>[Write('deleteActivity', orphans.first.id)]);
      expect(find.text('2 entries'), findsOne);
      expect(find.text(DeletedHabitPage.deleted(1)), findsOne);
      expect(find.text('Undo'), findsNothing);
    });

    testWidgets('deletes all of them after confirming', (
      WidgetTester tester,
    ) async {
      await pump(tester, route: DeletedHabitPage.route);
      await tester.tap(find.text(DeletedHabitPage.deleteAll));
      await tester.pumpAndSettle();
      expect(find.text(DeletedHabitPage.confirmAll(3)), findsOne);

      await tester.tap(find.text(DeletedHabitPage.delete));
      await tester.pumpAndSettle();
      expect(writes.writes.map((Write w) => (w.op, w.id)), <(String, String)>[
        for (final ViceActivity a in orphans) ('deleteActivity', a.id),
      ]);
      expect(find.text(DeletedHabitPage.empty), findsOne);
      expect(find.text(DeletedHabitPage.deleted(3)), findsOne);
    });

    testWidgets('brings back an entry whose delete is refused', (
      WidgetTester tester,
    ) async {
      final FirebaseException denied = FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
      );
      writes.respond = (Write write) => write.id == orphans.first.id
          ? Future<void>.error(denied)
          : Future<void>.value();
      await pump(tester, route: DeletedHabitPage.route);
      await tester.tap(find.text(DeletedHabitPage.deleteAll));
      await tester.pumpAndSettle();
      await tester.tap(find.text(DeletedHabitPage.delete));
      await tester.pumpAndSettle();
      expect(find.text('1 entry'), findsOne);
      expect(find.text(DeletedHabitPage.failed(1, denied)), findsOne);
    });

    testWidgets('reads each row as its day, time and amount', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      await pump(tester, route: DeletedHabitPage.route);
      final String when = formatDayAndTime(
        orphans.first.createdAt.toDate(),
        alwaysUse24HourFormat: false,
      );
      expect(
        find.bySemanticsLabel(
          RegExp('^${RegExp.escape(when)}.*2\$', dotAll: true),
        ),
        findsOne,
      );
      semantics.dispose();
    });

    testWidgets('offers Retry when the read fails', (
      WidgetTester tester,
    ) async {
      await pump(
        tester,
        route: DeletedHabitPage.route,
        entries: AsyncError<List<ViceActivity>>(
          FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'),
          StackTrace.empty,
        ),
      );
      expect(find.text('Retry'), findsOne);
    });
  });

  test('the page reads nothing until the habits are known', () {
    final ProviderContainer container = ProviderContainer(
      overrides: [
        userProvider.overrideWith((ref) => Stream.value(FakeUser(ownerID))),
        viceListProvider.overrideWithValue(const AsyncLoading<List<Vice>>()),
      ],
    );
    addTearDown(container.dispose);
    expect(container.read(deletedHabitActivitiesProvider).isLoading, isTrue);
  });
}
