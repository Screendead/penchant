import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/manage_data.dart';
import 'package:tracker/providers/unarchived_vice_list_provider.dart';
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/providers/vice_activity_day_provider.dart';
import 'package:tracker/providers/vice_list_provider.dart';
import 'package:tracker/vice_tracker.dart';
import 'package:tracker/widgets/info_box.dart';

import 'fakes.dart';

Finder _button(String tooltip) => find.byTooltip(tooltip);

bool _enabled(WidgetTester tester, String tooltip) =>
    tester
        .widget<IconButton>(
          find.ancestor(
            of: _button(tooltip),
            matching: find.byType(IconButton),
          ),
        )
        .onPressed !=
    null;

double _chartedQuantity(WidgetTester tester) => tester
    .widget<RadarChart>(find.byType(RadarChart))
    .data
    .dataSets
    .single
    .dataEntries
    .first
    .value;

Future<void> _pumpApp(
  WidgetTester tester,
  List<Override> overrides,
  Widget home,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(home: Scaffold(body: home)),
    ),
  );
  await tester.pump();
}

void main() {
  group('day navigation', () {
    final DateTime today = startOfDay(DateTime.now());
    final Vice vice = fakeVice('coffee');
    final List<Vice> vices = [vice, fakeVice('beer'), fakeVice('cigarettes')];
    late StreamController<List<ViceActivity>?> neverEmits;
    late List<DateTime> requestedDays;

    setUp(() {
      neverEmits = StreamController<List<ViceActivity>?>();
      requestedDays = <DateTime>[];
    });

    // close() completes only once a listener receives done, and most tests
    // never subscribe to this stream.
    tearDown(() {
      neverEmits.close();
    });

    List<Override> overrides() => [
      unarchivedViceListProvider.overrideWith((ref) => Stream.value(vices)),
      viceActivityDayProvider.overrideWith((ref, DateTime day) {
        requestedDays.add(day);
        final int daysAgo = daysBetween(day, today);

        if (daysAgo == 2) {
          return neverEmits.stream;
        }

        return Stream.value([fakeActivity(vice.id, daysAgo + 1, day)]);
      }),
    ];

    testWidgets('arrows change the charted day and stay enabled', (
      WidgetTester tester,
    ) async {
      await _pumpApp(tester, overrides(), const ViceTracker());

      expect(find.text('Today'), findsOneWidget);
      expect(_chartedQuantity(tester), 1);
      expect(_enabled(tester, 'Next day'), isFalse);

      await tester.tap(_button('Previous day'));
      await tester.pump();
      await tester.pump();

      expect(find.text('Yesterday'), findsOneWidget);
      expect(_chartedQuantity(tester), 2);
      expect(_enabled(tester, 'Previous day'), isTrue);
      expect(_enabled(tester, 'Next day'), isTrue);

      await tester.tap(_button('Next day'));
      await tester.pump();

      expect(find.text('Today'), findsOneWidget);
      expect(_chartedQuantity(tester), 1);
      expect(requestedDays, [today, addDays(today, -1)]);
    });

    testWidgets('a day whose data never arrives does not freeze controls', (
      WidgetTester tester,
    ) async {
      await _pumpApp(tester, overrides(), const ViceTracker());

      await tester.tap(_button('Previous day'));
      await tester.pump();
      await tester.tap(_button('Previous day'));
      await tester.pump();

      expect(find.text('2 days ago'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(_enabled(tester, 'Previous day'), isTrue);
      expect(_enabled(tester, 'Next day'), isTrue);

      await tester.tap(_button('Next day'));
      await tester.pump();

      expect(find.text('Yesterday'), findsOneWidget);
      expect(_chartedQuantity(tester), 2);
    });

    testWidgets('the dropdown selects the charted day', (
      WidgetTester tester,
    ) async {
      await _pumpApp(tester, overrides(), const ViceTracker());

      await tester.tap(find.byType(DropdownButton<DateTime>));
      await tester.pumpAndSettle();
      await tester.tap(
        find
            .text(DateFormat('EEEE, MMMM d, yyyy').format(addDays(today, -1)))
            .last,
      );
      await tester.pumpAndSettle();

      expect(find.text('Yesterday'), findsOneWidget);
      expect(_chartedQuantity(tester), 2);
    });

    testWidgets('the back arrow stops at the oldest selectable day', (
      WidgetTester tester,
    ) async {
      await _pumpApp(tester, overrides(), const ViceTracker());

      for (int i = 0; i < ViceTracker.selectableDays - 1; i++) {
        await tester.tap(_button('Previous day'));
        await tester.pump();
      }

      expect(
        find.text('${ViceTracker.selectableDays - 1} days ago'),
        findsOneWidget,
      );
      expect(_enabled(tester, 'Previous day'), isFalse);
      expect(_enabled(tester, 'Next day'), isTrue);
    });

    testWidgets('a day with nothing recorded is not shown as an error', (
      WidgetTester tester,
    ) async {
      await _pumpApp(tester, [
        unarchivedViceListProvider.overrideWith((ref) => Stream.value(vices)),
        viceActivityDayProvider.overrideWith(
          (ref, DateTime day) => Stream.value(const <ViceActivity>[]),
        ),
      ], const ViceTracker());

      expect(find.text('Nothing recorded on this day'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });

  group('fewer vices than radar axes', () {
    final DateTime today = startOfDay(DateTime.now());
    final Vice coffee = fakeVice('coffee');
    final Vice beer = fakeVice('beer');

    List<Override> overrides(List<Vice> vices) => [
      unarchivedViceListProvider.overrideWith((ref) => Stream.value(vices)),
      viceActivityDayProvider.overrideWith((ref, DateTime day) {
        final int daysAgo = daysBetween(day, today);

        return Stream.value([
          fakeActivity(coffee.id, daysAgo + 2, day),
          fakeActivity(beer.id, daysAgo + 1, day),
        ]);
      }),
    ];

    List<double> barValues(WidgetTester tester) => [
      for (final BarChartGroupData group
          in tester.widget<BarChart>(find.byType(BarChart)).data.barGroups)
        group.barRods.single.toY,
    ];

    Finder barTitle(String text) =>
        find.descendant(of: find.byType(BarChart), matching: find.text(text));

    testWidgets('one vice is charted as a bar', (WidgetTester tester) async {
      await _pumpApp(tester, overrides([coffee]), const ViceTracker());
      await tester.pumpAndSettle();

      expect(find.byType(RadarChart), findsNothing);
      expect(barValues(tester), [2]);
      expect(barTitle('coffee (2 items)'), findsOneWidget);
    });

    testWidgets('two vices are charted as bars that follow the selected day', (
      WidgetTester tester,
    ) async {
      await _pumpApp(tester, overrides([coffee, beer]), const ViceTracker());
      await tester.pumpAndSettle();

      expect(find.byType(RadarChart), findsNothing);
      expect(barValues(tester), [2, 1]);
      expect(barTitle('coffee (2 items)'), findsOneWidget);
      expect(barTitle('beer (1 item)'), findsOneWidget);

      await tester.tap(_button('Previous day'));
      await tester.pumpAndSettle();

      expect(find.text('Yesterday'), findsOneWidget);
      expect(barValues(tester), [3, 2]);
      expect(barTitle('coffee (3 items)'), findsOneWidget);
      expect(barTitle('beer (2 items)'), findsOneWidget);
    });

    testWidgets('a third vice switches to the radar', (
      WidgetTester tester,
    ) async {
      await _pumpApp(
        tester,
        overrides([coffee, beer, fakeVice('tea')]),
        const ViceTracker(),
      );
      await tester.pumpAndSettle();

      expect(find.byType(BarChart), findsNothing);
      expect(find.byType(RadarChart), findsOneWidget);
    });
  });

  group('an account with no vices', () {
    List<Override> overrides() => [
      userProvider.overrideWith((ref) => Stream.value(FakeUser(ownerID))),
      viceListProvider.overrideWith((ref) => Stream.value(const <Vice>[])),
      unarchivedViceListProvider.overrideWith(
        (ref) => Stream.value(const <Vice>[]),
      ),
    ];

    testWidgets('sees an empty state on the Today tab, not a spinner', (
      WidgetTester tester,
    ) async {
      await _pumpApp(tester, overrides(), const ViceTracker());
      await tester.pumpAndSettle();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(
        find.descendant(
          of: find.byType(InfoBox),
          matching: find.textContaining('No vices yet'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('can reach Add vice from Manage Data', (
      WidgetTester tester,
    ) async {
      await _pumpApp(tester, overrides(), const ManageData());
      await tester.pumpAndSettle();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.textContaining('No vices yet'), findsOneWidget);
      expect(find.byTooltip('Add vice'), findsOneWidget);
    });
  });
}
