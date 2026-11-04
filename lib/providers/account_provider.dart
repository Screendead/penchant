import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/account/account.dart';
import 'package:tracker/account/export.dart';

final accountProvider = Provider<Account>((ref) {
  return Account(FirebaseAuth.instance, FirebaseFirestore.instance);
});

final exportShareProvider = Provider<ExportShare>((ref) {
  return const ExportShare();
});
