import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/insights/after_event.dart';
import 'package:tracker/insights/calendar_source.dart';
import 'package:tracker/insights/daily_series.dart' show HabitUse;
import 'package:tracker/insights/health_source.dart';
import 'package:tracker/insights/insights_report.dart';
import 'package:tracker/insights/insights_timing.dart';
import 'package:tracker/providers/calendar_provider.dart';
import 'package:tracker/providers/insights_provider.dart';
import 'package:tracker/providers/insights_session.dart';

import 'fakes.dart';
import 'insights/hours_after_synthetic.dart';
import 'insights_harness.dart';

class _Uid extends Notifier<String?> {
  @override
  String? build() => 'alice';

  void become(String? uid) => state = uid;
}

final _uidProvider = NotifierProvider<_Uid, String?>(_Uid.new);

class _ChangingHealth extends FakeHealthSource {
  _ChangingHealth(this.current, {super.sampleData});

  HealthRead current;

  @override
  HealthRead? get read => current;
}

class _Calendar implements CalendarSource {
  List<CalendarEvent> held = const <CalendarEvent>[];

  @override
  Future<CalendarAccess> access() async => CalendarAccess.full;

  @override
  Future<bool> requestAccess() async => true;

  @override
  Future<List<CalendarEvent>> events(DateTime start, DateTime end) async => [
    for (final CalendarEvent e in held)
      if (!e.start.isBefore(start) && e.start.isBefore(end)) e,
  ];
}

class _Harness {
  _Harness({
    List<ViceActivity>? journal,
    HealthRead? health,
    Map<HealthSampleMetric, List<HealthSample>> samples =
        const <HealthSampleMetric, List<HealthSample>>{},
    this.calendar,
  }) : journal = journal ?? insightsJournal().activities,
       health = _ChangingHealth(
         health ?? HealthValues(insightsJournal().health),
         sampleData: samples,
       ) {
    container = ProviderContainer(
      overrides: <Override>[
        ...insightsOverrides(
          health: this.health,
          readActivities: () => this.journal,
          runner: (InsightsInput input) async {
            runs++;
            return computeInsights(input);
          },
          uid: (Ref ref) => ref.watch(_uidProvider),
        ),
        healthConnectedProvider.overrideWith((ref) async => true),
        calendarSourceProvider.overrideWithValue(calendar),
      ],
    );
    addTearDown(container.dispose);
  }

  late final ProviderContainer container;
  final _ChangingHealth health;
  final _Calendar? calendar;
  List<ViceActivity> journal;
  int runs = 0;

  ProviderSubscription<AsyncValue<InsightsView>>? _sub;

  /// Opens the page's provider; the first value it gives.
  AsyncValue<InsightsView> open() {
    _sub = container.listen(insightsProvider, (_, _) {});
    return container.read(insightsProvider);
  }

  Future<InsightsView> settled() async {
    InsightsView? view;
    for (int i = 0; i < 400; i++) {
      view = container.read(insightsProvider).value;
      if (view != null &&
          view.result != null &&
          !view.updating &&
          !view.hoursPending) {
        return view;
      }
      await Future<void>.delayed(Duration.zero);
    }
    fail('Insights never settled');
  }

