import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/providers/signed_in_user.dart';

typedef ViceActivityHistoryQuery = ({String viceID, int limit});

// The newest [limit] activities of one vice.
final viceActivityHistoryForUserProvider = StreamProvider.autoDispose
    .family<List<ViceActivity>, ({String uid, ViceActivityHistoryQuery query})>(
      (ref, key) {
        return FirebaseFirestore.instance
            .collection('activities')
            .where('viceID', isEqualTo: key.query.viceID)
            .where('ownerID', isEqualTo: key.uid)
            .orderBy('createdAt', descending: true)
            .limit(key.query.limit)
            .snapshots()
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
    .family<List<ViceActivity>, ({String uid, ViceActivityGraphQuery query})>((
      ref,
      key,
    ) {
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
    });

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

// Null when the signed-in user has no activity with this id. A query rather
// than a document read: the rules deny reading a missing document, so a
// deleted activity would surface as permission-denied.
final viceActivityForUserProvider = StreamProvider.autoDispose
    .family<ViceActivity?, ({String uid, String activityID})>((ref, key) {
      return FirebaseFirestore.instance
          .collection('activities')
          .where('ownerID', isEqualTo: key.uid)
          .where(FieldPath.documentId, isEqualTo: key.activityID)
          .limit(1)
          .snapshots()
          .map(
            (QuerySnapshot<Map<String, dynamic>> snapshot) =>
                ViceActivity.fromQuerySnapshot(snapshot).firstOrNull,
          );
    });

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
    .family<int, ({String uid, String viceID})>((ref, key) async {
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
