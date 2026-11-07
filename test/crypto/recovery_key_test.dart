import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/crypto/recovery_key.dart';

void main() {
  final Uint8List key = RecoveryKey.generate(Random(7));
  final String formatted = RecoveryKey.format(key);

  test('formats as 8 groups of 4 Crockford characters', () {
    expect(
      formatted,
      matches(RegExp(r'^([0-9A-HJKMNP-TV-Z]{4}-){7}[0-9A-HJKMNP-TV-Z]{4}$')),
    );
  });

  test('round trips', () {
    final RecoveryKeyParse parsed = RecoveryKey.parse(formatted);
    expect(parsed, isA<RecoveryKeyOk>());
    expect((parsed as RecoveryKeyOk).key, key);
  });

  test('ignores case, spaces and hyphens', () {
    final String typed = '  ${formatted.toLowerCase().replaceAll('-', ' ')} ';
    expect((RecoveryKey.parse(typed) as RecoveryKeyOk).key, key);
  });

  test('reads I and L as 1 and O as 0', () {
    // A key whose text holds both a 1 and a 0, found deterministically.
    final Random random = Random(1);
    late Uint8List k;
    late String f;
    do {
      k = RecoveryKey.generate(random);
      f = RecoveryKey.format(k);
    } while (!f.contains('1') || !f.contains('0'));

    final String misread = f
        .replaceFirst('1', 'I')
        .replaceFirst('1', 'l')
        .replaceAll('0', 'O');
    expect((RecoveryKey.parse(misread) as RecoveryKeyOk).key, k);
  });

  test('locates one wrong character, by position and group', () {
    final String plain = RecoveryKey.normalise(formatted);
    for (final int position in <int>[1, 14, 32]) {
      final String original = plain[position - 1];
      final String wrong = original == 'X' ? 'Y' : 'X';
      final String typo = plain.replaceRange(position - 1, position, wrong);

      final RecoveryKeyParse parsed = RecoveryKey.parse(typo);
      expect(parsed, isA<RecoveryKeyTypo>());
      expect((parsed as RecoveryKeyTypo).position, position);
      expect(parsed.group, (position - 1) ~/ 4 + 1);
    }
  });

  test('two wrong characters are a mismatch with no position', () {
    final String plain = RecoveryKey.normalise(formatted);
    String flip(String s, int i) =>
        s.replaceRange(i, i + 1, s[i] == 'X' ? 'Y' : 'X');
    final RecoveryKeyParse parsed = RecoveryKey.parse(flip(flip(plain, 3), 20));
    expect(parsed, isA<RecoveryKeyTypo>());
    expect((parsed as RecoveryKeyTypo).position, isNull);
  });

  test('a character outside the alphabet is reported where it is', () {
    final String withU = formatted.replaceRange(5, 6, 'U');
    final RecoveryKeyParse parsed = RecoveryKey.parse(withU);
    expect(parsed, isA<RecoveryKeyBadCharacter>());
    expect((parsed as RecoveryKeyBadCharacter).position, 5);
    expect(parsed.character, 'U');
  });

  test('a short key reports its length', () {
    final RecoveryKeyParse parsed = RecoveryKey.parse(
      formatted.substring(0, 30),
    );
    expect((parsed as RecoveryKeyWrongLength).length, 24);
  });

  test('round trips 1,000 random keys', () {
    final Random random = Random(11);
    for (int i = 0; i < 1000; i++) {
      final Uint8List k = RecoveryKey.generate(random);
      expect(
        (RecoveryKey.parse(RecoveryKey.format(k)) as RecoveryKeyOk).key,
        k,
      );
    }
  });

  test('no single substitution passes the checksum', () {
    final String plain = RecoveryKey.normalise(formatted);
    for (int i = 0; i < plain.length; i++) {
      for (final String c in RecoveryKey.alphabet.split('')) {
        if (c == plain[i]) {
          continue;
        }
        expect(
          RecoveryKey.parse(plain.replaceRange(i, i + 1, c)),
          isA<RecoveryKeyTypo>(),
          reason: 'position ${i + 1} as $c',
        );
      }
    }
  });

  test('refuses to format a key of the wrong length', () {
    expect(() => RecoveryKey.format(Uint8List(32)), throwsArgumentError);
  });
}
