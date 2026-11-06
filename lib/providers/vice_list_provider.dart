import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/data/sealed.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/providers/firestore_retry.dart';
import 'package:tracker/providers/signed_in_user.dart';

final viceListForUserProvider = StreamProvider.autoDispose
    .family<List<Vice>, String>(retry: firestoreRetry, (ref, uid) {
      final SealedOpener opener = SealedOpener(ref.watch(sealerProvider));
      return FirebaseFirestore.instance
          .collection('vices')
          .where('ownerID', isEqualTo: uid)
          .orderBy('createdAt', descending: true)
          .snapshots()
          .asyncMap((snapshot) => Vice.openQuerySnapshot(snapshot, opener));
    });

final viceListProvider = Provider.autoDispose<AsyncValue<List<Vice>>>((ref) {
  return watchForSignedInUser(ref, viceListForUserProvider.call);
});
