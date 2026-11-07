import 'dart:developer' as developer;

import 'package:cryptography/cryptography.dart';
import 'package:cryptography_flutter/cryptography_flutter.dart';
import 'package:flutter/foundation.dart';

/// AES-GCM through CryptoKit, with no silent fallback to Dart.
///
/// FlutterCipher.defaultChannelPolicy sends anything under 2000 bytes to the
/// pure-Dart fallback, which is every blob this app writes; and when the
/// plugin is missing, FlutterAesGcm quietly uses BackgroundAesGcm. Either
/// would move the app into another export-compliance row, so the policy here
/// routes every length to the plugin and the fallback refuses.
AesGcm nativeAesGcm({required int secretKeyLength}) => FlutterAesGcm(
  secretKeyLength: secretKeyLength,
  channelPolicy: const CryptographyChannelPolicy(minLength: 0, maxLength: null),
  fallback: RefusingAesGcm(secretKeyLength),
);

class NativeAesUnavailable extends StateError {
  NativeAesUnavailable(super.message);
}

class RefusingAesGcm extends AesGcm {
  RefusingAesGcm(this.secretKeyLength) : super.constructor();

  @override
  final int secretKeyLength;

  @override
  int get nonceLength => AesGcm.defaultNonceLength;

  @override
  Future<List<int>> decrypt(
    SecretBox secretBox, {
    required SecretKey secretKey,
    List<int> aad = const <int>[],
    Uint8List? possibleBuffer,
  }) => throw NativeAesUnavailable('AES-GCM would have run in Dart');

  @override
  Future<SecretBox> encrypt(
    List<int> clearText, {
    required SecretKey secretKey,
    List<int>? nonce,
    List<int> aad = const <int>[],
    Uint8List? possibleBuffer,
  }) => throw NativeAesUnavailable('AES-GCM would have run in Dart');
}

/// NIST GCM test case 14: AES-256, zero key, zero nonce, 16 zero bytes.
const List<int> kat14CipherText = <int>[
  0xce, 0xa7, 0x40, 0x3d, 0x4d, 0x60, 0x6b, 0x6e, //
  0x07, 0x4e, 0xc5, 0xd3, 0xba, 0xf3, 0x9d, 0x18,
];
const List<int> kat14Tag = <int>[
  0xd0, 0xd1, 0xc8, 0xa7, 0x99, 0x99, 0x6b, 0xf0, //
  0x26, 0x5b, 0x98, 0xb5, 0xd4, 0x8a, 0xb9, 0x19,
];

class NativeAesReport {
  NativeAesReport({
    required this.pluginPresent,
    required this.cupertino,
    required this.knownAnswer,
    required this.elapsed,
  });

  final bool pluginPresent;
  final bool cupertino;
  final bool knownAnswer;
  final Duration elapsed;

  bool get native => pluginPresent && cupertino && knownAnswer;

  @override
  String toString() =>
      'native AES-GCM: $native (plugin $pluginPresent, cupertino $cupertino, '
      'NIST case 14 $knownAnswer, ${elapsed.inMicroseconds} us)';
}

/// Runs NIST case 14 through [aes]. With [nativeAesGcm] a Dart path throws
/// [NativeAesUnavailable], so a passing known answer means CryptoKit ran.
Future<NativeAesReport> checkNativeAesGcm(AesGcm aes) async {
  final Stopwatch watch = Stopwatch()..start();
  bool knownAnswer = false;

  try {
    final SecretBox box = await aes.encrypt(
      List<int>.filled(16, 0),
      secretKey: SecretKey(List<int>.filled(32, 0)),
      nonce: List<int>.filled(12, 0),
    );
    knownAnswer =
        listEquals(box.cipherText, kat14CipherText) &&
        listEquals(box.mac.bytes, kat14Tag);
  } on NativeAesUnavailable {
    knownAnswer = false;
  }

  final NativeAesReport report = NativeAesReport(
    pluginPresent: FlutterCryptography.isPluginPresent,
    cupertino:
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS,
    knownAnswer: knownAnswer,
    elapsed: watch.elapsed,
  );
  developer.log(report.toString(), name: 'penchant.crypto');
  return report;
}
