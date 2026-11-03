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

  String nameFor(int count) => count == 1 ? singular : plural;
  String label(int count) => '$count ${nameFor(count)}';

  @override
  String toString() {
    return super.toString().split('.').last;
  }

  static Unit? tryParse(String? unit) {
    for (final Unit value in Unit.values) {
      if (value.name == unit) {
        return value;
      }
    }
    return null;
  }

  static Unit fromString(String unit) {
    return Unit.values.firstWhere(
      (e) => e.toString().split('.').last == unit,
    );
  }
}
