import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// Seals a whole file with the journal key. [context] names the user and the
/// file, so a file copied from another user or renamed fails to open.
abstract interface class FileSealer {
  Future<Uint8List> sealFile(List<int> bytes, {required String context});

  Future<Uint8List> openFile(List<int> envelope, {required String context});
}

/// Unlike a document path (`vices/{id}`), which [FieldSealer] binds to, so
/// no device file opens as a document field or the other way round.
String deviceFileContext(String uid, String name) =>
    'device-file/v1/${uid.length}:$uid/$name';

final RegExp _fileName = RegExp(r'^[a-z0-9-]{1,80}$');

String _baseName(FileSystemEntity e) =>
    e.path.substring(e.path.lastIndexOf(Platform.pathSeparator) + 1);

/// The device's files that hold journal content, findings or Health-derived
/// values: Caches/sealed, one folder per user, each file sealed with that
/// user's journal key. Caches is left out of backups.
class DeviceFiles {
  DeviceFiles({Future<Directory> Function()? caches})
    : _caches = caches ?? getApplicationCacheDirectory;

  final Future<Directory> Function() _caches;

  static const String folder = 'sealed';

  /// The plaintext store builds before sealing wrote; deleted, never read.
  static const List<String> legacy = <String>[
    'health-daily.json',
    'health-daily.json.next',
  ];

  /// Sign-out and account deletion. Never throws.
  Future<void> clearAll() async {
    try {
      final Directory caches = await _caches();
      final Directory sealed = Directory('${caches.path}/$folder');
      if (await sealed.exists()) await sealed.delete(recursive: true);
      await _deleteLegacy(caches);
    } catch (_) {
      // Left for the next sign-in's first use, which removes other users'.
    }
  }

  /// At launch, whether or not a key loads. Never throws.
  Future<void> deleteLegacy() async {
    try {
      await _deleteLegacy(await _caches());
    } catch (_) {
      // Tried again next launch.
    }
  }

  SealedFiles forUser(String uid, FileSealer sealer) =>
      SealedFiles._(this, uid, sealer);

  Future<Directory> _userFolder(String uid) async {
    final Directory caches = await _caches();
    final String mine = _folderName(uid);
    final Directory sealed = Directory('${caches.path}/$folder');
    // Another user's files go on this user's first use: a uid change.
    if (await sealed.exists()) {
      await for (final FileSystemEntity e in sealed.list(followLinks: false)) {
        if (_baseName(e) != mine) {
          await e.delete(recursive: true);
        }
      }
    }
    await _deleteLegacy(caches);
    return Directory('${sealed.path}/$mine');
  }

  static Future<void> _deleteLegacy(Directory caches) async {
    for (final String name in legacy) {
      final File file = File('${caches.path}/$name');
      if (await file.exists()) await file.delete();
    }
  }

  static String _folderName(String uid) =>
      base64Url.encode(utf8.encode(uid)).replaceAll('=', '');
}

/// One user's sealed device files. Every read treats a missing, corrupt or
/// unopenable file as absent and deletes it.
class SealedFiles {
  SealedFiles._(this._files, this.uid, this._sealer);

  final DeviceFiles _files;
  final String uid;
  final FileSealer _sealer;
  Directory? _dir;

  Future<Directory> _folder() async => _dir ??= await _files._userFolder(uid);

  File _file(Directory dir, String name) {
    if (!_fileName.hasMatch(name)) {
      throw ArgumentError.value(name, 'name', 'not a device file name');
    }
    return File('${dir.path}/$name');
  }

  /// Null when absent or when it will not open. Never throws.
  Future<Uint8List?> read(String name) async {
    File? file;
    try {
      file = _file(await _folder(), name);
      if (!await file.exists()) return null;
      return await _sealer.openFile(
        await file.readAsBytes(),
        context: deviceFileContext(uid, name),
      );
    } catch (_) {
      try {
        await file?.delete();
      } catch (_) {
        // Read as absent either way.
      }
      return null;
    }
  }

  /// Replaces [name] whole or not at all. Throws when it cannot.
  Future<void> write(String name, List<int> bytes) async {
    final Uint8List sealed = await _sealer.sealFile(
      bytes,
      context: deviceFileContext(uid, name),
    );
    final Directory dir = await _folder();
    await dir.create(recursive: true);
    final File file = _file(dir, name);
    final File next = File('${file.path}.next');
    await next.writeAsBytes(sealed, flush: true);
    await next.rename(file.path);
  }

  Future<void> delete(String name) async {
    final File file = _file(await _folder(), name);
    if (await file.exists()) await file.delete();
  }

  /// The names of the files kept, none of a half-written one.
  Future<List<String>> names() async {
    final Directory dir = await _folder();
    if (!await dir.exists()) return const <String>[];
    return <String>[
      await for (final FileSystemEntity e in dir.list(followLinks: false))
        if (e is File && _fileName.hasMatch(_baseName(e))) _baseName(e),
    ];
  }
}
