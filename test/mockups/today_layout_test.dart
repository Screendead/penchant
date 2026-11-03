// Renders the Today layout mock-ups to docs/pitch/mockups/today-layout/.
// flutter test test/mockups --update-goldens

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/mockups/today_layout/chart_today.dart';
import 'package:tracker/mockups/today_layout/fixtures.dart';
import 'package:tracker/mockups/today_layout/journal_today.dart';
import 'package:tracker/mockups/today_layout/shared.dart';
import 'package:tracker/mockups/today_layout/tiles_today.dart';

const String _out = '../../docs/pitch/mockups/today-layout';
const Key _frame = ValueKey('frame');

Future<void> _loadFont(String family, List<String> files) async {
  final String dir =
      '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts';
  final FontLoader loader = FontLoader(family);
  for (final String file in files) {
    final Uint8List bytes = File('$dir/$file').readAsBytesSync();
    loader.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  await loader.load();
}

Future<void> _render(
  WidgetTester tester,
  Widget screen,
  String name, {
  double height = 852,
  Future<void> Function()? interact,
}) async {
  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = Size(393 * 3, height * 3);
  // iPhone status bar and home indicator.
  tester.view.padding = const FakeViewPadding(top: 59 * 3, bottom: 34 * 3);
  addTearDown(tester.view.reset);
  // Off, Card elevation renders as a hard outline. The binding checks it is
  // back on before tearDown runs.
  debugDisableShadows = false;

  // Captured above the Navigator so routes such as sheets are in the image.
  await tester.pumpWidget(
    RepaintBoundary(
      key: _frame,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: mockAppTheme(),
        home: screen,
      ),
    ),
  );
  // Stream.value delivers after the first frame; fl_chart animates for 600ms.
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  if (interact != null) {
    await interact();
    await tester.pump(const Duration(seconds: 1));
  }

  try {
    await expectLater(find.byKey(_frame), matchesGoldenFile('$_out/$name.png'));
  } finally {
    debugDisableShadows = true;
  }
}

void main() {
  setUpAll(() async {
    await _loadFont('Roboto', [
      'Roboto-Light.ttf',
      'Roboto-Regular.ttf',
      'Roboto-Italic.ttf',
      'Roboto-Medium.ttf',
      'Roboto-Bold.ttf',
    ]);
    await _loadFont('MaterialIcons', ['MaterialIcons-Regular.otf']);
  });

  final Map<String, MockDay> days = {
    '2-vices': twoVices,
    '5-vices': fiveVices,
    'clean-day': cleanDay,
  };

  for (final MapEntry(key: String suffix, value: MockDay day) in days.entries) {
    testWidgets('A journal $suffix', (WidgetTester tester) async {
      await _render(tester, JournalToday(day: day), 'a-journal-$suffix');
    });
    testWidgets('B tiles $suffix', (WidgetTester tester) async {
      await _render(tester, TilesToday(day: day), 'b-tiles-$suffix');
    });
    testWidgets('C chart $suffix', (WidgetTester tester) async {
      await _render(tester, ChartToday(day: day), 'c-chart-$suffix');
    });
  }

  testWidgets('B tiles, after a tap on Wine', (WidgetTester tester) async {
    await _render(
      tester,
      TilesToday(day: fiveVicesAfterWineTap),
      'b-tiles-5-vices-tapped',
      interact: () async {
        await tester.tap(find.byKey(const ValueKey('tile-wine')));
        await tester.pump();
        expect(find.byType(QuickLogSheet), findsOneWidget);
      },
    );
  });

  testWidgets('A journal 5-vices, whole page', (WidgetTester tester) async {
    await _render(
      tester,
      JournalToday(day: fiveVices),
      'a-journal-5-vices-full',
      height: 1640,
    );
  });
}
