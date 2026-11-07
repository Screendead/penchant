import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

/// A keychain that keeps synced and this-device items apart, as the real one
/// does, and can refuse synced items like a build without the entitlement.
class FakeKeychain extends Fake implements FlutterSecureStorage {
  FakeKeychain({this.refuseSynced = false, this.refuseSyncedReads = false});

  final bool refuseSynced;

  /// The real keychain, refusing synced items, refuses the synced lookup too.
  final bool refuseSyncedReads;
  final Map<(String, bool), String> items = <(String, bool), String>{};

  static bool _synced(AppleOptions? i, AppleOptions? m) {
    expect(i?.synchronizable, m?.synchronizable, reason: 'iOS and macOS agree');
    return i?.synchronizable ?? false;
  }

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    final bool synced = _synced(iOptions, mOptions);
    if (synced && refuseSyncedReads) {
      throw PlatformException(
        code: '-34018',
        message: 'errSecMissingEntitlement',
      );
    }
    return items[(key, synced)];
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    final bool synced = _synced(iOptions, mOptions);
    if (synced && refuseSynced) {
      throw PlatformException(
        code: '-34018',
        message: 'errSecMissingEntitlement',
      );
    }
    items[(key, synced)] = value!;
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    items.remove((key, _synced(iOptions, mOptions)));
  }
}
