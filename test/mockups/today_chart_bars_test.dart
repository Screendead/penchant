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

// Renders the Today tab for the pitch page. The PNGs are written only by
// `flutter test --update-goldens test/mockups/today_chart_bars_test.dart`:
// glyph rasterisation differs between macOS and CI's Linux, so a plain run
// lays each day out and checks it draws without error, but compares nothing.

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

const Map<String, List<int>> _days = {
  'sparse': [1, 0, 1, 0, 0],
  'busy': [6, 1, 3, 2, 1],
  'one': [0, 0, 2, 0, 0],
};

Future<void> _loadFonts() async {
  final String fonts =
      '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts';
  Future<ByteData> font(String file) async =>
      ByteData.sublistView(await File('$fonts/$file').readAsBytes());

  await (FontLoader('Roboto')
        ..addFont(font('Roboto-Regular.ttf'))
        ..addFont(font('Roboto-Medium.ttf'))
        ..addFont(font('Roboto-Bold.ttf')))
      .load();
  await (FontLoader(
    'MaterialIcons',
  )..addFont(font('MaterialIcons-Regular.otf'))).load();
}

void main() {
  setUpAll(() async {
    if (autoUpdateGoldenFiles) {
      await _loadFonts();
    }
  });

  for (final MapEntry<String, List<int>> day in _days.entries) {
    testWidgets('Today as bars, ${day.key} day', (WidgetTester tester) async {
      tester.view.devicePixelRatio = 3;
      tester.view.physicalSize = const Size(428 * 3, 926 * 3);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            todayProvider.overrideWith(_FixedToday.new),
            userProvider.overrideWith((ref) => Stream.value(FakeUser(ownerID))),
            offlineProvider.overrideWith((ref) => Stream.value(false)),
            viceListProvider.overrideWith((ref) => AsyncData(_vices)),
            unarchivedViceListProvider.overrideWith((ref) => AsyncData(_vices)),
            viceActivityDayProvider.overrideWith(
              (ref, DateTime date) => AsyncData(<ViceActivity>[
                for (int i = 0; i < _vices.length; i++)
                  if (day.value[i] > 0)
                    fakeActivity(_vices[i].id, day.value[i], date),
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
      expect(tester.takeException(), isNull);

      if (autoUpdateGoldenFiles) {
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile(
            '../../docs/pitch/mockups/today-chart/bars/${day.key}.png',
          ),
        );
      }
    });
  }
}
