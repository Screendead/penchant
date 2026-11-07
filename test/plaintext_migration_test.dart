import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:tracker/account/account.dart';
import 'package:tracker/crypto/plaintext_migration.dart';
import 'package:tracker/crypto/plaintext_migrator.dart';
import 'package:tracker/data/category.dart';
import 'package:tracker/data/sealed.dart';
import 'package:tracker/data/unit.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/providers/offline_provider.dart';
import 'package:tracker/providers/package_info_provider.dart';
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/settings.dart';

import 'fake_sealer.dart';
import 'fake_writes.dart';
import 'fakes.dart';

// Firestore's collections as maps, with updates applied as the server would.
class MemorySource implements MigrationSource {
  final Map<String, Map<String, Map<String, dynamic>>> collections =
      <String, Map<String, Map<String, dynamic>>>{
        'vices': <String, Map<String, dynamic>>{},
        'activities': <String, Map<String, dynamic>>{},
      };
  final List<int> batchSizes = <int>[];
  int pages = 0;
  int settles = 0;
  Object? failPage;
  Object? failSettle;
  int? failCommitNumber;

  @override
  Future<void> settlePendingWrites() async {
    settles++;
    if (failSettle != null) {
      throw failSettle!;
    }
  }

  @override
  Future<List<StoredDocument>> page(
    String collection,
    String uid, {
    String? after,
    required int limit,
  }) async {
    pages++;
    if (failPage != null) {
      throw failPage!;
    }
    final List<String> ids =
        collections[collection]!.entries
            .where((e) => e.value['ownerID'] == uid)
            .map((e) => e.key)
            .where((String id) => after == null || id.compareTo(after) > 0)
            .toList()
          ..sort();
    return <StoredDocument>[
      for (final String id in ids.take(limit))
        (id: id, data: Map<String, dynamic>.of(collections[collection]![id]!)),
    ];
  }

  @override
  Future<void> commit(
    String collection,
    Map<String, Map<String, Object>> updates,
  ) async {
    if (failCommitNumber == batchSizes.length) {
      throw FirebaseException(plugin: 'cloud_firestore', code: 'unavailable');
    }
    batchSizes.add(updates.length);
    for (final MapEntry<String, Map<String, Object>>(:key, :value)
        in updates.entries) {
      final Map<String, dynamic> doc = collections[collection]![key]!;
      for (final MapEntry<String, Object>(key: field, :value)
          in value.entries) {
        if (value == FieldValue.delete()) {
          doc.remove(field);
        } else {
          doc[field] = value;
        }
      }
    }
  }

  void addVice(String id, {String owner = ownerID, bool sealed = false}) {
    collections['vices']![id] = <String, dynamic>{
      'ownerID': owner,
      'createdAt': Timestamp.fromMillisecondsSinceEpoch(0),
      if (sealed) sealedField: Blob(Uint8List(4)),
      if (!sealed) ...<String, dynamic>{'name': 'Tea $id', 'unit': 'drink'},
    };
  }

  void addActivity(String id, {String owner = ownerID}) {
    collections['activities']![id] = <String, dynamic>{
      'ownerID': owner,
      'viceID': 'v0',
      'createdAt': Timestamp.fromMillisecondsSinceEpoch(0),
      'quantity': 2,
    };
  }

  int get plaintextLeft => collections['vices']!.values
      .where(
        (d) =>
            d['ownerID'] == ownerID &&
            (d.containsKey('name') || d.containsKey('unit')),
      )
      .length;
}

String id(int n) => n.toString().padLeft(5, '0');

