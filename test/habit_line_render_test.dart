// Renders a habit's line as light stills, beside the picked mock-up
// (docs/pitch/round-17/goals/optionC.html):
//   flutter test test/habit_line_render_test.dart --dart-define=RENDER_DIR=<dir>
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart' hide Interval;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tracker/data/category.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/data/habit_line.dart';
import 'package:tracker/data/unit.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/design/app_theme.dart';
import 'package:tracker/insights/health_source.dart';
import 'package:tracker/insights/insights_report.dart';
import 'package:tracker/insights/stats.dart';
import 'package:tracker/insights/what_follows.dart';
import 'package:tracker/insights_page.dart';
import 'package:tracker/main.dart';
import 'package:tracker/providers/insights_provider.dart';
import 'package:tracker/providers/offline_provider.dart';
import 'package:tracker/providers/tracker_writes_provider.dart';
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/providers/vice_activity_day_provider.dart';
import 'package:tracker/trends/trends_sheet.dart';
import 'package:tracker/vice_form.dart';
import 'package:tracker/vice_tracker.dart';
import 'package:tracker/widgets/pill_toggle.dart';

import 'fake_writes.dart';
import 'fakes.dart';
import 'insights_harness.dart';
import 'render_fonts.dart';
import 'trends_harness.dart';

const String _dir = String.fromEnvironment('RENDER_DIR');

final DateTime _today = startOfDay(DateTime.now());

Vice _habit(
  String id,
  String name,
  int order,
  ViceCategory category, {
  String? unitLabel,
  String? unitSingular,
  HabitLine? line,
}) => Vice(
  id: id,
  name: name,
  unit: Unit.item,
  ownerID: ownerID,
  createdAt: Timestamp.fromDate(DateTime.utc(2026, 1, order)),
  archived: false,
  category: category,
  unitLabel: unitLabel,
  unitSingular: unitSingular,
  line: line,
);

final Vice _coffee = _habit(
  'coffee',
  'Coffee',
  1,
  ViceCategory.caffeine,
  unitLabel: 'cups',
  unitSingular: 'cup',
);
Vice _wine([HabitLine? line = const HabitLine(3, LinePeriod.day)]) => _habit(
  'wine',
  'Wine',
  2,
  ViceCategory.alcohol,
  unitLabel: 'glasses',
  unitSingular: 'glass',
  line: line,
);
final Vice _cigarettes = _habit(
  'cigarettes',
  'Cigarettes',
  3,
  ViceCategory.nicotine,
  unitLabel: 'cigarettes',
  unitSingular: 'cigarette',
  line: const HabitLine(30, LinePeriod.week),
);

List<ViceActivity> _entries(String id, int count, DateTime day, int hour) =>
    <ViceActivity>[
      for (int i = 0; i < count; i++)
        fakeActivity(id, 1, day.add(Duration(hours: hour + i, minutes: 10))),
    ];

// Wine 0 to 5 glasses a day in a fixed pattern over 400 days.
final List<ViceActivity> _wineJournal = <ViceActivity>[
  for (int back = 400; back >= 0; back--)
    ..._entries(
      'wine',
      const <int>[2, 0, 3, 1, 4, 2, 0, 5, 2, 1, 3][back % 11],
      addDays(_today, -back),
      18,
    ),
];

void _phone(WidgetTester tester, double height) {
  debugDisableShadows = false;
  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = Size(390 * 3, height * 3);
  tester.view.padding = const FakeViewPadding(top: 47 * 3, bottom: 34 * 3);
  addTearDown(tester.view.reset);
}

Future<void> _save(WidgetTester tester, GlobalKey frame, String name) async {
  await tester.runAsync(() async {
    final ui.Image image =
        await (frame.currentContext!.findRenderObject()!
                as RenderRepaintBoundary)
            .toImage(pixelRatio: 3);
    final ByteData? png = await image.toByteData(
      format: ui.ImageByteFormat.png,
    );
    await File('$_dir/$name.png').writeAsBytes(png!.buffer.asUint8List());
  });
  debugDisableShadows = true;
}

Widget _app(GlobalKey frame, List<Override> overrides, Widget home) =>
    ProviderScope(
      overrides: <Override>[
        userProvider.overrideWith((ref) => Stream.value(FakeUser(ownerID))),
        offlineProvider.overrideWithValue(const AsyncData(false)),
        trackerWritesProvider.overrideWithValue(FakeTrackerWrites()),
        memoryJournal(),
        ...overrides,
      ],
      child: RepaintBoundary(
        key: frame,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: appTheme(Brightness.light),
          home: home,
          onGenerateRoute: generateRoute,
        ),
      ),
    );

