// Renders Today at the Day Dial mock-up's data and clock (21:10, Thu 5 Nov
// 2026, en_GB), with the mock-up's own generator for the other days, for
// side-by-side comparison with it (tools/fidelity/README.md):
//   flutter test test/fidelity_render_test.dart --dart-define=RENDER_DIR=<dir>
// It prints each block's rect for the busy light shot.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:clock/clock.dart';
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
import 'package:tracker/design/tokens.dart';
import 'package:tracker/formats.dart';
import 'package:tracker/homepage.dart';
import 'package:tracker/providers/offline_provider.dart';
import 'package:tracker/providers/sync_status_provider.dart';
import 'package:tracker/providers/tracker_writes_provider.dart';
import 'package:tracker/providers/unarchived_vice_list_provider.dart';
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/providers/vice_activity_day_provider.dart';
import 'package:tracker/providers/vice_activity_history_provider.dart';
import 'package:tracker/providers/vice_list_provider.dart';
import 'package:tracker/widgets/log_fan.dart';
import 'package:tracker/widgets/circle_button.dart';
import 'package:tracker/widgets/day_dial.dart';
import 'package:tracker/widgets/day_picker.dart';
import 'package:tracker/widgets/tally_row.dart';

import 'fake_writes.dart';
import 'fakes.dart';

const String _dir = String.fromEnvironment('RENDER_DIR');
final DateTime _today = DateTime(2026, 11, 5);
final DateTime _now = DateTime(2026, 11, 5, 21, 10, 0);

Vice _vice(
  String id,
  String name,
  Unit unit,
  int order, {
  bool archived = false,
}) => Vice(
  id: id,
  name: name,
  unit: unit,
  ownerID: ownerID,
  createdAt: Timestamp.fromDate(DateTime.utc(2026, 1, order)),
  archived: archived,
);

final List<Vice> _habits = <Vice>[
  _vice('coffee', 'Coffee', Unit.drink, 1),
  _vice('takeaway', 'Takeaway', Unit.item, 2),
  _vice('alcohol', 'Alcohol', Unit.drink, 3),
  _vice('late', 'Late nights', Unit.time, 4),
  _vice('scroll', 'Doomscrolling', Unit.minute, 5),
  _vice('sugar', 'Sugar', Unit.item, 6, archived: true),
];

const Map<String, List<(int, int, int)>> _scenes = {
  'busy': [
    (3, 40, 1),
    (0, 425, 1),
    (4, 440, 15),
    (0, 580, 1),
    (0, 595, 1),
    (4, 750, 20),
    (1, 770, 2),
    (0, 795, 1),
    (0, 950, 1),
    (4, 1005, 10),
    (2, 1120, 1),
    (1, 1160, 3),
    (2, 1170, 2),
    (4, 1205, 35),
    (2, 1250, 1),
  ],
  'sparse': [(0, 490, 1), (1, 1165, 1)],
  'record': [
    (3, 40, 1),
    (0, 425, 1),
    (4, 440, 15),
    (0, 580, 1),
    (1, 770, 2),
    (4, 1005, 10),
  ],
  'clear': [],
};

// The mock-up's generator (index.html, gen()), ported bit for bit.
const int _m = 0xffffffff;
int _hash(String s) {
  int h = 2166136261;
  for (final int c in s.codeUnits) {
    h = (h ^ c) & _m;
    h = (h * 16777619) & _m;
  }
  return h;
}

double Function() _rng(int seed) {
  int a = seed & _m;
  return () {
    a = (a + 0x6D2B79F5) & _m;
    int t = ((a ^ (a >> 15)) * (1 | a)) & _m;
    t = ((t + (((t ^ (t >> 7)) * (61 | t)) & _m)) & _m) ^ t;
    return ((t ^ (t >> 14)) & _m) / 4294967296;
  };
}

