// Captures 1f's motion every 16 ms, for reviewing it frame by frame:
//   flutter test test/motion_frames_render_test.dart --dart-define=RENDER_DIR=<dir>
// Each scene writes <dir>/<scene>/frame-NNN.png; tools/motion-frames.sh turns
// them into GIFs and contact sheets.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/design/app_theme.dart';
import 'package:tracker/main.dart';
import 'package:tracker/providers/offline_provider.dart';
import 'package:tracker/providers/tracker_writes_provider.dart';
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/providers/vice_activity_day_provider.dart';
import 'package:tracker/providers/vice_activity_history_provider.dart';
import 'package:tracker/vice_tracker.dart';
import 'package:tracker/widgets/day_dial.dart';
import 'package:tracker/widgets/rejected_writes_banner.dart';
import 'package:tracker/widgets/sync_status.dart';
import 'package:tracker/writes/rejected_writes.dart';

import 'fake_writes.dart';
import 'fakes.dart';
import 'trends_harness.dart';
import 'render_fonts.dart';

const String _dir = String.fromEnvironment('RENDER_DIR');

class _Rejected extends RejectedWrites {
  @override
  List<RejectedWrite> build() => const <RejectedWrite>[];

  void show(List<RejectedWrite> rejected) => state = rejected;
}

final List<Vice> _vices = <Vice>[fakeVice('Coffee'), fakeVice('Tea')];

// Each day's beads sit apart from the next day's, so a day change shows.
List<ViceActivity> _entries(DateTime day) => <ViceActivity>[
  for (final (int i, int minute) in <(int, int)>[
    (0, 8 * 60 + 10),
    (1, 10 * 60 + 30),
    (0, 13 * 60),
    (1, 16 * 60 + 45),
    (0, 19 * 60 + 20),
  ])
    fakeActivity(
      _vices[i].id,
      1,
      day.add(Duration(minutes: minute + day.day % 2 * 150)),
    ),
];

List<Override> _overrides(Stream<bool> offline, {bool liveGraph = false}) =>
    <Override>[
      ...habitOverrides(_vices),
      userProvider.overrideWith((ref) => Stream.value(FakeUser(ownerID))),
      offlineProvider.overrideWith((ref) => offline),
      trackerWritesProvider.overrideWithValue(FakeTrackerWrites()),
      memoryJournal(),
      viceActivityDayProvider.overrideWith(
        (ref, DateTime day) => AsyncData(_entries(day)),
      ),
      // Live, a new range's query starts with no value, as Firestore's does.
      if (liveGraph)
        viceActivityGraphForUserProvider.overrideWith(
          (ref, key) => Stream<List<ViceActivity>>.fromFuture(
            Future<List<ViceActivity>>.delayed(
              const Duration(milliseconds: 48),
              () => _graph(key.query).requireValue,
            ),
          ),
        )
      else
        viceActivityGraphProvider.overrideWith(
          (ref, ViceActivityGraphQuery query) => _graph(query),
        ),
    ];

final AsyncValue<List<ViceActivity>> Function(ViceActivityGraphQuery) _graph =
    inRange(_history());

// A year and more of the first habit, a few a day, rising and falling.
List<ViceActivity> _history() {
  final DateTime today = DateUtils.dateOnly(DateTime.now());
  return <ViceActivity>[
    for (int ago = 0; ago < 400; ago++)
      for (int i = 0; i < 1 + (ago * 7 % 5) + (ago ~/ 30) % 3; i++)
        fakeActivity(
          _vices[0].id,
          1,
          DateTime(
            today.year,
            today.month,
            today.day - ago,
          ).add(Duration(hours: 8 + i * 3)),
        ),
  ];
}

Future<void> Function() _recorder(
  WidgetTester tester,
  GlobalKey frame,
  String scene,
) {
  final Directory out = Directory('$_dir/$scene')..createSync(recursive: true);
  int n = 0;
  return () => tester.runAsync(() async {
    final ui.Image image =
        await (frame.currentContext!.findRenderObject()!
                as RenderRepaintBoundary)
            .toImage(pixelRatio: 1);
    final ByteData? png = await image.toByteData(
      format: ui.ImageByteFormat.png,
    );
    await File(
      '${out.path}/frame-${(n++).toString().padLeft(3, '0')}.png',
    ).writeAsBytes(png!.buffer.asUint8List());
  });
}

