import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tracker/design/app_theme.dart';
import 'package:tracker/insights/habit_follows.dart';
import 'package:tracker/insights/health_source.dart';
import 'package:tracker/insights/insights_report.dart';
import 'package:tracker/insights/what_follows.dart';
import 'package:tracker/insights_page.dart';
import 'package:tracker/providers/insights_provider.dart';
import 'package:tracker/widgets/habit_follows_card.dart';

import 'insights_harness.dart';

HabitFollows _pair(
  String lead,
  String follower, {
  double share = 0.62,
  double chance = 0.18,
  FollowsVerdict verdict = FollowsVerdict.found,
}) => HabitFollows(
  leadId: lead,
  followerId: follower,
  days: 61,
  followedDays: 40,
  uses: 84,
  share: share,
  chance: chance,
  pValue: 0.0001,
  verdict: verdict,
);

Future<void> _pump(WidgetTester tester, List<HabitFollows> follows) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    healthConnectedKey: true,
  });
  tester.view.physicalSize = const Size(800, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final List<Override> overrides = insightsOverrides(
    health: FakeHealthSource(read: HealthValues(insightsJournal().health)),
    runner: (_) async => InsightsReport(
      findings: const <HabitFinding>[],
      refused: const <HabitRefusal>[],
      follows: follows,
    ),
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: appTheme(Brightness.light),
        home: const InsightsPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  const String sentence =
      'Coffee and Tea tend to come together: you log Tea in the 15 minutes '
      'after Coffee 62% of the time. Your usual timing of each would give '
      '18%.';
  const String basis = 'From 84 uses of Coffee on 61 days with both';
  const String line =
      'With Water: 40% of the time, against 18% by your usual timing';

  testWidgets('a habit that follows another within minutes gets a card '
      'under What sets it off, in plain words', (WidgetTester tester) async {
    await _pump(tester, <HabitFollows>[
      _pair('coffee', 'tea'),
      _pair('water', 'tea', share: 0.4),
    ]);

    expect(find.byType(HabitFollowsCard), findsOneWidget);
    expect(find.text(sentence), findsOneWidget);
    expect(find.text(basis), findsOneWidget);
    expect(find.text(line), findsOneWidget);
    expect(find.text(InsightsPage.setsOffBody), findsNothing);
    expect(
      tester.getTopLeft(find.text(sentence)).dy,
      greaterThan(tester.getTopLeft(find.text(InsightsPage.setsOffHeading)).dy),
    );
  });

  testWidgets('a pair that is not a finding, or names a habit the page does '
      'not know, shows nothing', (WidgetTester tester) async {
    await _pump(tester, <HabitFollows>[
      _pair('coffee', 'tea', verdict: FollowsVerdict.chance),
      _pair('water', 'tea', verdict: FollowsVerdict.tooFewDays),
      _pair('coffee', 'water', verdict: FollowsVerdict.tooSmall),
      _pair('gone', 'coffee'),
      _pair('tea', 'gone'),
    ]);

    expect(find.byType(HabitFollowsCard), findsNothing);
    expect(find.text(InsightsPage.setsOffBody), findsOneWidget);
  });

  testWidgets('habits with no card say why behind a row, one line each', (
    WidgetTester tester,
  ) async {
    await _pump(tester, <HabitFollows>[
      _pair('coffee', 'tea', verdict: FollowsVerdict.chance),
      _pair('water', 'tea', verdict: FollowsVerdict.tooFewDays),
      _pair('coffee', 'water', verdict: FollowsVerdict.tooSmall),
      _pair('gone', 'coffee'),
    ]);

    expect(find.text(InsightsPage.setsOffWhyNot), findsOneWidget);
    await tester.tap(find.text(InsightsPage.setsOffWhyNot));
    await tester.pumpAndSettle();

    expect(find.byType(InsightsSetsOffPage), findsOneWidget);
    expect(find.text(InsightsPage.refusedHeading), findsOneWidget);
    for (final String other in <String>['Water', 'Coffee']) {
      expect(
        find.text(
          'With $other: too small to matter, under 10 points over your usual '
          'timing',
        ),
        findsOneWidget,
      );
    }
    expect(
      find.text('With Coffee: could be chance, one of many comparisons'),
      findsOneWidget,
    );
  });

  testWidgets('Copy as text carries the card under its heading', (
    WidgetTester tester,
  ) async {
    final List<String?> copied = <String?>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add(
            (call.arguments as Map<Object?, Object?>)['text'] as String?,
          );
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await _pump(tester, <HabitFollows>[
      _pair('coffee', 'tea'),
      _pair('water', 'tea', share: 0.4),
    ]);

    await tester.tap(find.text(InsightsPage.copyLabel));
    await tester.pump();

    expect(
      copied.single,
      contains(
        '\n${InsightsPage.setsOffHeading}\n\nTea\n$sentence\n$basis\n$line\n'
        '\n${InsightsPage.foot}\n',
      ),
    );
  });

  test('the copied text has no such heading without a card', () {
    expect(
      insightsText(
        cards: const <InsightCard>[],
        refused: const <HabitRefusal>[],
        firstDay: null,
        nameOf: (String id) => id,
        locale: 'en',
      ),
      isNot(contains(InsightsPage.setsOffHeading)),
    );
  });

  test('the engine judges pairs in the report, saying nothing of an archived '
      'habit', () {
    final InsightsReport report = computeInsights(
      InsightsInput.from(
        activities: insightsJournal().activities,
        health: insightsJournal().health,
        today: insightsToday,
        archived: const <String>{'tea'},
      ),
    );

    expect(report.follows, isNotEmpty);
    for (final HabitFollows f in report.follows) {
      expect(f.verdict, isNotNull);
      expect(<String>[f.leadId, f.followerId], isNot(contains('tea')));
    }
  });
}
