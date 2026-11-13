import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/habit_line.dart';
import 'package:tracker/data/unit.dart';
import 'package:tracker/data/usage_series.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/design/app_theme.dart';
import 'package:tracker/design/habit_mark.dart';
import 'package:tracker/providers/tracker_writes_provider.dart';
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/providers/vice_list_provider.dart';
import 'package:tracker/trends/trends_chart.dart';
import 'package:tracker/widgets/line_offer.dart';
import 'package:tracker/widgets/rejected_writes_banner.dart';
import 'package:tracker/widgets/tally_row.dart';

import 'fake_writes.dart';
import 'fakes.dart';

Vice _wine({HabitLine? line, bool archived = false}) => Vice(
  id: 'wine',
  name: 'Wine',
  unit: Unit.drink,
  ownerID: ownerID,
  createdAt: Timestamp.fromMillisecondsSinceEpoch(0),
  archived: archived,
  unitLabel: 'glasses',
  unitSingular: 'glass',
  line: line,
);

void main() {
  group('Today', () {
    Future<void> pumpRow(WidgetTester tester, Vice vice, num lineTotal) =>
        tester.pumpWidget(
          MaterialApp(
            theme: appTheme(Brightness.light),
            home: Scaffold(
              body: TallyRow(
                vice: vice,
                mark: const HabitMark(1),
                total: 2,
                day: DateTime(2026, 11, 13),
                onLog: (_) {},
                lineTotal: vice.line == null ? null : lineTotal,
              ),
            ),
          ),
        );

    testWidgets('a habit without a line shows no mark', (tester) async {
      await pumpRow(tester, _wine(), 2);
      expect(find.textContaining('of'), findsNothing);
      expect(
        find.byType(CustomPaint).evaluate().where((Element e) {
          return (e.widget as CustomPaint).painter is LineBarPainter;
        }),
        isEmpty,
      );
    });

    testWidgets('a day line reads "2 of 3 a day", spoken with the total', (
      tester,
    ) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      await pumpRow(tester, _wine(line: const HabitLine(3, LinePeriod.day)), 2);
      expect(find.text('2 of 3 a day'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Wine, 2 glasses, your line 3 a day'),
        findsOneWidget,
      );
      semantics.dispose();
    });

    testWidgets('a week line reads the last 7 days against it', (tester) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      await pumpRow(
        tester,
        _wine(line: const HabitLine(30, LinePeriod.week)),
        22,
      );
      expect(find.text('22 of 30 in 7 days'), findsOneWidget);
      expect(
        find.bySemanticsLabel(
          'Wine, 2 glasses, 22 glasses in the last 7 days, your line 30 a '
          'week',
        ),
        findsOneWidget,
      );
      semantics.dispose();
    });
  });

  test('Trends counts the buckets over the line and says so', () {
    const HabitLine line = HabitLine(3, LinePeriod.day);
    final UsageRange range = usageRange(DateTime(2026, 11, 13), 7, 1);
    final List<double> totals = <double>[1, 3, 4, 0, 5, 2, 3];
    expect(TrendsChart.overLine(totals, line), 2);
    expect(
      TrendsChart.summary(
        vice: _wine(line: line),
        range: range,
        totals: totals,
        smoothingWindow: 1,
        line: line,
      ),
      contains('A dashed line marks your line, 3 a day; 2 days over it.'),
    );
  });

  group('Insights offer', () {
    late FakeTrackerWrites writes;
    setUp(() => writes = FakeTrackerWrites());

    Future<void> pumpOffer(WidgetTester tester, Vice vice) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            trackerWritesProvider.overrideWithValue(writes),
            memoryJournal(),
            userProvider.overrideWith((ref) => Stream.value(FakeUser(ownerID))),
            viceListProvider.overrideWithValue(AsyncData<List<Vice>>([vice])),
          ],
          child: MaterialApp(
            theme: appTheme(Brightness.light),
            builder: rejectedWritesBuilder,
            home: const Scaffold(body: LineOffer(habitId: 'wine', cut: 3)),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('with no line, marks the amount a day as the line', (
      tester,
    ) async {
      await pumpOffer(tester, _wine());
      expect(find.text(LineOffer.offerNote('Wine')), findsOneWidget);
      await tester.tap(find.text("Mark 3 a day as Wine's line"));
      await tester.pumpAndSettle();
      expect(writes.writes, [
        const Write('updateVice', 'wine', <String, Object?>{
          'line': HabitLine(3, LinePeriod.day),
        }),
      ]);
      expect(find.text("Wine's line: 3 glasses a day"), findsOneWidget);
    });

    testWidgets('with another line, offers to change it, showing both', (
      tester,
    ) async {
      await pumpOffer(
        tester,
        _wine(line: const HabitLine(30, LinePeriod.week)),
      );
      expect(find.text("Wine's line is 30 glasses a week."), findsOneWidget);
      expect(find.text('Change it to 3 a day'), findsOneWidget);
    });

    testWidgets('once set, says so and offers nothing', (tester) async {
      await pumpOffer(tester, _wine(line: const HabitLine(3, LinePeriod.day)));
      expect(
        find.text("Wine's line is 3 glasses a day. ${LineOffer.editHint}"),
        findsOneWidget,
      );
      expect(find.byType(OutlinedButton), findsNothing);
    });

    testWidgets('an archived habit gets no offer', (tester) async {
      await pumpOffer(tester, _wine(archived: true));
      expect(find.byType(OutlinedButton), findsNothing);
    });

    testWidgets('without the journal key it writes nothing', (tester) async {
      writes.canCreate = false;
      await pumpOffer(tester, _wine());
      await tester.tap(find.byType(OutlinedButton));
      await tester.pumpAndSettle();
      expect(writes.writes, isEmpty);
    });
  });
}
