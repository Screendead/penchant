// Renders the lock screen and Settings with App lock on, light and dark, at 390x844 to PNGs for the pitch. Skipped
// unless a directory is given:
//   flutter test test/app_lock_render_test.dart --dart-define=RENDER_DIR=<dir>
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
import 'package:tracker/app_lock/app_lock.dart';
import 'package:tracker/app_lock/app_lock_gate.dart';
import 'package:tracker/app_lock/device_auth.dart';
import 'package:tracker/design/app_theme.dart';
import 'package:tracker/providers/account_provider.dart';
import 'package:tracker/providers/package_info_provider.dart';
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/settings.dart';

import 'fake_account.dart';
import 'fake_device_auth.dart';
import 'fakes.dart';
import 'render_fonts.dart';

const String _dir = String.fromEnvironment('RENDER_DIR');

void main() {
  setUpAll(loadRenderFonts);
  setUp(
    () => SharedPreferences.setMockInitialValues(<String, Object>{
      AppLock.key: true,
    }),
  );
  for (final Brightness brightness in Brightness.values) {
    for (final String name in <String>['lock-screen', 'settings']) {
      testWidgets('renders app lock $name ${brightness.name}', (
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
        final bool lockScreen = name == 'lock-screen';
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              // A cancelled first prompt leaves the lock screen up.
              deviceAuthProvider.overrideWithValue(
                FakeDeviceAuth(outcomes: <AuthOutcome>[AuthOutcome.cancelled]),
              ),
              appLockSavedProvider.overrideWithValue(true),
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
                debugShowCheckedModeBanner: false,
                theme: appTheme(Brightness.light),
                darkTheme: appTheme(Brightness.dark),
                builder: lockScreen
                    ? (BuildContext context, Widget? child) =>
                          AppLockGate(child: child!)
                    : null,
                home: const Settings(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.text(LockScreen.title),
          lockScreen ? findsOneWidget : findsNothing,
        );
        await tester.runAsync(() async {
          final ui.Image image =
              await (frame.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage(pixelRatio: 3);
          final ByteData? png = await image.toByteData(
            format: ui.ImageByteFormat.png,
          );
          await File(
            '$_dir/app-lock-$name-${brightness.name}.png',
          ).writeAsBytes(png!.buffer.asUint8List());
        });
        debugDisableShadows = true;
      }, skip: _dir.isEmpty);
    }
  }
}
