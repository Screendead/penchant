import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/providers/firestore_retry.dart';
import 'package:tracker/providers/signed_in_user.dart';

// Every vice's activities in [start, end), archived vices' included: filtering
// by vice would need an `in` filter, which takes at most 30 values. The screen
// drops what it does not draw. One shape for every window, so one index.
Query<Map<String, dynamic>> _activitiesBetween(
  String uid,
  DateTime start,
  DateTime end,
) => FirebaseFirestore.instance
    .collection('activities')
    .where('ownerID', isEqualTo: uid)
    .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
    .where('createdAt', isLessThan: Timestamp.fromDate(end))
    .orderBy('createdAt', descending: true);

final viceActivityDayForUserProvider = StreamProvider.autoDispose
    .family<List<ViceActivity>, ({String uid, DateTime day})>(
      retry: firestoreRetry,
      (ref, key) {
        final DateTime startOfSelectedDay = startOfDay(key.day);

        return _activitiesBetween(
              key.uid,
              startOfSelectedDay,
              addDays(startOfSelectedDay, 1),
            )
            // The server's acknowledgement of a local write changes only
            // metadata, and clears an entry's not-yet-synced mark.
            .snapshots(includeMetadataChanges: true)
            .map(ViceActivity.fromQuerySnapshot);
      },
    );

final viceActivityDayProvider = Provider.autoDispose
    .family<AsyncValue<List<ViceActivity>>, DateTime>((ref, day) {
      return watchForSignedInUser(
        ref,
        (String uid) => viceActivityDayForUserProvider((uid: uid, day: day)),
      );
    });

// The calendar month holding [month], for the calendar's dots.
final viceActivityMonthForUserProvider = StreamProvider.autoDispose
    .family<List<ViceActivity>, ({String uid, DateTime month})>(
      retry: firestoreRetry,
      (ref, key) => _activitiesBetween(
        key.uid,
        DateTime(key.month.year, key.month.month),
        DateTime(key.month.year, key.month.month + 1),
      ).snapshots().map(ViceActivity.fromQuerySnapshot),
    );

final viceActivityMonthProvider = Provider.autoDispose
    .family<AsyncValue<List<ViceActivity>>, DateTime>((ref, month) {
      final DateTime first = DateTime(month.year, month.month);
      return watchForSignedInUser(
        ref,
        (String uid) =>
            viceActivityMonthForUserProvider((uid: uid, month: first)),
      );
    });
