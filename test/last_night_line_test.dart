import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/design/app_theme.dart';
import 'package:tracker/insights/last_night.dart';
import 'package:tracker/insights_page.dart';
import 'package:tracker/widgets/last_night_line.dart';

import 'last_night_fakes.dart';

const LastNight _above = LastNight(
  sleepingHeartRate: NightCompare(value: 57, usual: 54, low: 53, high: 55),
);

Future<List<String>> _pump(
  WidgetTester tester,
  List<Override> overrides,
) async {
  final List<String> opened = <String>[];
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: appTheme(Brightness.light),
        home: const Scaffold(body: LastNightLine()),
        onGenerateRoute: (RouteSettings settings) {
          opened.add(settings.name!);
          return MaterialPageRoute<void>(builder: (_) => const Scaffold());
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
  return opened;
}

void main() {
  testWidgets('in the morning, last night\'s sleeping heart rate against the '
      'usual, opening Insights', (WidgetTester tester) async {
    final List<String> opened = await _pump(
      tester,
      lastNightLineOverrides(_above),
    );

    expect(
      find.text(
        'Last night · heart rate 3 bpm above usual',
        findRichText: true,
      ),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(
        'Last night, sleeping heart rate 3 bpm above your usual',
      ),
      findsOneWidget,
    );
    await tester.tap(find.byType(LastNightLine));
    await tester.pumpAndSettle();
    expect(opened, <String>[InsightsPage.route]);
  });

  testWidgets('nothing from noon', (WidgetTester tester) async {
    await _pump(tester, lastNightLineOverrides(_above, morning: false));
    expect(find.textContaining('Last night', findRichText: true), findsNothing);
  });

  testWidgets('nothing without last night\'s sleeping heart rate, even with '
      'the rest', (WidgetTester tester) async {
    await _pump(
      tester,
      lastNightLineOverrides(
        const LastNight(
          asleep: NightCompare(value: 300, usual: 430, low: 400, high: 450),
        ),
      ),
    );
    expect(find.textContaining('Last night', findRichText: true), findsNothing);
  });

  test('a night inside the usual range says so', () {
    expect(
      LastNightLine.body(
        const NightCompare(value: 54.4, usual: 54, low: 53, high: 55),
      ),
      'heart rate within usual',
    );
    expect(
      LastNightLine.body(
        const NightCompare(value: 50.6, usual: 54, low: 53, high: 55),
      ),
      'heart rate 3 bpm below usual',
    );
  });
}
