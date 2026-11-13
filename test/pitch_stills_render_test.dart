// Renders the built-but-undecided features as light stills for a pitch page:
// a habit's own unit and price, Trends' spend, Health and trigger views, the
// place and calendar cards, and the picker's calendar suggestion:
//   flutter test test/pitch_stills_render_test.dart --dart-define=RENDER_DIR=<dir>
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart' hide Interval;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/category.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/data/unit.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/design/app_theme.dart';
import 'package:tracker/design/habit_mark.dart';
import 'package:tracker/formats.dart';
import 'package:tracker/insights/calendar_days.dart';
import 'package:tracker/insights/calendar_days_copy.dart';
import 'package:tracker/insights/calendar_suggestion.dart';
import 'package:tracker/insights/health_source.dart';
import 'package:tracker/insights/places.dart';
import 'package:tracker/insights/stats.dart';
import 'package:tracker/insights_page.dart';
import 'package:tracker/main.dart';
import 'package:tracker/providers/insights_provider.dart';
import 'package:tracker/providers/offline_provider.dart';
import 'package:tracker/providers/tracker_writes_provider.dart';
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/trends/trends_sheet.dart';
import 'package:tracker/vice_form.dart';
import 'package:tracker/vice_tracker.dart';
import 'package:tracker/widgets/after_event_card.dart';
import 'package:tracker/widgets/at_place_card.dart';
import 'package:tracker/widgets/pill_toggle.dart';
import 'package:tracker/widgets/settings_card.dart';
import 'package:tracker/widgets/trigger_picker.dart';

import 'fake_writes.dart';
import 'fakes.dart';
import 'render_fonts.dart';
import 'trends_harness.dart';

const String _dir = String.fromEnvironment('RENDER_DIR');

final DateTime _today = startOfDay(DateTime.now());

Vice _habit(
  String id,
  String name,
  Unit unit,
  int order,
  ViceCategory category, {
  String? unitLabel,
  double? cost,
}) => Vice(
  id: id,
  name: name,
  unit: unit,
  ownerID: ownerID,
  createdAt: Timestamp.fromDate(DateTime.utc(2026, 1, order)),
  archived: false,
  category: category,
  unitLabel: unitLabel,
  costPerUnit: cost,
  currency: cost == null ? null : 'GBP',
);

final Vice _coffee = _habit(
  'coffee',
  'Coffee',
  Unit.drink,
  1,
  ViceCategory.caffeine,
);
final Vice _wine = _habit(
  'wine',
  'Wine',
  Unit.drink,
  2,
  ViceCategory.alcohol,
  unitLabel: 'glasses',
  cost: 2.5,
);
final Vice _cigarettes = _habit(
  'cigarettes',
  'Cigarettes',
  Unit.item,
  3,
  ViceCategory.nicotine,
);
final List<Vice> _habits = <Vice>[_coffee, _wine, _cigarettes];

int _seed = 0;
int _next(int bound) {
  _seed = (_seed * 1103515245 + 12345) & 0x7fffffff;
  return _seed % bound;
}

const List<String> _wineTriggers = <String>[
  'social/friends',
  'social/friends',
  'routine/meal',
  'routine/wind-down',
  'feeling/stressed',
  'work/long-day',
  'work/done',
  'place/bar',
];