Future<void> _todayShot(
  WidgetTester tester,
  String name, {
  required int wine,
  required int week,
}) async {
  _phone(tester, 700);
  final GlobalKey frame = GlobalKey();
  final List<ViceActivity> day = <ViceActivity>[
    ..._entries('coffee', 3, _today, 7),
    ..._entries('wine', wine, _today, 18),
    ..._entries('cigarettes', 4, _today, 12),
  ];
  await tester.pumpWidget(
    _app(frame, <Override>[
      ...trendsOverrides(
        <Vice>[_coffee, _wine(), _cigarettes],
        inRange(const <ViceActivity>[]),
        days: (DateTime d) => d == _today ? day : const <ViceActivity>[],
      ),
      viceActivityWeekProvider.overrideWith(
        (ref, DateTime d) => AsyncData(<ViceActivity>[
          ...day,
          for (final ViceActivity a in _entries(
            'cigarettes',
            week - 4,
            _today,
            0,
          ))
            fakeActivity('cigarettes', 1, addDays(a.createdAt.toDate(), -2)),
        ]),
      ),
    ], const Scaffold(body: ViceTracker())),
  );
  await tester.pumpAndSettle();
  await _save(tester, frame, name);
}

Future<void> _insights(WidgetTester tester, String name, Vice wine) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    healthConnectedKey: true,
  });
  _phone(tester, 1000);
  final GlobalKey frame = GlobalKey();
  await tester.pumpWidget(
    _app(
      frame,
      insightsOverrides(
        health: FakeHealthSource(read: HealthValues(insightsJournal().health)),
        vices: AsyncData<List<Vice>>(<Vice>[wine]),
        runner: (_) async => InsightsReport(
          findings: <HabitFinding>[
            HabitFinding(
              habitId: 'wine',
              metricId: HealthMetric.sleepDeep.id,
              lagDays: 1,
              usableDays: 74,
              exposedDays: 21,
              raw: null,
              kind: InsightKind.doseLine,
              cut: 3,
              effect: -18,
              interval: const Interval(-27, -9),
              standardized: -0.5,
              pValue: 0.001,
            ),
          ],
          refused: const <HabitRefusal>[],
        ),
      ),
      const InsightsPage(),
    ),
  );
  await tester.pumpAndSettle();
  await _save(tester, frame, name);
}

void main() {
  setUpAll(loadRenderFonts);

  testWidgets('edit-habit-line', (WidgetTester tester) async {
    _phone(tester, 960);
    final GlobalKey frame = GlobalKey();
    await tester.pumpWidget(
      _app(frame, habitOverrides(<Vice>[_wine()]), ViceForm(vice: _wine())),
    );
    await tester.pumpAndSettle();
    await _save(tester, frame, 'edit-habit-line');
  }, skip: _dir.isEmpty);

  testWidgets('today-lines-under', (WidgetTester tester) async {
    await _todayShot(tester, 'today-lines-under', wine: 2, week: 22);
  }, skip: _dir.isEmpty);

  testWidgets('today-lines-over', (WidgetTester tester) async {
    await _todayShot(tester, 'today-lines-over', wine: 4, week: 34);
  }, skip: _dir.isEmpty);

  Future<void> trends(
    WidgetTester tester,
    String name, {
    List<Override> extra = const <Override>[],
    String? toggle,
    String? pick,
  }) async {
    _phone(tester, 1000);
    final GlobalKey frame = GlobalKey();
    await tester.pumpWidget(
      _app(frame, <Override>[
        ...extra,
        ...trendsOverrides(<Vice>[_coffee, _wine()], inRange(_wineJournal)),
      ], const Scaffold(body: ViceTracker())),
    );
    await tester.pumpAndSettle();
    await openTrends(tester);
    Future<void> tap(Finder f) async {
      final Finder target = inTrends(f).first;
      await tester.ensureVisible(target);
      await tester.pumpAndSettle();
      await tester.tap(target);
      await tester.pumpAndSettle();
    }

    await tap(find.widgetWithText(PillToggle, 'Wine'));
    if (toggle != null) await tap(find.text(toggle));
    if (pick != null) await tap(find.text(pick));
    await tester.ensureVisible(inTrends(find.text(TrendsSheet.title)).last);
    await tester.pumpAndSettle();
    await _save(tester, frame, name);
  }

  testWidgets('trends-line', (WidgetTester tester) async {
    await trends(tester, 'trends-line');
  }, skip: _dir.isEmpty);

  testWidgets(
    'trends-line-with-health',
    (WidgetTester tester) async {
      await trends(
        tester,
        'trends-line-with-health',
        extra: <Override>[
          healthStateProvider.overrideWith(
            (ref) async => HealthReady(<DailyOutcome>[
              for (int back = 120; back >= 0; back--)
                DailyOutcome(
                  addDays(_today, -back),
                  HealthMetric.restingHeartRate.id,
                  56.0 + (back * 7 % 9),
                ),
            ]),
          ),
        ],
        toggle: TrendsSheet.healthLabel,
        pick: 'Resting heart rate',
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
    skip: _dir.isEmpty,
  );

  testWidgets('trends-line-by-week', (WidgetTester tester) async {
    await trends(tester, 'trends-line-by-week', toggle: 'Week');
  }, skip: _dir.isEmpty);

  testWidgets('insights-line-offer', (WidgetTester tester) async {
    await _insights(tester, 'insights-line-offer', _wine(null));
  }, skip: _dir.isEmpty);

  testWidgets('insights-line-set', (WidgetTester tester) async {
    await _insights(tester, 'insights-line-set', _wine());
  }, skip: _dir.isEmpty);
}
