import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/providers/user_provider.dart';

final viceActivityHistoryProvider =
    StreamProvider.family<List<ViceActivity>?, String>((ref, viceID) {
  final User? user = ref.watch(userProvider).value;

  if (user == null) {
    return const Stream<List<ViceActivity>?>.empty();
  }

  return FirebaseFirestore.instance
      .collection('activities')
      .where('viceID', isEqualTo: viceID)
      .where('ownerID', isEqualTo: user.uid)
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map(ViceActivity.fromQuerySnapshot);
});

class ViceActivityGraphQuery {
  ViceActivityGraphQuery({
    required this.viceID,
    required this.start,
    required this.end,
  });

  final String viceID;
  final DateTime start;
  final DateTime end;

  @override
  bool operator ==(Object other) {
    return other is ViceActivityGraphQuery &&
        other.viceID == viceID &&
        other.start == start &&
        other.end == end;
  }

  @override
  int get hashCode => Object.hash(viceID, start, end);
}

final viceActivityGraphProvider =
    StreamProvider.family<List<ViceActivity>?, ViceActivityGraphQuery>(
        (ref, query) {
  final User? user = ref.watch(userProvider).value;

  if (user == null) {
    return const Stream<List<ViceActivity>?>.empty();
  }

  return FirebaseFirestore.instance
      .collection('activities')
      .where('viceID', isEqualTo: query.viceID)
      .where('ownerID', isEqualTo: user.uid)
      .where(
        'createdAt',
        isGreaterThanOrEqualTo: Timestamp.fromDate(query.start),
      )
      .where('createdAt', isLessThan: Timestamp.fromDate(query.end))
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map(ViceActivity.fromQuerySnapshot);
});

final allViceActivityProvider = StreamProvider<List<ViceActivity>?>((ref) {
  final User? user = ref.watch(userProvider).value;

  if (user == null) {
    return const Stream<List<ViceActivity>?>.empty();
  }

  return FirebaseFirestore.instance
      .collection('activities')
      .where('ownerID', isEqualTo: user.uid)
      .orderBy('createdAt', descending: false)
      .snapshots()
      .map(ViceActivity.fromQuerySnapshot);
});

class ActivityWindow {
  ActivityWindow({required this.start, required this.end});

  final DateTime start;
  final DateTime end;

  @override
  bool operator ==(Object other) {
    return other is ActivityWindow &&
        other.start == start &&
        other.end == end;
  }

  @override
  int get hashCode => Object.hash(start, end);
}

final viceActivityWindowProvider =
    StreamProvider.family<List<ViceActivity>?, ActivityWindow>((ref, window) {
  final User? user = ref.watch(userProvider).value;

  if (user == null) {
    return const Stream<List<ViceActivity>?>.empty();
  }

  return FirebaseFirestore.instance
      .collection('activities')
      .where('ownerID', isEqualTo: user.uid)
      .where(
        'createdAt',
        isGreaterThanOrEqualTo: Timestamp.fromDate(window.start),
      )
      .where('createdAt', isLessThan: Timestamp.fromDate(window.end))
      .orderBy('createdAt', descending: false)
      .snapshots()
      .map(ViceActivity.fromQuerySnapshot);
});