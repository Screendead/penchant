import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/insights/experiment.dart';
import 'package:tracker/reminder/daily_nudge.dart';
import 'package:tracker/reminder/heavy_day.dart';
import 'package:tracker/reminder/heavy_day_nudge.dart';

import 'dst.dart';
import 'fakes.dart';

class _FakeScheduler implements NudgeScheduler {
  final List<HeavyPrompt> scheduled = <HeavyPrompt>[];
  int cancels = 0;
  bool grant = true;

  @override
  Future<void> scheduleHeavyDay(HeavyPrompt prompt) async =>
      scheduled.add(prompt);

  @override
  Future<void> cancelHeavyDay() async => cancels++;

  @override
  Future<void> scheduleUrgeCheck(String urgeID, DateTime at) async {}

  @override
  Future<void> cancelUrgeCheck(String urgeID) async {}

  @override
  Future<void> cancelUrgeChecks() async {}

  @override
  Future<bool> requestPermission() async => grant;

  @override
  Future<bool> isPermitted() async => grant;

  @override
  Future<void> start(void Function(NudgeTap tap) onTap) async {}

  @override
  Future<NudgeTap?> launchAction() async => null;

  @override
  Future<void> scheduleDaily(TimeOfDay time) async {}

  @override
  Future<void> cancel() async {}

  @override
  Future<void> scheduleWeeklyReview() async {}

  @override
  Future<void> cancelWeeklyReview() async {}

  @override
  Future<void> scheduleExperiment(List<ExperimentNotice> notices) async {}

  @override
  Future<void> cancelExperiment() async {}
}

final DateTime _today = DateTime(2026, 11, 15);

// [perDay] logged at noon on each of the [days] days before [day], from
// the oldest.
List<ViceActivity> _daily(
  String vice,
  DateTime day,
  int days, {
  int Function(int i)? perDay,
}) => <ViceActivity>[
  for (int i = 0; i < days; i++)
    fakeActivity(
      vice,
      perDay?.call(i) ?? 1,
      addDays(day, i - days).add(const Duration(hours: 12)),
    ),
];

