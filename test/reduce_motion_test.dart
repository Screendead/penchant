import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tracker/design/app_theme.dart';
import 'package:tracker/main.dart';
import 'package:tracker/providers/account_provider.dart';
import 'package:tracker/providers/package_info_provider.dart';
import 'package:tracker/providers/reduce_motion_provider.dart';
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/reduce_motion_settings.dart';
import 'package:tracker/settings.dart';
import 'package:tracker/trends/trends_chart.dart';
import 'package:tracker/widgets/pill_drop.dart';
import 'package:tracker/widgets/reduce_motion_scope.dart';
import 'package:tracker/widgets/undo_bar.dart';

import 'fake_account.dart';

/// Reads the flag the way every animated widget in the app does.
class _Probe extends StatelessWidget {
  const _Probe();

  @override
  Widget build(BuildContext context) =>
      Text('reduced: ${MediaQuery.disableAnimationsOf(context)}');
}

Widget _app({
  required bool system,
  Widget home = const _Probe(),
  List<Override> overrides = const <Override>[],
}) => ProviderScope(
  overrides: overrides,
  child: MediaQuery(
    data: MediaQueryData(disableAnimations: system),
    child: MaterialApp(
      theme: appTheme(Brightness.light),
      onGenerateRoute: generateRoute,
      home: home,
      builder: (BuildContext context, Widget? child) =>
          ReduceMotionScope(child: child!),
    ),
  ),
);

Widget _settingsApp({required bool system}) => _app(
  system: system,
  home: const Settings(),
  overrides: [
    accountProvider.overrideWithValue(FakeAccount()),
    exportShareProvider.overrideWithValue(FakeExportShare()),
    userProvider.overrideWith((ref) => Stream.value(null)),
    userProfileProvider.overrideWith((ref) => Stream.value(null)),
    packageInfoProvider.overrideWith(
      (ref) async => PackageInfo(
        appName: 'Penchant',
        packageName: 'penchant',
        version: '0.2.0',
        buildNumber: '212',
      ),
    ),
  ],
);

