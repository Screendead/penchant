import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/crypto/journal_cipher.dart';
import 'package:tracker/crypto/journal_reader.dart';
import 'package:tracker/crypto/migrator.dart';
import 'package:tracker/data/unit.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/data/vice_activity.dart';

import 'fakes.dart';

void main() {
  final JournalCipher cipher = JournalCipher(
    aes: AesGcm.with256bits(),
    key: SecretKey(List<int>.filled(32, 5)),
  );
  final Timestamp at = Timestamp.fromMillisecondsSinceEpoch(0);
  final JournalMigrator migrator = JournalMigrator(
    cipher: cipher,
    store: FakeKeyStore(),
  );

  group('migrator', () {
    test('seals a plaintext vice and deletes name and unit', () async {
      final Map<String, Object>? update = await migrator.viceUpdate('v1', {
        'name': 'Wine', 'unit': 'drink', 'ownerID': 'alice', 'createdAt': at,
        'archived': false,
      });

      expect(update!.keys, unorderedEquals(['enc', 'name', 'unit']));
      expect(update['name'], FieldValue.delete());
      final Blob enc = update['enc']! as Blob;
      expect(enc.bytes.length, 285);
      expect(
        await cipher.open(collection: 'vices', docId: 'v1', ownerID: 'alice', blob: enc.bytes),
        {'n': 'Wine', 'u': 'drink'},
      );
    });

    test('adds archived to a legacy vice that lacks it', () async {
      final Map<String, Object>? update = await migrator.viceUpdate('v1', {
        'name': 'Booze', 'unit': 'drink', 'ownerID': 'alice', 'createdAt': at,
      });
      expect(update!['archived'], false);
    });

    test('seals a quantity, bound to the activity and its vice', () async {
      final Map<String, Object>? update = await migrator.activityUpdate('a1', {
        'viceID': 'v1', 'quantity': 0, 'ownerID': 'alice', 'createdAt': at,
      });
      expect(update!.keys, unorderedEquals(['enc', 'quantity']));
      final Blob enc = update['enc']! as Blob;
      expect(enc.bytes.length, 93);
      expect(
        await cipher.open(
          collection: 'activities', docId: 'a1', ownerID: 'alice', viceID: 'v1', blob: enc.bytes,
        ),
        {'q': 0},
      );
    });

    test('is idempotent: a second run skips documents that have enc', () async {
      final Blob enc = Blob(await cipher.seal(
        collection: 'vices', docId: 'v1', ownerID: 'alice', fields: {'n': 'Wine', 'u': 'drink'},
      ));
      expect(
        await migrator.viceUpdate('v1', {
          'enc': enc, 'ownerID': 'alice', 'createdAt': at, 'archived': false,
        }),
        isNull,
      );
      expect(
        await migrator.activityUpdate('a1', {
          'enc': enc, 'viceID': 'v1', 'ownerID': 'alice', 'createdAt': at,
        }),
        isNull,
      );
    });

    test('a device that already migrated skips the pass entirely', () async {
      final FakeKeyStore store = FakeKeyStore()..migrated.add('alice');
      final MigrationReport report =
          await JournalMigrator(cipher: cipher, store: store).run('alice');
      expect(report.skipped, isTrue);
    });
  });

  group('dual-shape parsers', () {
    test('a plaintext vice parses as before', () {
      final Vice vice = Vice.fromJson(id: 'v', json: {
        'name': 'Coffee', 'unit': 'drink', 'ownerID': 'alice', 'createdAt': at, 'archived': false,
      });
      expect(vice.name, 'Coffee');
      expect(vice.sealed, isFalse);
      expect(vice.unreadable, isFalse);
    });

    test('a sealed vice takes its fields from what it opened to', () {
      final Vice vice = Vice.fromJson(
        id: 'v',
        json: {'enc': Blob(Uint8List(285)), 'ownerID': 'alice', 'createdAt': at, 'archived': true},
        opened: {'n': 'Wine', 'u': 'drink'},
      );
      expect(vice.name, 'Wine');
      expect(vice.unit, Unit.drink);
      expect(vice.archived, isTrue);
      expect(vice.sealed, isTrue);
    });

    test('a sealed vice with a unit outside the enum falls back to items', () {
      final Vice vice = Vice.fromJson(
        id: 'v',
        json: {'enc': Blob(Uint8List(285)), 'ownerID': 'alice', 'createdAt': at, 'archived': false},
        opened: {'n': 'Snus', 'u': 'pouch'},
      );
      expect(vice.unit, Unit.item);
    });

    test('a sealed document that did not open is an Unreadable entry', () {
      final Vice vice = Vice.fromJson(
        id: 'v',
        json: {'enc': Blob(Uint8List(285)), 'ownerID': 'alice', 'createdAt': at, 'archived': false},
      );
      expect(vice.name, Vice.unreadableName);
      expect(vice.unreadable, isTrue);

      final ViceActivity activity = ViceActivity.fromJson(
        id: 'a',
        json: {'enc': Blob(Uint8List(93)), 'viceID': 'v', 'ownerID': 'alice', 'createdAt': at},
      );
      expect(activity.unreadable, isTrue);
      expect(activity.quantity, 0);
    });

    test('openSealed returns null for a tampered blob and memoises good ones', () async {
      final DecryptMemo memo = <String, Map<String, dynamic>>{};
      final Uint8List blob = await cipher.seal(
        collection: 'activities', docId: 'a', ownerID: 'alice', viceID: 'v', fields: {'q': 4},
      );
      Map<String, dynamic> json(Uint8List b) =>
          {'enc': Blob(b), 'viceID': 'v', 'ownerID': 'alice', 'createdAt': at};

      final Map<String, dynamic>? opened = await openSealed(
        cipher: cipher, memo: memo, collection: 'activities', docId: 'a', json: json(blob),
      );
      expect(opened, {'q': 4});
      expect(memo, hasLength(1));

      final Uint8List tampered = Uint8List.fromList(blob)..[20] ^= 1;
      expect(
        await openSealed(
          cipher: cipher, memo: memo, collection: 'activities', docId: 'a', json: json(tampered),
        ),
        isNull,
      );
      expect(memo, hasLength(1));
    });
  });
}