  Future<void> close() async {
    _sub?.close();
    _sub = null;
    for (int i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }
}

InsightsReport _report(InsightsView view) =>
    (view.result! as InsightsComputed).report;

void main() {
  setUp(() => insightsTimingLog = (_) {});
  tearDown(() => insightsTimingLog = debugPrint);

  test(
    'a second open shows the last report at once and reruns nothing',
    () async {
      final _Harness h = _Harness();
      expect(h.open(), isA<AsyncLoading<InsightsView>>());
      final InsightsView first = await h.settled();
      final int runs = h.runs;
      final int changeChecks = h.health.changeChecks;
      await h.close();

      final AsyncValue<InsightsView> reopened = h.open();
      expect(reopened.value?.updating, isTrue);
      expect(identical(reopened.value!.result, first.result), isTrue);
      final InsightsView second = await h.settled();
      // Health and the journal were asked again, behind the shown report.
      expect(h.health.changeChecks, greaterThan(changeChecks));
      expect(h.runs, runs);
      expect(identical(second.result, first.result), isTrue);
    },
  );

  test('a new journal entry runs the engine again', () async {
    final _Harness h = _Harness();
    h.open();
    final InsightsView first = await h.settled();
    final int runs = h.runs;
    await h.close();

    h.journal = <ViceActivity>[
      ...h.journal,
      fakeActivity(
        'coffee',
        2,
        addDays(insightsToday, -1).add(const Duration(hours: 10)),
      ),
    ];
    h.open();
    final InsightsView second = await h.settled();
    expect(h.runs, greaterThan(runs));
    expect(identical(second.result, first.result), isFalse);
  });

  test('the same journal read again reuses the report', () async {
    final _Harness h = _Harness();
    h.open();
    await h.settled();
    final int runs = h.runs;
    await h.close();

    // A fresh read: new objects, the same uses.
    h.journal = <ViceActivity>[
      for (final ViceActivity a in h.journal)
        fakeActivity(a.viceID, a.quantity, a.createdAt.toDate()),
    ];
    h.open();
    await h.settled();
    expect(h.runs, runs);
  });

  test('a change in Health runs the engine again', () async {
    final _Harness h = _Harness();
    h.open();
    await h.settled();
    final int runs = h.runs;
    await h.close();

    final List<DailyOutcome> values = <DailyOutcome>[
      ...insightsJournal().health,
    ];
    final DailyOutcome last = values.removeLast();
    h.health.current = HealthValues(<DailyOutcome>[
      ...values,
      DailyOutcome(last.date, last.metricId, last.value + 1),
    ]);
    h.open();
    await h.settled();
    expect(h.runs, greaterThan(runs));
  });

  test('a change in the calendar runs the engine again', () async {
    final _Calendar calendar = _Calendar();
    final _Harness h = _Harness(calendar: calendar);
    h.open();
    await h.settled();
    final int runs = h.runs;
    await h.close();

    h.open();
    await h.settled();
    expect(h.runs, runs);
    await h.close();

    final DateTime start = addDays(
      insightsToday,
      -3,
    ).add(const Duration(hours: 8));
    calendar.held = <CalendarEvent>[
      CalendarEvent(start, start.add(const Duration(hours: 1))),
    ];
    h.open();
    await h.settled();
    expect(h.runs, greaterThan(runs));
  });

  test('the engine inputs differ on what the engine reads', () {
    final List<ViceActivity> journal = insightsJournal().activities;
    EngineInputs inputs({
      List<ViceActivity>? activities,
      DateTime? today,
      String archived = '',
    }) => EngineInputs(
      activities: activities ?? journal,
      health: const <DailyOutcome>[],
      samples: const <String, List<HealthSample>>{},
      today: today ?? insightsToday,
      archived: archived,
      events: const <CalendarEvent>[],
    );
    expect(inputs(), inputs());
    expect(inputs(archived: 'coffee'), isNot(inputs()));
    expect(inputs(today: addDays(insightsToday, 1)), isNot(inputs()));
    final ViceActivity a = journal.first;
    expect(
      inputs(
        activities: <ViceActivity>[
          fakeActivity(a.viceID, a.quantity + 1, a.createdAt.toDate()),
          ...journal.skip(1),
        ],
      ),
      isNot(inputs()),
    );
  });

  test('another user never sees the last report', () async {
    final _Harness h = _Harness();
    h.open();
    await h.settled();
    final InsightsSession? alice = h.container.read(insightsSessionProvider);
    expect(alice?.lastView, isNotNull);
    await h.close();

    h.container.read(_uidProvider.notifier).become('bob');
    final InsightsSession? bob = h.container.read(insightsSessionProvider);
    expect(bob, isNot(same(alice)));
    expect(bob!.lastView, isNull);
    expect(h.open(), isA<AsyncLoading<InsightsView>>());
    await h.close();

    h.container.read(_uidProvider.notifier).become(null);
    expect(h.container.read(insightsSessionProvider), isNull);
    expect(h.open(), isA<AsyncLoading<InsightsView>>());
  });

  test('hours-after samples of settled days are read once a session', () async {
    final Synthetic s = insightsHoursYear();
    final _Harness h = _Harness(
      journal: <ViceActivity>[
        for (final HabitUse u in s.uses) fakeActivity(u.habitId, 1, u.at),
      ],
      health: HealthValues(<DailyOutcome>[
        for (int i = 1; i < 60; i++)
          DailyOutcome(
            addDays(insightsToday, -i),
            HealthMetric.sleepDeep.id,
            70.0 + i % 5,
          ),
      ]),
      samples: <HealthSampleMetric, List<HealthSample>>{
        for (final HealthSampleMetric m in HealthSampleMetric.values)
          if (s.samples[m.id] case final List<HealthSample> list) m: list,
      },
    );
    h.open();
    final InsightsView first = await h.settled();
    expect(_report(first).hoursAfterChecks, greaterThan(0));
    final int firstCalls = h.health.sampleCalls;
    final int runs = h.runs;
    await h.close();

    h.open();
    final InsightsView second = await h.settled();
    final int again = h.health.sampleCalls - firstCalls;
    expect(again, lessThan(firstCalls ~/ 10));
    expect(h.runs, runs);
    expect(_report(second).hoursAfterChecks, _report(first).hoursAfterChecks);
  });
}