Future<GlobalKey> _pumpToday(
  WidgetTester tester, {
  required bool reduced,
  GlobalKey<NavigatorState>? navigator,
  Stream<bool>? offline,
  Brightness brightness = Brightness.light,
  List<Override> overrides = const <Override>[],
  bool statusBar = false,
  bool liveGraph = false,
}) async {
  debugDisableShadows = false;
  tester.view.devicePixelRatio = 2;
  tester.view.physicalSize = const Size(390 * 2, 844 * 2);
  addTearDown(tester.view.reset);
  final GlobalKey frame = GlobalKey();
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        ..._overrides(
          offline ?? Stream<bool>.value(false),
          liveGraph: liveGraph,
        ),
        ...overrides,
      ],
      child: RepaintBoundary(
        key: frame,
        child: MediaQuery(
          data: MediaQueryData(
            size: const Size(390, 844),
            devicePixelRatio: 2,
            disableAnimations: reduced,
            padding: EdgeInsets.only(top: statusBar ? 47 : 0),
          ),
          child: MaterialApp(
            navigatorKey: navigator,
            onGenerateRoute: generateRoute,
            debugShowCheckedModeBanner: false,
            theme: appTheme(brightness),
            builder: statusBar ? rejectedWritesBuilder : null,
            home: const Scaffold(
              body: SafeArea(
                child: Column(
                  children: <Widget>[
                    OfflineBanner(),
                    Expanded(child: ViceTracker()),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return frame;
}

Future<void> _run(
  WidgetTester tester,
  Future<void> Function() capture,
  int frames,
) async {
  await capture();
  for (int i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 16));
    await capture();
  }
  await tester.pumpAndSettle();
  debugDisableShadows = true;
}

void main() {
  setUpAll(loadRenderFonts);
  testWidgets('dial drag snap-back', (WidgetTester tester) async {
    final GlobalKey frame = await _pumpToday(tester, reduced: false);
    final Future<void> Function() capture = _recorder(tester, frame, 'snap');
    final TestGesture drag = await tester.startGesture(
      tester.getCenter(find.byType(DayDial)),
    );
    for (int i = 0; i < 8; i++) {
      await drag.moveBy(const Offset(-5, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await capture();
    await drag.up();
    await _run(tester, capture, 18);
  }, skip: _dir.isEmpty);

  testWidgets('reduce-motion day change', (WidgetTester tester) async {
    final GlobalKey frame = await _pumpToday(tester, reduced: true);
    final Future<void> Function() capture = _recorder(
      tester,
      frame,
      'reduced-day',
    );
    await capture();
    await tester.tap(find.byTooltip('Previous day'));
    await _run(tester, capture, 22);
  }, skip: _dir.isEmpty);

  for (final bool reduced in <bool>[false, true]) {
    testWidgets('page push, reduce motion $reduced', (
      WidgetTester tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final GlobalKey<NavigatorState> navigator = GlobalKey<NavigatorState>();
      final GlobalKey frame = await _pumpToday(
        tester,
        reduced: reduced,
        navigator: navigator,
      );
      final Future<void> Function() capture = _recorder(
        tester,
        frame,
        reduced ? 'page-reduced' : 'page',
      );
      await capture();
      navigator.currentState!.pushNamed('/manage-data');
      await _run(tester, capture, 22);
      debugDefaultTargetPlatformOverride = null;
    }, skip: _dir.isEmpty);
  }

  for (final bool reduced in <bool>[false, true]) {
    testWidgets('offline pill, reduce motion $reduced', (
      WidgetTester tester,
    ) async {
      final StreamController<bool> offline = StreamController<bool>();
      addTearDown(() => unawaited(offline.close()));
      final GlobalKey frame = await _pumpToday(
        tester,
        reduced: reduced,
        offline: offline.stream,
      );
      offline.add(false);
      await tester.pumpAndSettle();
      final Future<void> Function() capture = _recorder(
        tester,
        frame,
        reduced ? 'offline-reduced' : 'offline',
      );
      await capture();
      offline.add(true);
      await tester.pump();
      await _run(tester, capture, 22);
    }, skip: _dir.isEmpty);
  }

  testWidgets('chart morph between ranges', (WidgetTester tester) async {
    final GlobalKey frame = await _pumpToday(
      tester,
      reduced: false,
      liveGraph: true,
    );
    await openTrends(tester);
    final Future<void> Function() capture = _recorder(tester, frame, 'morph');
    await tester.tap(inTrends(find.text('90D')));
    await tester.pump();
    await _run(tester, capture, 30);
  }, skip: _dir.isEmpty);

  for (final Brightness brightness in Brightness.values) {
    testWidgets('refused-write pill under a status bar, ${brightness.name}', (
      WidgetTester tester,
    ) async {
      final GlobalKey frame = await _pumpToday(
        tester,
        reduced: false,
        brightness: brightness,
        statusBar: true,
        overrides: <Override>[
          rejectedWritesProvider.overrideWith(_Rejected.new),
        ],
      );
      final Future<void> Function() capture = _recorder(
        tester,
        frame,
        'rejected-${brightness.name}',
      );
      await capture();
      (ProviderScope.containerOf(
                tester.element(find.byType(ViceTracker)),
              ).read(rejectedWritesProvider.notifier)
              as _Rejected)
          .show(const <RejectedWrite>[
            RejectedWrite('Not saved: Coffee, 1 cup, today 09:10', null),
          ]);
      await tester.pump();
      await _run(tester, capture, 30);
      debugDisableShadows = false;
      await tester.tap(find.text(RejectedWritesBanner.dismissLabel));
      await tester.pump();
      await _run(tester, capture, 20);
    }, skip: _dir.isEmpty);
  }
}
