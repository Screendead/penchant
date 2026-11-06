import 'dart:ui' show Offset;

import 'package:flutter_riverpod/flutter_riverpod.dart';

// Where each just-logged entry was logged from, in global coordinates, so the
// dial can fly its bead in from there once the entry reaches the day's list.
// A plain object, not state: the dial reads it when its entries change.
class BeadArrivals {
  static const Duration _expiry = Duration(seconds: 3);

  final Map<String, ({Offset from, DateTime at})> _launched =
      <String, ({Offset from, DateTime at})>{};

  void launch(String activityID, Offset from) {
    _launched[activityID] = (from: from, at: DateTime.now());
  }

  // Removes and returns the launch points of [ids] logged within the last
  // few seconds; older ones are dropped, as no flight would be expected.
  Map<String, Offset> takeAll(Iterable<String> ids) {
    final DateTime cutoff = DateTime.now().subtract(_expiry);
    _launched.removeWhere(
      (_, ({Offset from, DateTime at}) l) => l.at.isBefore(cutoff),
    );
    return <String, Offset>{
      for (final String id in ids)
        if (_launched.remove(id) case final ({Offset from, DateTime at}) l)
          id: l.from,
    };
  }
}

final beadArrivalsProvider = Provider<BeadArrivals>((_) => BeadArrivals());
