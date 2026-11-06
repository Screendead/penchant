import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/crypto/native_aes.dart';

void main() {
  test('the known answer matches NIST GCM test case 14', () async {
    final SecretBox box = await AesGcm.with256bits().encrypt(
      List<int>.filled(16, 0),
      secretKey: SecretKey(List<int>.filled(32, 0)),
      nonce: List<int>.filled(12, 0),
    );
    expect(box.cipherText, kat14CipherText);
    expect(box.mac.bytes, kat14Tag);
  });

  test('the fallback refuses to run AES-GCM in Dart', () async {
    final RefusingAesGcm refusing = RefusingAesGcm(32);
    expect(
      () => refusing.encrypt(<int>[
        1,
      ], secretKey: SecretKey(List<int>.filled(32, 0))),
      throwsA(isA<NativeAesUnavailable>()),
    );
  });

  test(
    'a Dart AES-GCM passes the known answer but is not reported native',
    () async {
      final NativeAesReport report = await checkNativeAesGcm(
        AesGcm.with256bits(),
      );
      expect(report.knownAnswer, isTrue);
      expect(report.native, isFalse);
    },
  );

  test(
    'without the plugin the native AES-GCM refuses instead of falling back',
    () async {
      final NativeAesReport report = await checkNativeAesGcm(
        nativeAesGcm(secretKeyLength: 32),
      );
      expect(report.native, isFalse);
    },
  );
}
