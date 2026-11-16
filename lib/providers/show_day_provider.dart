import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A day another page asked Today to show (Ask your journal's "Open … in
/// Today"), waiting for Today to pop back to itself and select it.
final pendingShowDayProvider = NotifierProvider<PendingShowDay, DateTime?>(
  PendingShowDay.new,
);

class PendingShowDay extends Notifier<DateTime?> {
  @override
  DateTime? build() => null;

  void request(DateTime day) => state = day;

  void clear() => state = null;
}
