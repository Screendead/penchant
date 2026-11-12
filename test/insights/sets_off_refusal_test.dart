import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/insights/after_event.dart';
import 'package:tracker/insights/before_use.dart';
import 'package:tracker/insights/habit_follows.dart';
import 'package:tracker/insights/insights_report.dart';
import 'package:tracker/insights/sets_off_refusal.dart';
import 'package:tracker/insights/trigger_amounts.dart';
import 'package:tracker/insights/what_follows.dart';

BeforeUse _before(
  String habit,
  RefusalReason? refusal, {
  BeforeUseKind kind = BeforeUseKind.whether,
  int usableDays = 64,
  int exposedDays = 22,
}) => BeforeUse(
  habitId: habit,
  metricId: 'sleepAsleep',
  kind: kind,
  usableDays: usableDays,
  exposedDays: exposedDays,
  refusal: refusal,
);

HabitFollows _pair(
  String lead,
  String follower,
  FollowsVerdict verdict, {
  int days = 61,
  int followedDays = 40,
  double share = 0.4,
}) => HabitFollows(
  leadId: lead,
  followerId: follower,
  days: days,
  followedDays: followedDays,
  uses: 84,
  share: share,
  chance: 0.18,
  pValue: 0.2,
  verdict: verdict,
);

AfterEvent _calendar(String habit, RefusalReason? refusal, {int days = 30}) =>
    AfterEvent(
      habitId: habit,
      eventDays: days,
      controlDays: 30,
      eventRate: 0.2,
      controlRate: 0.2,
      refusal: refusal,
    );

List<SetsOffRefusal> _pick(
  InsightsReport report, {
  List<String> habits = const <String>['coffee', 'tea'],
  Set<String> shown = const <String>{},
  Set<String>? logged,
}) => setsOffRefusals(
  habitIds: habits,
  report: report,
  shown: shown,
  logged: logged ?? habits.toSet(),
);

InsightsReport _report({
  List<BeforeUse> beforeUse = const <BeforeUse>[],
  List<HabitFollows> follows = const <HabitFollows>[],
  List<AfterEvent> afterEvent = const <AfterEvent>[],
  List<HabitTriggers> triggers = const <HabitTriggers>[],
}) => InsightsReport(
  triggers: triggers,
  findings: const <HabitFinding>[],
  refused: const <HabitRefusal>[],
  beforeUse: beforeUse,
  follows: follows,
  afterEvent: afterEvent,
);

HabitTriggers _tagged(String habit, List<TriggerAmount> triggers) =>
    HabitTriggers(habitId: habit, entries: 40, tagged: 12, triggers: triggers);

TriggerAmount _trigger(
  String trigger,
  TriggerVerdict verdict, {
  int withDays = 9,
  int withoutDays = 8,
}) => TriggerAmount(
  trigger: trigger,
  entries: 10,
  withDays: withDays,
  withoutDays: withoutDays,
  withMean: 2,
  withoutMean: 2,
  pValue: verdict == TriggerVerdict.tooFewDays ? null : 0.3,
  verdict: verdict,
);

String _name(String id) => switch (id) {
  'coffee' => 'Coffee',
  'tea' => 'Tea',
  _ => id,
};

String _why(SetsOffRefusal r) => setsOffReason(r, _name);

