import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/providers/firestore_retry.dart';
import 'package:tracker/providers/signed_in_user.dart';

final unarchivedViceListForUserProvider = StreamProvider.autoDispose
    .family<List<Vice>, String>(retry: firestoreRetry, (ref, uid) {
      return FirebaseFirestore.instance
          .collection('vices')
          .where('ownerID', isEqualTo: uid)
          .where('archived', isEqualTo: false)
          .orderBy('createdAt', descending: true)
          .snapshots()
          .map(Vice.fromQuerySnapshot);
    });

final unarchivedViceListProvider = Provider.autoDispose<AsyncValue<List<Vice>>>(
  (ref) {
    return watchForSignedInUser(ref, unarchivedViceListForUserProvider.call);
  },
);
