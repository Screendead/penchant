enum Unit {
  time('times'),
  item('items'),
  puff('puffs'),
  drink('drinks'),
  minute('minutes'),
  hour('hours');

  final String plural;

  const Unit(this.plural);

  String get singular => name;

  String nameFor(int count) => count == 1 ? singular : plural;
  String label(int count) => '$count ${nameFor(count)}';

  @override
  String toString() {
    return super.toString().split('.').last;
  }

  static Unit fromString(String unit) {
    return Unit.values.firstWhere(
      (e) => e.toString().split('.').last == unit,
      orElse: () {
        // Log the unknown unit for debugging
        print('Unknown unit: "$unit", defaulting to "item"');
        return Unit.item;
      },
    );
  }
}