void main() {
  test('one line per habit with no card, the most telling of its refused '
      'comparisons', () {
    final List<SetsOffRefusal> got = _pick(
      _report(
        beforeUse: <BeforeUse>[
          _before('coffee', RefusalReason.tooFewDays, usableDays: 12),
          _before('coffee', RefusalReason.withinNoise),
        ],
        afterEvent: <AfterEvent>[_calendar('coffee', RefusalReason.chance)],
      ),
      habits: <String>['coffee'],
    );

    expect(got, hasLength(1));
    expect(
      _why(got.single),
      'After calendar events: could be chance, one of many comparisons',
    );
  });

  test('on a tie, before a use comes first, then a pair, then the '
      'calendar', () {
    final List<SetsOffRefusal> got = _pick(
      _report(
        beforeUse: <BeforeUse>[_before('coffee', RefusalReason.withinNoise)],
        afterEvent: <AfterEvent>[
          _calendar('coffee', RefusalReason.withinNoise),
          _calendar('tea', RefusalReason.withinNoise),
        ],
        follows: <HabitFollows>[
          _pair('coffee', 'tea', FollowsVerdict.tooFewDays, days: 9),
        ],
      ),
    );

    expect(got.map(_why), <String>[
      'Before it: within the noise, no clear difference',
      'After calendar events: within the noise, no clear difference',
    ]);
  });

  test('a pair names the other habit, and its count is the gate that '
      'stopped it', () {
    expect(
      _pick(
        _report(
          follows: <HabitFollows>[
            _pair('coffee', 'tea', FollowsVerdict.tooFewDays, days: 9),
          ],
        ),
      ).map(_why),
      <String>[
        'With Tea: too few days with both yet: 9 of 21',
        'With Coffee: too few days with both yet: 9 of 21',
      ],
    );
    expect(
      _why(
        _pick(
          _report(
            follows: <HabitFollows>[
              _pair('coffee', 'tea', FollowsVerdict.chance, share: 0.1),
            ],
          ),
        ).first,
      ),
      'With Tea: no more often than your usual timing of each would give',
    );
  });

  test('before a use: a count only where that gate stopped it', () {
    String why(BeforeUse b) => _why(
      _pick(
        _report(beforeUse: <BeforeUse>[b]),
        habits: <String>['coffee'],
      ).single,
    );

    expect(
      why(_before('coffee', RefusalReason.tooFewDays, usableDays: 12)),
      'Before it: too few days yet: 12 of 21',
    );
    expect(
      why(
        _before(
          'coffee',
          RefusalReason.tooFewDays,
          usableDays: 30,
          exposedDays: 27,
        ),
      ),
      'Before it: used almost every day, too few days without it to compare',
    );
    expect(
      why(_before('coffee', RefusalReason.tooFewDays, exposedDays: 3)),
      'Before it: too few days with it yet: 3 of 7',
    );
    expect(
      why(
        _before('coffee', RefusalReason.tooFewDays, kind: BeforeUseKind.amount),
      ),
      'Before it: too few days yet to compare',
    );
  });

  test('a habit on a card, as either side of a pair, gets no line; nor does '
      'a found comparison count as a reason', () {
    final List<SetsOffRefusal> got = _pick(
      _report(
        beforeUse: <BeforeUse>[_before('tea', null)],
        follows: <HabitFollows>[_pair('coffee', 'tea', FollowsVerdict.found)],
      ),
      shown: <String>{'coffee'},
    );

    expect(got.single.habitId, 'tea');
    expect(
      _why(got.single),
      'Nothing to compare it with yet: no sleep or heart readings in Health, '
      'no calendar events, no other habit logged and no triggers tagged',
    );
  });

  test('only the habits asked about, so an archived one gets none', () {
    final List<SetsOffRefusal> got = _pick(
      _report(
        afterEvent: <AfterEvent>[
          _calendar('coffee', RefusalReason.withinNoise),
          _calendar('tea', RefusalReason.withinNoise),
        ],
        follows: <HabitFollows>[
          _pair('coffee', 'tea', FollowsVerdict.tooSmall),
        ],
      ),
      habits: <String>['coffee'],
    );

    expect(got.map(_why), <String>[
      'After calendar events: within the noise, no clear difference',
    ]);
  });

  test('a habit with no entries says so', () {
    expect(
      _why(_pick(_report(), habits: <String>['coffee'], logged: {}).single),
      'No entries yet in the time Insights reads',
    );
  });

  test('a trigger says how much is tagged where tagging stopped it', () {
    final List<SetsOffRefusal> got = _pick(
      _report(
        triggers: <HabitTriggers>[
          _tagged('coffee', <TriggerAmount>[
            _trigger('work', TriggerVerdict.tooFewDays, withDays: 3),
          ]),
          _tagged('tea', <TriggerAmount>[
            _trigger('social/friends', TriggerVerdict.tooSmall),
            _trigger('Bored', TriggerVerdict.chance),
          ]),
        ],
      ),
    );

    expect(got.map(_why), <String>[
      'Tagged Work: too few days with it yet: 3 of 7 (12 of 40 entries '
          'tagged)',
      'Tagged Social › With friends: too small to matter, under 20% more or less '
          'than on your other tagged entries',
    ]);
  });

  test('a calendar refusal comes before a trigger one of the same kind', () {
    final List<SetsOffRefusal> got = _pick(
      _report(
        afterEvent: <AfterEvent>[_calendar('coffee', RefusalReason.chance)],
        triggers: <HabitTriggers>[
          _tagged('coffee', <TriggerAmount>[
            _trigger('work', TriggerVerdict.chance),
          ]),
        ],
      ),
      habits: <String>['coffee'],
    );

    expect(got.single.calendar, isNotNull);
  });
}
