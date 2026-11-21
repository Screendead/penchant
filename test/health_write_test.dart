import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tracker/data/category.dart';
import 'package:tracker/data/habit_strength.dart';
import 'package:tracker/data/unit.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/health_write/health_write.dart';
import 'package:tracker/health_write/health_write_sync.dart';
import 'package:tracker/providers/tracker_writes_provider.dart';
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/providers/vice_list_provider.dart';
import 'package:tracker/vice_form.dart';

import 'fake_writes.dart';
import 'fakes.dart';

Vice _vice(String id, HabitStrength? strength, {bool locked = false}) => Vice(
  id: id,
  name: id,
  unit: Unit.drink,
  ownerID: ownerID,
  createdAt: Timestamp.fromMillisecondsSinceEpoch(0),
  archived: false,
  locked: locked,
  category: ViceCategory.other,
  strength: strength,
);

final DateTime _now = DateTime(2026, 11, 16, 20);

ViceActivity _entry(
  String id,
  String viceID, {
  int quantity = 1,
  double? amount,
  double? abv,
  double? caffeineMg,
  DateTime? at,
  bool locked = false,
}) => ViceActivity(
  id: id,
  viceID: viceID,
  quantity: quantity,
  amount: amount,
  ownerID: ownerID,
  createdAt: Timestamp.fromDate(at ?? _now),
  abv: abv,
  caffeineMg: caffeineMg,
  locked: locked,
);

const HabitStrength _pint = HabitStrength.alcohol(
  unit: StrengthUnit.ukUnit,
  servingMl: 568,
  abv: 4.5,
);
const HabitStrength _cup = HabitStrength.caffeine(caffeineMg: 95);

class _FakeWriter implements HealthWriter {
  bool allow = true;
  final List<String> calls = <String>[];

  @override
  Future<bool> requestWrite(HealthWriteKind kind) async {
    calls.add('request ${kind.name}');
    return allow;
  }

  @override
  Future<void> writeEntry({
    required HealthWriteKind kind,
    required String activityID,
    required String viceID,
    required double value,
    required DateTime at,
  }) async => calls.add('write $activityID $value');

  @override
  Future<void> deleteEntry(String activityID) async =>
      calls.add('delete $activityID');

  @override
  Future<void> deleteHabit(String viceID) async =>
      calls.add('deleteHabit $viceID');
}

