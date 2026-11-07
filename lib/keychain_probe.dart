import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:tracker/crypto/key_store.dart';

/// Built with `--dart-define=KEYCHAIN_PROBE=true`, the app is this one screen
/// and never starts Firebase. A const false compiles the probe out of every
/// other build.
const bool keychainProbe = bool.fromEnvironment('KEYCHAIN_PROBE');

@immutable
class ProbeItem {
  const ProbeItem({
    required this.code,
    required this.writtenOn,
    required this.writtenAt,
    required this.location,
  });

  final String code;
  final String writtenOn;
  final DateTime? writtenAt;
  final KeyLocation location;
}

@immutable
class ProbeReading {
  const ProbeReading({this.item, this.syncedError});

  final ProbeItem? item;

  /// The keychain's refusal of the synced read or write, as code: message.
  final String? syncedError;
}

/// One test item stored with the journal key's exact keychain attributes
/// ([KeyStore.syncedIOS] and the rest), under its own name.
class KeychainProbe {
  KeychainProbe([FlutterSecureStorage? storage, Random? random])
    : _storage = storage ?? const FlutterSecureStorage(),
      _random = random ?? Random.secure();

  final FlutterSecureStorage _storage;
  final Random _random;

  static const String itemName = 'keychain-sync-probe';

  static const String _alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  Future<ProbeReading> read() async {
    String? syncedError;
    try {
      final String? synced = await _storage.read(
        key: itemName,
        iOptions: KeyStore.syncedIOS,
        mOptions: KeyStore.syncedMac,
      );
      if (synced != null) {
        return ProbeReading(item: _decode(synced, KeyLocation.synced));
      }
    } on PlatformException catch (e) {
      syncedError = _describe(e);
    }
    final String? local = await _storage.read(
      key: itemName,
      iOptions: KeyStore.localIOS,
      mOptions: KeyStore.localMac,
    );
    return ProbeReading(
      item: local == null ? null : _decode(local, KeyLocation.thisDevice),
      syncedError: syncedError,
    );
  }

  /// Writes a new random code, synced where the keychain allows it and
  /// this-device-only where it refuses, as [KeyStore.save] does.
  Future<ProbeReading> write({required String writtenOn, DateTime? at}) async {
    final String value = jsonEncode(<String, String>{
      'code': List<String>.generate(
        8,
        (_) => _alphabet[_random.nextInt(_alphabet.length)],
      ).join(),
      'on': writtenOn,
      'at': (at ?? DateTime.now()).toUtc().toIso8601String(),
    });
    try {
      await _storage.write(
        key: itemName,
        value: value,
        iOptions: KeyStore.syncedIOS,
        mOptions: KeyStore.syncedMac,
      );
      return ProbeReading(item: _decode(value, KeyLocation.synced));
    } on PlatformException catch (e) {
      await _storage.write(
        key: itemName,
        value: value,
        iOptions: KeyStore.localIOS,
        mOptions: KeyStore.localMac,
      );
      return ProbeReading(
        item: _decode(value, KeyLocation.thisDevice),
        syncedError: _describe(e),
      );
    }
  }

  /// Deleting the synced item deletes it on every device on the Apple ID.
  Future<void> delete() async {
    await _storage.delete(
      key: itemName,
      iOptions: KeyStore.syncedIOS,
      mOptions: KeyStore.syncedMac,
    );
    await _storage.delete(
      key: itemName,
      iOptions: KeyStore.localIOS,
      mOptions: KeyStore.localMac,
    );
  }

  static String _describe(PlatformException e) =>
      e.message == null ? e.code : '${e.code}: ${e.message}';

