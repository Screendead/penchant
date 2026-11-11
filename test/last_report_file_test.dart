import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/crypto/journal_field_sealer.dart';
import 'package:tracker/crypto/sealed_files.dart';
import 'package:tracker/crypto/sealer.dart';
import 'package:tracker/data/sealed.dart';
import 'package:tracker/insights/health_source.dart';
import 'package:tracker/insights/insights_report.dart';
import 'package:tracker/insights/insights_timing.dart';
import 'package:tracker/insights/last_report_file.dart';
import 'package:tracker/insights/report_codec.dart';
import 'package:tracker/insights/stats.dart';
import 'package:tracker/insights/what_follows.dart';
import 'package:tracker/providers/calendar_provider.dart';
import 'package:tracker/providers/device_files_provider.dart';
import 'package:tracker/providers/insights_provider.dart';
import 'package:tracker/providers/insights_session.dart';

import 'insights_harness.dart';

JournalFieldSealer _sealer() => JournalFieldSealer(
  Sealer(aes: AesGcm.with256bits(), key: List<int>.filled(32, 7)),
);

// A report the journal below never gives, so the test can tell them apart.
final InsightsView _saved = (
  health: HealthReady(<DailyOutcome>[
    DailyOutcome(insightsToday, HealthMetric.sleepDeep.id, 64),
  ]),
  result: const InsightsComputed(
    InsightsReport(
      findings: <HabitFinding>[
        HabitFinding(
          habitId: 'coffee',
          metricId: 'sleepDeep',
          lagDays: 1,
          usableDays: 77,
          exposedDays: 33,
          raw: null,
          effect: -33.25,
          interval: Interval(-40, -26),
          standardized: -2,
          pValue: 1e-6,
        ),
      ],
      refused: <HabitRefusal>[],
    ),
  ),
  hoursPending: false,
  updating: false,
);

double? _firstEffect(InsightsView? view) => switch (view?.result) {
  InsightsComputed(:final InsightsReport report) =>
    report.findings.firstOrNull?.effect,
  _ => null,
};

