import 'package:cloud_firestore/cloud_firestore.dart';

// summaries/{uid}, written monthly by functions/ over the last 90 days and
// read-only to the app. Absent until the first run, so empty means "none".
class HabitSummary {
  const HabitSummary({this.typicals = const <String, double>{}});

  static const HabitSummary none = HabitSummary();

  // Each habit's typical entry, by vice ID.
  final Map<String, double> typicals;

  factory HabitSummary.fromData(Map<String, dynamic>? data) {
    final Object? vices = data?['vices'];
    if (vices is! Map) {
      return none;
    }
    return HabitSummary(
      typicals: <String, double>{
        for (final MapEntry<Object?, Object?>(:key, :value) in vices.entries)
          if (key is String && value is Map && _positive(value['typical']))
            key: (value['typical'] as num).toDouble(),
      },
    );
  }

  factory HabitSummary.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> s) =>
      HabitSummary.fromData(s.data());

  static bool _positive(Object? v) => v is num && v.isFinite && v > 0;
}