// 400 days: Coffee most mornings; Wine most evenings, more at the weekend,
// most entries tagged; Cigarettes alongside Wine some evenings.
final List<ViceActivity> _journal = () {
  _seed = 42;
  final List<ViceActivity> out = <ViceActivity>[];
  for (int back = 400; back >= 0; back--) {
    final DateTime day = addDays(_today, -back);
    final bool weekend = day.weekday >= DateTime.friday;
    for (int i = 0; i < 1 + _next(3); i++) {
      out.add(
        fakeActivity(
          'coffee',
          1,
          day.add(Duration(hours: 7 + 3 * i, minutes: _next(50))),
          triggers: i == 0 ? const <String>['routine/morning'] : const [],
        ),
      );
    }
    if (_next(10) < (weekend ? 9 : 5)) {
      final int glasses = 1 + _next(weekend ? 3 : 2);
      for (int g = 0; g < glasses; g++) {
        out.add(
          fakeActivity(
            'wine',
            1,
            day.add(Duration(hours: 18 + g, minutes: 10 + _next(40))),
            triggers: _next(5) == 0
                ? const <String>[]
                : <String>[_wineTriggers[_next(_wineTriggers.length)]],
          ),
        );
      }
      if (_next(3) == 0) {
        out.add(
          fakeActivity(
            'cigarettes',
            1 + _next(3),
            day.add(Duration(hours: 21, minutes: _next(50))),
          ),
        );
      }
    }
  }
  return out;
}();

double _glasses(DateTime day) => <ViceActivity>[
  for (final ViceActivity a in _journal)
    if (a.viceID == 'wine' && startOfDay(a.createdAt.toDate()) == day) a,
].length.toDouble();

// Resting heart rate up the morning after a night of wine; sleep down.
final List<DailyOutcome> _health = () {
  _seed = 7;
  double noise(double spread) => (_next(1000) / 1000 - 0.5) * spread;
  return <DailyOutcome>[
    for (int back = 120; back >= 0; back--)
      ...() {
        final DateTime day = addDays(_today, -back);
        final double before = _glasses(addDays(day, -1));
        return <DailyOutcome>[
          DailyOutcome(
            day,
            HealthMetric.restingHeartRate.id,
            56 + 1.6 * before + noise(3),
          ),
          DailyOutcome(
            day,
            HealthMetric.sleepAsleep.id,
            440 - 12 * before + noise(40),
          ),
        ];
      }(),
  ];
}();

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

// Today with Trends opened on Wine.
Future<void> _trendsOnWine(
  WidgetTester tester,
  GlobalKey frame, {
  List<Override> extra = const <Override>[],
}) async {
  await tester.pumpWidget(
    _app(frame, <Override>[
      ...extra,
      ...trendsOverrides(
        _habits,
        inRange(_journal),
        days: (DateTime day) => <ViceActivity>[
          for (final ViceActivity a in _journal)
            if (startOfDay(a.createdAt.toDate()) == day) a,
        ],
      ),
    ], const Scaffold(body: ViceTracker())),
  );
  await tester.pumpAndSettle();
  await openTrends(tester);
  await _tapIn(tester, find.widgetWithText(PillToggle, 'Wine'));
}

