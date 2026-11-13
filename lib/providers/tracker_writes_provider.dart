import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/data/sealed.dart';
import 'package:tracker/providers/log_zone_provider.dart';
import 'package:tracker/providers/sync_status_provider.dart';
import 'package:tracker/writes/tracker_writes.dart';

final trackerWritesProvider = Provider<TrackerWrites>((ref) {
  return TrackerWrites(
    FirebaseFirestore.instance,
    onWrite: () => ref.read(syncStatusProvider.notifier).track(),
    sealer: ref.watch(sealerProvider),
    zone: () => ref.read(logZoneProvider),
  );
});
