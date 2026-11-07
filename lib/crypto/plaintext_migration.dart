import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:tracker/crypto/plaintext_migrator.dart';
import 'package:tracker/data/sealed.dart';
import 'package:tracker/errors/report_error.dart';
import 'package:tracker/providers/offline_provider.dart';
import 'package:tracker/providers/package_info_provider.dart';
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/writes/queued_write_journal.dart';

enum MigrationPhase { idle, waiting, sealing, done, failed }

class MigrationStatus {
  const MigrationStatus(this.phase, [this.sealed = 0]);

  static const MigrationStatus idle = MigrationStatus(MigrationPhase.idle);

  final MigrationPhase phase;

  /// Documents sealed by this launch's run so far.
  final int sealed;

  @override
  bool operator ==(Object other) =>
      other is MigrationStatus &&
      other.phase == phase &&
      other.sealed == sealed;

  @override
  int get hashCode => Object.hash(phase, sealed);
}

/// The uids and app versions the migrator has finished for, on this device.
/// A new version runs again, to seal what an older build on another device
/// may have written in plaintext since.
class MigrationMarkers {
  MigrationMarkers(this._store);

  final JournalStore _store;

  static String key(String uid, String version) => '$uid $version';

  Future<Set<String>> _read() async {
    try {
      final String? contents = await _store.read();
      if (contents == null) {
        return <String>{};
      }
      return <String>{
        for (final Object? entry in jsonDecode(contents) as List<Object?>)
          if (entry is String) entry,
      };
    } catch (e, stack) {
      reportError(e, stack, context: 'while reading the sealing markers');
      return <String>{};
    }
  }

  Future<bool> isDone(String uid, String version) async =>
      (await _read()).contains(key(uid, version));

  Future<void> markDone(String uid, String version) async {
    final Set<String> done = await _read()
      ..add(key(uid, version));
    await _store.write(jsonEncode(done.toList()));
  }
}

final migrationSourceProvider = Provider<MigrationSource>(
  (ref) => FirestoreMigrationSource(FirebaseFirestore.instance),
);

final migrationMarkersProvider = Provider<MigrationMarkers>(
  (ref) => MigrationMarkers(
    FileJournalStore(
      Firebase.app().options.projectId,
      name: 'sealed-migrations',
    ),
  ),
);

// Holds the run in progress across rebuilds of plaintextMigrationProvider,
// so a rebuild (going offline and back) never starts a second run beside it:
// two runs sealing the same document would have the second refused.
class _MigrationLock {
  Future<void> last = Future<void>.value();
}

final _migrationLockProvider = Provider<_MigrationLock>(
  (ref) => _MigrationLock(),
);

const Duration migrationRetryDelay = Duration(seconds: 30);

/// Seals the signed-in user's plaintext documents once per uid and app
/// version, in the background, once a key is on the device and Firestore is
/// answering from the server. MyApp keeps it listened to; Settings shows its
/// status.
final plaintextMigrationProvider =
    NotifierProvider.autoDispose<PlaintextMigration, MigrationStatus>(
      PlaintextMigration.new,
    );

class PlaintextMigration extends Notifier<MigrationStatus> {
  @override
  MigrationStatus build() {
    // The sealer first: without a key nothing else is read.
    final FieldSealer? sealer = ref.watch(sealerProvider);
    if (sealer == null) {
      return MigrationStatus.idle;
    }
    final String? uid = ref.watch(userProvider.select((v) => v.value?.uid));
    final PackageInfo? info = ref.watch(packageInfoProvider).value;
    if (uid == null || info == null) {
      return MigrationStatus.idle;
    }
    final _MigrationLock lock = ref.watch(_migrationLockProvider);
    // A cached answer could leave documents out, so the run waits until the
    // vices listener has heard from the server.
    final bool? offline = ref.watch(offlineProvider).value;
    if (offline != false) {
      return offline == true
          ? const MigrationStatus(MigrationPhase.waiting)
          : MigrationStatus.idle;
    }

    bool current = true;
    Timer? retry;
    ref.onDispose(() {
      current = false;
      retry?.cancel();
    });
    final String version = '${info.version}+${info.buildNumber}';
    final MigrationMarkers markers = ref.watch(migrationMarkersProvider);
    final PlaintextMigrator migrator = PlaintextMigrator(
      source: ref.watch(migrationSourceProvider),
      sealer: sealer,
    );

    void report(MigrationStatus status) {
      if (current) {
        state = status;
      }
    }

    lock.last = lock.last.then((_) async {
      if (!current || await markers.isDone(uid, version)) {
        return;
      }
      try {
        report(const MigrationStatus(MigrationPhase.sealing));
        final int sealed = await migrator.run(
          uid,
          onProgress: (int sealed) =>
              report(MigrationStatus(MigrationPhase.sealing, sealed)),
          stillWanted: () => current,
        );
        if (!current) {
          return;
        }
        await markers.markDone(uid, version);
        report(MigrationStatus(MigrationPhase.done, sealed));
      } catch (e, stack) {
        if (!current) {
          return;
        }
        final bool unreachable =
            e is FirebaseException && e.code == 'unavailable';
        if (!unreachable) {
          reportError(e, stack, context: 'while sealing plaintext entries');
        }
        report(
          MigrationStatus(
            unreachable ? MigrationPhase.waiting : MigrationPhase.failed,
            state.sealed,
          ),
        );
        retry = Timer(migrationRetryDelay, ref.invalidateSelf);
      }
    });
    return MigrationStatus.idle;
  }
}
