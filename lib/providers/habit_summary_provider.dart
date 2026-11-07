import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/data/habit_summary.dart';
import 'package:tracker/providers/firestore_retry.dart';
import 'package:tracker/providers/signed_in_user.dart';

final habitSummaryForUserProvider = StreamProvider.autoDispose
    .family<HabitSummary, String>(retry: firestoreRetry, (ref, uid) {
      return FirebaseFirestore.instance
          .collection('summaries')
          .doc(uid)
          .snapshots()
          .map(HabitSummary.fromSnapshot);
    });

final habitSummaryProvider = Provider.autoDispose<AsyncValue<HabitSummary>>((
  ref,
) {
  return watchForSignedInUser(ref, habitSummaryForUserProvider.call);
});

// The stored typicals, or none while the summary loads, fails or was never
// written, so the dial falls back to the shown day's own median.
final storedTypicalsProvider = Provider.autoDispose<Map<String, double>>((ref) {
  return ref.watch(habitSummaryProvider).value?.typicals ??
      const <String, double>{};
});
