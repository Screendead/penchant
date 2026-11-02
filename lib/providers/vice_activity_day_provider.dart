import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/providers/vice_list_provider.dart';

final viceActivityDayProvider =
    StreamProvider.family<List<ViceActivity>?, DateTime>((ref, selectedDate) {
  final User? user = ref.watch(userProvider).value;
  final List<Vice>? viceList = ref.watch(viceListProvider).value;

  if (user == null || viceList == null || viceList.isEmpty) {
    return const Stream<List<ViceActivity>?>.empty();
  }

  final DateTime startOfDay = DateTime(
    selectedDate.year,
    selectedDate.month,
    selectedDate.day,
  );
  final DateTime startOfNextDay = startOfDay.add(const Duration(days: 1));
  final List<String> viceIDs = viceList.map((Vice vice) => vice.id).toList();

  return FirebaseFirestore.instance
      .collection('activities')
      .where('viceID', whereIn: viceIDs)
      .where('ownerID', isEqualTo: user.uid)
      .where(
        'createdAt',
        isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay),
      )
      .where('createdAt', isLessThan: Timestamp.fromDate(startOfNextDay))
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map(ViceActivity.fromQuerySnapshot);
});