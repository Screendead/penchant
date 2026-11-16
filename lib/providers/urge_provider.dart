import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/data/sealed.dart';
import 'package:tracker/data/urge.dart';
import 'package:tracker/providers/firestore_retry.dart';
import 'package:tracker/providers/signed_in_user.dart';

typedef UrgeWindow = ({DateTime start, DateTime end});

// Every urge of the user noted in [start, end), newest first, all habits:
// the chart and the day view filter on the device, so one index serves both.
// Bounded by the window like the day and graph queries. `createdAt` is the
// device clock, so an urge noted offline still matches.
final urgesForUserProvider = StreamProvider.autoDispose
    .family<List<Urge>, ({String uid, UrgeWindow window})>(
      retry: firestoreRetry,
      (ref, key) {
        final SealedOpener opener = SealedOpener(ref.watch(sealerProvider));
        return FirebaseFirestore.instance
            .collection(urgesCollection)
            .where('ownerID', isEqualTo: key.uid)
            .where(
              'createdAt',
              isGreaterThanOrEqualTo: Timestamp.fromDate(key.window.start),
            )
            .where('createdAt', isLessThan: Timestamp.fromDate(key.window.end))
            .orderBy('createdAt', descending: true)
            // The acknowledgement changes only metadata, and clears the
            // pending mark.
            .snapshots(includeMetadataChanges: true)
            .asyncMap(
              (QuerySnapshot<Map<String, dynamic>> snapshot) async => <Urge>[
                for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
                    in snapshot.docs)
                  await Urge.open(doc, doc.data(), opener),
              ],
            );
      },
    );

final urgesProvider = Provider.autoDispose
    .family<AsyncValue<List<Urge>>, UrgeWindow>(
      (ref, window) => watchForSignedInUser(
        ref,
        (String uid) => urgesForUserProvider((uid: uid, window: window)),
      ),
    );