String _key(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
int _ago(DateTime d) => DateTime.utc(
  _today.year,
  _today.month,
  _today.day,
).difference(DateTime.utc(d.year, d.month, d.day)).inDays;
int _round(double x) => (x + 0.5).floor();

List<(int, int)> _gen(DateTime date, int hi) {
  final double Function() r = _rng(_hash('${_key(date)}:${_habits[hi].id}'));
  final int dow = date.weekday % 7;
  final int ago = _ago(date);
  final bool wkend = dow == 0 || dow == 6;
  final List<(int, int)> out = <(int, int)>[];
  void push(double min, int q) {
    if (min >= 0 && min < 1440) out.add((_round(min), q));
  }

  switch (_habits[hi].id) {
    case 'coffee':
      int n = wkend ? 1 + (r() * 3).floor() : 2 + (r() * 4).floor();
      if (ago < 21 && r() < .5) n = n - 1 < 1 ? 1 : n - 1;
      double t = 405 + r() * 80;
      for (int i = 0; i < n; i++) {
        final double at = t;
        push(at, r() < .1 ? 2 : 1);
        t += 70 + r() * 150;
      }
    case 'takeaway':
      if (r() < .32) {
        final double at = 725 + r() * 70;
        push(at, 1 + (r() * 2).floor());
      }
      if (r() < (dow == 5 || dow == 6 ? .7 : .25)) {
        final double at = 1100 + r() * 100;
        push(at, 1 + (r() * 3).floor());
      }
    case 'alcohol':
      final int n = dow == 5 || dow == 6
          ? 1 + (r() * 3).floor()
          : (r() < .28 ? 1 : 0);
      final List<double> ts = <double>[
        for (int i = 0; i < n; i++) 1080 + r() * 250,
      ]..sort();
      for (final double t in ts) {
        push(t, r() < .25 ? 2 : 1);
      }
    case 'late':
      if (r() < (dow == 6 || dow == 0 ? .6 : .2)) push(15 + r() * 110, 1);
    case 'scroll':
      const List<int> slots = <int>[430, 765, 1330];
      final int n = 1 + (r() * 3).floor();
      for (int i = 0; i < n; i++) {
        final double at = slots[i] + r() * 50 - 15;
        push(at, 5 * (1 + (r() * 7).floor()));
      }
    case 'sugar':
      if (ago > 46) {
        final int n = (r() * 3).floor();
        for (int i = 0; i < n; i++) {
          push(880 + r() * 320, 1);
        }
      }
  }
  return out;
}

List<ViceActivity> _dayEntries(
  DateTime day,
  String scene, {
  required bool clearDay,
}) {
  final DateTime d = DateTime(day.year, day.month, day.day);
  final List<(int, int, int)> rows;
  if (_ago(d) == 0) {
    rows = _scenes[scene]!;
  } else if (clearDay && _ago(d) == 2) {
    rows = const <(int, int, int)>[];
  } else if (d.isAfter(_today)) {
    rows = const <(int, int, int)>[];
  } else {
    rows = <(int, int, int)>[
      for (int h = 0; h < _habits.length; h++)
        for (final (int min, int q) in _gen(d, h)) (h, min, q),
    ];
  }
  return <ViceActivity>[
    for (final (int h, int min, int q) in rows)
      fakeActivity(_habits[h].id, q, d.add(Duration(minutes: min))),
  ];
}

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
  final String? flutterRoot = Platform.environment['FLUTTER_ROOT'];
  final File icons = File(
    '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  );
  if (icons.existsSync()) {
    final Uint8List bytes = icons.readAsBytesSync();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(Future<ByteData>.value(ByteData.sublistView(bytes)))).load();
  }
}

