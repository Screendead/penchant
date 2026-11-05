import 'package:tracker/data/vice.dart';

// How a habit is drawn: habits 1-5 are filled in data1-data5, 6-10 hollow
// rings and 11-15 dotted rings in the same five hues. The mock-up stops at 15;
// past it the three styles repeat.
enum HabitMarkStyle { filled, ring, dotted }

class HabitMark {
  const HabitMark(this.creationIndex) : assert(creationIndex >= 0);

  static const int colourCount = 5;

  // 0 for the oldest habit, archived habits included.
  final int creationIndex;

  // Which of data1-data5 (0 to 4).
  int get slot => creationIndex % colourCount;

  HabitMarkStyle get style =>
      HabitMarkStyle.values[(creationIndex ~/ colourCount) %
          HabitMarkStyle.values.length];

  @override
  bool operator ==(Object other) =>
      other is HabitMark && other.creationIndex == creationIndex;

  @override
  int get hashCode => creationIndex.hashCode;

  @override
  String toString() => 'HabitMark($creationIndex: slot $slot, ${style.name})';
}

// Every vice's mark, keyed by id. Pass the whole list, archived vices
// included, or later habits change colour when one is archived. Equal
// creation times (legacy documents without one all read as the epoch) are
// ordered by id, so a vice keeps its colour from one snapshot to the next.
Map<String, HabitMark> habitMarks(Iterable<Vice> vices) {
  final List<Vice> ordered = vices.toList()
    ..sort((Vice a, Vice b) {
      final int byTime = a.createdAt.compareTo(b.createdAt);
      return byTime != 0 ? byTime : a.id.compareTo(b.id);
    });
  return <String, HabitMark>{
    for (int i = 0; i < ordered.length; i++) ordered[i].id: HabitMark(i),
  };
}
