import 'package:flutter/foundation.dart';
import 'package:tracker/data/limits.dart';
import 'package:tracker/data/usage_series.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/formats.dart';

// What a habit's Units view counts, chosen by the person. Stored by name, as
// `strengthUnit`. The alcohol definitions follow the NHS: "One unit equals
// 10ml or 8g of pure alcohol", and strength (ABV) × volume (ml) ÷ 1,000 =
// units (nhs.uk/live-well/alcohol-advice/calculating-alcohol-units).
enum StrengthUnit {
  ukUnit('UK units'),
  grams('Grams of alcohol'),
  standardDrink('Standard drinks'),
  mg('Caffeine (mg)');

  const StrengthUnit(this.label);

  final String label;

  bool get alcohol => this != mg;

  static StrengthUnit? fromString(Object? value) => StrengthUnit.values
      .where((StrengthUnit u) => u.name == value)
      .firstOrNull;
}

// The NHS's grams in one UK unit.
const double gramsPerUkUnit = 8;

// How strong one serving of a habit is: for alcohol a serving size in ml and
// usually a strength (ABV %), counted in the unit the person chose; for
// caffeine usually an amount in mg. An entry may carry its own strength,
// which wins. Sealed content only, like the price and the line.
@immutable
class HabitStrength {
  const HabitStrength.alcohol({
    required this.unit,
    required double this.servingMl,
    this.abv,
    this.drinkGrams,
  }) : caffeineMg = null;

  const HabitStrength.caffeine({this.caffeineMg})
    : unit = StrengthUnit.mg,
      servingMl = null,
      abv = null,
      drinkGrams = null;

  final StrengthUnit unit;
  final double? servingMl;
  // The usual strength, in percent alcohol by volume.
  final double? abv;
  // A standard drink's grams of pure alcohol, as the person set it.
  final double? drinkGrams;
  final double? caffeineMg;

  // A missing, mistyped or out-of-range value reads as absent; an alcohol
  // definition without its serving size, or a standard drink without its
  // size, reads as no strength at all.
  static HabitStrength? read(Map<String, Object?> content) {
    final StrengthUnit? unit = StrengthUnit.fromString(content['strengthUnit']);
    if (unit == null) {
      return null;
    }
    if (!unit.alcohol) {
      return HabitStrength.caffeine(
        caffeineMg: readCaffeineMg(content['caffeineMg']),
      );
    }
    final double? serving = readServingMl(content['servingMl']);
    final double? grams = readDrinkGrams(content['drinkGrams']);
    if (serving == null ||
        (unit == StrengthUnit.standardDrink && grams == null)) {
      return null;
    }
    return HabitStrength.alcohol(
      unit: unit,
      servingMl: serving,
      abv: readAbv(content['abv']),
      drinkGrams: unit == StrengthUnit.standardDrink ? grams : null,
    );
  }

  Map<String, Object> get content => <String, Object>{
    'strengthUnit': unit.name,
    'servingMl': ?servingMl,
    'abv': ?abv,
    'drinkGrams': ?drinkGrams,
    'caffeineMg': ?caffeineMg,
  };

  // The habit's unit in one serving at the entry's own strength, else the
  // habit's; null when neither is known.
  double? perServing({double? abv, double? caffeineMg}) {
    if (!unit.alcohol) {
      return caffeineMg ?? this.caffeineMg;
    }
    final double? strength = abv ?? this.abv;
    if (strength == null) {
      return null;
    }
    final double ukUnits = strength * servingMl! / 1000;
    return switch (unit) {
      StrengthUnit.grams => ukUnits * gramsPerUkUnit,
      StrengthUnit.standardDrink => ukUnits * gramsPerUkUnit / drinkGrams!,
      _ => ukUnits,
    };
  }

  // One entry in the habit's unit, or null when no strength applies to it.
  double? of(ViceActivity activity) {
    final double? each = perServing(
      abv: activity.abv,
      caffeineMg: activity.caffeineMg,
    );
    return each == null ? null : each * activity.measure;
  }

  // "18.4 units", "147 g", "2.1 standard drinks", "380 mg". Grams and mg are
  // whole; units and drinks to a tenth.
  String label(double value) => '${number(value)} ${word(value)}';

  String number(double value) => switch (unit) {
    StrengthUnit.grams || StrengthUnit.mg => formatCount(value.round()),
    _ => formatAverage(value),
  };

  String word(double value) => switch (unit) {
    StrengthUnit.ukUnit => value == 1 ? 'unit' : 'units',
    StrengthUnit.standardDrink =>
      value == 1 ? 'standard drink' : 'standard drinks',
    StrengthUnit.grams => 'g',
    StrengthUnit.mg => 'mg',
  };

  // The axis prints whole values.
  String axis(int value) => switch (unit) {
    StrengthUnit.grams => '$value g',
    StrengthUnit.mg => '$value mg',
    _ => formatCount(value),
  };

  // What the view is called in a sentence: "units", "grams of alcohol".
  String get noun => switch (unit) {
    StrengthUnit.ukUnit => 'units',
    StrengthUnit.grams => 'grams of alcohol',
    StrengthUnit.standardDrink => 'standard drinks',
    StrengthUnit.mg => 'caffeine',
  };

  // The habit's strength in words: "568 ml at 4.5%", "95 mg".
  String get describe => unit.alcohol
      ? '${formatCount(servingMl!)} ml'
            '${abv == null ? '' : ' at ${formatCount(abv!)}%'}'
      : caffeineMg == null
      ? 'mg per serving'
      : '${formatCount(caffeineMg!)} mg';

  @override
  bool operator ==(Object other) =>
      other is HabitStrength &&
      other.unit == unit &&
      other.servingMl == servingMl &&
      other.abv == abv &&
      other.drinkGrams == drinkGrams &&
      other.caffeineMg == caffeineMg;

  @override
  int get hashCode => Object.hash(unit, servingMl, abv, drinkGrams, caffeineMg);
}

double? _within(Object? value, double most) =>
    value is num && value.isFinite && value > 0 && value <= most
    ? value.toDouble()
    : null;

double? readServingMl(Object? value) => _within(value, maxServingMl);
double? readAbv(Object? value) => _within(value, maxAbv);
double? readDrinkGrams(Object? value) => _within(value, maxDrinkGrams);
double? readCaffeineMg(Object? value) => _within(value, maxCaffeineMg);

// A typed strength kept to two decimal places, which is finer than any label
// and keeps an entry's envelope a known length.
double roundStrength(num value) => (value * 100).round() / 100;

// Each bucket's total in the habit's unit, and how many entries in the range
// had no strength to count.
typedef UnitTotals = ({List<double> totals, int without});

UnitTotals bucketUnits(
  UsageRange range,
  Iterable<ViceActivity> activities,
  HabitStrength strength,
) {
  final List<double> totals = List<double>.filled(range.bucketCount, 0);
  int without = 0;
  for (final ViceActivity activity in activities) {
    final int? bucket = range.bucketOf(activity.createdAt.toDate());
    if (bucket == null) {
      continue;
    }
    final double? units = strength.of(activity);
    if (units == null) {
      without++;
    } else {
      totals[bucket] += units;
    }
  }
  return (totals: totals, without: without);
}