void main() {
  group('what an entry writes', () {
    test('alcohol: one drink per serving, whatever its strength', () {
      expect(healthValueOf(_pint, _entry('a', 'beer')), 1);
      expect(healthValueOf(_pint, _entry('a', 'beer', abv: 6.5)), 1);
      expect(healthValueOf(_pint, _entry('a', 'beer', quantity: 3)), 3);
      expect(
        healthValueOf(_pint, _entry('a', 'beer', quantity: 2, amount: 1.5)),
        1.5,
      );
      const HabitStrength noAbv = HabitStrength.alcohol(
        unit: StrengthUnit.grams,
        servingMl: 175,
      );
      expect(healthValueOf(noAbv, _entry('a', 'wine')), 1);
    });

    test("caffeine: the entry's mg wins; none writes nothing", () {
      expect(healthValueOf(_cup, _entry('c', 'coffee', quantity: 2)), 190);
      expect(healthValueOf(_cup, _entry('c', 'coffee', caffeineMg: 60)), 60);
      const HabitStrength unknown = HabitStrength.caffeine();
      expect(healthValueOf(unknown, _entry('c', 'tea')), isNull);
      expect(
        healthValueOf(unknown, _entry('c', 'tea', caffeineMg: 40.5)),
        40.5,
      );
    });

    test('the kind follows the strength', () {
      expect(HealthWriteKind.of(null), isNull);
      expect(HealthWriteKind.of(_pint), HealthWriteKind.alcohol);
      expect(HealthWriteKind.of(_cup), HealthWriteKind.caffeine);
    });
  });

  group('keeping Health in step', () {
    final List<Vice> vices = <Vice>[
      _vice('beer', _pint),
      _vice('coffee', _cup),
      _vice('tea', const HabitStrength.caffeine()),
      _vice('locked', _cup, locked: true),
    ];
    final DateTime windowStart = DateTime(2026, 10, 18);

    HealthWriteStep step(
      List<ViceActivity> activities,
      Map<String, ({String viceID, HealthSample sample})> written, {
      Set<String> chosen = const <String>{'beer', 'coffee', 'tea', 'locked'},
    }) => healthWriteStep(
      vices: vices,
      activities: activities,
      chosen: chosen,
      windowStart: windowStart,
      written: written,
    );

    test('writes each chosen entry with a value, once', () {
      final HealthWriteStep first = step(<ViceActivity>[
        _entry('b1', 'beer'),
        _entry('c1', 'coffee'),
        _entry('t1', 'tea'),
        _entry('l1', 'locked'),
        _entry('b2', 'beer', locked: true),
      ], const {});
      expect(first.write.keys, unorderedEquals(<String>['b1', 'c1']));
      expect(first.write['c1']!.value, 95);
      expect(first.write['b1']!.kind, HealthWriteKind.alcohol);
      expect(first.delete, isEmpty);

      final HealthWriteStep again = step(
        <ViceActivity>[_entry('b1', 'beer'), _entry('c1', 'coffee')],
        <String, ({String viceID, HealthSample sample})>{
          for (final MapEntry<String, HealthSample> e in first.write.entries)
            e.key: (viceID: e.key == 'b1' ? 'beer' : 'coffee', sample: e.value),
        },
      );
      expect(again.write, isEmpty);
      expect(again.delete, isEmpty);
    });

    final Map<String, ({String viceID, HealthSample sample})> written =
        <String, ({String viceID, HealthSample sample})>{
          'c1': (
            viceID: 'coffee',
            sample: (kind: HealthWriteKind.caffeine, value: 95, at: _now),
          ),
        };

    test('an edit rewrites; a time change too', () {
      expect(
        step(<ViceActivity>[
          _entry('c1', 'coffee', caffeineMg: 120),
        ], written).write['c1']!.value,
        120,
      );
      final DateTime earlier = _now.subtract(const Duration(hours: 2));
      expect(
        step(<ViceActivity>[
          _entry('c1', 'coffee', at: earlier),
        ], written).write['c1']!.at,
        earlier,
      );
    });

    test('a delete in the window removes; one out of it does not', () {
      expect(step(const <ViceActivity>[], written).delete, <String>{'c1'});
      final Map<String, ({String viceID, HealthSample sample})> old =
          <String, ({String viceID, HealthSample sample})>{
            'c0': (
              viceID: 'coffee',
              sample: (
                kind: HealthWriteKind.caffeine,
                value: 95,
                at: windowStart.subtract(const Duration(minutes: 1)),
              ),
            ),
          };
      expect(step(const <ViceActivity>[], old).delete, isEmpty);
    });

    test('a habit no longer chosen keeps its samples', () {
      final HealthWriteStep off = step(
        const <ViceActivity>[],
        written,
        chosen: const <String>{'beer'},
      );
      expect(off.delete, isEmpty);
      expect(off.write, isEmpty);
    });

    test('an entry that loses its value is removed', () {
      final HealthWriteStep none = healthWriteStep(
        vices: <Vice>[_vice('coffee', const HabitStrength.caffeine())],
        activities: <ViceActivity>[_entry('c1', 'coffee')],
        chosen: const <String>{'coffee'},
        windowStart: windowStart,
        written: written,
      );
      expect(none.delete, <String>{'c1'});
    });
  });

  group('the channel', () {
    const MethodChannel channel = MethodChannel('test/health-write');
    final List<MethodCall> calls = <MethodCall>[];

    setUp(() {
      calls.clear();
      TestWidgetsFlutterBinding.ensureInitialized();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
            calls.add(call);
            if (call.method == 'deleteHabit') {
              throw PlatformException(code: 'denied');
            }
            return call.method == 'requestWrite' ? true : null;
          });
    });

    test(
      'sends ids derived from the documents, and swallows failures',
      () async {
        const HealthWriter writer = HealthWriter(channel: channel);
        expect(await writer.requestWrite(HealthWriteKind.caffeine), isTrue);
        await writer.writeEntry(
          kind: HealthWriteKind.alcohol,
          activityID: 'a1',
          viceID: 'v1',
          value: 2,
          at: DateTime.fromMillisecondsSinceEpoch(1000),
        );
        await writer.deleteEntry('a1');
        await writer.deleteHabit('v1');
        expect(calls.map((MethodCall c) => c.method), <String>[
          'requestWrite',
          'writeEntry',
          'deleteEntry',
          'deleteHabit',
        ]);
        final Map<Object?, Object?> write =
            calls[1].arguments as Map<Object?, Object?>;
        expect(write['syncID'], 'penchant.entry.a1');
        expect(write['habit'], 'penchant.habit.v1');
        expect(write['kind'], 'alcohol');
        expect(write['value'], 2.0);
        expect(write['at'], 1000);
        expect(write['version'], isA<int>());
      },
    );

    test('a missing channel answers false', () async {
      const HealthWriter writer = HealthWriter(
        channel: MethodChannel('test/none'),
      );
      expect(await writer.requestWrite(HealthWriteKind.alcohol), isFalse);
      await writer.deleteEntry('a1');
    });
  });

  group("the habit form's switch", () {
    late _FakeWriter writer;
    late FakeTrackerWrites writes;

    setUp(() {
      writer = _FakeWriter();
      writes = FakeTrackerWrites();
    });

    Future<ProviderContainer> open(
      WidgetTester tester,
      Vice vice, {
      List<String> stored = const <String>[],
    }) async {
      await tester.pumpWidget(const SizedBox());
      SharedPreferences.setMockInitialValues(<String, Object>{
        HealthWriteChoices.keyOf(ownerID): stored,
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            trackerWritesProvider.overrideWithValue(writes),
            memoryJournal(),
            userProvider.overrideWith((ref) => Stream.value(FakeUser(ownerID))),
            viceListProvider.overrideWith((ref) => AsyncData(<Vice>[vice])),
            healthWriterProvider.overrideWithValue(writer),
            healthWriteSupportedProvider.overrideWithValue(true),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Consumer(
                builder: (BuildContext context, WidgetRef ref, _) {
                  ref.watch(userProvider);
                  return TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => EditVice(viceID: vice.id),
                      ),
                    ),
                    child: const Text('open'),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return ProviderScope.containerOf(tester.element(find.byType(ViceForm)));
    }

    Future<void> tapSwitch(WidgetTester tester) async {
      final Finder toggle = find.byKey(ViceForm.healthWriteKey);
      await tester.ensureVisible(toggle);
      await tester.pumpAndSettle();
      await tester.tap(toggle);
      await tester.pumpAndSettle();
    }

    Future<void> save(WidgetTester tester) async {
      await tester.tap(find.widgetWithText(TextButton, 'Save'));
      await tester.pumpAndSettle();
    }

    testWidgets('turning it on asks Health, and saving keeps it', (
      WidgetTester tester,
    ) async {
      final ProviderContainer container = await open(
        tester,
        _vice('beer', _pint),
      );
      await tapSwitch(tester);
      expect(writer.calls, <String>['request alcohol']);
      expect(container.read(healthWriteChoicesProvider(ownerID)), isEmpty);
      await save(tester);
      expect(container.read(healthWriteChoicesProvider(ownerID)), <String>{
        'beer',
      });
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList(HealthWriteChoices.keyOf(ownerID)), <String>[
        'beer',
      ]);
    });

    testWidgets('turning it off offers once to remove what was written', (
      WidgetTester tester,
    ) async {
      final ProviderContainer container = await open(
        tester,
        _vice('beer', _pint),
        stored: <String>['beer'],
      );
      expect(
        tester.widget<Switch>(find.byKey(ViceForm.healthWriteKey)).value,
        isTrue,
      );
      await tapSwitch(tester);
      expect(find.text(ViceForm.healthRemoveTitle), findsOneWidget);
      await tester.tap(find.text(ViceForm.healthRemove));
      await tester.pumpAndSettle();
      expect(writer.calls, isEmpty);
      await save(tester);
      expect(writer.calls, <String>['deleteHabit beer']);
      expect(container.read(healthWriteChoicesProvider(ownerID)), isEmpty);
    });

    testWidgets('Keep leaves the samples', (WidgetTester tester) async {
      await open(tester, _vice('beer', _pint), stored: <String>['beer']);
      await tapSwitch(tester);
      await tester.tap(find.text(ViceForm.healthKeep));
      await tester.pumpAndSettle();
      await save(tester);
      expect(writer.calls, isEmpty);
    });
  });
}
