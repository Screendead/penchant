import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/data/sealed.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/errors/report_error.dart';
import 'package:tracker/providers/firestore_retry.dart';
import 'package:tracker/providers/offline_provider.dart';
import 'package:tracker/providers/signed_in_user.dart';
import 'package:tracker/writes/settle_write.dart';

typedef ViceActivityHistoryQuery = ({String viceID, int limit});

// The newest [limit] activities of one vice.
final viceActivityHistoryForUserProvider = StreamProvider.autoDispose
    .family<List<ViceActivity>, ({String uid, ViceActivityHistoryQuery query})>(
      retry: firestoreRetry,
      (ref, key) {
        final SealedOpener opener = SealedOpener(ref.watch(sealerProvider));
        return FirebaseFirestore.instance
            .collection('activities')
            .where('viceID', isEqualTo: key.query.viceID)
            .where('ownerID', isEqualTo: key.uid)
            .orderBy('createdAt', descending: true)
            .limit(key.query.limit)
            // The server's acknowledgement of a local write changes only
            // metadata, and clears an entry's not-yet-synced mark.
            .snapshots(includeMetadataChanges: true)
            .asyncMap(
              (snapshot) => ViceActivity.openQuerySnapshot(snapshot, opener),
            );
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
        final SealedOpener opener = SealedOpener(ref.watch(sealerProvider));
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
            .asyncMap(
              (snapshot) => ViceActivity.openQuerySnapshot(snapshot, opener),
            );
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
        final SealedOpener opener = SealedOpener(ref.watch(sealerProvider));
        return FirebaseFirestore.instance
            .collection('activities')
            .doc(key.activityID)
            .snapshots()
            .asyncMap(
              (DocumentSnapshot<Map<String, dynamic>> snapshot) =>
                  switch (snapshot.data()) {
                    null => null,
                    final Map<String, dynamic> json => ViceActivity.open(
                      snapshot,
                      json,
                      opener,
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

enum CountSource { server, deviceOffline, deviceServerFailed }

typedef ActivityCount = ({int count, CountSource source});

// Long enough that a lasting refusal (a missing index, say) does not repeat a
// billed aggregation every few seconds while the page is open.
const Duration countRetryDelay = Duration(seconds: 30);

// Counted on the server, so it is not live and ignores writes still queued on
// the device. Aggregations skip the cache and fail offline, so offline, or if
// the server cannot answer, it counts what this device holds instead, which
// may be only part of the history. Coming back online re-runs it through
// offlineProvider; a server failure while online sets no flag, so it retries.
// With [countCached] false a device count is not taken and its count is 0.
Future<ActivityCount> _countActivities(
  Ref ref,
  Query<Map<String, dynamic>> query, {
  bool countCached = true,
}) async {
  final bool offline = ref.watch(
    offlineProvider.select((AsyncValue<bool> value) => value.value == true),
  );

  if (!offline) {
    try {
      final AggregateQuerySnapshot snapshot = await query.count().get().timeout(
        writeTimeout,
      );
      return (count: snapshot.count ?? 0, source: CountSource.server);
    } on FirebaseException catch (e, stack) {
      reportError(e, stack, context: 'while counting activities');
    } on TimeoutException {
      // Counted from the cache below.
    }
    if (ref.mounted) {
      final Timer retry = Timer(countRetryDelay, ref.invalidateSelf);
      ref.onDispose(retry.cancel);
    }
  }

  final int cached = countCached
      ? (await query.get(const GetOptions(source: Source.cache))).size
      : 0;
  return (
    count: cached,
    source: offline
        ? CountSource.deviceOffline
        : CountSource.deviceServerFailed,
  );
}

final viceActivityCountForUserProvider = FutureProvider.autoDispose
    .family<ActivityCount, ({String uid, String viceID})>(
      retry: firestoreRetry,
      (ref, key) => _countActivities(
        ref,
        FirebaseFirestore.instance
            .collection('activities')
            .where('viceID', isEqualTo: key.viceID)
            .where('ownerID', isEqualTo: key.uid),
      ),
    );

// Every activity the user owns, whatever its viceID: Habits subtracts the
// per-habit counts from it to learn whether entries of a deleted habit exist.
// Only the server's count is used, and a device count would load every cached
// entry, so none is taken.
final activityTotalCountForUserProvider = FutureProvider.autoDispose
    .family<ActivityCount, String>(
      retry: firestoreRetry,
      (ref, uid) => _countActivities(
        ref,
        FirebaseFirestore.instance
            .collection('activities')
            .where('ownerID', isEqualTo: uid),
        countCached: false,
      ),
    );

final activityTotalCountProvider =
    Provider.autoDispose<AsyncValue<ActivityCount>>((ref) {
      return watchForSignedInUser(ref, activityTotalCountForUserProvider.call);
    });

final viceActivityCountProvider = Provider.autoDispose
    .family<AsyncValue<ActivityCount>, String>((ref, viceID) {
      return watchForSignedInUser(
        ref,
        (String uid) =>
            viceActivityCountForUserProvider((uid: uid, viceID: viceID)),
      );
    });
