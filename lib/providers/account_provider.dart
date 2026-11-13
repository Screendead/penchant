import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/account/account.dart';
import 'package:tracker/account/export.dart';
import 'package:tracker/data/sealed.dart';
import 'package:tracker/providers/device_files_provider.dart';
import 'package:tracker/reminder/daily_nudge.dart';
import 'package:tracker/writes/queued_write_journal.dart';

final accountProvider = Provider<Account>((ref) {
  return Account(
    FirebaseAuth.instance,
    FirebaseFirestore.instance,
    ref.watch(queuedWriteJournalProvider),
    sealer: ref.watch(sealerProvider),
    clearDeviceFiles: () async {
      await ref.read(deviceFilesProvider).clearAll();
      // Its plan went with the files; its notifications go too.
      try {
        await ref.read(nudgeSchedulerProvider).cancelExperiment();
      } catch (_) {
        // Up to a week of them may still arrive; none names the habit.
      }
    },
  );
});

final exportShareProvider = Provider<ExportShare>((ref) {
  return const ExportShare();
});
