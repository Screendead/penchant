// Renders sign-in, sign-up, Settings, Appearance and Account Settings at the Day Dial mock-up's size and
// text, for side-by-side comparison with it (tools/fidelity/README.md):
//   flutter test test/fidelity_account_render_test.dart --dart-define=RENDER_DIR=<dir>
import 'dart:io';
import 'dart:ui' as ui;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tracker/account_settings.dart';
import 'package:tracker/appearance_settings.dart';
import 'package:tracker/authenticate.dart';
import 'package:tracker/design/app_theme.dart';
import 'package:tracker/providers/account_provider.dart';
import 'package:tracker/providers/package_info_provider.dart';
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/settings.dart';

import 'fake_account.dart';
import 'fakes.dart';
import 'render_fonts.dart';

const String _dir = String.fromEnvironment('RENDER_DIR');

void main() {
  setUpAll(loadRenderFonts);
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));
  for (final Brightness brightness in Brightness.values) {
    for (final String name in <String>[
      'signin',
      'signup',
      'settings',
      'account',
      'appearance',
    ]) {
      testWidgets('fidelity $name ${brightness.name}', (
        WidgetTester tester,
      ) async {
        debugDisableShadows = false;
        tester.view.devicePixelRatio = 3;
        tester.view.physicalSize = const Size(390 * 3, 844 * 3);
        tester.view.padding = const FakeViewPadding(
          top: 47 * 3,
          bottom: 34 * 3,
        );
        tester.platformDispatcher.platformBrightnessTestValue = brightness;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        final User user = FakeUser(ownerID, email: 'sam@example.com');
        final GlobalKey frame = GlobalKey();
        final GlobalKey<NavigatorState> navigator = GlobalKey<NavigatorState>();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              accountProvider.overrideWithValue(FakeAccount()),
              exportShareProvider.overrideWithValue(FakeExportShare()),
              userProvider.overrideWith((ref) => Stream.value(user)),
              userProfileProvider.overrideWith((ref) => Stream.value(user)),
              packageInfoProvider.overrideWith(
                (ref) async => PackageInfo(
                  appName: 'Penchant',
                  packageName: 'penchant',
                  version: '0.2.0',
                  buildNumber: '212',
                ),
              ),
            ],
            child: RepaintBoundary(
              key: frame,
              child: MaterialApp(
                navigatorKey: navigator,
                debugShowCheckedModeBanner: false,
                theme: appTheme(Brightness.light),
                darkTheme: appTheme(Brightness.dark),
                home:
                    const <String>{
                      'settings',
                      'account',
                      'appearance',
                    }.contains(name)
                    ? const Scaffold()
                    : const Authenticate(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        if (const <String>{
          'settings',
          'account',
          'appearance',
        }.contains(name)) {
          navigator.currentState!.push(
            MaterialPageRoute<void>(
              builder: (_) => switch (name) {
                'settings' => const Settings(),
                'appearance' => const AppearanceSettings(),
                _ => const AccountSettings(),
              },
            ),
          );
          await tester.pumpAndSettle();
        } else {
          if (name == 'signup') {
            await tester.tap(find.byKey(Authenticate.registerTab));
            await tester.pumpAndSettle();
          }
          final Finder fields = find.byType(TextFormField);
          await tester.enterText(fields.at(0), 'sam@example.com');
          if (name == 'signup') {
            await tester.enterText(fields.at(1), 'Morning7');
            await tester.enterText(fields.at(2), 'Morning');
          } else {
            await tester.enterText(fields.at(1), 'quiet-morning');
          }
          FocusManager.instance.primaryFocus?.unfocus();
          await tester.pumpAndSettle();
        }
        await tester.runAsync(() async {
          final ui.Image image =
              await (frame.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage(pixelRatio: 3);
          final ByteData? png = await image.toByteData(
            format: ui.ImageByteFormat.png,
          );
          await File(
            '$_dir/app-$name-${brightness.name}.png',
          ).writeAsBytes(png!.buffer.asUint8List());
        });
        debugDisableShadows = true;
      }, skip: _dir.isEmpty);
    }
  }
}
