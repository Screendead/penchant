import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tracker/appearance_settings.dart';
import 'package:tracker/design/app_theme.dart';
import 'package:tracker/main.dart';
import 'package:tracker/providers/account_provider.dart';
import 'package:tracker/providers/appearance_provider.dart';
import 'package:tracker/providers/package_info_provider.dart';
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/settings.dart';

import 'fake_account.dart';

Widget _settingsApp({FakeExportShare? share}) => ProviderScope(
  overrides: [
    accountProvider.overrideWithValue(FakeAccount()),
    exportShareProvider.overrideWithValue(share ?? FakeExportShare()),
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
  child: Consumer(
    builder: (BuildContext context, WidgetRef ref, _) => MaterialApp(
      theme: appTheme(Brightness.light),
      darkTheme: appTheme(Brightness.dark),
      themeMode: ref.watch(appearanceProvider),
      onGenerateRoute: generateRoute,
      home: const Settings(),
    ),
  ),
);

void main() {
  test(
    'a saved choice is read back; anything else matches the system',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        Appearance.key: 'dark',
      });
      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(appearanceProvider), ThemeMode.system);
      await pumpEventQueue();
      expect(container.read(appearanceProvider), ThemeMode.dark);

      expect(Appearance.parse('sepia'), isNull);
      expect(Appearance.parse(null), isNull);
    },
  );

  testWidgets('Settings › Appearance switches the theme and saves the choice', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await tester.pumpWidget(_settingsApp());
    await tester.pumpAndSettle();

    expect(find.text('Match system'), findsOneWidget);
    await tester.tap(find.text('Appearance'));
    await tester.pumpAndSettle();
    expect(find.byType(AppearanceSettings), findsOneWidget);

    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.dark,
    );
    expect(
      Theme.of(tester.element(find.text('Dark'))).brightness,
      Brightness.dark,
    );
    expect(
      tester.getSemantics(find.text('Dark')),
      matchesSemantics(
        label: 'Dark',
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
    expect(prefs.getString(Appearance.key), 'dark');

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Dark'), findsOneWidget);
    expect(find.text('Match system'), findsNothing);
  });

  testWidgets('Settings › Export my data shares the CSV and JSON', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final FakeExportShare share = FakeExportShare();
    await tester.pumpWidget(_settingsApp(share: share));
    await tester.pumpAndSettle();

    expect(find.text('CSV, JSON'), findsOneWidget);
    await tester.tap(find.text('Export my data'));
    await tester.pumpAndSettle();

    expect(share.shared, hasLength(1));
    expect(
      share.shared.single.map((f) => f.name.split('.').last),
      containsAll(<String>['csv', 'json']),
    );
  });
}