void main() {
  setUpAll(_loadFonts);

  // name, data scene, the mock-up's sparse world (a clear day 2 days back),
  // days to step back, open the fan.
  const List<(String, String, bool, int, bool)> shots = [
    ('busy', 'busy', false, 0, false),
    ('sparse', 'sparse', true, 0, false),
    ('clear-today', 'clear', false, 0, false),
    ('clear-past', 'sparse', true, 2, false),
    ('record', 'record', false, 0, false),
    ('fan', 'record', false, 0, true),
    ('menu', 'busy', false, 0, false),
  ];

  for (final Brightness brightness in Brightness.values) {
    for (final (String name, String scene, bool clearDay, int back, bool fan)
        in shots) {
      testWidgets('fidelity $name ${brightness.name}', (
        WidgetTester tester,
      ) async {
        await withClock(Clock.fixed(_now), () async {
          // flutter_test paints shadows unblurred unless told otherwise; the
          // flag is back on before the test ends, as the binding checks.
          debugDisableShadows = false;
          tester.view.devicePixelRatio = 3;
          tester.view.physicalSize = const Size(390 * 3, 844 * 3);
          tester.view.padding = const FakeViewPadding(
            top: 47 * 3,
            bottom: 34 * 3,
          );
          tester.platformDispatcher.platformBrightnessTestValue = brightness;
          debugFormatLocales = const <Locale>[Locale('en', 'GB')];
          addTearDown(() => debugFormatLocales = null);
          addTearDown(tester.view.reset);
          addTearDown(
            tester.platformDispatcher.clearPlatformBrightnessTestValue,
          );
          final User user = FakeUser(ownerID);
          final GlobalKey frame = GlobalKey();
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                userProvider.overrideWith((ref) => Stream.value(user)),
                offlineProvider.overrideWith((ref) => Stream.value(false)),
                trackerWritesProvider.overrideWithValue(FakeTrackerWrites()),
                pendingWritesWaiterProvider.overrideWithValue(() async {}),
                viceListProvider.overrideWith((ref) => AsyncData(_habits)),
                unarchivedViceListProvider.overrideWith(
                  (ref) => AsyncData(<Vice>[
                    for (final Vice v in _habits)
                      if (!v.archived) v,
                  ]),
                ),
                viceActivityDayProvider.overrideWith(
                  (ref, DateTime day) =>
                      AsyncData(_dayEntries(day, scene, clearDay: clearDay)),
                ),
                viceActivityGraphProvider.overrideWith((
                  ref,
                  ViceActivityGraphQuery q,
                ) {
                  final List<ViceActivity> out = <ViceActivity>[];
                  for (
                    DateTime d = DateTime(
                      q.start.year,
                      q.start.month,
                      q.start.day,
                    );
                    d.isBefore(q.end);
                    d = DateTime(d.year, d.month, d.day + 1)
                  ) {
                    out.addAll(
                      _dayEntries(
                        d,
                        scene,
                        clearDay: clearDay,
                      ).where((ViceActivity a) => a.viceID == q.viceID),
                    );
                  }
                  return AsyncData(out);
                }),
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
          for (int i = 0; i < back; i++) {
            await tester.tap(find.byTooltip('Previous day'));
            await tester.pumpAndSettle();
          }
          if (fan) {
            await tester.tap(find.byType(LogButton));
            await tester.pumpAndSettle();
          }
          if (name == 'menu') {
            await tester.tap(find.byKey(Homepage.menuKey));
            await tester.pumpAndSettle();
          }
          if (name == 'busy' && brightness == Brightness.light) {
            void show(String what, Finder f) {
              for (final Element e in f.evaluate()) {
                final RenderBox b = e.renderObject! as RenderBox;
                // ignore: avoid_print
                print('RECT $what ${b.localToGlobal(Offset.zero)} ${b.size}');
              }
            }

            show('header', find.byType(TodayHeader));
            show('menu', find.byKey(Homepage.menuKey));
            show('daypicker', find.byType(DayPicker));
            show('circlebtn', find.byType(CircleButton));
            show('dial', find.byType(DayDial));
            show('tally', find.byType(TallyRow));
            show('log', find.byType(LogButton));
            show('trendsTitle', find.text('Trends'));
            show('title', find.text('Penchant'));
            show('synced', find.text(SyncPill.synced));
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
        });
      }, skip: _dir.isEmpty);
    }
  }
}
