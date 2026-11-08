// Renders the Mac window at 2000x1250 (fullscreen on a 16" display) and
// 1200x780 (the default window), light and dark, with made-up habits, for the
// mac-fullscreen pitch. Skipped unless a directory is given:
//   flutter test test/mac_fullscreen_render_test.dart --dart-define=RENDER_DIR=<dir>
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/unit.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/design/app_theme.dart';
import 'package:tracker/homepage.dart';
import 'package:tracker/providers/offline_provider.dart';
import 'package:tracker/providers/sync_status_provider.dart';
import 'package:tracker/providers/tracker_writes_provider.dart';
import 'package:tracker/providers/unarchived_vice_list_provider.dart';
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/providers/vice_activity_day_provider.dart';
import 'package:tracker/providers/vice_activity_history_provider.dart';
import 'package:tracker/providers/vice_list_provider.dart';

import 'fake_writes.dart';
import 'fakes.dart';
import 'render_fonts.dart';

const String _dir = String.fromEnvironment('RENDER_DIR');

Vice _vice(String id, String name, Unit unit, int order) => Vice(
  id: id,
  name: name,
  unit: unit,
  ownerID: ownerID,
  createdAt: Timestamp.fromDate(DateTime.utc(2026, 1, order)),
  archived: false,
);

// Enough habits that the Trends chips outrun a 720 pt column.
final List<Vice> _habits = <Vice>[
  _vice('coffee', 'Coffee', Unit.drink, 1),
  _vice('tea', 'Tea', Unit.drink, 2),
  _vice('water', 'Water', Unit.drink, 3),
  _vice('wine', 'Wine', Unit.drink, 4),
  _vice('running', 'Running', Unit.minute, 5),
  _vice('beer', 'Beer', Unit.drink, 6),
  _vice('chocolate', 'Chocolate', Unit.item, 7),
  _vice('cycling', 'Cycling', Unit.minute, 8),
  _vice('walking', 'Walking', Unit.minute, 9),
  _vice('sparkling', 'Sparkling water', Unit.drink, 10),
  _vice('meditation', 'Meditation', Unit.minute, 11),
];

const List<(int, int, int)> _scene = <(int, int, int)>[
  (0, 425, 1),
  (2, 440, 1),
  (4, 450, 30),
  (0, 580, 1),
  (1, 640, 1),
  (2, 700, 1),
  (0, 795, 1),
  (6, 900, 1),
  (1, 950, 1),
  (2, 1000, 1),
  (3, 1170, 1),
  (5, 1200, 1),
  (3, 1250, 1),
];

List<ViceActivity> _day(DateTime day) => <ViceActivity>[
  for (final (int h, int minute, int q) in _scene)
    fakeActivity(_habits[h].id, q, day.add(Duration(minutes: minute))),
];

List<ViceActivity> _history(String viceID, DateTime start, DateTime end) {
  final List<ViceActivity> out = <ViceActivity>[];
  int seed = viceID.hashCode & 0xffff;
  int next(int bound) {
    seed = (seed * 1103515245 + 12345) & 0x7fffffff;
    return seed % bound;
  }

  for (
    DateTime d = start;
    d.isBefore(end);
    d = DateTime(d.year, d.month, d.day + 1)
  ) {
    final int count = next(5);
    for (int i = 0; i < count; i++) {
      final int hour = (7 + next(4) + (i * 5)) % 24;
      out.add(
        fakeActivity(
          viceID,
          1 + next(2),
          d.add(Duration(hours: hour, minutes: next(60))),
        ),
      );
    }
  }
  return out;
}

class _Synced extends SyncTracker {
  @override
  SyncStatus build() => const SyncStatus(SyncState.synced);
}

void main() {
  setUpAll(loadRenderFonts);

  for (final Brightness brightness in Brightness.values) {
    for (final Size size in const <Size>[Size(2000, 1250), Size(1200, 780)]) {
      final String name =
          '${size.width.toInt()}x${size.height.toInt()}-${brightness.name}';
      testWidgets('renders the Mac window, $name', (WidgetTester tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        tester.platformDispatcher.platformBrightnessTestValue = brightness;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        final User user = FakeUser(ownerID);
        final GlobalKey frame = GlobalKey();

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              userProvider.overrideWith((ref) => Stream.value(user)),
              offlineProvider.overrideWith((ref) => Stream.value(false)),
              syncStatusProvider.overrideWith(_Synced.new),
              trackerWritesProvider.overrideWithValue(FakeTrackerWrites()),
              memoryJournal(),
              viceListProvider.overrideWith((ref) => AsyncData(_habits)),
              unarchivedViceListProvider.overrideWith(
                (ref) => AsyncData(_habits),
              ),
              viceActivityDayProvider.overrideWith(
                (ref, DateTime day) => AsyncData(_day(day)),
              ),
              viceActivityGraphProvider.overrideWith(
                (ref, ViceActivityGraphQuery q) =>
                    AsyncData(_history(q.viceID, q.start, q.end)),
              ),
            ],
            child: RepaintBoundary(
              key: frame,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: appTheme(Brightness.light),
                darkTheme: appTheme(Brightness.dark),
                home: const Homepage(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.runAsync(() async {
          final ui.Image image =
              await (frame.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage(pixelRatio: 1);
          final ByteData? png = await image.toByteData(
            format: ui.ImageByteFormat.png,
          );
          Directory(_dir).createSync(recursive: true);
          await File(
            '$_dir/mac-$name.png',
          ).writeAsBytes(png!.buffer.asUint8List());
        });
      }, skip: _dir.isEmpty);
    }
  }
}
