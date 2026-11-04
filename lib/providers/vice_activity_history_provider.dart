import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/providers/firestore_retry.dart';
import 'package:tracker/providers/signed_in_user.dart';

typedef ViceActivityHistoryQuery = ({String viceID, int limit});

// The newest [limit] activities of one vice.
final viceActivityHistoryForUserProvider = StreamProvider.autoDispose
    .family<List<ViceActivity>, ({String uid, ViceActivityHistoryQuery query})>(
      retry: firestoreRetry,
      (ref, key) {
        return FirebaseFirestore.instance
            .collection('activities')
            .where('viceID', isEqualTo: key.query.viceID)
            .where('ownerID', isEqualTo: key.uid)
            .orderBy('createdAt', descending: true)
            .limit(key.query.limit)
            // The server's acknowledgement of a local write changes only
            // metadata, and clears an entry's not-yet-synced mark.
            .snapshots(includeMetadataChanges: true)
            .map(ViceActivity.fromQuerySnapshot);
      },
    );

final viceActivityHistoryProvider = Provider.autoDispose
    .family<AsyncValue<List<ViceActivity>>, ViceActivityHistoryQuery>((
      ref,
      query,
    ) {
      return watchForSignedInUser(
        ref,
        (String uid) =>
            viceActivityHistoryForUserProvider((uid: uid, query: query)),
      );
    });

typedef ViceActivityGraphQuery = ({
  String viceID,
  DateTime start,
  DateTime end,
});

final viceActivityGraphForUserProvider = StreamProvider.autoDispose
    .family<List<ViceActivity>, ({String uid, ViceActivityGraphQuery query})>(
      retry: firestoreRetry,
      (ref, key) {
        return FirebaseFirestore.instance
            .collection('activities')
            .where('viceID', isEqualTo: key.query.viceID)
            .where('ownerID', isEqualTo: key.uid)
            .where(
              'createdAt',
              isGreaterThanOrEqualTo: Timestamp.fromDate(key.query.start),
            )
            .where('createdAt', isLessThan: Timestamp.fromDate(key.query.end))
            .orderBy('createdAt', descending: true)
            .snapshots()
            .map(ViceActivity.fromQuerySnapshot);
      },
    );

final viceActivityGraphProvider = Provider.autoDispose
    .family<AsyncValue<List<ViceActivity>>, ViceActivityGraphQuery>((
      ref,
      query,
    ) {
      return watchForSignedInUser(
        ref,
        (String uid) =>
            viceActivityGraphForUserProvider((uid: uid, query: query)),
      );
    });

// The rules deny reading a missing or foreign document, so an activity that is
// gone, or is deleted while this listens, ends the stream with
// permission-denied. That is final, so it is not retried: riverpod's default
// retry would hold the editor in loading for about 38 s while it reopened the
// listener ten times, each a billed denied read.
final viceActivityForUserProvider = StreamProvider.autoDispose
    .family<ViceActivity?, ({String uid, String activityID})>(
      retry: (_, _) => null,
      (ref, key) {
        return FirebaseFirestore.instance
            .collection('activities')
            .doc(key.activityID)
            .snapshots()
            .map(
              (DocumentSnapshot<Map<String, dynamic>> snapshot) =>
                  switch (snapshot.data()) {
                    null => null,
                    final Map<String, dynamic> json => ViceActivity.fromJson(
                      id: snapshot.id,
                      json: json,
                      pending: snapshot.metadata.hasPendingWrites,
                    ),
                  },
            );
      },
    );

final viceActivityProvider = Provider.autoDispose
    .family<AsyncValue<ViceActivity?>, String>((ref, activityID) {
      return watchForSignedInUser(
        ref,
        (String uid) =>
            viceActivityForUserProvider((uid: uid, activityID: activityID)),
      );
    });

// Counted on the server, so it is not live, ignores writes still queued on the
// device, and fails offline.
final viceActivityCountForUserProvider = FutureProvider.autoDispose
    .family<int, ({String uid, String viceID})>(retry: firestoreRetry, (
      ref,
      key,
    ) async {
      final AggregateQuerySnapshot snapshot = await FirebaseFirestore.instance
          .collection('activities')
          .where('viceID', isEqualTo: key.viceID)
          .where('ownerID', isEqualTo: key.uid)
          .count()
          .get();
      return snapshot.count ?? 0;
    });

final viceActivityCountProvider = Provider.autoDispose
    .family<AsyncValue<int>, String>((ref, viceID) {
      return watchForSignedInUser(
        ref,
        (String uid) =>
            viceActivityCountForUserProvider((uid: uid, viceID: viceID)),
      );
    });
