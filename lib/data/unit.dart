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

// A habit's words for its unit: its own label (mg, cups), with its own form
// for one (cup) if given, else used as typed whatever the count; else the
// preset's singular and plural.
class UnitWords {
  const UnitWords(this.unit, [this.custom, this.customOne]);

  final Unit unit;
  final String? custom;
  // Ignored without [custom].
  final String? customOne;

  String get singular =>
      custom == null ? unit.singular : (customOne ?? custom!);
  String get plural => custom ?? unit.plural;

  String nameFor(num count) => custom == null
      ? unit.nameFor(count)
      : pluralWord(count, one: singular, other: custom!);
  String label(num count) => '${formatCount(count)} ${nameFor(count)}';
}
