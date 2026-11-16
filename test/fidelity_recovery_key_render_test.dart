// Renders the recovery key screens at the Day Dial mock-up's size, for
// side-by-side comparison with the e2e-encryption mock-up's screens
// (tools/fidelity/README.md):
//   flutter test test/fidelity_recovery_key_render_test.dart --dart-define=RENDER_DIR=<dir>
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/crypto/e2ee_enabled.dart';
import 'package:tracker/crypto/recovery_key.dart';
import 'package:tracker/design/app_theme.dart';
import 'package:tracker/design/tokens.dart';
import 'package:tracker/journal_key/recovery_key_screens.dart';
import 'package:tracker/journal_key/recovery_key_state.dart';
import 'package:tracker/providers/user_provider.dart';

import 'fakes.dart';

const String _dir = String.fromEnvironment('RENDER_DIR');

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
  setUpAll(_loadFonts);
  final String formatted = RecoveryKey.format(RecoveryKey.generate(Random(11)));
  for (final Brightness brightness in Brightness.values) {
    for (final String name in <String>['key', 'confirm', 'entry', 'lost']) {
      testWidgets('fidelity recovery-$name ${brightness.name}', (
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
        final GlobalKey frame = GlobalKey();
        final GlobalKey<NavigatorState> navigator = GlobalKey<NavigatorState>();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              e2eeEnabledProvider.overrideWithValue(true),
              userProvider.overrideWith((ref) => Stream.value(FakeUser('u'))),
              recoveryKeyStatusProvider.overrideWithValue(
                RecoveryKeyStatus(
                  formatted: formatted,
                  keyCreatedAt: DateTime(2026, 10, 20),
                ),
              ),
              journalNeedsRecoveryKeyProvider.overrideWithValue(
                name == 'entry' || name == 'lost',
              ),
            ],
            child: RepaintBoundary(
              key: frame,
              child: MaterialApp(
                navigatorKey: navigator,
                debugShowCheckedModeBanner: false,
                theme: appTheme(Brightness.light),
                darkTheme: appTheme(Brightness.dark),
                builder: (context, child) => RecoveryKeyGate(child: child!),
                home: const Scaffold(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        if (name == 'entry') {
          final String plain = formatted.replaceAll('-', '');
          final String typo = plain.replaceRange(
            13,
            14,
            plain[13] == 'A' ? 'B' : 'A',
          );
          await tester.enterText(
            find.byKey(RecoveryKeyEntryPage.field),
            <String>[
              for (int g = 0; g < RecoveryKey.groups; g++)
                typo.substring(g * 4, g * 4 + 4),
            ].join(' '),
          );
          await tester.tap(find.text(RecoveryKeyCopy.unlock));
        } else if (name == 'lost') {
          await tester.tap(find.text(RecoveryKeyCopy.lostKey));
        } else {
          navigator.currentState!.push(
            MaterialPageRoute<void>(builder: (_) => const RecoveryKeyPage()),
          );
          await tester.pumpAndSettle();
          if (name == 'confirm') {
            await tester.tap(find.text(RecoveryKeyCopy.savedIt));
            await tester.pumpAndSettle();
            await tester.enterText(
              find.byKey(RecoveryKeyPage.confirmField),
              RecoveryKey.groupsOf(formatted).first,
            );
            await tester.tap(find.text(RecoveryKeyCopy.confirm));
          }
        }
        FocusManager.instance.primaryFocus?.unfocus();
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
            '$_dir/app-recovery-$name-${brightness.name}.png',
          ).writeAsBytes(png!.buffer.asUint8List());
        });
        debugDisableShadows = true;
      }, skip: _dir.isEmpty);
    }
  }
}
