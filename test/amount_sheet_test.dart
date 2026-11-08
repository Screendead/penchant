import 'dart:async';

import 'package:clock/clock.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/unit.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/formats.dart';
import 'package:tracker/providers/tracker_writes_provider.dart';
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/providers/vice_activity_history_provider.dart';
import 'package:tracker/vice_activity_editor_page.dart';
import 'package:tracker/widgets/amount_fields.dart';
import 'package:tracker/widgets/record_new_activity_dialog.dart';
import 'package:tracker/writes/log_one.dart';

import 'fake_writes.dart';
import 'fakes.dart';

final DateTime _now = DateTime(2026, 11, 5, 18, 30);

final Vice _coffee = Vice(
  id: 'coffee',
  name: 'Coffee',
  unit: Unit.drink,
  ownerID: ownerID,
  createdAt: Timestamp.fromDate(DateTime.utc(2026, 1, 1)),
  archived: false,
);

Finder get _quantity =>
    find.widgetWithText(TextFormField, AmountFields.quantityLabel);

String _shownQuantity(WidgetTester tester) =>
    tester.widget<TextFormField>(_quantity).controller!.text;

Future<void> _open(
  WidgetTester tester,
  FakeTrackerWrites writes, {
  String? initialViceID,
  Widget? page,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...habitOverrides(<Vice>[_coffee]),
        trackerWritesProvider.overrideWithValue(writes),
        memoryJournal(),
        userProvider.overrideWith((ref) => Stream.value(FakeUser(ownerID))),
        viceActivityProvider.overrideWith(
          (ref, String id) => AsyncData(fakeActivity('coffee', 3, _now)),
        ),
      ],
      child: MaterialApp(
        builder: (BuildContext context, Widget? child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child!,
        ),
        home: Scaffold(
          body: Consumer(
            builder: (BuildContext context, WidgetRef ref, _) {
              ref.watch(userProvider);
              return TextButton(
                onPressed: () => page == null
                    ? RecordNewActivityDialog.show(
                        context,
                        initialViceID: initialViceID,
                      )
                    : Navigator.of(
                        context,
                      ).push(MaterialPageRoute<void>(builder: (_) => page)),
                child: const Text('open'),
              );
            },
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  late FakeTrackerWrites writes;

  setUp(() {
    writes = FakeTrackerWrites();
  });

  testWidgets('a held wedge titles the sheet with its habit, starts at the '
      'default amount, and says what it will log', (tester) async {
    await withClock(Clock.fixed(_now), () async {
      await _open(tester, writes, initialViceID: _coffee.id);

      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
      expect(find.text('Coffee'), findsOneWidget);
      expect(_shownQuantity(tester), formatAmount(defaultQuantity));
      expect(find.text('Log 1 drink at 18:30'), findsOneWidget);
    });
  });

  testWidgets('+ and − step the amount, and − stops at one', (tester) async {
    await withClock(Clock.fixed(_now), () async {
      await _open(tester, writes, initialViceID: _coffee.id);
      final Finder less = find.byTooltip(AmountFields.lessTooltip);
      final Finder more = find.byTooltip(AmountFields.moreTooltip);

      expect(tester.widget<IconButton>(_iconButton(less)).onPressed, isNull);
      await tester.tap(more);
      await tester.tap(more);
      await tester.pump();
      expect(_shownQuantity(tester), '3');
      expect(find.text('drinks'), findsOneWidget);
      expect(find.text('Log 3 drinks at 18:30'), findsOneWidget);
      await tester.tap(less);
      await tester.pump();
      expect(_shownQuantity(tester), '2');

      await tester.tap(find.byKey(RecordNewActivityDialog.submitKey));
      await tester.pumpAndSettle();
      expect(writes.writes.single.op, 'recordActivity');
      expect(writes.writes.single.fields['quantity'], 2);
      expect(find.byType(RecordNewActivityDialog), findsNothing);
    });
  });

  testWidgets('a typed decimal steps by whole units', (tester) async {
    await withClock(Clock.fixed(_now), () async {
      await _open(tester, writes, initialViceID: _coffee.id);
      await tester.enterText(_quantity, formatAmount(1.5));
      await tester.tap(find.byTooltip(AmountFields.moreTooltip));
      await tester.pump();
      expect(_shownQuantity(tester), formatAmount(2.5));
      await tester.tap(find.byTooltip(AmountFields.lessTooltip));
      await tester.tap(find.byTooltip(AmountFields.lessTooltip));
      await tester.pump();
      expect(_shownQuantity(tester), formatAmount(1));
    });
  });

  testWidgets('without a habit the sheet asks for one', (tester) async {
    await withClock(Clock.fixed(_now), () async {
      await _open(tester, writes);

      expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
      await tester.tap(find.byKey(RecordNewActivityDialog.submitKey));
      await tester.pump();
      expect(find.text('Please select a habit'), findsOneWidget);
      expect(writes.writes, isEmpty);
    });
  });

  testWidgets('the close button dismisses the sheet', (tester) async {
    await withClock(Clock.fixed(_now), () async {
      await _open(tester, writes, initialViceID: _coffee.id);
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.byType(RecordNewActivityDialog), findsNothing);
      expect(writes.writes, isEmpty);
    });
  });

  testWidgets('a drag cannot close the sheet while it saves', (tester) async {
    await withClock(Clock.fixed(_now), () async {
      writes.respond = (_) => Completer<void>().future;
      await _open(tester, writes, initialViceID: _coffee.id);
      await tester.tap(find.byKey(RecordNewActivityDialog.submitKey));
      await tester.pump();
      await tester.drag(
        find.text('Coffee'),
        const Offset(0, 500),
        warnIfMissed: false,
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(RecordNewActivityDialog), findsOneWidget);
      expect(writes.writes, hasLength(1));
      // The save outlasts its timeout, so the sheet closes as queued.
      await tester.pump(const Duration(seconds: 11));
      await tester.pumpAndSettle();
      expect(find.byType(RecordNewActivityDialog), findsNothing);
      await tester.pump(const Duration(seconds: 10));
    });
  });

  testWidgets('the editor steps the stored amount and saves it', (
    tester,
  ) async {
    final String id = fakeActivity('coffee', 3, _now).id;
    await _open(
      tester,
      writes,
      page: ViceActivityEditorPage(viceID: 'coffee', activityID: id),
    );

    expect(_shownQuantity(tester), '3');
    await tester.tap(find.byTooltip(AmountFields.moreTooltip));
    await tester.pump();
    expect(_shownQuantity(tester), '4');
    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await tester.pumpAndSettle();

    expect(writes.writes.single.op, 'updateActivity');
    expect(writes.writes.single.id, id);
    expect(writes.writes.single.fields['quantity'], 4);
  });
}

Finder _iconButton(Finder tooltip) =>
    find.ancestor(of: tooltip, matching: find.byType(IconButton)).first;
