import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Uses of a free-text trigger at which the picker offers it as a choice.
const int freeTextPromotionUses = 3;

/// How often each free-text trigger has been saved on an entry, per user, kept
/// on this device only.
class FreeTextTriggers {
  const FreeTextTriggers();

  static String key(String uid) => 'freeTextTriggerUses.$uid';

  Future<Map<String, int>> uses(String uid) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? raw = prefs.getString(key(uid));
    if (raw == null) return <String, int>{};
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map<String, Object?>) return <String, int>{};
      return <String, int>{
        for (final MapEntry<String, Object?> e in decoded.entries)
          if (e.value case final int n) e.key: n,
      };
    } on FormatException {
      return <String, int>{};
    }
  }

  /// Counts one use of each of [labels].
  Future<void> recordUses(String uid, Iterable<String> labels) async {
    final Set<String> distinct = labels.toSet();
    if (distinct.isEmpty) return;
    final Map<String, int> counts = await uses(uid);
    for (final String label in distinct) {
      counts[label] = (counts[label] ?? 0) + 1;
    }
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(key(uid), jsonEncode(counts));
  }

  /// The free-text triggers used at least [freeTextPromotionUses] times, most
  /// used first.
  Future<List<String>> promoted(String uid) async {
    final Map<String, int> counts = await uses(uid);
    final List<String> labels =
        counts.keys
            .where((String l) => counts[l]! >= freeTextPromotionUses)
            .toList()
          ..sort((String a, String b) => counts[b]!.compareTo(counts[a]!));
    return labels;
  }
}

final freeTextTriggersProvider = Provider<FreeTextTriggers>(
  (ref) => const FreeTextTriggers(),
);
