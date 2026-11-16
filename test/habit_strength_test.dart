import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/activity_content.dart';
import 'package:tracker/data/habit_strength.dart';
import 'package:tracker/data/limits.dart';
import 'package:tracker/data/usage_series.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/formats.dart';
import 'package:tracker/trends/trends_chart.dart';
import 'package:tracker/trends/trends_sheet.dart';

import 'fakes.dart';

const HabitStrength pint = HabitStrength.alcohol(
  unit: StrengthUnit.ukUnit,
  servingMl: 568,
  abv: 4.5,
);

ViceActivity entry(
  DateTime at, {
  int quantity = 1,
  double? amount,
  double? abv,
  double? caffeineMg,
}) => ViceActivity(
  id: '${at.millisecondsSinceEpoch}-$quantity',
  viceID: 'beer',
  quantity: quantity,
  amount: amount,
  ownerID: 'owner',
  createdAt: Timestamp.fromDate(at),
  abv: abv,
  caffeineMg: caffeineMg,
);

void main() {
  final DateTime noon = DateTime(2026, 11, 16, 12);

  group('one serving', () {
    test('UK units are ABV × ml ÷ 1,000 (NHS)', () {
      // 4.5 × 568 ÷ 1000
      expect(pint.perServing(), closeTo(2.556, 1e-9));
      expect(pint.label(pint.perServing()!), '2.6 units');
      expect(pint.label(1), '1.0 unit');
    });

    test('grams are 8 a UK unit (NHS)', () {
      const HabitStrength grams = HabitStrength.alcohol(
        unit: StrengthUnit.grams,
        servingMl: 175,
        abv: 12,
      );
      // 12 × 175 ÷ 1000 = 2.1 units, × 8
      expect(grams.perServing(), closeTo(16.8, 1e-9));
      expect(grams.label(16.8), '17 g');
    });

    test('standard drinks are of the size the person set', () {
      const HabitStrength drinks = HabitStrength.alcohol(
        unit: StrengthUnit.standardDrink,
        servingMl: 568,
        abv: 5,
        drinkGrams: 14,
      );
      // 5 × 568 ÷ 1000 = 2.84 units = 22.72 g, ÷ 14
      expect(drinks.perServing(), closeTo(22.72 / 14, 1e-9));
      expect(drinks.label(1.6), '1.6 standard drinks');
    });

    test('caffeine is mg a serving', () {
      const HabitStrength coffee = HabitStrength.caffeine(caffeineMg: 95);
      expect(coffee.perServing(), 95);
      expect(coffee.perServing(caffeineMg: 140), 140);
      expect(coffee.label(380), '380 mg');
    });

    test("an entry's own strength wins over the habit's", () {
      expect(pint.perServing(abv: 6.5), closeTo(3.692, 1e-9));
      // A caffeine override means nothing to an alcohol habit.
      expect(pint.perServing(caffeineMg: 200), closeTo(2.556, 1e-9));
    });

    test('no usual strength and none on the entry counts nothing', () {
      const HabitStrength open = HabitStrength.alcohol(
        unit: StrengthUnit.ukUnit,
        servingMl: 568,
      );
      expect(open.perServing(), isNull);
      expect(open.perServing(abv: 4), closeTo(2.272, 1e-9));
      expect(const HabitStrength.caffeine().perServing(), isNull);
    });
  });

  test('an entry counts its measure, decimals included', () {
    expect(
      pint.of(entry(noon, quantity: 2, amount: 1.5)),
      closeTo(3.834, 1e-9),
    );
    expect(pint.of(entry(noon, quantity: 2)), closeTo(5.112, 1e-9));
    // An older build edited the quantity alone: the quantity wins.
    expect(
      pint.of(entry(noon, quantity: 3, amount: 1.5)),
      closeTo(7.668, 1e-9),
    );
  });

  test('bucketUnits sums each day and counts entries with no strength', () {
    final UsageRange range = usageRange(noon, 7, 1);
    const HabitStrength open = HabitStrength.alcohol(
      unit: StrengthUnit.ukUnit,
      servingMl: 500,
    );
    final UnitTotals units = bucketUnits(range, <ViceActivity>[
      entry(noon, abv: 4),
      entry(noon.subtract(const Duration(hours: 1)), abv: 6, amount: 0.5),
      entry(noon.subtract(const Duration(days: 1))),
      // Outside the range: neither counted nor counted as missing.
      entry(noon.subtract(const Duration(days: 30))),
    ], open);
    expect(units.totals.length, 7);
    // 4 × 500 ÷ 1000 + 6 × 250 ÷ 1000
    expect(units.totals.last, closeTo(3.5, 1e-9));
    expect(units.totals[5], 0);
    expect(units.without, 1);
  });

  group('reading stored content', () {
    test('reads each definition back from what it writes', () {
      for (final HabitStrength strength in <HabitStrength>[
        pint,
        const HabitStrength.alcohol(
          unit: StrengthUnit.standardDrink,
          servingMl: 330,
          drinkGrams: 10,
        ),
        const HabitStrength.caffeine(caffeineMg: 80),
        const HabitStrength.caffeine(),
      ]) {
        expect(HabitStrength.read(strength.content), strength);
      }
    });

    test('a missing, mistyped or out-of-range value reads as absent', () {
      expect(HabitStrength.read(<String, Object?>{}), isNull);
      expect(
        HabitStrength.read(<String, Object?>{'strengthUnit': 'usUnit'}),
        isNull,
      );
      // Alcohol without its serving, or a standard drink without its size.
      expect(
        HabitStrength.read(<String, Object?>{
          'strengthUnit': 'ukUnit',
          'abv': 4,
        }),
        isNull,
      );
      expect(
        HabitStrength.read(<String, Object?>{
          'strengthUnit': 'standardDrink',
          'servingMl': 568,
        }),
        isNull,
      );
      final HabitStrength? odd = HabitStrength.read(<String, Object?>{
        'strengthUnit': 'ukUnit',
        'servingMl': 568,
        'abv': maxAbv + 1,
      });
      expect(odd?.abv, isNull);
      expect(
        HabitStrength.read(<String, Object?>{
          'strengthUnit': 'mg',
          'caffeineMg': '95',
        })?.caffeineMg,
        isNull,
      );
    });
  });

  group("an entry's own strength", () {
    test('is sealed content that survives answers and follow-ups', () {
      const ActivityContent own = ActivityContent(abv: 6.5);
      expect(own.toMap()['abv'], 6.5);
      expect(ActivityContent.read(own.toMap()).abv, 6.5);
      expect(
        own.withAnswers(triggers: <String>['social'], urge: 2, note: 'x').abv,
        6.5,
      );
      expect(own.withFollowUp(null).abv, 6.5);
      expect(own.triggersAlone, isFalse);
      expect(own.answersDiffer(const ActivityContent()), isTrue);
      expect(
        const ActivityContent(
          caffeineMg: 120,
        ).withStrength(abv: null, caffeineMg: null).caffeineMg,
        isNull,
      );
      expect(ActivityContent.read(<String, Object?>{'abv': 101}).abv, isNull);
    });

    test(
      'is kept to two places, within the envelope answersTooLong allows',
      () {
        expect(roundStrength(6.456), 6.46);
        expect(
          answersTooLong(triggers: const <String>[], urge: 5, note: 'x' * 500),
          isNull,
        );
      },
    );

    test('is bounded in the form', () {
      expect(strengthError('', maxAbv), isNull);
      expect(strengthError('', maxServingMl, optional: false), isNotNull);
      expect(strengthError('0', maxAbv), isNotNull);
      expect(strengthError('101', maxAbv), isNotNull);
      expect(strengthError(formatAmount(4.5), maxAbv), isNull);
    });
  });

  test('the Units chart says what it counts', () {
    final UsageRange range = usageRange(noon, 7, 1);
    final String summary = TrendsChart.summary(
      vice: fakeVice('beer', name: 'Beer'),
      range: range,
      totals: <double>[0, 0, 0, 0, 0, 2.6, 5.1],
      smoothingWindow: 1,
      scale: strengthScale(pint),
    );
    expect(summary, startsWith('Daily units from Beer'));
    expect(summary, contains('7.7 units in all'));
    expect(TrendsSheet.noStrength(2), contains('2 entries had no strength'));
  });
}