bool _heavy(List<ViceActivity> history, List<int> today, {DateTime? day}) {
  final DateTime d = day ?? _today;
  return heavyDayOf(
    day: d,
    habits: [fakeVice('wine')],
    entries: <ViceActivity>[
      ...history,
      for (final int q in today)
        fakeActivity('wine', q, d.add(const Duration(hours: 19))),
    ],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('heavy day', () {
    test('a once-a-day habit: 1 is ordinary, 2 is heavy', () {
      final List<ViceActivity> history = _daily('wine', _today, 60);
      expect(_heavy(history, <int>[1]), isFalse);
      expect(_heavy(history, <int>[1, 1]), isTrue);
      expect(_heavy(history, <int>[]), isFalse);
    });

    test('a rarely used habit: one ordinary use is not heavy', () {
      final List<ViceActivity> history = <ViceActivity>[
        for (int i = 0; i < 12; i++)
          fakeActivity('wine', 1, addDays(_today, -7 * (i + 1))),
      ];
      expect(_heavy(history, <int>[1]), isFalse);
      expect(_heavy(history, <int>[2]), isTrue);
    });

    test('strictly above the nearest-rank 90th percentile', () {
      // Use days 1..10: the 9th smallest is 9.
      final List<ViceActivity> history = _daily(
        'wine',
        _today,
        40,
        perDay: (int i) => i < 30 ? 0 : i - 29,
      ).where((ViceActivity a) => a.quantity > 0).toList();
      // First entry must be 30 days old: add an old zero-free use.
      final List<ViceActivity> withAge = <ViceActivity>[
        ...history,
        fakeActivity('wine', 1, addDays(_today, -40)),
      ];
      // Now 11 use days: 1,1,2,...,10; ceil(9.9) = 10th smallest is 9.
      expect(_heavy(withAge, <int>[9]), isFalse);
      expect(_heavy(withAge, <int>[10]), isTrue);
    });

    test('never heavy under 30 days old or under 10 days of use', () {
      expect(_heavy(_daily('wine', _today, 29), <int>[5]), isFalse);
      expect(_heavy(_daily('wine', _today, 30), <int>[5]), isTrue);
      final List<ViceActivity> nine = <ViceActivity>[
        for (int i = 0; i < 9; i++)
          fakeActivity('wine', 1, addDays(_today, -6 * (i + 1))),
      ];
      expect(_heavy(nine, <int>[5]), isFalse);
    });

    test('days older than the 90-day window do not count', () {
      final List<ViceActivity> old = <ViceActivity>[
        for (int i = 0; i < 20; i++)
          fakeActivity('wine', 1, addDays(_today, -100 - i)),
        for (int i = 0; i < 5; i++)
          fakeActivity('wine', 1, addDays(_today, -10 - i)),
      ];
      expect(_heavy(old, <int>[5]), isFalse);
    });

    test('amounts count by measure', () {
      final List<ViceActivity> history = <ViceActivity>[
        for (int i = 1; i <= 40; i++)
          fakeActivity('wine', 1, addDays(_today, -i), amount: 0.5),
      ];
      expect(
        heavyDayOf(
          day: _today,
          habits: [fakeVice('wine')],
          entries: <ViceActivity>[
            ...history,
            fakeActivity('wine', 1, _today, amount: 0.75),
          ],
        ),
        isTrue,
      );
    });

    test('only the habits given count', () {
      final List<ViceActivity> entries = <ViceActivity>[
        ..._daily('wine', _today, 60),
        fakeActivity('wine', 3, _today),
      ];
      expect(
        heavyDayOf(day: _today, habits: [fakeVice('coffee')], entries: entries),
        isFalse,
      );
    });

    final DateTime? dst = firstDstTransitionDay(2026);
    test('a DST day is one day: an entry late on it counts on it', () {
      final DateTime day = dst!;
      final List<ViceActivity> history = _daily('wine', day, 60);
      final List<ViceActivity> entries = <ViceActivity>[
        ...history,
        fakeActivity('wine', 1, DateTime(day.year, day.month, day.day, 0, 30)),
        fakeActivity('wine', 1, DateTime(day.year, day.month, day.day, 23, 30)),
      ];
      expect(
        heavyDayOf(day: day, habits: [fakeVice('wine')], entries: entries),
        isTrue,
      );
      // The day after holds no entry of the DST day's.
      final DateTime next = addDays(day, 1);
      expect(
        heavyDayOf(
          day: next,
          habits: [fakeVice('wine')],
          entries: <ViceActivity>[
            ...entries,
            fakeActivity('wine', 1, next.add(const Duration(hours: 1))),
          ],
        ),
        isFalse,
      );
    }, skip: dst == null ? noDstSkipReason : false);
  });

  group('planned prompt', () {
    const TimeOfDay nine = TimeOfDay(hour: 21, minute: 0);
    final DateTime yesterday = addDays(_today, -1);
    DateTime at(DateTime d, int h) => DateTime(d.year, d.month, d.day, h);

    HeavyPrompt? plan(
      DateTime now, {
      bool today = false,
      bool yesterdayHeavy = false,
      List<HeavyPrompt> fired = const <HeavyPrompt>[],
    }) => plannedHeavyPrompt(
      now: now,
      time: nine,
      todayHeavy: today,
      yesterdayHeavy: yesterdayHeavy,
      fired: fired,
    );

    test('heavy before the set time: tonight, about today', () {
      final HeavyPrompt? p = plan(at(_today, 15), today: true);
      expect(p, HeavyPrompt(_today, at(_today, 21)));
      expect(p!.aboutToday, isTrue);
      expect(plan(at(_today, 15)), isNull);
    });

    test('heavy first seen after the set time: tomorrow at 9, about today', () {
      final HeavyPrompt? p = plan(at(_today, 22), today: true);
      expect(p, HeavyPrompt(_today, at(addDays(_today, 1), 9)));
      expect(p!.aboutToday, isFalse);
    });

    test('next morning: yesterday unasked gets 9:00, not after 9:00', () {
      expect(
        plan(at(_today, 7), yesterdayHeavy: true),
        HeavyPrompt(yesterday, at(_today, 9)),
      );
      expect(plan(at(_today, 10), yesterdayHeavy: true), isNull);
    });

    test('a day already asked about is not asked again', () {
      final List<HeavyPrompt> fired = <HeavyPrompt>[
        HeavyPrompt(yesterday, at(yesterday, 21)),
      ];
      expect(plan(at(_today, 7), yesterdayHeavy: true, fired: fired), isNull);
    });

    test('at most one a day: the earlier wins, the other waits a morning', () {
      expect(
        plan(at(_today, 7), today: true, yesterdayHeavy: true),
        HeavyPrompt(yesterday, at(_today, 9)),
      );
      final List<HeavyPrompt> fired = <HeavyPrompt>[
        HeavyPrompt(yesterday, at(_today, 9)),
      ];
      expect(
        plan(at(_today, 15), today: true, yesterdayHeavy: true, fired: fired),
        isNull,
      );
      final DateTime tomorrow = addDays(_today, 1);
      expect(
        plannedHeavyPrompt(
          now: at(tomorrow, 7),
          time: nine,
          todayHeavy: false,
          yesterdayHeavy: true,
          fired: fired,
        ),
        HeavyPrompt(_today, at(tomorrow, 9)),
      );
    });

    test('prompts survive encoding', () {
      final HeavyPrompt p = HeavyPrompt(_today, at(_today, 21));
      expect(HeavyPrompt.decode(p.encode()), p);
      expect(HeavyPrompt.decode('nonsense'), isNull);
    });
  });

  group('scheduling', () {
    late _FakeScheduler scheduler;
    late ProviderContainer container;
    late DateTime now;
    const HeavyDayVerdict heavy = (today: true, yesterday: false);
    const HeavyDayVerdict calm = (today: false, yesterday: false);

    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{
        HeavyDayNudge.enabledKey: true,
      });
      scheduler = _FakeScheduler();
      container = ProviderContainer(
        overrides: [nudgeSchedulerProvider.overrideWithValue(scheduler)],
      );
      addTearDown(container.dispose);
      now = DateTime(2026, 11, 15, 15);
    });

    Future<void> run(Future<void> Function(HeavyDayNudge n) body) => withClock(
      Clock(() => now),
      () => body(container.read(heavyDayNudgeProvider.notifier)),
    );

    test('schedules tonight, then cancels when the day calms', () async {
      await run((HeavyDayNudge n) async {
        await n.evaluate(heavy);
        await n.evaluate(heavy);
        expect(scheduler.scheduled, <HeavyPrompt>[
          HeavyPrompt(_today, DateTime(2026, 11, 15, 21)),
        ]);
        await n.evaluate(calm);
        expect(scheduler.cancels, 1);
        final SharedPreferences prefs = await SharedPreferences.getInstance();
        expect(prefs.getStringList(HeavyDayNudge.promptsKey), isEmpty);
      });
    });

    test('one delivered tonight is not repeated tomorrow morning', () async {
      await run((HeavyDayNudge n) async {
        await n.evaluate(heavy);
        now = DateTime(2026, 11, 16, 7);
        await n.evaluate((today: false, yesterday: true));
        expect(scheduler.scheduled, hasLength(1));
        expect(scheduler.cancels, 0);
      });
    });

    test('seen after the time: one at 9 the next morning, kept', () async {
      now = DateTime(2026, 11, 15, 22);
      await run((HeavyDayNudge n) async {
        await n.evaluate(heavy);
        expect(scheduler.scheduled, <HeavyPrompt>[
          HeavyPrompt(_today, DateTime(2026, 11, 16, 9)),
        ]);
        now = DateTime(2026, 11, 16, 7);
        await n.evaluate((today: false, yesterday: true));
        expect(scheduler.scheduled, hasLength(1));
        expect(scheduler.cancels, 0);
      });
    });

    test('a resume on a later day ignores the earlier verdict', () async {
      now = DateTime(2026, 11, 15, 22);
      await run((HeavyDayNudge n) async {
        await n.evaluate(heavy);
        expect(scheduler.scheduled, hasLength(1));
        now = DateTime(2026, 11, 16, 7, 30);
        final TestWidgetsFlutterBinding binding =
            TestWidgetsFlutterBinding.instance;
        binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await n.setTime(const TimeOfDay(hour: 20, minute: 0));
        expect(scheduler.scheduled, hasLength(1));
        expect(scheduler.cancels, 0);
      });
    });

    test('a new time reschedules it; off cancels it', () async {
      await run((HeavyDayNudge n) async {
        await n.evaluate(heavy);
        await n.setTime(const TimeOfDay(hour: 20, minute: 30));
        expect(
          scheduler.scheduled.last,
          HeavyPrompt(_today, DateTime(2026, 11, 15, 20, 30)),
        );
        await n.turnOff();
        expect(scheduler.cancels, 1);
        await n.evaluate(heavy);
        expect(scheduler.scheduled, hasLength(2));
      });
    });

    test('sign-out cancels the pending one', () async {
      await run((HeavyDayNudge n) async {
        await n.evaluate(heavy);
        await n.forget();
        expect(scheduler.cancels, 1);
        final SharedPreferences prefs = await SharedPreferences.getInstance();
        expect(prefs.getStringList(HeavyDayNudge.promptsKey), isEmpty);
      });
    });

    test('off by default: nothing is scheduled', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final ProviderContainer fresh = ProviderContainer(
        overrides: [nudgeSchedulerProvider.overrideWithValue(scheduler)],
      );
      addTearDown(fresh.dispose);
      await withClock(
        Clock(() => now),
        () => fresh.read(heavyDayNudgeProvider.notifier).evaluate(heavy),
      );
      expect(scheduler.scheduled, isEmpty);
      expect(fresh.read(heavyDayVerdictProvider), isNull);
    });
  });
}
