import 'package:tracker/formats.dart';

enum Unit {
  item('items'),
  time('times'),
  puff('puffs'),
  drink('drinks'),
  minute('minutes'),
  hour('hours');

  final String plural;

  const Unit(this.plural);

  String get singular => name;

  String nameFor(num count) => pluralWord(count, one: singular, other: plural);
  String label(num count) => '${formatCount(count)} ${nameFor(count)}';

  static const Unit fallback = Unit.item;

  static Unit fromString(Object? unit) {
    return Unit.values.firstWhere(
      (e) => e.name == unit,
      orElse: () => fallback,
    );
  }
}

// A habit's words for its unit: its own label, used as typed whatever the
// count (mg, cups), else the preset's singular and plural.
class UnitWords {
  const UnitWords(this.unit, [this.custom]);

  final Unit unit;
  final String? custom;

  String get singular => custom ?? unit.singular;
  String get plural => custom ?? unit.plural;

  String nameFor(num count) => custom ?? unit.nameFor(count);
  String label(num count) => '${formatCount(count)} ${nameFor(count)}';
}
