// Run with --dart-define=RENDER_DIR=<dir> to also save the day-tag cards and
// the drill-in page as PNGs, light and dark, 390x844:
//   flutter test test/insights_day_tags_page_test.dart --dart-define=RENDER_DIR=<dir>
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tracker/data/unit.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/design/app_theme.dart';
import 'package:tracker/design/tokens.dart';
import 'package:tracker/insights/day_tags.dart';
import 'package:tracker/insights/health_source.dart';
import 'package:tracker/insights/insights_report.dart';
import 'package:tracker/insights/trigger_amounts.dart';
import 'package:tracker/insights/what_follows.dart';
import 'package:tracker/insights_page.dart';
import 'package:tracker/providers/insights_provider.dart';
import 'package:tracker/widgets/day_tags_card.dart';

import 'fakes.dart';
import 'insights_harness.dart';

const String _dir = String.fromEnvironment('RENDER_DIR');

final List<Vice> _vices = <Vice>[
  fakeVice('wine', name: 'Wine', unit: Unit.drink),
  fakeVice('coffee', name: 'Coffee', unit: Unit.drink),
  fakeVice('tea', name: 'Tea', unit: Unit.drink),
];

DayTagAmount _tag(
  String tag, {
  double withMean = 3.1,
  double withoutMean = 1.8,
  int withDays = 15,
  RefusalReason? refusal,
}) => DayTagAmount(
  tag: tag,
  withDays: withDays,
  withoutDays: 48 - withDays,
  withMean: withMean,
  withoutMean: withoutMean,
  effect: refusal == null ? withMean - withoutMean : null,
  pValue: refusal == null ? 0.0004 : null,
  refusal: refusal,
);

final InsightsReport _report = InsightsReport(
  findings: const <HabitFinding>[],
  refused: const <HabitRefusal>[],
  dayTags: <HabitDayTags>[
    HabitDayTags(
      habitId: 'wine',
      days: 130,
      tagged: 48,
      tags: <DayTagAmount>[
        _tag('Bad day'),
        _tag('work', withMean: 1.2, withoutMean: 2.3, withDays: 20),
      ],
    ),
    HabitDayTags(
      habitId: 'coffee',
      days: 120,
      tagged: 48,
      tags: <DayTagAmount>[
        _tag('feeling/stressed', withMean: 4.2, withoutMean: 2.6),
      ],
    ),
    HabitDayTags(
      habitId: 'tea',
      days: 90,
      tagged: 21,
      tags: <DayTagAmount>[
        _tag('social', withDays: 4, refusal: RefusalReason.tooFewDays),
      ],
    ),
  ],
  triggers: const <HabitTriggers>[
    HabitTriggers(
      habitId: 'coffee',
      entries: 140,
      tagged: 70,
      triggers: <TriggerAmount>[
        TriggerAmount(
          trigger: 'feeling/stressed',
          entries: 30,
          withDays: 18,
          withoutDays: 25,
          withMean: 2.9,
          withoutMean: 2,
          pValue: 0.001,
          verdict: TriggerVerdict.found,
        ),
      ],
    ),
  ],
);

Future<void> _pump(
  WidgetTester tester, {
  Size size = const Size(800, 4000),
  double ratio = 1,
  Brightness brightness = Brightness.light,
  GlobalKey? frame,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    healthConnectedKey: true,
  });
  tester.view.physicalSize = size * ratio;
  tester.view.devicePixelRatio = ratio;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: insightsOverrides(
        health: FakeHealthSource(read: HealthValues(insightsJournal().health)),
        vices: AsyncData<List<Vice>>(_vices),
        runner: (_) async => _report,
      ),
      child: RepaintBoundary(
        key: frame,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: appTheme(brightness),
          home: const InsightsPage(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _loadFonts() async {
  for (final (String family, String file) in <(String, String)>[
    (DialFonts.display, 'RedHatDisplay'),
    (DialFonts.text, 'RedHatText'),
    (DialFonts.mono, 'RedHatMono'),
  ]) {
    await (FontLoader(
      family,
    )..addFont(rootBundle.load('assets/fonts/$file-Variable.ttf'))).load();
  }
}

void main() {
  group('renders', () {
    setUpAll(_loadFonts);
    for (final Brightness brightness in Brightness.values) {
      for (final String scene in <String>['card', 'joined', 'refusal']) {
        testWidgets('day tags, $scene, ${brightness.name}', (
          WidgetTester tester,
        ) async {
          final GlobalKey frame = GlobalKey();
          await _pump(
            tester,
            size: const Size(390, 844),
            ratio: 3,
            brightness: brightness,
            frame: frame,
          );
          if (scene == 'refusal') {
            await tester.scrollUntilVisible(
              find.text(InsightsPage.setsOffWhyNot),
              300,
              scrollable: find.byType(Scrollable).first,
            );
            await tester.tap(find.text(InsightsPage.setsOffWhyNot));
          } else {
            final Finder card = find.byType(DayTagsCard);
            await tester.scrollUntilVisible(
              card.first,
              300,
              scrollable: find.byType(Scrollable).first,
            );
            await tester.pumpAndSettle();
            await tester.ensureVisible(
              scene == 'card' ? card.first : card.at(1),
            );
          }
          await tester.pumpAndSettle();
          await tester.runAsync(() async {
            final ui.Image image =
                await (frame.currentContext!.findRenderObject()!
                        as RenderRepaintBoundary)
                    .toImage(pixelRatio: 3);
            final ByteData? png = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await File(
              '$_dir/day-tags-$scene-${brightness.name}.png',
            ).writeAsBytes(png!.buffer.asUint8List());
          });
        }, skip: _dir.isEmpty);
      }
    }
  });
}