  static ProbeItem _decode(String value, KeyLocation location) {
    final Object? map = jsonDecode(value);
    if (map is! Map<String, dynamic> || map['code'] is! String) {
      return ProbeItem(
        code: value,
        writtenOn: 'unknown',
        writtenAt: null,
        location: location,
      );
    }
    return ProbeItem(
      code: map['code'] as String,
      writtenOn: map['on'] is String ? map['on'] as String : 'unknown',
      writtenAt: map['at'] is String
          ? DateTime.tryParse(map['at'] as String)?.toLocal()
          : null,
      location: location,
    );
  }
}

String deviceKindOf(TargetPlatform platform) => switch (platform) {
  TargetPlatform.iOS => 'iPhone',
  TargetPlatform.macOS => 'Mac',
  _ => platform.name,
};

class KeychainProbeApp extends StatelessWidget {
  const KeychainProbeApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Keychain sync probe',
    home: KeychainProbeScreen(
      probe: KeychainProbe(),
      deviceKind: deviceKindOf(defaultTargetPlatform),
    ),
  );
}

class KeychainProbeScreen extends StatefulWidget {
  const KeychainProbeScreen({
    super.key,
    required this.probe,
    required this.deviceKind,
  });

  final KeychainProbe probe;
  final String deviceKind;

  @override
  State<KeychainProbeScreen> createState() => _KeychainProbeScreenState();
}

class _KeychainProbeScreenState extends State<KeychainProbeScreen> {
  ProbeReading? _reading;
  String? _error;
  bool _busy = true;
  DateTime? _readAt;

  @override
  void initState() {
    super.initState();
    _run(widget.probe.read);
  }

  Future<void> _run(Future<ProbeReading> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final ProbeReading reading = await action();
      if (!mounted) return;
      setState(() {
        _reading = reading;
        _readAt = DateTime.now();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<ProbeReading> _delete() async {
    await widget.probe.delete();
    return widget.probe.read();
  }

  static String _time(DateTime t) => <int>[
    t.hour,
    t.minute,
    t.second,
  ].map((int n) => n.toString().padLeft(2, '0')).join(':');

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ProbeItem? item = _reading?.item;
    final String? syncedError = _reading?.syncedError;
    return Scaffold(
      appBar: AppBar(title: const Text('Keychain sync probe')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            Text('This device: ${widget.deviceKind}', style: text.titleMedium),
            const SizedBox(height: 16),
            if (_reading == null && _busy)
              const Center(child: CircularProgressIndicator())
            else if (item == null)
              Text('No test value on this device.', style: text.bodyLarge)
            else ...<Widget>[
              SelectableText(
                item.code,
                style: text.displaySmall?.copyWith(
                  fontFamily: 'Courier',
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Written on ${item.writtenOn}'
                '${item.writtenAt == null ? '' : ' at ${_time(item.writtenAt!)}'}',
              ),
              Text(switch (item.location) {
                KeyLocation.synced => 'Stored synced (iCloud Keychain).',
                KeyLocation.thisDevice =>
                  'Stored on this device only: the synced keychain refused it.',
              }),
            ],
            if (syncedError != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                'Synced keychain error: $syncedError',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            if (_error != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                'Error: $_error',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            if (_readAt != null) ...<Widget>[
              const SizedBox(height: 8),
              Text('Last read at ${_time(_readAt!)}', style: text.bodySmall),
            ],
            const SizedBox(height: 24),
            if (_reading != null && item == null)
              FilledButton(
                onPressed: _busy
                    ? null
                    : () => _run(
                        () => widget.probe.write(writtenOn: widget.deviceKind),
                      ),
                child: const Text('Write test value'),
              ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _busy ? null : () => _run(widget.probe.read),
              child: const Text('Read again'),
            ),
            if (item != null) ...<Widget>[
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _busy ? null : () => _run(_delete),
                child: const Text('Delete test value'),
              ),
            ],
            const SizedBox(height: 24),
            Text(
              "Item '${KeychainProbe.itemName}', with the journal key's "
              'attributes: synchronizable, accessible after first unlock, '
              "the app's default access group. Touches no Firestore data.",
              style: text.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
