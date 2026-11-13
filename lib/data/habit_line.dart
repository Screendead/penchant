import 'package:flutter/foundation.dart';
import 'package:tracker/data/limits.dart';
import 'package:tracker/data/unit.dart';
import 'package:tracker/formats.dart';

// Stored by name, as `linePeriod`; firestore.rules lists the same names.
enum LinePeriod {
  day('a day'),
  week('a week');

  const LinePeriod(this.words);

  final String words;

  static LinePeriod? fromString(Object? value) =>
      LinePeriod.values.where((LinePeriod p) => p.name == value).firstOrNull;
}

// A habit's own line: an amount a day, or over the last 7 days. Only a mark
// to read the totals against; nothing changes colour or alerts past it.
@immutable
class HabitLine {
  const HabitLine(this.amount, this.period);

  // Sealed content, as `lineAmount` and `linePeriod`: a missing, mistyped or
  // out-of-range half reads as no line.
  static HabitLine? read(Object? amount, Object? period) {
    final LinePeriod? per = LinePeriod.fromString(period);
    if (per == null ||
        amount is! num ||
        !amount.isFinite ||
        amount <= 0 ||
        amount > maxLineAmount) {
      return null;
    }
    return HabitLine(amount.toDouble(), per);
  }

  final double amount;
  final LinePeriod period;

  // The days a total is read against it over: 1, or the 7 ending on the day.
  int get days => period == LinePeriod.day ? 1 : 7;

  // "3 a day"
  String get short => '${formatCount(amount)} ${period.words}';

  // "3 glasses a day"
  String words(UnitWords units) => '${units.label(amount)} ${period.words}';

  Map<String, Object> get content => <String, Object>{
    'lineAmount': amount,
    'linePeriod': period.name,
  };

  @override
  bool operator ==(Object other) =>
      other is HabitLine && other.amount == amount && other.period == period;

  @override
  int get hashCode => Object.hash(amount, period);
}