void main() {
  group('PlaintextMigrator.update', () {
    final FakeSealer sealer = FakeSealer();
    final PlaintextMigrator migrator = PlaintextMigrator(
      source: MemorySource(),
      sealer: sealer,
    );

    test('seals a vice\'s name and unit and deletes them', () async {
      final Map<String, Object>? update = await migrator.update('vices', 'v1', {
        'name': 'Tea',
        'unit': 'drink',
        'ownerID': ownerID,
        'archived': false,
      });
      expect(
        update!.keys,
        unorderedEquals(<String>[sealedField, 'name', 'unit']),
      );
      expect(update['name'], FieldValue.delete());
      expect(update['unit'], FieldValue.delete());
      expect(
        await sealer.open(
          (update[sealedField]! as Blob).bytes,
          context: 'vices/v1',
        ),
        <String, Object>{
          'name': 'Tea',
          'unit': 'drink',
          'category': guessCategory('Tea').name,
        },
      );
    });

    test('seals a stored category, and deletes it', () async {
      final Map<String, Object>? update = await migrator.update('vices', 'v1', {
        'name': 'Tea',
        'unit': 'drink',
        'category': 'food',
        'ownerID': ownerID,
      });
      expect(update!['category'], FieldValue.delete());
      expect(
        (await sealer.open(
          (update[sealedField]! as Blob).bytes,
          context: 'vices/v1',
        ))['category'],
        'food',
      );
    });

    test('leaves an activity without triggers alone', () async {
      expect(
        await migrator.update('activities', 'a1', {
          'quantity': 0,
          'viceID': 'v1',
          'ownerID': ownerID,
        }),
        isNull,
      );
    });

    test('seals an activity\'s triggers, leaving its quantity', () async {
      final Map<String, Object>? update = await migrator.update(
        'activities',
        'a1',
        {
          'quantity': 2,
          'amount': 1.5,
          'viceID': 'v1',
          'ownerID': ownerID,
          'triggers': <Object?>['social'],
        },
      );
      expect(update!.keys, unorderedEquals(<String>[sealedField, 'triggers']));
      expect(
        await sealer.open(
          (update[sealedField]! as Blob).bytes,
          context: 'activities/a1',
        ),
        <String, Object>{
          'triggers': <Object?>['social'],
        },
      );
    });

    test(
      'what it writes, the reader opens to the same vice, on that document only',
      () async {
        final Map<String, dynamic> stored = <String, dynamic>{
          'name': 'Tea',
          'unit': 'drink',
          'ownerID': ownerID,
          'createdAt': Timestamp.fromMillisecondsSinceEpoch(0),
          'archived': false,
        };
        final Map<String, Object> update = (await migrator.update(
          'vices',
          'v1',
          stored,
        ))!;
        for (final MapEntry<String, Object>(:key, :value) in update.entries) {
          value == FieldValue.delete()
              ? stored.remove(key)
              : stored[key] = value;
        }
        expect(stored.keys, isNot(contains('name')));

        final SealedOpener opener = SealedOpener(sealer);
        final Vice vice = Vice.fromJson(
          id: 'v1',
          json: stored,
          opened: await opener.open('vices', 'v1', stored),
        );
        expect((vice.name, vice.unit, vice.locked), ('Tea', Unit.drink, false));

        final Vice copied = Vice.fromJson(
          id: 'v2',
          json: stored,
          opened: await opener.open('vices', 'v2', stored),
        );
        expect(copied.locked, isTrue);
      },
    );

    test('deletes only the plaintext fields a legacy document has', () async {
      final Map<String, Object>? update = await migrator.update('vices', 'v1', {
        'name': 'Tea',
        'ownerID': ownerID,
      });
      expect(update!.keys, unorderedEquals(<String>[sealedField, 'name']));
    });

    test('leaves a sealed document, or one with nothing to seal', () async {
      expect(
        await migrator.update('vices', 'v1', {
          sealedField: Blob(Uint8List(1)),
          'name': 'Tea',
          'ownerID': ownerID,
        }),
        isNull,
      );
      expect(
        await migrator.update('activities', 'a1', {'ownerID': ownerID}),
        isNull,
      );
    });
  });

  group('PlaintextMigrator.run', () {
    test(
      'seals every plaintext document the user owns, 500 at most per batch',
      () async {
        final MemorySource source = MemorySource();
        for (int n = 0; n < 1206; n++) {
          source.addVice(id(n));
        }
        source.addVice('sealed', sealed: true);
        source.addVice('other', owner: 'someone-else');
        source.addActivity('a0');
        final List<int> progress = <int>[];

        final int sealed = await PlaintextMigrator(
          source: source,
          sealer: FakeSealer(),
        ).run(ownerID, onProgress: progress.add);

        expect(sealed, 1206);
        expect(source.plaintextLeft, 0);
        expect(source.batchSizes, <int>[500, 500, 206]);
        expect(progress, <int>[500, 1000, 1206]);
        expect(source.collections['activities']!['a0']!['quantity'], 2);
        expect(source.collections['vices']!['other']!['name'], 'Tea other');
      },
    );

    test('a second run writes nothing', () async {
      final MemorySource source = MemorySource()
        ..addVice('v0')
        ..addActivity('a0');
      final PlaintextMigrator migrator = PlaintextMigrator(
        source: source,
        sealer: FakeSealer(),
      );
      await migrator.run(ownerID);
      source.batchSizes.clear();

      expect(await migrator.run(ownerID), 0);
      expect(source.batchSizes, isEmpty);
    });

    test('a run cut short is finished by the next', () async {
      final MemorySource source = MemorySource();
      for (int n = 0; n < 1100; n++) {
        source.addVice(id(n));
      }
      source.failCommitNumber = 1;
      final PlaintextMigrator migrator = PlaintextMigrator(
        source: source,
        sealer: FakeSealer(),
      );

      await expectLater(
        migrator.run(ownerID),
        throwsA(isA<FirebaseException>()),
      );
      expect(source.plaintextLeft, 600);

      source.failCommitNumber = null;
      expect(await migrator.run(ownerID), 600);
      expect(source.plaintextLeft, 0);
    });

    test('offline, the server read fails before anything is written', () async {
      final MemorySource source = MemorySource()..addVice('v0');
      source.failPage = FirebaseException(
        plugin: 'cloud_firestore',
        code: 'unavailable',
      );

      await expectLater(
        PlaintextMigrator(source: source, sealer: FakeSealer()).run(ownerID),
        throwsA(isA<FirebaseException>()),
      );
      expect(source.batchSizes, isEmpty);
    });

    test(
      'queued writes that never reach the server stop it before any read',
      () async {
        final MemorySource source = MemorySource()..addVice('v0');
        source.failSettle = FirebaseException(
          plugin: 'cloud_firestore',
          code: 'unavailable',
        );

        await expectLater(
          PlaintextMigrator(source: source, sealer: FakeSealer()).run(ownerID),
          throwsA(isA<FirebaseException>()),
        );
        expect(source.pages, 0);
        expect(source.batchSizes, isEmpty);

        source.failSettle = null;
        expect(
          await PlaintextMigrator(
            source: source,
            sealer: FakeSealer(),
          ).run(ownerID),
          1,
        );
        expect(source.settles, 2);
      },
    );

    test('stops before the next page once no longer wanted', () async {
      final MemorySource source = MemorySource()
        ..addVice('v0')
        ..addActivity('a0');

      expect(
        await PlaintextMigrator(
          source: source,
          sealer: FakeSealer(),
        ).run(ownerID, stillWanted: () => false),
        0,
      );
      expect(source.pages, 0);
    });
  });

  group('plaintextMigrationProvider', () {
    PackageInfo info(String build) => PackageInfo(
      appName: 'Penchant',
      packageName: 'com.screendead.penchant',
      version: '0.1.0',
      buildNumber: build,
    );

    ProviderContainer container({
      required MemorySource source,
      required MemoryJournalStore markers,
      FieldSealer? sealer,
      bool offline = false,
      String build = '1',
    }) {
      final ProviderContainer container = ProviderContainer(
        overrides: [
          sealerProvider.overrideWithValue(sealer),
          userProvider.overrideWith((ref) => Stream.value(FakeUser(ownerID))),
          packageInfoProvider.overrideWith((ref) async => info(build)),
          offlineProvider.overrideWith((ref) => Stream.value(offline)),
          migrationSourceProvider.overrideWithValue(source),
          migrationMarkersProvider.overrideWithValue(MigrationMarkers(markers)),
        ],
      );
      addTearDown(container.dispose);
      container.listen(plaintextMigrationProvider, (_, _) {});
      return container;
    }

    Future<MigrationStatus> settle(ProviderContainer container) async {
      for (int i = 0; i < 20; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      return container.read(plaintextMigrationProvider);
    }

    test('does nothing without a key', () async {
      final MemorySource source = MemorySource()..addVice('v0');
      final ProviderContainer c = container(
        source: source,
        markers: MemoryJournalStore(),
      );
      expect(await settle(c), MigrationStatus.idle);
      expect(source.pages, 0);
    });

    test('waits while offline', () async {
      final MemorySource source = MemorySource()..addVice('v0');
      final ProviderContainer c = container(
        source: source,
        markers: MemoryJournalStore(),
        sealer: FakeSealer(),
        offline: true,
      );
      expect(await settle(c), const MigrationStatus(MigrationPhase.waiting));
      expect(source.pages, 0);
    });

    test('seals once per uid and app version', () async {
      final MemorySource source = MemorySource()
        ..addVice('v0')
        ..addActivity('a0');
      final MemoryJournalStore markers = MemoryJournalStore();

      final ProviderContainer first = container(
        source: source,
        markers: markers,
        sealer: FakeSealer(),
      );
      expect(
        await settle(first),
        const MigrationStatus(MigrationPhase.done, 1),
      );
      expect(source.plaintextLeft, 0);
      expect(jsonDecode(markers.contents!), <String>['$ownerID 0.1.0+1']);

      source.pages = 0;
      final ProviderContainer again = container(
        source: source,
        markers: markers,
        sealer: FakeSealer(),
      );
      expect(await settle(again), MigrationStatus.idle);
      expect(source.pages, 0);

      final ProviderContainer upgraded = container(
        source: source,
        markers: markers,
        sealer: FakeSealer(),
        build: '2',
      );
      expect(
        await settle(upgraded),
        const MigrationStatus(MigrationPhase.done, 0),
      );
      expect(source.pages, greaterThan(0));
    });

    test('an unreachable server leaves it waiting and unmarked', () async {
      final MemorySource source = MemorySource()..addVice('v0');
      source.failPage = FirebaseException(
        plugin: 'cloud_firestore',
        code: 'unavailable',
      );
      final MemoryJournalStore markers = MemoryJournalStore();
      final ProviderContainer c = container(
        source: source,
        markers: markers,
        sealer: FakeSealer(),
      );
      expect(await settle(c), const MigrationStatus(MigrationPhase.waiting));
      expect(markers.contents, isNull);
    });
  });

  test('Settings says nothing unless sealing has something to report', () {
    expect(migrationNote(MigrationStatus.idle), isNull);
    expect(migrationNote(const MigrationStatus(MigrationPhase.done)), isNull);
    expect(
      migrationNote(const MigrationStatus(MigrationPhase.sealing, 40)),
      'Sealing habits: 40',
    );
    expect(
      migrationNote(const MigrationStatus(MigrationPhase.waiting)),
      'Sealing waits for a connection',
    );
  });
}
