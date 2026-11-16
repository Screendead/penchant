import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tracker/account/account.dart';
import 'package:tracker/backup/backup_file.dart';
import 'package:tracker/backup/restore.dart';
import 'package:tracker/crypto/journal_key.dart';
import 'package:tracker/crypto/key_service.dart';
import 'package:tracker/crypto/native_aes.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/errors/report_error.dart';
import 'package:tracker/providers/user_provider.dart';

/// What a backup needs of the signed-in account's key: the key itself, the
/// server's record of it (whose wrapped copy the file carries), and the
/// recovery key when this device holds it, to check the file opens.
class BackupKey {
  const BackupKey({
    required this.uid,
    required this.journalKey,
    required this.record,
    this.recoveryKey,
  });

  final String uid;
  final JournalKey journalKey;
  final KeyRecord record;
  final Uint8List? recoveryKey;
}

/// Null while no key is ready and checked against the server's record. Only
/// the key service overrides it (`keyServiceOverrides`).
final backupKeyProvider = Provider<BackupKey?>((ref) => null);

class BackupCiphers {
  const BackupCiphers({required this.aes128, required this.aes256});

  final AesGcm aes128;
  final AesGcm aes256;
}

final backupCiphersProvider = Provider<BackupCiphers>(
  (ref) => BackupCiphers(
    aes128: nativeAesGcm(secretKeyLength: 16),
    aes256: nativeAesGcm(secretKeyLength: 32),
  ),
);

/// The system's save panel and file picker. Nothing is kept: the iOS side
/// deletes the file it hands the export panel once the panel closes.
abstract interface class BackupFiles {
  /// True once saved; false when the person cancelled.
  Future<bool> save(Uint8List bytes, String name);

  /// Null when the person cancelled.
  Future<Uint8List?> pick();
}

class ChannelBackupFiles implements BackupFiles {
  const ChannelBackupFiles();

  static const MethodChannel _channel = MethodChannel(
    'com.screendead.penchant/backup_files',
  );

  @override
  Future<bool> save(Uint8List bytes, String name) async =>
      await _channel.invokeMethod<bool>('save', <String, Object>{
        'bytes': bytes,
        'name': name,
      }) ??
      false;

  @override
  Future<Uint8List?> pick() => _channel.invokeMethod<Uint8List>('pick');
}

final backupFilesProvider = Provider<BackupFiles>(
  (ref) => const ChannelBackupFiles(),
);

final restoreTargetProvider = Provider<RestoreTarget>(
  (ref) => FirestoreRestoreTarget(FirebaseFirestore.instance),
);

/// The file did not open with this device's own recovery key, so it would be
/// no use; it is not offered to the save panel.
class BackupSelfCheckFailed implements Exception {
  const BackupSelfCheckFailed(this.cause);

  final Object cause;
}

/// Reads the journal from the server and seals it into a backup file. Opens
/// the result again with this device's recovery key, when it holds one, and
/// checks every document came back.
Future<Uint8List> makeBackup({
  required Account account,
  required BackupKey key,
  required BackupCiphers ciphers,
  required DateTime now,
}) async {
  final Map<String, List<StoredDocument>> stored = await account.fetchStored();
  final Uint8List bytes = await BackupFile.write(
    uid: key.uid,
    journalKey: key.journalKey,
    record: key.record,
    collections: stored,
    aes256: ciphers.aes256,
    createdAt: now,
  );
  final Uint8List? recovery = key.recoveryKey;
  if (recovery != null) {
    try {
      final OpenedBackup opened = await BackupFile.open(
        bytes,
        recoveryKey: recovery,
        aes128: ciphers.aes128,
        aes256: ciphers.aes256,
      );
      for (final MapEntry<String, List<StoredDocument>>(:key, :value)
          in stored.entries) {
        if (opened.collections[key]?.length != value.length) {
          throw StateError('$key came back with a different count');
        }
      }
    } on Object catch (e) {
      throw BackupSelfCheckFailed(e);
    }
  }
  return bytes;
}

String backupFileName(DateTime now) {
  String two(int n) => n.toString().padLeft(2, '0');
  return 'Penchant backup ${now.year}-${two(now.month)}-${two(now.day)}'
      '.penchantbackup';
}

/// When this device last saved a backup for the signed-in user, and last
/// put the monthly offer away. Per device, in shared_preferences: nothing about
/// backups reaches the server.
class BackupDates {
  const BackupDates({this.savedAt, this.dismissedAt, this.loaded = false});

  final DateTime? savedAt;
  final DateTime? dismissedAt;
  final bool loaded;
}

final backupDatesProvider = NotifierProvider<BackupDatesNotifier, BackupDates>(
  BackupDatesNotifier.new,
);

class BackupDatesNotifier extends Notifier<BackupDates> {
  static String savedKey(String uid) => 'backup.savedAt.$uid';
  static String dismissedKey(String uid) => 'backup.offerDismissedAt.$uid';

  String? get _uid => ref.read(userProvider).value?.uid;

  @override
  BackupDates build() {
    final String? uid = ref.watch(userProvider.select((v) => v.value?.uid));
    if (uid != null) {
      _load(uid);
    }
    return const BackupDates();
  }

  Future<void> _load(String uid) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      DateTime? at(String key) => switch (prefs.getInt(key)) {
        final int ms => DateTime.fromMillisecondsSinceEpoch(ms),
        null => null,
      };
      if (_uid == uid) {
        state = BackupDates(
          savedAt: at(savedKey(uid)),
          dismissedAt: at(dismissedKey(uid)),
          loaded: true,
        );
      }
    } catch (e, stack) {
      reportError(e, stack, context: 'while reading the backup dates');
    }
  }

  Future<void> markSaved(DateTime at) => _set(savedKey, at, saved: true);

  Future<void> dismissOffer(DateTime at) => _set(dismissedKey, at);

  Future<void> _set(
    String Function(String) key,
    DateTime at, {
    bool saved = false,
  }) async {
    final String? uid = _uid;
    if (uid == null) {
      return;
    }
    state = BackupDates(
      savedAt: saved ? at : state.savedAt,
      dismissedAt: saved ? state.dismissedAt : at,
      loaded: true,
    );
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setInt(key(uid), at.millisecondsSinceEpoch);
    } catch (e, stack) {
      reportError(e, stack, context: 'while saving a backup date');
    }
  }
}

const int backupOfferEveryDays = 30;

/// Whether Today offers a backup: once the recovery key is saved (a backup
/// opens only with it), the key is a month old, and neither a backup nor a
/// dismissal on this device is from the last month.
bool backupOfferDue({
  required bool recoveryKeySaved,
  required DateTime? keyCreatedAt,
  required BackupDates dates,
  required DateTime today,
}) {
  if (!recoveryKeySaved || keyCreatedAt == null || !dates.loaded) {
    return false;
  }
  bool recent(DateTime? at) =>
      at != null &&
      today.isBefore(addDays(startOfDay(at), backupOfferEveryDays));
  return !recent(keyCreatedAt) &&
      !recent(dates.savedAt) &&
      !recent(dates.dismissedAt);
}
