// The pitch names this file; its hyphen is the option's name.
// ignore_for_file: file_names
// Renders the Today tab for the "radar-polished" pitch into
// docs/pitch/mockups/today-chart/radar-polished/. Regenerate with
// `flutter test --update-goldens test/mockups/today_chart_radar-polished_test.dart`.
@TestOn('mac-os')
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/unit.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/homepage.dart';
import 'package:tracker/providers/offline_provider.dart';
import 'package:tracker/providers/today_provider.dart';
import 'package:tracker/providers/unarchived_vice_list_provider.dart';
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/providers/vice_activity_day_provider.dart';
import 'package:tracker/providers/vice_activity_history_provider.dart';
import 'package:tracker/providers/vice_list_provider.dart';
import 'package:tracker/theme.dart';

import '../fakes.dart';

const String _out = '../../docs/pitch/mockups/today-chart/radar-polished';

final GlobalKey _screen = GlobalKey();

// The header shows the date, so the images would change every day.
class _PinnedToday extends Today {
  @override
  DateTime build() => DateTime(2026, 11, 5);
}

Vice _vice(String id, String name, Unit unit) => Vice(
  id: id,
  name: name,
  unit: unit,
  ownerID: ownerID,
  createdAt: Timestamp.fromMillisecondsSinceEpoch(0),
  archived: false,
);

final List<Vice> _vices = [
  _vice('snacking', 'Evening Snacking', Unit.item),
  _vice('nights', 'Late Nights', Unit.time),
  _vice('coffee', 'Coffee', Unit.drink),
  _vice('takeaway', 'Takeaway', Unit.item),
  _vice('scrolling', 'Doomscrolling', Unit.time),
];

// flutter_tester lives in <flutter>/bin/cache/artifacts/engine/<host>/.
Directory _materialFonts() => Directory(
  '${File(Platform.resolvedExecutable).parent.parent.parent.path}'
  '/material_fonts',
);

Future<void> _loadFonts() async {
  final String dir = _materialFonts().path;
  Future<ByteData> font(String file) async =>
      ByteData.sublistView(await File('$dir/$file').readAsBytes());

  final FontLoader roboto = FontLoader('Roboto');
  for (final String file in [
    'Roboto-Regular.ttf',
    'Roboto-Medium.ttf',
    'Roboto-Bold.ttf',
  ]) {
    roboto.addFont(font(file));
  }
  await roboto.load();
  await (FontLoader(
    'MaterialIcons',
  )..addFont(font('MaterialIcons-Regular.otf'))).load();
}

Future<void> _render(
  WidgetTester tester,
  String name,
  List<int> amounts,
) async {
  // iPhone 13 Pro Max: 428 x 926 points at 3x, with its safe areas.
  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = const Size(428 * 3, 926 * 3);
  tester.view.padding = const FakeViewPadding(top: 47 * 3, bottom: 34 * 3);
  tester.view.viewPadding = const FakeViewPadding(top: 47 * 3, bottom: 34 * 3);
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        todayProvider.overrideWith(_PinnedToday.new),
        userProvider.overrideWith((ref) => Stream.value(FakeUser(ownerID))),
        offlineProvider.overrideWith((ref) => Stream.value(false)),
        viceListProvider.overrideWith((ref) => AsyncData(_vices)),
        unarchivedViceListProvider.overrideWith((ref) => AsyncData(_vices)),
        viceActivityDayProvider.overrideWith(
          (ref, DateTime day) => AsyncData([
            for (int i = 0; i < _vices.length; i++)
              if (amounts[i] > 0)
                fakeActivity(
                  _vices[i].id,
                  amounts[i],
                  day.add(const Duration(hours: 9)),
                ),
          ]),
        ),
        viceActivityGraphProvider.overrideWith(
          (ref, ViceActivityGraphQuery query) =>
              const AsyncData(<ViceActivity>[]),
        ),
      ],
      child: RepaintBoundary(
        key: _screen,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: appTheme(),
          home: const Homepage(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);

  // A golden of a finder is captured at one pixel per point; this keeps 3x.
  final RenderRepaintBoundary screen = tester.renderObject(find.byKey(_screen));
  final ui.Image image = (await tester.runAsync(
    () => screen.toImage(pixelRatio: 3),
  ))!;
  addTearDown(image.dispose);
  await expectLater(image, matchesGoldenFile('$_out/$name.png'));
}

void main() {
  setUpAll(_loadFonts);

  testWidgets('sparse', (WidgetTester tester) async {
    await _render(tester, 'sparse', [1, 0, 1, 0, 0]);
  });

  testWidgets('busy', (WidgetTester tester) async {
    await _render(tester, 'busy', [6, 1, 3, 2, 1]);
  });

  testWidgets('one', (WidgetTester tester) async {
    await _render(tester, 'one', [0, 0, 2, 0, 0]);
  });
}
