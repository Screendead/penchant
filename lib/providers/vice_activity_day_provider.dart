import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/providers/firestore_retry.dart';
import 'package:tracker/providers/signed_in_user.dart';

// Every vice's activities for the day, archived vices' included: filtering by
// vice would need an `in` filter, which takes at most 30 values. The chart
// drops what it does not draw.
final viceActivityDayForUserProvider = StreamProvider.autoDispose
    .family<List<ViceActivity>, ({String uid, DateTime day})>(
      retry: firestoreRetry,
      (ref, key) {
        final DateTime startOfSelectedDay = startOfDay(key.day);
        final DateTime startOfNextDay = addDays(startOfSelectedDay, 1);

        return FirebaseFirestore.instance
            .collection('activities')
            .where('ownerID', isEqualTo: key.uid)
            .where(
              'createdAt',
              isGreaterThanOrEqualTo: Timestamp.fromDate(startOfSelectedDay),
            )
            .where('createdAt', isLessThan: Timestamp.fromDate(startOfNextDay))
            .orderBy('createdAt', descending: true)
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
