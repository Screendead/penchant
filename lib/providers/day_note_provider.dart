import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/data/day_note.dart';
import 'package:tracker/data/sealed.dart';
import 'package:tracker/providers/firestore_retry.dart';
import 'package:tracker/providers/signed_in_user.dart';

// The note about one day, null while there is none. A query bounded to the
// note's one id, not a document listener: the rules deny reading a missing
// document, so a day with no note would end the stream with
// permission-denied. Equality on ownerID ordered by document id is served by
// the automatic single-field index, as TrackerWrites.serverDocument is.
final dayNoteForUserProvider = StreamProvider.autoDispose
    .family<DayNote?, ({String uid, String day})>(retry: firestoreRetry, (
      ref,
      key,
    ) {
      final SealedOpener opener = SealedOpener(ref.watch(sealerProvider));
      final String id = dayNoteID(key.uid, key.day);
      return FirebaseFirestore.instance
          .collection(dayNotesCollection)
          .where('ownerID', isEqualTo: key.uid)
          .orderBy(FieldPath.documentId)
          .startAt(<Object>[id])
          .endAt(<Object>[id])
          // The server's acknowledgement changes only metadata, and clears
          // the note's pending mark.
          .snapshots(includeMetadataChanges: true)
          .asyncMap(
            (QuerySnapshot<Map<String, dynamic>> snapshot) =>
                switch (snapshot.docs) {
                  [] => null,
                  [
                    final QueryDocumentSnapshot<Map<String, dynamic>> doc,
                    ...,
                  ] =>
                    DayNote.open(doc, doc.data(), opener),
                },
          );
    });

// Keyed on the local day; any time within it names the same note.
final dayNoteProvider = Provider.autoDispose
    .family<AsyncValue<DayNote?>, DateTime>((ref, day) {
      final String key = dayKey(day);
      return watchForSignedInUser(
        ref,
        (String uid) => dayNoteForUserProvider((uid: uid, day: key)),
      );
    });

// Every day note of the user, read once (Ask your journal's tables). Equality
// on ownerID alone, served by the automatic single-field index; offline the
// cache answers, as for the entries read beside it.
final allDayNotesForUserProvider = FutureProvider.autoDispose
    .family<List<DayNote>, String>((ref, uid) async {
      final SealedOpener opener = SealedOpener(ref.watch(sealerProvider));
      final QuerySnapshot<Map<String, dynamic>> snapshot =
          await FirebaseFirestore.instance
              .collection(dayNotesCollection)
              .where('ownerID', isEqualTo: uid)
              .get();
      return <DayNote>[
        for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
            in snapshot.docs)
          await DayNote.open(doc, doc.data(), opener),
      ];
    });

final allDayNotesProvider = Provider.autoDispose<AsyncValue<List<DayNote>>>(
  (ref) => watchForSignedInUser(ref, allDayNotesForUserProvider.call),
);