Future<void> _tapIn(WidgetTester tester, Finder finder) async {
  final Finder target = inTrends(finder).first;
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Widget _cardPage(Widget card) => CardPage(
  title: 'Insights',
  children: <Widget>[const CardSectionLabel(InsightsPage.setsOffHeading), card],
);

void main() {
  setUpAll(loadRenderFonts);

  testWidgets('units-edit-habit', (WidgetTester tester) async {
    _phone(tester, 844);
    final GlobalKey frame = GlobalKey();
    await tester.pumpWidget(
      _app(frame, habitOverrides(_habits), ViceForm(vice: _wine)),
    );
    await tester.pumpAndSettle();
    await _save(tester, frame, 'units-edit-habit');
  }, skip: _dir.isEmpty);

  testWidgets('trends-spend', (WidgetTester tester) async {
    _phone(tester, 1000);
    final GlobalKey frame = GlobalKey();
    await _trendsOnWine(tester, frame);
    await _tapIn(tester, find.text(TrendsSheet.spendLabel));
    await tester.ensureVisible(inTrends(find.text(TrendsSheet.title)).last);
    await tester.pumpAndSettle();
    await _save(tester, frame, 'trends-spend');
  }, skip: _dir.isEmpty);

  testWidgets(
    'trends-health',
    (WidgetTester tester) async {
      _phone(tester, 1000);
      final GlobalKey frame = GlobalKey();
      await _trendsOnWine(
        tester,
        frame,
        extra: <Override>[
          healthStateProvider.overrideWith((ref) async => HealthReady(_health)),
        ],
      );
      await _tapIn(tester, find.text(TrendsSheet.healthLabel));
      await _tapIn(tester, find.text('Resting heart rate'));
      await tester.ensureVisible(inTrends(find.text(TrendsSheet.title)).last);
      await tester.pumpAndSettle();
      await _save(tester, frame, 'trends-health');
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
    skip: _dir.isEmpty,
  );

  testWidgets('trends-triggers', (WidgetTester tester) async {
    _phone(tester, 1000);
    final GlobalKey frame = GlobalKey();
    await _trendsOnWine(tester, frame);
    await tester.ensureVisible(inTrends(find.text(TrendsSheet.triggersTitle)));
    await tester.pumpAndSettle();
    await _save(tester, frame, 'trends-triggers');
  }, skip: _dir.isEmpty);

  testWidgets('insights-place', (WidgetTester tester) async {
    _phone(tester, 520);
    final GlobalKey frame = GlobalKey();
    await tester.pumpWidget(
      _app(
        frame,
        const <Override>[],
        _cardPage(
          AtPlaceCardView(
            finding: const AtPlace(
              habitId: 'coffee',
              placeId: 1,
              days: 64,
              useShare: 0.58,
              timeShare: 0.34,
              effect: 0.24,
              interval: Interval(0.15, 0.33),
              pValue: 0.0004,
            ),
            habit: 'Coffee',
            place: 'Office',
            mark: const HabitMark(0),
            locale: formatLocale,
            top: 0,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _save(tester, frame, 'insights-place');
  }, skip: _dir.isEmpty);

  testWidgets('insights-calendar', (WidgetTester tester) async {
    _phone(tester, 560);
    final GlobalKey frame = GlobalKey();
    await tester.pumpWidget(
      _app(
        frame,
        const <Override>[],
        _cardPage(
          CalendarDayCardView(
            card: const CalendarDayCard(
              CalendarDay(
                habitId: 'wine',
                feature: CalendarDayFeature.meetingMinutes,
                cut: 120,
                usableDays: 118,
                moreDays: 52,
                effect: 0.21,
                interval: Interval(0.09, 0.33),
                pValue: 0.001,
              ),
              <CalendarDay>[
                CalendarDay(
                  habitId: 'wine',
                  feature: CalendarDayFeature.backToBack,
                  cut: 1,
                  usableDays: 118,
                  moreDays: 41,
                  effect: 0.14,
                  interval: Interval(0.03, 0.25),
                  pValue: 0.01,
                ),
              ],
            ),
            habit: 'Wine',
            mark: const HabitMark(1),
            locale: formatLocale,
            top: 0,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _save(tester, frame, 'insights-calendar');
  }, skip: _dir.isEmpty);

  testWidgets('picker-meeting-suggestion', (WidgetTester tester) async {
    _phone(tester, 844);
    final GlobalKey frame = GlobalKey();
    final GlobalKey<NavigatorState> navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      ProviderScope(
        child: RepaintBoundary(
          key: frame,
          child: MaterialApp(
            navigatorKey: navigator,
            debugShowCheckedModeBanner: false,
            theme: appTheme(Brightness.light),
            home: const Scaffold(),
          ),
        ),
      ),
    );
    showModalBottomSheet<void>(
      context: navigator.currentContext!,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (BuildContext context) => TriggerPickerSheet(
        viceName: 'Coffee',
        usual: const <String>['routine/morning', 'body/tired'],
        suggested: const <String>[meetingTrigger],
        onDone: (List<String> _) {},
      ),
    );
    await tester.pumpAndSettle();
    await _save(tester, frame, 'picker-meeting-suggestion');
  }, skip: _dir.isEmpty);
}
