import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/crypto/journal_cipher.dart';
import 'package:tracker/crypto/native_aes.dart';

JournalCipher cipherWith(int fill) => JournalCipher(
  aes: AesGcm.with256bits(),
  key: SecretKey(List<int>.filled(32, fill)),
);

void main() {
  final JournalCipher cipher = cipherWith(1);

  Future<Uint8List> sealActivity({
    String docId = 'act1',
    String ownerID = 'alice',
    String viceID = 'vice1',
    Map<String, Object?> fields = const {'q': 3},
  }) => cipher.seal(
    collection: 'activities',
    docId: docId,
    ownerID: ownerID,
    viceID: viceID,
    fields: fields,
  );

  Future<Map<String, dynamic>> openActivity(
    List<int> blob, {
    JournalCipher? using,
    String collection = 'activities',
    String docId = 'act1',
    String ownerID = 'alice',
    String? viceID = 'vice1',
  }) => (using ?? cipher).open(
    collection: collection,
    docId: docId,
    ownerID: ownerID,
    viceID: viceID,
    blob: blob,
  );

  Future<int> viceBlobLength(String name) async => (await cipher.seal(
    collection: 'vices',
    docId: 'v',
    ownerID: 'alice',
    fields: {'n': name, 'u': 'drink'},
  )).length;

  test('round trip', () async {
    final Uint8List blob = await sealActivity(fields: {'q': 12, 'note': 'é'});
    expect(await openActivity(blob), {'q': 12, 'note': 'é'});
  });

  test('two seals of the same fields differ (random nonce)', () async {
    expect(await sealActivity(), isNot(equals(await sealActivity())));
  });

  test('a wrong key is rejected', () async {
    final Uint8List blob = await sealActivity();
    await expectLater(
      openActivity(blob, using: cipherWith(2)),
      throwsA(isA<SecretBoxAuthenticationError>()),
    );
  });

  test('a flipped bit anywhere after the version byte is rejected', () async {
    final Uint8List blob = await sealActivity();
    for (final int i in <int>[1, 12, 13, 40, blob.length - 1]) {
      final Uint8List tampered = Uint8List.fromList(blob);
      tampered[i] ^= 0x01;
      await expectLater(
        openActivity(tampered),
        throwsA(isA<SecretBoxAuthenticationError>()),
        reason: 'byte $i',
      );
    }
  });

  test('a blob moved to another document, owner, vice or collection is '
      'rejected (AAD)', () async {
    final Uint8List blob = await sealActivity();
    for (final Future<Map<String, dynamic>> Function() attempt in [
      () => openActivity(blob, docId: 'act2'),
      () => openActivity(blob, ownerID: 'bob'),
      () => openActivity(blob, viceID: 'vice2'),
      () => openActivity(blob, viceID: null),
      () => openActivity(blob, collection: 'vices', viceID: null),
    ]) {
      await expectLater(attempt(), throwsA(isA<SecretBoxAuthenticationError>()));
    }
  });

  test('a wrong length or version is refused before decrypting', () async {
    final Uint8List blob = await sealActivity();
    await expectLater(
      openActivity(blob.sublist(0, blob.length - 1)),
      throwsA(isA<JournalCipherException>()),
    );
    final Uint8List v2 = Uint8List.fromList(blob)..[0] = 2;
    await expectLater(openActivity(v2), throwsA(isA<JournalCipherException>()));
  });

  test('the AAD string is the documented one', () {
    expect(
      utf8.decode(JournalCipher.aadFor(
        collection: 'activities',
        docId: 'a',
        ownerID: 'o',
        viceID: 'v',
      )),
      'tracker:v1:activities:a:o:v',
    );
    expect(
      utf8.decode(JournalCipher.aadFor(collection: 'vices', docId: 'a', ownerID: 'o')),
      'tracker:v1:vices:a:o',
    );
  });

  group('bucket lengths', () {
    test('blob lengths are 29 bytes over each bucket', () {
      expect(JournalCipher.blobLengths, [93, 285, 1053, 4125]);
    });

    test('firestore.rules accepts exactly these lengths', () {
      final String rules = File('firestore.rules').readAsStringSync();
      final RegExpMatch? match = RegExp(
        r'blobLengths\(\)\s*\{\s*return\s*\[([0-9,\s]+)\]',
      ).firstMatch(rules);
      expect(match, isNotNull, reason: 'firestore.rules defines blobLengths()');
      expect(
        match!.group(1)!.split(',').map((s) => int.parse(s.trim())).toList(),
        JournalCipher.blobLengths,
      );
    });

    test('an activity quantity seals to 93 bytes', () async {
      expect((await sealActivity(fields: {'q': 1})).length, 93);
      expect((await sealActivity(fields: {'q': 999999999})).length, 93);
    });

    test('every vice is at least 285, so short and long names look alike', () async {
      expect(await viceBlobLength('A'), 285);
      expect(await viceBlobLength('x' * 60), 285);
    });

    test('a 60-code-unit emoji name (30 emoji, 120 UTF-8 bytes) is 285', () async {
      final String name = '🍺' * 30;
      expect(name.length, 60);
      expect(await viceBlobLength(name), 285);
    });

    test('a 60-character escaped-quote name (120 JSON bytes) is 285', () async {
      final String name = '"' * 60;
      expect(utf8.encode(jsonEncode(name)).length, 122);
      expect(await viceBlobLength(name), 285);
    });

    test('the worst case, 60 control characters escaped as \\u00XX, is 1053', () async {
      expect(await viceBlobLength('\u0001' * 60), 1053);
    });

    test('fields over the largest bucket are refused', () async {
      await expectLater(
        sealActivity(fields: {'note': 'x' * 4100}),
        throwsA(isA<JournalCipherException>()),
      );
    });
  });

  test('the NIST vector checkNativeAesGcm uses matches AES-256-GCM', () async {
    final SecretBox box = await AesGcm.with256bits().encrypt(
      List<int>.filled(16, 0),
      secretKey: SecretKey(List<int>.filled(32, 0)),
      nonce: List<int>.filled(12, 0),
    );
    expect(box.cipherText, kat14CipherText);
    expect(box.mac.bytes, kat14Tag);
  });

  test('off a device the native check fails rather than run in Dart', () async {
    final NativeAesReport report = await checkNativeAesGcm(
      nativeAesGcm(secretKeyLength: 32),
    );
    expect(report.pluginPresent, isFalse);
    expect(report.knownAnswer, isFalse);
    expect(report.native, isFalse);
  });

  test('opens a blob sealed by the Node helper the rules tests use', () async {
    final Map<String, dynamic> fixture = jsonDecode(
      File('tests/firestore-rules/fixtures/node-sealed.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final JournalCipher node = JournalCipher(
      aes: AesGcm.with256bits(),
      key: SecretKey(base64.decode(fixture['dek'] as String)),
    );
    for (final Map<String, dynamic> doc
        in (fixture['docs'] as List).cast<Map<String, dynamic>>()) {
      expect(
        await node.open(
          collection: doc['collection'] as String,
          docId: doc['docId'] as String,
          ownerID: doc['ownerID'] as String,
          viceID: doc['viceID'] as String?,
          blob: base64.decode(doc['enc'] as String),
        ),
        doc['fields'],
      );
    }
  });
}