void main() {
  test(
    'a saved choice is read back; anything else follows the system',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        ReduceMotion.key: 'full',
      });
      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(reduceMotionProvider), MotionPreference.system);
      await pumpEventQueue();
      expect(container.read(reduceMotionProvider), MotionPreference.full);

      expect(ReduceMotion.parse('slow'), isNull);
      expect(ReduceMotion.parse(null), isNull);
    },
  );

  test('each choice resolves against the system flag', () {
    expect(MotionPreference.system.resolve(system: true), isTrue);
    expect(MotionPreference.system.resolve(system: false), isFalse);
    expect(MotionPreference.reduce.resolve(system: false), isTrue);
    expect(MotionPreference.full.resolve(system: true), isFalse);
  });

  for (final bool system in <bool>[false, true]) {
    testWidgets('system with the system at $system reads $system', (
      WidgetTester tester,
    ) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        ReduceMotion.key: MotionPreference.system.name,
      });
      await tester.pumpWidget(_app(system: system));
      await tester.pump();
      expect(find.text('reduced: $system'), findsOneWidget);
    });
  }

  testWidgets('pushed routes, dialogs and sheets read the override', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      ReduceMotion.key: 'reduce',
    });
    await tester.pumpWidget(_app(system: false));
    await tester.pump();
    final NavigatorState navigator = tester.state(find.byType(Navigator));

    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Center(child: _Probe())),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('reduced: true'), findsOneWidget);

    showDialog<void>(
      context: navigator.context,
      builder: (_) => const AlertDialog(title: _Probe()),
    );
    await tester.pumpAndSettle();
    expect(find.text('reduced: true'), findsNWidgets(2));
    navigator.pop();
    await tester.pumpAndSettle();

    showModalBottomSheet<void>(
      context: navigator.context,
      builder: (_) => const _Probe(),
    );
    await tester.pumpAndSettle();
    expect(find.text('reduced: true'), findsNWidgets(2));
    expect(find.text('reduced: false'), findsNothing);
  });

  testWidgets('Settings › Reduce motion applies at once and saves the choice', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await tester.pumpWidget(_settingsApp(system: false));
    await tester.pumpAndSettle();

    expect(find.text('Follows iOS'), findsOneWidget);
    await tester.tap(find.text('Reduce motion'));
    await tester.pumpAndSettle();
    expect(find.byType(ReduceMotionSettings), findsOneWidget);
    expect(find.text('Follow system'), findsOneWidget);
    expect(find.text('Reduce'), findsOneWidget);
    expect(find.text('Full'), findsOneWidget);

    BuildContext context() => tester.element(find.byType(ReduceMotionSettings));
    expect(MediaQuery.disableAnimationsOf(context()), isFalse);
    await tester.tap(find.text('Reduce'));
    await tester.pumpAndSettle();
    expect(MediaQuery.disableAnimationsOf(context()), isTrue);
    expect(
      tester.getSemantics(find.text('Reduce')),
      matchesSemantics(
        label: 'Reduce',
        isButton: true,
        hasSelectedState: true,
        isSelected: true,
        isInMutuallyExclusiveGroup: true,
        hasTapAction: true,
        hasFocusAction: true,
        isFocusable: true,
        hasEnabledState: false,
      ),
    );
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(ReduceMotion.key), 'reduce');

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Reduce'), findsOneWidget);
    expect(find.text('Follows iOS'), findsNothing);
  });

  group('Full with iOS Reduce Motion on keeps the app\'s own motion', () {
    // Flutter scales every default AnimationController by 0.05 while the
    // platform flag is set, whatever MediaQuery says.
    Future<void> fullOnReducingSystem(WidgetTester tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      SharedPreferences.setMockInitialValues(<String, Object>{
        ReduceMotion.key: 'full',
      });
      await tester.pumpWidget(
        _app(system: true, home: const Scaffold(body: _Probe())),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('reduced: false'), findsOneWidget);
    }

    testWidgets('the Undo countdown runs over its five seconds', (
      WidgetTester tester,
    ) async {
      await fullOnReducingSystem(tester);
      showUndoBar(
        ScaffoldMessenger.of(tester.element(find.byType(_Probe))),
        const TextSpan(text: 'Logged'),
        onUndo: () {},
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      final CircularProgressIndicator ring = tester.widget(
        find.byType(CircularProgressIndicator),
      );
      expect(ring.value, greaterThan(0.9));
      await tester.pumpAndSettle(const Duration(seconds: 10));
    });

    testWidgets('a pushed page keeps its transition clock', (
      WidgetTester tester,
    ) async {
      await fullOnReducingSystem(tester);
      final NavigatorState navigator = tester.state(find.byType(Navigator));
      final TransitionRoute<void> route =
          generateRoute(const RouteSettings(name: '/nowhere'))
              as TransitionRoute<void>;
      navigator.push(route);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(route.animation!.value, lessThan(0.5));
      await tester.pumpAndSettle();
    });

    testWidgets('the Trends chart morphs between ranges over 450 ms', (
      WidgetTester tester,
    ) async {
      await fullOnReducingSystem(tester);
      final List<MorphFrame?> frames = <MorphFrame?>[];
      Widget morph(int days, double value) => _app(
        system: true,
        home: RangeMorph(
          shape: (days: days, stepDays: 1),
          totals: List<double>.filled(days, value),
          smoothed: null,
          top: value,
          builder: (BuildContext context, MorphFrame? frame, bool tween) {
            frames.add(frame);
            return const SizedBox();
          },
        ),
      );
      await tester.pumpWidget(morph(7, 2));
      await tester.pumpWidget(morph(30, 6));
      await tester.pump(const Duration(milliseconds: 225));
      expect(frames.last, isNotNull);
      expect(frames.last!.top, inExclusiveRange(2, 6));
      await tester.pumpAndSettle();
    });

    testWidgets('a status pill drops in on its spring', (
      WidgetTester tester,
    ) async {
      await fullOnReducingSystem(tester);
      Widget pill({required bool shown}) => _app(
        system: true,
        home: Scaffold(
          body: Column(
            children: <Widget>[
              PillDrop(shown: shown, child: const Text('Offline')),
            ],
          ),
        ),
      );
      await tester.pumpWidget(pill(shown: false));
      await tester.pumpWidget(pill(shown: true));
      await tester.pump(const Duration(milliseconds: 50));
      final double y = tester
          .widget<Transform>(
            find
                .ancestor(
                  of: find.text('Offline'),
                  matching: find.byType(Transform),
                )
                .first,
          )
          .transform
          .getTranslation()
          .y;
      expect(y, lessThan(0));
      await tester.pumpAndSettle();
    });
  });

  testWidgets('Reduce with iOS Reduce Motion on keeps a pill\'s fade', (
    WidgetTester tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    SharedPreferences.setMockInitialValues(<String, Object>{
      ReduceMotion.key: 'reduce',
    });
    Widget pill({required bool shown}) => _app(
      system: true,
      home: Scaffold(
        body: Column(
          children: <Widget>[
            PillDrop(shown: shown, child: const Text('Offline')),
          ],
        ),
      ),
    );
    await tester.pumpWidget(pill(shown: false));
    await tester.pump();
    await tester.pumpWidget(pill(shown: true));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    final Opacity fade = tester.widget(
      find.ancestor(of: find.text('Offline'), matching: find.byType(Opacity)),
    );
    expect(fade.opacity, inExclusiveRange(0, 1));
    await tester.pumpAndSettle();
  });
}
