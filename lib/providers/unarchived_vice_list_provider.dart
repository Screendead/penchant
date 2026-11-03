import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/crypto/journal_cipher.dart';
import 'package:tracker/crypto/journal_key_provider.dart';
import 'package:tracker/crypto/journal_reader.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/providers/user_provider.dart';

final unarchivedViceListProvider = StreamProvider<List<Vice>?>((ref) {
  final User? user = ref.watch(userProvider).value;

  final JournalCipher? cipher = watchJournalCipher(ref);

  if (user == null || cipher == null) {
    return const Stream<List<Vice>?>.empty();
  }

  final DecryptMemo memo = ref.watch(decryptMemoProvider);

  return FirebaseFirestore.instance
      .collection('vices')
      .where('ownerID', isEqualTo: user.uid)
      .where('archived', isEqualTo: false)
      .orderBy('createdAt', descending: true)
      .snapshots()
      .asyncMap((snapshot) => openVices(snapshot, cipher, memo));
});
