import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/data/sealed.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/firebase_init.dart';
import 'package:tracker/insights/insights_report.dart'
    show insightsJournalStart;
import 'package:tracker/insights/insights_timing.dart';
import 'package:tracker/providers/journal_read.dart';
import 'package:tracker/writes/settle_write.dart' show writeTimeout;
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
        final SealedOpener opener = SealedOpener(ref.watch(sealerProvider));
        final DateTime startOfSelectedDay = startOfDay(key.day);

        return _activitiesBetween(
              key.uid,
              startOfSelectedDay,
              addDays(startOfSelectedDay, 1),
            )
            // The server's acknowledgement of a local write changes only
            // metadata, and clears an entry's not-yet-synced mark.
            .snapshots(includeMetadataChanges: true)
            .asyncMap(
              (snapshot) => ViceActivity.openQuerySnapshot(snapshot, opener),
            );
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
      (ref, key) {
        final SealedOpener opener = SealedOpener(ref.watch(sealerProvider));
        return _activitiesBetween(
          key.uid,
          DateTime(key.month.year, key.month.month),
          DateTime(key.month.year, key.month.month + 1),
        ).snapshots().asyncMap(
          (snapshot) => ViceActivity.openQuerySnapshot(snapshot, opener),
        );
      },
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

// The [days] days ending with [today], for the widgets' snapshot.
final viceActivityRecentForUserProvider = StreamProvider.autoDispose
    .family<List<ViceActivity>, ({String uid, DateTime today, int days})>(
      retry: firestoreRetry,
      (ref, key) {
        final SealedOpener opener = SealedOpener(ref.watch(sealerProvider));
        final DateTime end = addDays(startOfDay(key.today), 1);
        return _activitiesBetween(
          key.uid,
          addDays(end, -key.days),
          end,
        ).snapshots().asyncMap(
          (snapshot) => ViceActivity.openQuerySnapshot(snapshot, opener),
        );
      },
    );

typedef ActivityRange = ({DateTime start, DateTime end});

// Every activity in [start, end), for Insights, Ask and the reviews. The same
// query shape as the day's, so the same index. Read once rather than listened
// to: the range can be the whole journal, and a listener would read and open
// every entry again on each change, and rerun the engine over it. A range
// from [insightsJournalStart] is the whole journal, read through
// [readJournal]: after one full read, only what changed comes from the
// server. A shorter range is a plain read.
final viceActivityRangeForUserProvider = FutureProvider.autoDispose
    .family<List<ViceActivity>, ({String uid, ActivityRange range})>(
      retry: firestoreRetry,
      (ref, key) async {
        final SealedOpener opener = SealedOpener(ref.watch(sealerProvider));
        final Query<Map<String, dynamic>> query = _activitiesBetween(
          key.uid,
          key.range.start,
          key.range.end,
        );
        if (key.range.start.isAfter(insightsJournalStart)) {
          final QuerySnapshot<Map<String, dynamic>> snapshot =
              await timedInsightsStage('journal range read', query.get);
          return timedInsightsStage(
            'journal range open (${snapshot.size} entries)',
            () => ViceActivity.openQuerySnapshot(snapshot, opener),
          );
        }
        final JournalRead read = await timedInsightsStage(
          'journal read',
          () => readJournal(
            uid: key.uid,
            source: _FirestoreJournal(key.uid, key.range, query, opener),
            cursors: const PrefsJournalCursorStore(),
            now: DateTime.now().toUtc(),
          ),
        );
        insightsTimingLog(
          'journal read: ${read.kind.name}, ${read.entries.length} entries',
        );
        return read.entries;
      },
    );

// The whole-journal query's reads for [readJournal].
class _FirestoreJournal implements JournalSource {
  _FirestoreJournal(this.uid, this.range, this.query, this.opener);

  final String uid;
  final ActivityRange range;
  final Query<Map<String, dynamic>> query;
  final SealedOpener opener;

  // Bounds the wait for queued writes, which offline never ends.
  static const Duration _pendingWait = Duration(seconds: 2);

  @override
  bool get persistentCache =>
      !useFirebaseEmulators &&
      (FirebaseFirestore.instance.settings.persistenceEnabled ?? true);

  Future<JournalPage> _page(
    QuerySnapshot<Map<String, dynamic>> snapshot, {
    bool inRange = false,
  }) async {
    final List<ViceActivity> opened = await ViceActivity.openQuerySnapshot(
      snapshot,
      opener,
    );
    return (
      entries: inRange
          ? <ViceActivity>[
              for (final ViceActivity entry in opened)
                if (!entry.createdAt.toDate().isBefore(range.start) &&
                    entry.createdAt.toDate().isBefore(range.end))
                  entry,
            ]
          : opened,
      fromCache: snapshot.metadata.isFromCache,
      newest: newestStamp(snapshot),
    );
  }

  @override
  Future<void> settlePending() => FirebaseFirestore.instance
      .waitForPendingWrites()
      .timeout(_pendingWait, onTimeout: () {});

  @override
  Future<JournalPage> full() async => _page(await query.get());

  // Not bounded by createdAt: an inequality on two fields would need another
  // index, and an entry moved out of the range must still reach the cache.
  @override
  Future<JournalPage> changedSince(DateTime since) async => _page(
    await FirebaseFirestore.instance
        .collection('activities')
        .where('ownerID', isEqualTo: uid)
        // A literal, so test/firestore_indexes_test.dart reads the field.
        .where('updatedAt', isGreaterThanOrEqualTo: Timestamp.fromDate(since))
        .get(const GetOptions(source: Source.server)),
    inRange: true,
  );

  @override
  Future<int> serverCount() async =>
      (await query.count().get().timeout(writeTimeout)).count ?? 0;

  @override
  Future<JournalPage> cached() async =>
      _page(await query.get(const GetOptions(source: Source.cache)));
}

final viceActivityRangeProvider = Provider.autoDispose
    .family<AsyncValue<List<ViceActivity>>, ActivityRange>((ref, range) {
      return watchForSignedInUser(
        ref,
        (String uid) =>
            viceActivityRangeForUserProvider((uid: uid, range: range)),
      );
    });

// The 7 days ending with [day], for a week line's total on Today: the same
// rolling week Trends counts back from its last day.
final viceActivityWeekProvider = Provider.autoDispose
    .family<AsyncValue<List<ViceActivity>>, DateTime>((ref, day) {
      return watchForSignedInUser(
        ref,
        (String uid) => viceActivityRecentForUserProvider((
          uid: uid,
          today: startOfDay(day),
          days: 7,
        )),
      );
    });
