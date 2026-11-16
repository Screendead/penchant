// Records the Claude-working looks: run alone through tools/e2e-screenshots.sh
// on an iPhone simulator, never in all_test.dart (it waits out real calls'
// lengths). Each look plays a 3 s call and a staged one in light, and part of
// a staged one in dark, which Stop ends.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/claude/claude_working.dart';
import 'package:tracker/claude/claude_working_gallery.dart';
import 'package:tracker/design/app_theme.dart';

import 'support.dart';

Widget _gallery(ThemeMode mode) => ProviderScope(
  key: ValueKey<ThemeMode>(mode),
  child: MaterialApp(
    theme: appTheme(Brightness.light),
    darkTheme: appTheme(Brightness.dark),
    themeMode: mode,
    home: const ClaudeWorkingGallery(),
  ),
);

Future<void> _press(WidgetTester tester, Key key) async {
  await tester.ensureVisible(find.byKey(key));
  await tester.pump();
  await tester.tap(find.byKey(key));
}

void main() {
  ensureE2EBinding();

  testWidgets('each look, light and dark', (WidgetTester tester) async {
    await tester.pumpWidget(_gallery(ThemeMode.light));
    await screenshot(tester, 'ready');
    for (final ClaudeWorkingLook look in ClaudeWorkingLook.values) {
      await _press(tester, ClaudeWorkingGallery.button(look, GalleryRun.short));
      await screenshot(tester, '${look.name}-light-1');
      await pumpFor(tester, const Duration(milliseconds: 3500));
      await _press(
        tester,
        ClaudeWorkingGallery.button(look, GalleryRun.staged),
      );
      await pumpFor(tester, const Duration(milliseconds: 4500));
      await screenshot(tester, '${look.name}-light-2');
      await pumpFor(tester, const Duration(seconds: 12));
      await screenshot(tester, '${look.name}-light-3');
    }
    await tester.pumpWidget(_gallery(ThemeMode.dark));
    for (final ClaudeWorkingLook look in ClaudeWorkingLook.values) {
      await _press(
        tester,
        ClaudeWorkingGallery.button(look, GalleryRun.staged),
      );
      await pumpFor(tester, const Duration(milliseconds: 4500));
      await screenshot(tester, '${look.name}-dark-1');
      await tester.tap(find.text(ClaudeWorking.stop));
      await pumpFor(tester, const Duration(seconds: 2));
    }
  });
}
