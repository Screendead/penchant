// Renders the Today tab for the pitch page. Golden pixels depend on the host's
// font rasteriser, so this runs only when asked:
//   flutter test --update-goldens --dart-define=MOCKUPS=true \
//     test/mockups/today_chart_hybrid_test.dart
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
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
import 'package:tracker/providers/vice_list_provider.dart';
import 'package:tracker/theme.dart';

import '../fakes.dart';

const bool _enabled = bool.fromEnvironment('MOCKUPS');

final DateTime _day = DateTime(2026, 11, 5);

class _FixedToday extends Today {
  @override
  DateTime build() => _day;
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

Future<void> _loadFonts() async {
  final String fonts =
      '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts';
  Future<ByteData> load(String file) async =>
      ByteData.sublistView(await File('$fonts/$file').readAsBytes());

  await (FontLoader('Roboto')
        ..addFont(load('Roboto-Regular.ttf'))
        ..addFont(load('Roboto-Medium.ttf'))
        ..addFont(load('Roboto-Bold.ttf')))
      .load();
  await (FontLoader(
    'MaterialIcons',
  )..addFont(load('MaterialIcons-Regular.otf'))).load();
}

Future<void> _render(
  WidgetTester tester,
  String name,
  List<int> amounts,
) async {
  // iPhone 13 Pro Max: 428 x 926 pt at 3x, with its notch and home indicator.
  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = const Size(428 * 3, 926 * 3);
  tester.view.padding = const FakeViewPadding(top: 47 * 3, bottom: 34 * 3);
  tester.view.viewPadding = const FakeViewPadding(top: 47 * 3, bottom: 34 * 3);
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        userProvider.overrideWith((ref) => Stream.value(FakeUser(ownerID))),
        todayProvider.overrideWith(_FixedToday.new),
        offlineProvider.overrideWith((ref) => Stream.value(false)),
        viceListProvider.overrideWithValue(AsyncData(_vices)),
        unarchivedViceListProvider.overrideWithValue(AsyncData(_vices)),
        viceActivityDayProvider.overrideWith(
          (ref, DateTime day) => AsyncData(<ViceActivity>[
            for (int i = 0; i < _vices.length; i++)
              if (amounts[i] > 0)
                fakeActivity(
                  _vices[i].id,
                  amounts[i],
                  day.add(const Duration(hours: 9)),
                ),
          ]),
        ),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: appTheme(),
        home: const Homepage(),
      ),
    ),
  );
  await tester.pumpAndSettle();

  await expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile('../../docs/pitch/mockups/today-chart/hybrid/$name.png'),
  );
}

void main() {
  setUpAll(_loadFonts);

  testWidgets('sparse day', (WidgetTester tester) async {
    await _render(tester, 'sparse', [1, 0, 1, 0, 0]);
  }, skip: !_enabled);

  testWidgets('busy day', (WidgetTester tester) async {
    await _render(tester, 'busy', [6, 1, 3, 2, 1]);
  }, skip: !_enabled);

  testWidgets('one vice used', (WidgetTester tester) async {
    await _render(tester, 'one', [0, 0, 2, 0, 0]);
  }, skip: !_enabled);
}
