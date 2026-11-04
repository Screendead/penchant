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

  String nameFor(int count) => pluralWord(count, one: singular, other: plural);
  String label(int count) => '${formatCount(count)} ${nameFor(count)}';

  static const Unit fallback = Unit.item;

  static Unit fromString(Object? unit) {
    return Unit.values.firstWhere(
      (e) => e.name == unit,
      orElse: () => fallback,
    );
  }
}
