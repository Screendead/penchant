import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/providers/offline_provider.dart';
import 'package:tracker/providers/tracker_writes_provider.dart';
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/providers/vice_activity_day_provider.dart';
import 'package:tracker/vice_tracker.dart';
import 'package:tracker/widgets/app_menu_bar.dart';
import 'package:tracker/widgets/tally_row.dart';
import 'package:tracker/writes/log_one.dart';

import 'fake_writes.dart';
import 'fakes.dart';

final List<Vice> _habits = <Vice>[
  for (int i = 0; i < 10; i++) fakeVice('habit-$i'),
];

Future<FakeTrackerWrites> _pump(
  WidgetTester tester,
  List<Vice> habits, {
  bool withToday = true,
}) async {
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.menu,
    (MethodCall call) async => null,
  );
  final FakeTrackerWrites writes = FakeTrackerWrites();
  final List<Override> overrides = <Override>[
    ...habitOverrides(habits),
    userProvider.overrideWith((ref) => Stream.value(FakeUser(ownerID))),
    offlineProvider.overrideWith((ref) => Stream.value(false)),
    trackerWritesProvider.overrideWithValue(writes),
    memoryJournal(),
    viceActivityDayProvider.overrideWith(
      (ref, DateTime day) => const AsyncData([]),
    ),
  ];
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        builder: (BuildContext context, Widget? child) =>
            AppMenuBar(child: child!),
        home: Scaffold(
          body: withToday ? const ViceTracker() : const SizedBox.shrink(),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  return writes;
}

List<PlatformMenuItem> _menus(WidgetTester tester) =>
    tester.widget<PlatformMenuBar>(find.byType(PlatformMenuBar)).menus;

PlatformMenu? _logMenu(WidgetTester tester) => _menus(
  tester,
).whereType<PlatformMenu>().where((m) => m.label == 'Log').firstOrNull;

void main() {
  testWidgets(
    "the Log menu names the first nine habits in Today's order with Cmd-1 "
    'to Cmd-9, and logs one of the one picked',
    (WidgetTester tester) async {
      final FakeTrackerWrites writes = await _pump(tester, _habits);

      final List<String> tallies = <String>[
        for (final TallyRow row in tester.widgetList<TallyRow>(
          find.byType(TallyRow, skipOffstage: false),
        ))
          row.vice.name,
      ];
      final List<PlatformMenuItem> items = _logMenu(tester)!.menus;
      expect(<String>[
        for (final PlatformMenuItem i in items) i.label,
      ], tallies.take(9).toList());
      for (int i = 0; i < 9; i++) {
        final SingleActivator key = items[i].shortcut! as SingleActivator;
        expect((key.trigger, key.meta), (habitKey(i).trigger, true));
        expect(key.trigger.keyLabel, '${i + 1}');
      }
      expect(
        _menus(tester).map((PlatformMenuItem m) => m.label),
        containsAllInOrder(<String>['Edit', 'Log', 'View', 'Window']),
      );

      items[1].onSelected!();
      await tester.pump();
      final Write write = writes.writes.single;
      expect(write.op, 'recordActivity');
      expect(
        write.fields['viceID'],
        _habits.firstWhere((Vice v) => v.name == tallies[1]).id,
      );
      expect(write.fields['quantity'], defaultQuantity);
      expect(find.textContaining('Logged 1 '), findsOneWidget);
      await tester.pumpAndSettle();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'the Log menu follows the habit list and leaves the bar with none',
    (WidgetTester tester) async {
      await _pump(tester, _habits.take(2).toList());
      expect(_logMenu(tester)!.menus, hasLength(2));

      await _pump(tester, const <Vice>[]);
      expect(_logMenu(tester), isNull);
      expect(_menus(tester), isNotEmpty);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'with Today gone, a Log item does nothing',
    (WidgetTester tester) async {
      final FakeTrackerWrites writes = await _pump(
        tester,
        _habits.take(1).toList(),
        withToday: false,
      );
      _logMenu(tester)!.menus.single.onSelected!();
      await tester.pump();
      expect(writes.writes, isEmpty);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets('iOS has no menu bar', (WidgetTester tester) async {
    await _pump(tester, _habits);
    expect(find.byType(PlatformMenuBar), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
}
