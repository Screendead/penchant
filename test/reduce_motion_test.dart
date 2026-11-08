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
import 'package:tracker/widgets/reduce_motion_scope.dart';

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
    for (final (MotionPreference, bool) c in <(MotionPreference, bool)>[
      (MotionPreference.system, system),
      (MotionPreference.reduce, true),
      (MotionPreference.full, false),
    ]) {
      testWidgets('${c.$1.name} with the system at $system reads ${c.$2}', (
        WidgetTester tester,
      ) async {
        SharedPreferences.setMockInitialValues(<String, Object>{
          ReduceMotion.key: c.$1.name,
        });
        await tester.pumpWidget(_app(system: system));
        await tester.pump();
        expect(find.text('reduced: ${c.$2}'), findsOneWidget);
      });
    }
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

  testWidgets('Full overrides a system that reduces motion', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await tester.pumpWidget(_settingsApp(system: true));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reduce motion'));
    await tester.pumpAndSettle();

    BuildContext context() => tester.element(find.byType(ReduceMotionSettings));
    expect(MediaQuery.disableAnimationsOf(context()), isTrue);
    await tester.tap(find.text('Full'));
    await tester.pumpAndSettle();
    expect(MediaQuery.disableAnimationsOf(context()), isFalse);
  });
}
