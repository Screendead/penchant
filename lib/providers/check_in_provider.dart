import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/data/check_in.dart';
import 'package:tracker/data/json_fields.dart';
import 'package:tracker/data/sealed.dart';
import 'package:tracker/providers/signed_in_user.dart';

// Every answered check-in of the user, read once (Insights' comparison with
// entries' urges). Equality on ownerID alone, served by the automatic
// single-field index; offline the cache answers. One that will not open, or
// holds no strength, is left out.
final allCheckInsForUserProvider = FutureProvider.autoDispose
    .family<List<CheckInAnswer>, String>((ref, uid) async {
      final SealedOpener opener = SealedOpener(ref.watch(sealerProvider));
      final QuerySnapshot<Map<String, dynamic>> snapshot =
          await FirebaseFirestore.instance
              .collection(checkInsCollection)
              .where('ownerID', isEqualTo: uid)
              .get();
      final List<CheckInAnswer> answers = <CheckInAnswer>[];
      for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
          in snapshot.docs) {
        final Map<String, dynamic> json = doc.data();
        final Map<String, Object?>? opened = await opener.open(
          checkInsCollection,
          doc.id,
          json,
        );
        if (opened == null) continue;
        if (CheckInContent.read(opened).strength case final int strength) {
          answers.add((
            at: readTimestamp(
              json['createdAt'],
              pending: doc.metadata.hasPendingWrites,
            ).toDate(),
            strength: strength,
          ));
        }
      }
      return answers;
    });

final allCheckInsProvider =
    Provider.autoDispose<AsyncValue<List<CheckInAnswer>>>(
      (ref) => watchForSignedInUser(ref, allCheckInsForUserProvider.call),
    );
