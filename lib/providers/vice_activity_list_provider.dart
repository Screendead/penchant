import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/providers/vice_list_provider.dart';

final viceActivityListProvider = StreamProvider<List<ViceActivity>?>((ref) {
  final User? user = ref.watch(userProvider).value;
  final AsyncValue<List<Vice>?> viceListValue = ref.watch(viceListProvider);

  if (viceListValue case AsyncError(:final error, :final stackTrace)) {
    return Stream.error(error, stackTrace);
  }

  final List<Vice>? viceList = viceListValue.value;

  if (user == null || viceList == null) {
    return const Stream<List<ViceActivity>?>.empty();
  }

  // Firestore rejects an `in` filter with an empty value list.
  if (viceList.isEmpty) {
    return Stream.value(const <ViceActivity>[]);
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
