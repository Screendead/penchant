import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/formats.dart';
import 'package:tracker/manage_data.dart';
import 'package:tracker/providers/offline_provider.dart';
import 'package:tracker/providers/unarchived_vice_list_provider.dart';
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/providers/vice_activity_day_provider.dart';
import 'package:tracker/providers/vice_list_provider.dart';
import 'package:tracker/vice_tracker.dart';
import 'package:tracker/widgets/clean_day.dart';
import 'package:tracker/widgets/info_box.dart';
import 'package:tracker/widgets/record_new_activity_dialog.dart';
import 'package:tracker/writes/settle_write.dart';

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
    .first
    .dataEntries
    .first
    .value;

// WCAG 2.x contrast ratio.
double _contrast(Color a, Color b) {
  final double la = a.computeLuminance();
  final double lb = b.computeLuminance();
  return (max(la, lb) + 0.05) / (min(la, lb) + 0.05);
}

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
    late List<DateTime> requestedDays;

    setUp(() {
      requestedDays = <DateTime>[];
    });

    List<Override> overrides() => [
      unarchivedViceListProvider.overrideWithValue(AsyncData(vices)),
      viceActivityDayProvider.overrideWith((ref, DateTime day) {
        requestedDays.add(day);
        final int daysAgo = daysBetween(day, today);

        if (daysAgo == 2) {
          return const AsyncLoading();
        }

        return AsyncData([fakeActivity(vice.id, daysAgo + 1, day)]);
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
      // An auto-dispose day may be re-requested on return; how soon it is
      // disposed is Riverpod's scheduling, not this widget's.
      expect(requestedDays.toSet(), {today, addDays(today, -1)});
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
      await tester.tap(find.text(formatDay(addDays(today, -1))).last);
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
  });

  group('fewer vices than radar axes', () {
    final DateTime today = startOfDay(DateTime.now());
    final Vice coffee = fakeVice('coffee');
    final Vice beer = fakeVice('beer');

    List<Override> overrides(List<Vice> vices) => [
      unarchivedViceListProvider.overrideWithValue(AsyncData(vices)),
      viceActivityDayProvider.overrideWith((ref, DateTime day) {
        final int daysAgo = daysBetween(day, today);

        return AsyncData([
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

  group('a day with nothing recorded', () {
    final List<Vice> vices = [fakeVice('coffee')];

    List<Override> overrides() => [
      unarchivedViceListProvider.overrideWithValue(AsyncData(vices)),
      viceActivityDayProvider.overrideWith(
        (ref, DateTime day) => const AsyncData(<ViceActivity>[]),
      ),
    ];

    testWidgets('reads as a clear day, today and on past days', (
      WidgetTester tester,
    ) async {
      await _pumpApp(tester, overrides(), const ViceTracker());

      expect(find.byType(CleanDay), findsOneWidget);
      expect(find.text('A clear day so far'), findsOneWidget);
      expect(find.text('Nothing recorded today.'), findsOneWidget);
      expect(find.byType(BarChart), findsNothing);

      await tester.tap(_button('Previous day'));
      await tester.pump();
      await tester.pump();

      expect(find.text('A clear day'), findsOneWidget);
      expect(find.text('Nothing recorded on this day.'), findsOneWidget);
    });

    testWidgets('offline, says the device may not have the day rather than '
        'calling it clear', (WidgetTester tester) async {
      await _pumpApp(tester, [
        ...overrides(),
        offlineProvider.overrideWith((ref) => Stream.value(true)),
      ], const ViceTracker());
      await tester.pump();

      expect(find.byType(CleanDay), findsOneWidget);
      expect(find.text(CleanDay.offlineHeadline), findsOneWidget);
      expect(find.text('A clear day so far'), findsNothing);
    });

    for (final Brightness brightness in Brightness.values) {
      testWidgets('is green with readable text in the ${brightness.name} '
          'theme', (WidgetTester tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: overrides(),
            child: MaterialApp(
              theme: ThemeData(brightness: brightness),
              home: const Scaffold(body: ViceTracker()),
            ),
          ),
        );
        await tester.pump();

        final Color background =
            (tester
                        .widget<DecoratedBox>(
                          find
                              .descendant(
                                of: find.byType(CleanDay),
                                matching: find.byType(DecoratedBox),
                              )
                              .first,
                        )
                        .decoration
                    as BoxDecoration)
                .color!;
        final HSLColor hsl = HSLColor.fromColor(background);
        expect(hsl.hue, inInclusiveRange(80, 160), reason: 'green hue');

        for (final String text in [
          'A clear day so far',
          'Nothing recorded today.',
        ]) {
          final Color foreground = tester
              .widget<Text>(find.text(text))
              .style!
              .color!;
          expect(
            _contrast(foreground, background),
            greaterThanOrEqualTo(4.5),
            reason: text,
          );
        }
      });
    }
  });

  testWidgets('the recorded snackbar offers Undo for eight seconds and '
      'replaces an earlier one', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SizedBox.expand())),
    );
    final ScaffoldMessengerState messenger = tester.state(
      find.byType(ScaffoldMessenger),
    );
    final List<String> undone = <String>[];

    RecordNewActivityDialog.showRecorded(
      messenger,
      synced: true,
      onUndo: () => undone.add('first'),
    );
    await tester.pumpAndSettle();
    RecordNewActivityDialog.showRecorded(
      messenger,
      synced: false,
      onUndo: () => undone.add('second'),
    );
    await tester.pumpAndSettle();

    expect(find.text(RecordNewActivityDialog.recordedMessage), findsNothing);
    expect(find.text(queuedMessage), findsOneWidget);

    await tester.pump(const Duration(seconds: 7));
    expect(find.text('Undo'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    expect(undone, ['second']);

    RecordNewActivityDialog.showRecorded(
      messenger,
      synced: true,
      onUndo: () {},
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 7));
    expect(find.text(RecordNewActivityDialog.recordedMessage), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text(RecordNewActivityDialog.recordedMessage), findsNothing);
  });

  group('an account with no vices', () {
    List<Override> overrides() => [
      userProvider.overrideWith((ref) => Stream.value(FakeUser(ownerID))),
      viceListProvider.overrideWithValue(AsyncData(const <Vice>[])),
      unarchivedViceListProvider.overrideWithValue(const AsyncData(<Vice>[])),
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

  testWidgets('the day header takes its colour from the theme', (
    WidgetTester tester,
  ) async {
    final ThemeData light = ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          unarchivedViceListProvider.overrideWithValue(
            AsyncData([fakeVice('coffee')]),
          ),
          viceActivityDayProvider.overrideWith(
            (ref, DateTime day) => const AsyncData(<ViceActivity>[]),
          ),
        ],
        child: MaterialApp(
          theme: light,
          home: const Scaffold(body: ViceTracker()),
        ),
      ),
    );
    await tester.pump();

    final Color onSurface = light.colorScheme.onSurface;
    expect(
      tester.widget<Icon>(find.byIcon(Icons.calendar_month)).color,
      onSurface,
    );
    expect(
      tester.widget<Text>(find.text('Today').first).style?.color,
      onSurface,
    );
  });
}
