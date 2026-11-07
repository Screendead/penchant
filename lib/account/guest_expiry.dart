import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/providers/today_provider.dart';
import 'package:tracker/providers/user_provider.dart';

// Firebase's automatic clean-up may delete an anonymous account any time after
// it is 30 days old; one that existed when clean-up was turned on counts from
// that day instead (Jack turned it on 2026-11-07). Linking an email stops it.
abstract final class GuestExpiry {
  static final DateTime cleanupOn = DateTime.utc(2026, 11, 7);

  // Elapsed time, not calendar days: Firebase counts from an instant.
  static const Duration lifetime = Duration(days: 30);

  // Today warns from day 20 and blocks with a sheet in the last 3 days.
  static const int bannerDays = 10;
  static const int sheetDays = 3;

  static DateTime eraseFrom(DateTime created) =>
      (created.isAfter(cleanupOn) ? created : cleanupOn).add(lifetime);

  // Whole local days from today to the day the account becomes deletable;
  // zero or less means it may go at any moment.
  static int daysLeft(DateTime created, DateTime today) =>
      daysBetween(today, startOfDay(eraseFrom(created).toLocal()));
}

// Null unless the signed-in user is a guest. On userChanges(), which alone
// re-emits after linking, so the warning goes as soon as the journal is saved.
final guestDaysLeftProvider = Provider.autoDispose<int?>((ref) {
  final User? user = ref.watch(userProfileProvider).value;
  if (user == null || !user.isAnonymous) {
    return null;
  }
  final DateTime? created = user.metadata.creationTime;
  return created == null
      ? null
      : GuestExpiry.daysLeft(created, ref.watch(todayProvider));
});

// The day the blocking sheet last showed, so it comes once a day rather than
// on every visit to Today.
final guestSheetShownProvider = NotifierProvider<GuestSheetShown, DateTime?>(
  GuestSheetShown.new,
);

class GuestSheetShown extends Notifier<DateTime?> {
  @override
  DateTime? build() => null;

  void shownOn(DateTime day) => state = day;
}