Future<void> _until(bool Function() done, String what) async {
  for (int i = 0; i < 400; i++) {
    if (done()) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail(what);
}

void main() {
  late Directory caches;
  late DeviceFiles device;

  setUp(() async {
    insightsTimingLog = (_) {};
    caches = await Directory.systemTemp.createTemp('last-report-test');
    device = DeviceFiles(caches: () async => caches);
  });

  tearDown(() async {
    insightsTimingLog = debugPrint;
    if (await caches.exists()) await caches.delete(recursive: true);
  });

  Future<List<File>> filesOnDisk() async => <File>[
    await for (final FileSystemEntity e in caches.list(recursive: true))
      if (e is File) e,
  ];

  ProviderContainer container({
    String uid = 'alice',
    FieldSealer? sealer,
    Future<void>? gate,
    bool connected = true,
  }) {
    final ProviderContainer c = ProviderContainer(
      overrides: <Override>[
        ...insightsOverrides(
          health: FakeHealthSource(
            read: HealthValues(insightsJournal().health),
          ),
          runner: (InsightsInput input) async {
            if (gate != null) await gate;
            return computeInsights(input);
          },
          uid: (Ref ref) => uid,
        ),
        healthConnectedProvider.overrideWith((ref) async => connected),
        calendarSourceProvider.overrideWithValue(null),
        sealerProvider.overrideWithValue(sealer),
        deviceFilesProvider.overrideWithValue(device),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  test('a cold open shows the sealed report, updating, until the fresh one '
      'lands, which replaces it on the device', () async {
    final JournalFieldSealer sealer = _sealer();
    await LastReportFile(device.forUser('alice', sealer)).save(_saved);
    final Completer<void> gate = Completer<void>();
    final ProviderContainer c = container(sealer: sealer, gate: gate.future);
    c.listen(insightsProvider, (_, _) {});
    await _until(
      () => c.read(insightsProvider).value != null,
      'the saved report never showed',
    );
    final InsightsView shown = c.read(insightsProvider).value!;
    expect(shown.updating, isTrue);
    expect(_firstEffect(shown), -33.25);

    gate.complete();
    await _until(() {
      final InsightsView? v = c.read(insightsProvider).value;
      return v != null && !v.updating && !v.hoursPending;
    }, 'the fresh report never landed');
    final InsightsView fresh = c.read(insightsProvider).value!;
    expect(_firstEffect(fresh), isNot(-33.25));

    final List<int> expected = encodeInsightsView(fresh)!;
    List<int>? kept;
    await _until(() {
      unawaited(
        LastReportFile(device.forUser('alice', sealer)).load().then(
          (InsightsView? v) => kept = v == null ? null : encodeInsightsView(v),
        ),
      );
      return listEquals(kept, expected);
    }, 'the fresh report was never kept');
    for (final File f in await filesOnDisk()) {
      expect(
        utf8.decode(await f.readAsBytes(), allowMalformed: true),
        isNot(contains('sleepDeep')),
      );
    }
  });

  test('a view already in the session is never replaced by the file', () async {
    final JournalFieldSealer sealer = _sealer();
    await LastReportFile(device.forUser('alice', sealer)).save(_saved);
    final ProviderContainer c = container(
      sealer: sealer,
      gate: Completer<void>().future,
    );
    final InsightsView inSession = (
      health: const HealthNotConnected(),
      result: null,
      hoursPending: false,
      updating: false,
    );
    c.read(insightsSessionProvider)!.lastView = inSession;
    c.listen(insightsProvider, (_, _) {});
    for (int i = 0; i < 20; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    final InsightsView shown = c.read(insightsProvider).value!;
    expect(shown.health, isA<HealthNotConnected>());
    expect(shown.updating, isTrue);
  });

  test('another user never sees the saved report', () async {
    final JournalFieldSealer sealer = _sealer();
    await LastReportFile(device.forUser('alice', sealer)).save(_saved);
    final ProviderContainer c = container(
      uid: 'bob',
      sealer: sealer,
      gate: Completer<void>().future,
    );
    c.listen(insightsProvider, (_, _) {});
    for (int i = 0; i < 40; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(c.read(insightsProvider), isA<AsyncLoading<InsightsView>>());
  });

  test('with no key nothing is read or written', () async {
    final File planted = File(
      '${caches.path}/${DeviceFiles.folder}/'
      '${base64Url.encode(utf8.encode('alice')).replaceAll('=', '')}/'
      '${LastReportFile.name}',
    );
    await planted.create(recursive: true);
    await planted.writeAsBytes(<int>[1, 2, 3]);
    final ProviderContainer c = container();
    c.listen(insightsProvider, (_, _) {});
    await _until(() {
      final InsightsView? v = c.read(insightsProvider).value;
      return v != null && !v.updating && !v.hoursPending;
    }, 'the report never landed');
    for (int i = 0; i < 20; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(c.read(insightsSessionProvider)!.savedView, isNull);
    final List<File> files = await filesOnDisk();
    expect(files.single.path, planted.path);
    expect(await planted.readAsBytes(), <int>[1, 2, 3]);
  });

  test('a file that will not decode reads as absent and is deleted', () async {
    final SealedFiles files = device.forUser('alice', _sealer());
    await files.write(LastReportFile.name, utf8.encode('{"version": 1}'));
    expect(await LastReportFile(files).load(), isNull);
    expect(await files.names(), isEmpty);
  });

  test('sign-out and another user\'s first use remove it', () async {
    final JournalFieldSealer sealer = _sealer();
    await LastReportFile(device.forUser('alice', sealer)).save(_saved);
    expect(await device.forUser('alice', sealer).names(), <String>[
      LastReportFile.name,
    ]);
    await device.clearAll();
    expect(await filesOnDisk(), isEmpty);

    await LastReportFile(device.forUser('alice', sealer)).save(_saved);
    expect(await device.forUser('bob', sealer).names(), isEmpty);
    expect(await filesOnDisk(), isEmpty);
  });

  test('Health disconnected removes the kept report', () async {
    final JournalFieldSealer sealer = _sealer();
    await LastReportFile(device.forUser('alice', sealer)).save(_saved);
    final ProviderContainer c = container(sealer: sealer, connected: false);
    int? left;
    c.listen(insightsProvider, (_, _) {});
    await _until(
      () => c.read(insightsProvider).value?.health is HealthNotConnected,
      'not connected never showed',
    );
    await _until(() {
      unawaited(filesOnDisk().then((List<File> f) => left = f.length));
      return left == 0;
    }, 'the kept report was never removed');
  });

  test('a write in flight at sign-out leaves nothing behind', () async {
    final Completer<void> sealing = Completer<void>();
    final SealedFiles files = device.forUser(
      'alice',
      _GatedSealer(_sealer(), sealing.future),
    );
    final Future<void> write = files.write(LastReportFile.name, <int>[1, 2]);
    final Future<void> cleared = device.clearAll();
    sealing.complete();
    await expectLater(write, throwsStateError);
    await cleared;
    expect(await filesOnDisk(), isEmpty);
    await expectLater(files.write(LastReportFile.name, <int>[1, 2]), completes);
  });
}

class _GatedSealer implements FileSealer {
  _GatedSealer(this._inner, this._gate);

  final FileSealer _inner;
  final Future<void> _gate;

  @override
  Future<Uint8List> sealFile(List<int> bytes, {required String context}) async {
    await _gate;
    return _inner.sealFile(bytes, context: context);
  }

  @override
  Future<Uint8List> openFile(List<int> envelope, {required String context}) =>
      _inner.openFile(envelope, context: context);
}
