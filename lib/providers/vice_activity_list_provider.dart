import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/providers/vice_list_provider.dart';

final viceActivityListProvider = StreamProvider<List<ViceActivity>?>((ref) {
  final User? user = ref.watch(userProvider).value;
  final List<Vice>? viceList = ref.watch(viceListProvider).value;

  if (user == null || viceList == null || viceList.isEmpty) {
    return const Stream<List<ViceActivity>?>.empty();
  }

  final Iterable<String> viceIDs = viceList.map((vice) => vice.id);

  return FirebaseFirestore.instance
      .collection('activities')
      .where('viceID', whereIn: viceIDs)
      .where('ownerID', isEqualTo: user.uid)
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map(ViceActivity.fromQuerySnapshot);
});
