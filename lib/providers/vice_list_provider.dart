import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/providers/user_provider.dart';

final viceListProvider = StreamProvider<List<Vice>?>((ref) {
  final User? user = ref.watch(userProvider).value;

  if (user == null) {
    return const Stream<List<Vice>?>.empty();
  }

  return FirebaseFirestore.instance
      .collection('vices')
      .orderBy('createdAt', descending: true)
      .where('ownerID', isEqualTo: user.uid)
      .snapshots()
      .map<List<Vice>>(Vice.fromQuerySnapshot);
});
