import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cryptography/cryptography.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/account/account.dart';
import 'package:tracker/data/sealed.dart';
import 'package:tracker/providers/device_files_provider.dart';
import 'package:tracker/providers/insights_session.dart';
import 'package:tracker/crypto/journal_field_sealer.dart';
import 'package:tracker/crypto/sealed_files.dart';
import 'package:tracker/crypto/sealer.dart';
import 'package:tracker/insights/health_sample_cache.dart';
import 'package:tracker/insights/health_source.dart';
import 'package:tracker/insights/health_sync.dart';
import 'package:tracker/writes/queued_write_journal.dart';

import '../fake_sealer.dart';

JournalFieldSealer _sealer({int keyByte = 7}) => JournalFieldSealer(
  Sealer(aes: AesGcm.with256bits(), key: List<int>.filled(32, keyByte)),
);

class _Auth extends Mock implements FirebaseAuth {}

class _Firestore extends Mock implements FirebaseFirestore {}

class _Journal extends Mock implements QueuedWriteJournal {}

void main() {
  late Directory caches;
  late DeviceFiles device;

  setUp(() async {
    caches = await Directory.systemTemp.createTemp('sealed-files-test');
    device = DeviceFiles(caches: () async => caches);
  });

  tearDown(() async {
    if (await caches.exists()) await caches.delete(recursive: true);
  });

  Future<List<File>> filesOnDisk() async => <File>[
    await for (final FileSystemEntity e in caches.list(recursive: true))
      if (e is File) e,
  ];

  group('file padding', () {
    test('round trips any size, padded to a power of two', () async {
      final Sealer sealer = Sealer(
        aes: AesGcm.with256bits(),
        key: List<int>.filled(32, 7),
      );
      for (final int size in <int>[0, 1, 4092, 4093, 70000]) {
        final List<int> bytes = List<int>.generate(size, (i) => i % 251);
        final Uint8List padded = Sealer.padFile(bytes);
        expect(padded.length, greaterThanOrEqualTo(Sealer.smallestFileBucket));
        expect(padded.length & (padded.length - 1), 0);
        final Uint8List envelope = await sealer.sealFile(bytes);
        expect(envelope[0], Sealer.version);
        expect(envelope.length, padded.length + Sealer.overhead);
        expect(await sealer.openFile(envelope), bytes);
      }
    });

    test('a length past the padding is refused', () {
      final Uint8List padded = Sealer.padFile(<int>[1, 2, 3])..[0] = 0x7f;
      expect(() => Sealer.unpadFile(padded), throwsA(isA<SealException>()));
    });
  });

  group('SealedFiles', () {
    test('round trips, and nothing on disk holds the plaintext', () async {
      final SealedFiles files = device.forUser('alice', _sealer());
      await files.write('note', utf8.encode('stepCount 9000'));
      expect(utf8.decode((await files.read('note'))!), 'stepCount 9000');
      for (final File f in await filesOnDisk()) {
        expect(
          utf8.decode(await f.readAsBytes(), allowMalformed: true),
          isNot(contains('stepCount')),
        );
      }
    });

    test(
      'another user neither opens nor keeps the first user\'s files',
      () async {
        await device.forUser('alice', _sealer()).write('note', <int>[1, 2, 3]);
        final SealedFiles bob = device.forUser('bob', _sealer());
        expect(await bob.read('note'), isNull);
        expect(await filesOnDisk(), isEmpty);
      },
    );

    test('a file copied to another user\'s context does not open', () async {
      final JournalFieldSealer sealer = _sealer();
      final Uint8List envelope = await sealer.sealFile(<int>[
        1,
        2,
        3,
      ], context: deviceFileContext('alice', 'note'));
      expect(
        () => sealer.openFile(
          envelope,
          context: deviceFileContext('bob', 'note'),
        ),
        throwsA(isA<SealException>()),
      );
      expect(
        () => sealer.openFile(
          envelope,
          context: deviceFileContext('alice', 'other'),
        ),
        throwsA(isA<SealException>()),
      );
    });

    test('a renamed file reads as absent', () async {
      final SealedFiles files = device.forUser('alice', _sealer());
      await files.write('one', <int>[1, 2, 3]);
      final File one = (await filesOnDisk()).single;
      await one.rename('${one.parent.path}/two');
      expect(await files.read('two'), isNull);
    });

    test(
      'a corrupt file or another key reads as absent and is deleted',
      () async {
        final SealedFiles files = device.forUser('alice', _sealer());
        await files.write('note', <int>[1, 2, 3]);
        expect(
          await device.forUser('alice', _sealer(keyByte: 8)).read('note'),
          isNull,
        );
        expect(await filesOnDisk(), isEmpty);

        await files.write('note', <int>[1, 2, 3]);
        final File file = (await filesOnDisk()).single;
        final Uint8List bytes = await file.readAsBytes();
        bytes[bytes.length - 1] ^= 1;
        await file.writeAsBytes(bytes);
        expect(await files.read('note'), isNull);
        expect(await filesOnDisk(), isEmpty);

        await files.write('note', <int>[1, 2, 3]);
        await (await filesOnDisk()).single.writeAsBytes(<int>[1]);
        expect(await files.read('note'), isNull);
      },
    );

    test(
      'clearAll removes every user\'s files and the plaintext store',
      () async {
        await device.forUser('alice', _sealer()).write('note', <int>[1]);
        await File('${caches.path}/health-daily.json').writeAsString('{}');
        await device.clearAll();
        expect(await filesOnDisk(), isEmpty);
      },
    );
  });

  group('SealedHealthStoreFile', () {
    test('with no key nothing is read or written', () async {
      await File('${caches.path}/health-daily.json').writeAsString('{}');
      final SealedHealthStoreFile file = SealedHealthStoreFile(() => null);
      expect(await file.read(), isNull);
      await expectLater(file.write('{"version":1}'), throwsStateError);
      expect((await filesOnDisk()).single.path, endsWith('health-daily.json'));
    });

    test('round trips sealed and deletes the plaintext store', () async {
      await File('${caches.path}/health-daily.json').writeAsString('{}');
      final SealedFiles files = device.forUser('alice', _sealer());
      final SealedHealthStoreFile file = SealedHealthStoreFile(() => files);
      await file.write('{"values":{"stepCount":9000}}');
      expect(await file.read(), '{"values":{"stepCount":9000}}');
      final List<File> left = await filesOnDisk();
      expect(left.where((f) => f.path.endsWith('.json')), isEmpty);
      expect(
        await SealedHealthStoreFile(
          () => device.forUser('bob', _sealer()),
        ).read(),
        isNull,
      );
    });
  });

  group('HealthSampleCache', () {
    final CachedSpan nov3 = (
      metric: 'heartRate',
      start: DateTime(2026, 11, 3, 21, 15),
      end: DateTime(2026, 11, 4, 1, 15),
    );
    final CachedSpan nov4 = (
      metric: 'heartRate',
      start: DateTime(2026, 11, 4, 22),
      end: DateTime(2026, 11, 5, 2),
    );
    final List<HealthSample> samples = <HealthSample>[
      HealthSample(
        DateTime(2026, 11, 3, 21, 20, 1, 2, 3),
        DateTime(2026, 11, 3, 21, 20, 1, 2, 3),
        61.5,
      ),
      HealthSample(DateTime(2026, 11, 3, 22), DateTime(2026, 11, 3, 22, 5), 58),
    ];

    test('round trips across launches under opaque names', () async {
      await HealthSampleCache(
        device.forUser('alice', _sealer()),
      ).keepOnly(<CachedSpan, List<HealthSample>>{nov3: samples});
      final Map<CachedSpan, List<HealthSample>> loaded =
          await HealthSampleCache(
            DeviceFiles(caches: () async => caches).forUser('alice', _sealer()),
          ).load();
      expect(loaded, hasLength(1));
      expect(loaded[nov3], samples);
      final String name = (await filesOnDisk()).single.path.split('/').last;
      expect(name, matches(RegExp(r'^samples-[0-9a-f]{32}$')));
    });

    test('keeps no empty span and prunes spans no longer asked for', () async {
      final HealthSampleCache cache = HealthSampleCache(
        device.forUser('alice', _sealer()),
      );
      await cache.keepOnly(<CachedSpan, List<HealthSample>>{
        nov3: samples,
        nov4: const <HealthSample>[],
      });
      expect(await filesOnDisk(), hasLength(1));
      await cache.keepOnly(<CachedSpan, List<HealthSample>>{nov4: samples});
      final Map<CachedSpan, List<HealthSample>> loaded =
          await HealthSampleCache(device.forUser('alice', _sealer())).load();
      expect(loaded.keys, <CachedSpan>[nov4]);
    });

    test('another user, a corrupt file or clear leaves nothing', () async {
      final HealthSampleCache cache = HealthSampleCache(
        device.forUser('alice', _sealer()),
      );
      await cache.keepOnly(<CachedSpan, List<HealthSample>>{nov3: samples});
      expect(
        await HealthSampleCache(device.forUser('bob', _sealer())).load(),
        isEmpty,
      );

      final HealthSampleCache again = HealthSampleCache(
        device.forUser('alice', _sealer()),
      );
      await again.keepOnly(<CachedSpan, List<HealthSample>>{nov3: samples});
      await (await filesOnDisk()).single.writeAsBytes(<int>[0, 1, 2]);
      expect(
        await HealthSampleCache(device.forUser('alice', _sealer())).load(),
        isEmpty,
      );

      final HealthSampleCache third = HealthSampleCache(
        device.forUser('alice', _sealer()),
      );
      await third.keepOnly(<CachedSpan, List<HealthSample>>{nov3: samples});
      await third.clear();
      expect(await third.load(), isEmpty);
      expect(await filesOnDisk(), isEmpty);
    });
  });

  group('Account', () {
    test(
      'sign-out clears the device files even when the cache will not',
      () async {
        await device.forUser('alice', _sealer()).write('note', <int>[1]);
        final _Auth auth = _Auth();
        final _Firestore firestore = _Firestore();
        final _Journal journal = _Journal();
        when(firestore.waitForPendingWrites).thenAnswer((_) async {});
        when(auth.signOut).thenAnswer((_) async {});
        when(firestore.terminate).thenAnswer((_) async {});
        when(firestore.clearPersistence).thenThrow(
          FirebaseException(plugin: 'cloud_firestore', code: 'failed'),
        );
        when(journal.clear).thenAnswer((_) async {});
        await Account(
          auth,
          firestore,
          journal,
          clearDeviceFiles: device.clearAll,
        ).signOut();
        expect(await filesOnDisk(), isEmpty);
      },
    );
  });

  group('kept files', () {
    late Directory support;
    late DeviceFiles both;

    setUp(() async {
      support = await Directory.systemTemp.createTemp('sealed-support-test');
      both = DeviceFiles(
        caches: () async => caches,
        support: () async => support,
      );
    });

    tearDown(() async {
      if (await support.exists()) await support.delete(recursive: true);
    });

    Future<List<File>> kept() async => <File>[
      await for (final FileSystemEntity e in support.list(recursive: true))
        if (e is File) e,
    ];

    test('live in Application Support, sealed, apart from Caches', () async {
      final SealedFiles files = both.keptForUser('alice', _sealer());
      await files.write('experiment', utf8.encode('habit-1 sleepDeep'));
      expect(
        utf8.decode((await files.read('experiment'))!),
        'habit-1 sleepDeep',
      );
      expect(await filesOnDisk(), isEmpty);
      expect(await kept(), hasLength(1));
      expect(
        utf8.decode(
          await (await kept()).single.readAsBytes(),
          allowMalformed: true,
        ),
        isNot(contains('sleepDeep')),
      );
      expect(await both.forUser('alice', _sealer()).read('experiment'), isNull);
    });

    test('another user\'s first use removes them', () async {
      await both.keptForUser('alice', _sealer()).write('experiment', <int>[1]);
      final SealedFiles bob = both.keptForUser('bob', _sealer());
      expect(await bob.read('experiment'), isNull);
      expect(await kept(), isEmpty);
    });

    test('clearAll removes them with the Caches ones', () async {
      await both.keptForUser('alice', _sealer()).write('experiment', <int>[1]);
      await both.forUser('alice', _sealer()).write('note', <int>[1]);
      await both.clearAll();
      expect(await kept(), isEmpty);
      expect(await filesOnDisk(), isEmpty);
    });
  });

  test('deleteLegacy removes the plaintext store alone', () async {
    await File('${caches.path}/health-daily.json').writeAsString('{}');
    await File('${caches.path}/health-daily.json.next').writeAsString('{}');
    await device.forUser('alice', _sealer()).write('note', <int>[1]);
    await device.deleteLegacy();
    expect((await filesOnDisk()).single.path, endsWith('note'));
  });

  group('sealedFilesProvider', () {
    SealedFiles? files({String? uid, FieldSealer? sealer}) {
      final ProviderContainer container = ProviderContainer(
        overrides: [
          insightsUidProvider.overrideWithValue(uid),
          sealerProvider.overrideWithValue(sealer),
          deviceFilesProvider.overrideWithValue(device),
        ],
      );
      addTearDown(container.dispose);
      return container.read(sealedFilesProvider);
    }

    test('is null with no key, nobody signed in or no file sealer', () {
      expect(files(uid: 'alice'), isNull);
      expect(files(sealer: _sealer()), isNull);
      expect(files(uid: 'alice', sealer: FakeSealer()), isNull);
    });

    test('is the signed-in user\'s with the journal key', () {
      expect(files(uid: 'alice', sealer: _sealer())?.uid, 'alice');
    });
  });
}
