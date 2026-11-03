import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/dart.dart';

/// A 128-bit recovery key written as 32 Crockford base32 characters in 8
/// groups of 4: 26 characters carry the key, the rest a 32-bit checksum
/// (the first 4 bytes of SHA-256 over the key). The checksum is long enough to
/// locate one mistyped character by trying every substitution.
class RecoveryKey {
  RecoveryKey._();

  static const String alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
  static const int keyLength = 16;
  static const int checksumLength = 4;
  static const int characters = 32;
  static const int groupSize = 4;
  static const int groups = characters ~/ groupSize;

  static Uint8List generate([Random? random]) {
    final Random source = random ?? Random.secure();
    return Uint8List.fromList(
      List<int>.generate(keyLength, (_) => source.nextInt(256)),
    );
  }

  static String format(Uint8List key) {
    if (key.length != keyLength) {
      throw ArgumentError('A recovery key is $keyLength bytes');
    }

    final String plain = _encode(_withChecksum(key));
    return <String>[
      for (int g = 0; g < groups; g++)
        plain.substring(g * groupSize, (g + 1) * groupSize),
    ].join('-');
  }

  static List<String> groupsOf(String formatted) => formatted.split('-');

  /// Upper-cases, reads I and L as 1 and O as 0, and drops spaces and hyphens.
  static String normalise(String input) {
    final StringBuffer out = StringBuffer();
    for (final int rune in input.toUpperCase().runes) {
      final String c = String.fromCharCode(rune);
      switch (c) {
        case ' ' || '-' || '\t' || '\n':
          continue;
        case 'I' || 'L':
          out.write('1');
        case 'O':
          out.write('0');
        default:
          out.write(c);
      }
    }
    return out.toString();
  }

  static RecoveryKeyParse parse(String input) {
    final String plain = normalise(input);

    for (int i = 0; i < plain.length; i++) {
      if (!alphabet.contains(plain[i])) {
        return RecoveryKeyBadCharacter(position: i + 1, character: plain[i]);
      }
    }

    if (plain.length != characters) {
      return RecoveryKeyWrongLength(plain.length);
    }

    final Uint8List? key = _verified(plain);

    if (key != null) {
      return RecoveryKeyOk(key);
    }

    final List<int> suspects = <int>[];
    for (int i = 0; i < characters && suspects.length < 2; i++) {
      for (final String c in alphabet.split('')) {
        if (c == plain[i]) {
          continue;
        }

        final String candidate = plain.replaceRange(i, i + 1, c);
        if (_verified(candidate) != null) {
          suspects.add(i + 1);
          break;
        }
      }
    }

    // Two candidate positions would mean a guess, so only one is reported.
    return RecoveryKeyTypo(position: suspects.length == 1 ? suspects.single : null);
  }

  static Uint8List? _verified(String plain) {
    final Uint8List bytes = _decode(plain);
    final Uint8List key = bytes.sublist(0, keyLength);
    final Uint8List expected = _withChecksum(key);

    for (int i = 0; i < expected.length; i++) {
      if (expected[i] != bytes[i]) {
        return null;
      }
    }

    return key;
  }

  static Uint8List _withChecksum(Uint8List key) {
    final List<int> digest = const DartSha256().hashSync(key).bytes;
    return Uint8List.fromList(<int>[...key, ...digest.take(checksumLength)]);
  }

  static String _encode(Uint8List bytes) {
    final StringBuffer out = StringBuffer();
    int buffer = 0;
    int bits = 0;

    for (final int byte in bytes) {
      buffer = ((buffer << 8) | byte) & 0xfff;
      bits += 8;
      while (bits >= 5) {
        bits -= 5;
        out.write(alphabet[(buffer >> bits) & 31]);
      }
    }

    return out.toString();
  }

  static Uint8List _decode(String plain) {
    final BytesBuilder out = BytesBuilder();
    int buffer = 0;
    int bits = 0;

    for (int i = 0; i < plain.length; i++) {
      buffer = ((buffer << 5) | alphabet.indexOf(plain[i])) & 0xfff;
      bits += 5;
      if (bits >= 8) {
        bits -= 8;
        out.addByte((buffer >> bits) & 0xff);
      }
    }

    return out.toBytes();
  }
}

sealed class RecoveryKeyParse {
  const RecoveryKeyParse();
}

class RecoveryKeyOk extends RecoveryKeyParse {
  const RecoveryKeyOk(this.key);

  final Uint8List key;
}

class RecoveryKeyBadCharacter extends RecoveryKeyParse {
  const RecoveryKeyBadCharacter({
    required this.position,
    required this.character,
  });

  /// 1-based, counted after spaces and hyphens are dropped.
  final int position;
  final String character;
}

class RecoveryKeyWrongLength extends RecoveryKeyParse {
  const RecoveryKeyWrongLength(this.length);

  final int length;
}

class RecoveryKeyTypo extends RecoveryKeyParse {
  const RecoveryKeyTypo({required this.position});

  /// 1-based; null when no single substitution explains the mismatch.
  final int? position;

  int? get group =>
      position == null ? null : (position! - 1) ~/ RecoveryKey.groupSize + 1;
}
