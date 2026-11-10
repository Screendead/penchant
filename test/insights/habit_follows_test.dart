import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/insights/daily_series.dart';
import 'package:tracker/insights/habit_follows.dart';

import 'habit_follows_synthetic.dart';

HabitFollows _of(List<HabitFollows> pairs, String lead, String follower) =>
    pairs.singleWhere(
      (HabitFollows f) => f.leadId == lead && f.followerId == follower,
    );

HabitFollows _pair(
  String lead,
  String follower, {
  double share = 0.6,
  double chance = 0.2,
  double? pValue = 0.001,
  int followedDays = 30,
  FollowsVerdict? verdict,
}) => HabitFollows(
  leadId: lead,
  followerId: follower,
  days: 60,
  followedDays: followedDays,
  uses: 84,
  share: share,
  chance: chance,
  pValue: pValue,
  verdict: verdict,
);

void main() {
  final DateTime through = addDays(followsStart, 119);

  test('a habit logged minutes after half the uses of another is found, and '
      'only that way round', () {
    final List<HabitFollows> judged = judgeHabitFollows(
      habitFollows(
        uses: coffeeThenCigarettes(3, follow: 0.5),
        through: through,
      ),
    );

    expect(judged, hasLength(2));
    final HabitFollows after = _of(judged, 'coffee', 'cigarettes');
    expect(after.verdict, FollowsVerdict.found);
    expect(after.days, 120);
    expect(after.uses, inInclusiveRange(200, 240));
    expect(after.share, closeTo(0.55, 0.1));
    expect(after.chance, closeTo(0.13, 0.07));
    expect(after.pValue, lessThan(1e-6));
    expect(
      _of(judged, 'cigarettes', 'coffee').verdict,
      isNot(FollowsVerdict.found),
    );
  });

  test('habits at times of their own are not found', () {
    for (final int seed in <int>[1, 2, 3]) {
      final List<HabitFollows> judged = judgeHabitFollows(
        habitFollows(uses: coffeeThenCigarettes(seed), through: through),
      );
      expect(
        judged.map((HabitFollows f) => f.verdict),
        everyElement(isNot(FollowsVerdict.found)),
        reason: 'seed $seed',
      );
    }
  });

  test('under 21 days with both is too few, with no p-value', () {
    final HabitFollows pair = _of(
      judgeHabitFollows(
        habitFollows(
          uses: coffeeThenCigarettes(3, days: 20, follow: 0.9),
          through: through,
        ),
      ),
      'coffee',
      'cigarettes',
    );

    expect(pair.days, 20);
    expect(pair.pValue, isNull);
    expect(pair.verdict, FollowsVerdict.tooFewDays);
  });

  test('a skipped habit is in no pair, leading or following', () {
    final List<HabitFollows> pairs = habitFollows(
      uses: <HabitUse>[
        ...coffeeThenCigarettes(3, days: 30),
        for (int d = 0; d < 30; d++)
          useAt('tea', addDays(followsStart, d), 15 * 60),
      ],
      through: through,
      skip: const <String>{'cigarettes'},
    );

    expect(
      pairs.map((HabitFollows f) => (f.leadId, f.followerId)),
      unorderedEquals(<(String, String)>[('coffee', 'tea'), ('tea', 'coffee')]),
    );
  });

  test('days after the last whole day are left out', () {
    final List<HabitUse> uses = coffeeThenCigarettes(3, follow: 0.5);

    expect(
      _of(
        habitFollows(uses: uses, through: addDays(followsStart, 99)),
        'coffee',
        'cigarettes',
      ).days,
      100,
    );
  });

  test('a use counts on the evening it ends, and a run of uses inside one '
      'window counts once', () {
    final List<HabitUse> uses = <HabitUse>[
      for (int d = 0; d < 30; d++) ...<HabitUse>[
        // 00:30 and 00:35 the next calendar day.
        useAt('wine', addDays(followsStart, d), 24 * 60 + 30),
        useAt('wine', addDays(followsStart, d), 24 * 60 + 35),
        useAt('crisps', addDays(followsStart, d), 24 * 60 + 40),
      ],
    ];

    final HabitFollows pair = _of(
      habitFollows(uses: uses, through: addDays(followsStart, 29)),
      'wine',
      'crisps',
    );
    expect(pair.days, 30);
    expect(pair.uses, 30);
    expect(pair.share, 1);
  });

  test('a zero-quantity entry is not a use', () {
    final List<HabitFollows> pairs = habitFollows(
      uses: <HabitUse>[
        ...coffeeThenCigarettes(3, days: 30),
        HabitUse(habitId: 'tea', at: followsStart, amount: 0),
      ],
      through: through,
    );

    expect(pairs, hasLength(2));
  });

  group('judgeHabitFollows', () {
    test('a pair alone passes at p = 0.04; among many comparisons it could '
        'be chance', () {
      final HabitFollows pair = _pair('coffee', 'tea', pValue: 0.04);

      expect(
        judgeHabitFollows(<HabitFollows>[pair]).single.verdict,
        FollowsVerdict.found,
      );
      expect(
        judgeHabitFollows(
          <HabitFollows>[pair],
          alongside: List<double>.filled(20, 0.9),
        ).single.verdict,
        FollowsVerdict.chance,
      );
    });

    test('the day and size gates hide a pair that passed', () {
      final List<HabitFollows> judged = judgeHabitFollows(<HabitFollows>[
        _pair('a', 'b', followedDays: 6),
        _pair('a', 'c', share: 0.19, chance: 0.1),
        _pair('a', 'd', share: 0.25, chance: 0.1),
        _pair('a', 'e', pValue: null),
      ]);

      expect(judged.map((HabitFollows f) => f.verdict), <FollowsVerdict>[
        FollowsVerdict.tooFewDays,
        FollowsVerdict.tooSmall,
        FollowsVerdict.found,
        FollowsVerdict.tooFewDays,
      ]);
    });
  });

  group('followsCards', () {
    test('one card per following habit, strongest first, and of two habits '
        'that each follow the other only the stronger way round', () {
      const FollowsVerdict found = FollowsVerdict.found;
      final List<FollowsCard> cards = followsCards(<HabitFollows>[
        _pair('coffee', 'cigarettes', verdict: found),
        _pair('cigarettes', 'coffee', pValue: 0.01, verdict: found),
        _pair('tea', 'cigarettes', share: 0.4, verdict: found),
        _pair('tea', 'biscuits', share: 0.9, verdict: found),
        _pair('coffee', 'biscuits', verdict: FollowsVerdict.chance),
      ]);

      expect(cards.map((FollowsCard c) => c.habitId), <String>[
        'biscuits',
        'cigarettes',
      ]);
      expect(cards.first.others, isEmpty);
      expect(cards.last.headline.leadId, 'coffee');
      expect(cards.last.others.single.leadId, 'tea');
    });

    test('the copy says how often, against the usual timing, and from what', () {
      final HabitFollows pair = _pair('coffee', 'cigarettes', share: 0.617);

      expect(
        followsSentence(pair, 'Coffee', 'Cigarettes'),
        'After Coffee, you log Cigarettes within 15 minutes 62% of the time. '
        'Your usual timing of each would give 20%.',
      );
      expect(
        followsBasis(pair, 'Coffee'),
        'From 84 uses of Coffee on 60 days with both',
      );
      expect(
        followsLine(pair, 'Coffee'),
        'After Coffee: 62% of the time, against 20% by your usual timing',
      );
    });
  });
}
