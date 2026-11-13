// Renders the self-experiment's parts in the light theme to PNGs, to set
// beside docs/pitch/round-17/self-experiments/optionC.html: the button under a
// finding, the plan screen, Today's strip over a shaded dial, a clear result
// and a "can't tell" one (docs/pitch/round-18/built/self-experiments/):
//   flutter test test/experiment_render_test.dart --dart-define=RENDER_DIR=<dir>
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/design/app_theme.dart';
import 'package:tracker/design/habit_mark.dart';
import 'package:tracker/design/tokens.dart';
import 'package:tracker/experiment_page.dart';
import 'package:tracker/insights/experiment.dart';
import 'package:tracker/insights/stats.dart' as stats;
import 'package:tracker/insights/what_follows.dart';
import 'package:tracker/providers/experiment_provider.dart';
import 'package:tracker/providers/today_provider.dart';
import 'package:tracker/widgets/day_dial.dart';
import 'package:tracker/widgets/experiment_widgets.dart';
import 'package:tracker/widgets/settings_card.dart';

import 'insights_harness.dart';
import 'render_fonts.dart';

const String _dir = String.fromEnvironment('RENDER_DIR');

final DateTime _today = DateTime(2026, 11, 13);

final HabitFinding _wine = HabitFinding(
  habitId: 'wine',
  metricId: 'sleepDeep',
  lagDays: 1,
  usableDays: 212,
  exposedDays: 61,
  raw: null,
  effect: -14,
  interval: const stats.Interval(-22, -6),
  standardized: -0.5,
  pValue: 0.001,
);

ExperimentPlan _plan(String metric, {int seed = 3}) => ExperimentPlan.start(
  HabitFinding(
    habitId: 'wine',
    metricId: metric,
    lagDays: 1,
    usableDays: 212,
    exposedDays: 61,
    raw: null,
    effect: -14,
    interval: const stats.Interval(-22, -6),
    standardized: -0.5,
    pValue: 0.001,
  ),
  today: addDays(_today, -50),
  weeks: 6,
  seed: seed,
);

ExperimentResult _result(ExperimentPlan plan, double effect, int seed) {
  final Random r = Random(seed);
  double normal() =>
      sqrt(-2 * log(1 - r.nextDouble())) * cos(2 * pi * r.nextDouble());
  final List<({DateTime day, bool none})> days = plan.schedule;
  return analyseExperiment(
    plan,
    outcomes: <DateTime, double>{
      for (final (int i, ({DateTime day, bool none}) d) in days.indexed)
        if (i != 5 && i != 30)
          addDays(d.day, 1): 60 + 16 * normal() + (d.none ? effect : 0),
    },
    uses: <DateTime>[
      for (final ({DateTime day, bool none}) d
          in days.where((d) => d.none).skip(4).take(3))
        d.day.add(const Duration(hours: 20)),
    ],
  );
}

Future<void> _shoot(
  WidgetTester tester,
  GlobalKey frame,
  String name,
) => tester.runAsync(() async {
  final ui.Image image =
      await (frame.currentContext!.findRenderObject()! as RenderRepaintBoundary)
          .toImage(pixelRatio: 3);
  final ByteData? png = await image.toByteData(format: ui.ImageByteFormat.png);
  await File('$_dir/$name.png').writeAsBytes(png!.buffer.asUint8List());
});

void main() {
  setUpAll(loadRenderFonts);

  Future<GlobalKey> pump(
    WidgetTester tester,
    Widget home, {
    double height = 844,
  }) async {
    debugDisableShadows = false;
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = Size(390 * 3, height * 3);
    tester.view.padding = const FakeViewPadding(top: 47 * 3, bottom: 34 * 3);
    addTearDown(tester.view.reset);
    final GlobalKey frame = GlobalKey();
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          todayProvider.overrideWith(() => FixedToday(_today)),
          experimentSpreadProvider.overrideWith((Ref ref, String _) => 16),
        ],
        child: RepaintBoundary(
          key: frame,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: appTheme(Brightness.light),
            home: home,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return frame;
  }

  Widget page(List<Widget> children) => Scaffold(
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(DialSpace.gutter),
        children: children,
      ),
    ),
  );

  testWidgets('finding card button', (WidgetTester tester) async {
    final GlobalKey frame = await pump(
      tester,
      page(<Widget>[
        DialCard(
          top: 0,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
              child: ExperimentButton(onPressed: () {}),
            ),
          ],
        ),
      ]),
      height: 300,
    );
    await _shoot(tester, frame, 'experiment-button-light');
    debugDisableShadows = true;
  }, skip: _dir.isEmpty);

  testWidgets('plan screen', (WidgetTester tester) async {
    final GlobalKey frame = await pump(
      tester,
      ExperimentPage.plan(finding: _wine, habit: 'Wine'),
      height: 1100,
    );
    await _shoot(tester, frame, 'experiment-plan-light');
    debugDisableShadows = true;
  }, skip: _dir.isEmpty);

  testWidgets('Today strip and shaded dial', (WidgetTester tester) async {
    final ExperimentPlan plan = ExperimentPlan.start(
      _wine,
      today: addDays(_today, -9),
      weeks: 6,
      seed: 1,
    );
    DateTime day = _today;
    while (plan.noneOn(day) != true) {
      day = addDays(day, 1);
    }
    final GlobalKey frame = await pump(
      tester,
      page(<Widget>[
        ExperimentStrip(plan: plan, habit: 'Wine', day: day, locale: 'en'),
        Center(
          child: SizedBox.square(
            dimension: DialSize.dialDiameter,
            child: DayDial(
              day: day,
              today: day,
              entries: const <DialEntry>[],
              semanticsLabel: 'Today',
              shadeFromMinute: plan.fromHour * 60,
            ),
          ),
        ),
      ]),
      height: 600,
    );
    await _shoot(tester, frame, 'experiment-today-light');
    debugDisableShadows = true;
  }, skip: _dir.isEmpty);

  testWidgets('result cards', (WidgetTester tester) async {
    final ExperimentPlan clear = _plan('sleepDeep');
    final ExperimentPlan unclear = _plan('sleepAsleep', seed: 9);
    final GlobalKey frame = await pump(
      tester,
      page(<Widget>[
        const CardSectionLabel('Your experiment'),
        ExperimentResultCard(
          plan: clear,
          result: _result(clear, 20, 4),
          habit: 'Wine',
          mark: const HabitMark(1),
          locale: 'en',
          top: 0,
        ),
        ExperimentResultCard(
          plan: unclear,
          result: _result(unclear, 0, 5),
          habit: 'Coffee',
          mark: const HabitMark(0),
          locale: 'en',
          top: DialSpace.xs,
          onRunOn: () {},
        ),
      ]),
      height: 900,
    );
    await _shoot(tester, frame, 'experiment-results-light');
    debugDisableShadows = true;
  }, skip: _dir.isEmpty);
}
