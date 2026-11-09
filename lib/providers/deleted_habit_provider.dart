import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/data/json_fields.dart';
import 'package:tracker/data/sealed.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/providers/firestore_retry.dart';
import 'package:tracker/providers/signed_in_user.dart';
import 'package:tracker/providers/vice_activity_history_provider.dart';
import 'package:tracker/providers/vice_list_provider.dart';

// Entries whose viceID names none of the user's habits: written before the
// rules required an owned vice, so their habit is gone or another account's.

/// How many there are: every entry the user owns less those of each habit,
/// so it costs Habits one aggregation beyond the per-habit counts it already
/// shows. Null unless every count came from the server (device counts may
/// cover only part of the journal) and the difference is positive; the counts
/// are not taken at one instant, so a log between them can skew it by one.
final deletedHabitCountProvider = Provider.autoDispose<int?>((ref) {
  final List<Vice>? vices = ref.watch(viceListProvider).value;
  final ActivityCount? total = ref.watch(activityTotalCountProvider).value;
  if (vices == null || total == null) return null;
  final List<ActivityCount?> counts = <ActivityCount?>[
    for (final Vice vice in vices)
      ref.watch(viceActivityCountProvider(vice.id)).value,
  ];
  int counted = 0;
  for (final ActivityCount? count in <ActivityCount?>[total, ...counts]) {
    if (count == null || count.source != CountSource.server) return null;
  }
  for (final ActivityCount? count in counts) {
    counted += count!.count;
  }
  final int left = total.count - counted;
  return left > 0 ? left : null;
});

const int deletedHabitPageSize = 500;

// A Firestore document ID never holds a '/', so it parts the IDs.
const String _idSeparator = '/';

/// Read once per open of the page, not listened to: finding them means
/// reading every entry the user owns, the export's shape (paged by document
/// ID, so an entry lacking createdAt is not skipped), newest first.
final deletedHabitActivitiesForUserProvider = FutureProvider.autoDispose
    .family<List<ViceActivity>, ({String uid, String viceIDs})>(
      retry: firestoreRetry,
      (ref, key) async {
        final SealedOpener opener = SealedOpener(ref.watch(sealerProvider));
        final Set<String> known = <String>{
          if (key.viceIDs.isNotEmpty) ...key.viceIDs.split(_idSeparator),
        };
        final List<ViceActivity> found = <ViceActivity>[];
        Query<Map<String, dynamic>> page = FirebaseFirestore.instance
            .collection('activities')
            .where('ownerID', isEqualTo: key.uid)
            .orderBy(FieldPath.documentId)
            .limit(deletedHabitPageSize);
        while (true) {
          final QuerySnapshot<Map<String, dynamic>> snapshot = await page.get();
          for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
              in snapshot.docs) {
            final Map<String, dynamic> json = doc.data();
            if (!known.contains(readString(json['viceID']))) {
              found.add(await ViceActivity.open(doc, json, opener));
            }
          }
          if (snapshot.docs.length < deletedHabitPageSize) break;
          page = page.startAfterDocument(snapshot.docs.last);
        }
        return found..sort(
          (ViceActivity a, ViceActivity b) =>
              b.createdAt.compareTo(a.createdAt),
        );
      },
    );

final deletedHabitActivitiesProvider =
    Provider.autoDispose<AsyncValue<List<ViceActivity>>>((ref) {
      final AsyncValue<List<Vice>> vices = ref.watch(viceListProvider);
      if (vices case AsyncError(
        :final Object error,
        :final StackTrace stackTrace,
      )) {
        return AsyncError<List<ViceActivity>>(error, stackTrace);
      }
      final List<Vice>? list = vices.value;
      if (list == null) return const AsyncLoading<List<ViceActivity>>();
      // Every habit, archived included: an archived habit's entries are its own.
      final String viceIDs = ([
        for (final Vice vice in list) vice.id,
      ]..sort()).join(_idSeparator);
      return watchForSignedInUser(
        ref,
        (String uid) =>
            deletedHabitActivitiesForUserProvider((uid: uid, viceIDs: viceIDs)),
      );
    });
