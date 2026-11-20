// Renders a habit's strength as PNGs, light and dark, at 390x844: the habit
// form's Strength section, the amount sheet with an entry's own strength,
// with its Apple Health switch off and on, and Trends in the Units view:
//   flutter test test/strength_render_test.dart --dart-define=RENDER_DIR=<dir>
@Tags(<String>['render'])
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tracker/data/category.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/data/habit_strength.dart';
import 'package:tracker/data/unit.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/design/app_theme.dart';
import 'package:tracker/health_write/health_write.dart';
import 'package:tracker/main.dart';
import 'package:tracker/providers/offline_provider.dart';
import 'package:tracker/providers/tracker_writes_provider.dart';
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/trends/trends_sheet.dart';
import 'package:tracker/vice_form.dart';
import 'package:tracker/vice_tracker.dart';
import 'package:tracker/widgets/pill_toggle.dart';
import 'package:tracker/widgets/record_new_activity_dialog.dart';
import 'package:tracker/widgets/strength_field.dart';

import 'fake_writes.dart';
import 'fakes.dart';
import 'render_fonts.dart';
import 'trends_harness.dart';

const String _dir = String.fromEnvironment('RENDER_DIR');

final DateTime _today = startOfDay(DateTime.now());

final Vice _beer = Vice(
  id: 'beer',
  name: 'Beer',
  unit: Unit.drink,
  ownerID: ownerID,
  createdAt: Timestamp.fromDate(DateTime.utc(2026, 1, 1)),
  archived: false,
  category: ViceCategory.alcohol,
  unitLabel: 'pints',
  unitSingular: 'pint',
  strength: const HabitStrength.alcohol(
    unit: StrengthUnit.ukUnit,
    servingMl: 568,
    abv: 4.5,
  ),
);
final Vice _coffee = Vice(
  id: 'coffee',
  name: 'Coffee',
  unit: Unit.drink,
  ownerID: ownerID,
  createdAt: Timestamp.fromDate(DateTime.utc(2026, 1, 2)),
  archived: false,
  category: ViceCategory.caffeine,
  strength: const HabitStrength.caffeine(caffeineMg: 95),
);
final List<Vice> _habits = <Vice>[_beer, _coffee];

// Pints most evenings, more at the weekend, some of a stronger IPA.
final List<ViceActivity> _journal = <ViceActivity>[
  for (int back = 40; back >= 0; back--)
    for (int g = 0; g < (back % 7 < 2 ? 3 : back % 3); g++)
      ViceActivity(
        id: 'beer-$back-$g',
        viceID: 'beer',
        quantity: 1,
        ownerID: ownerID,
        createdAt: Timestamp.fromDate(
          addDays(_today, -back).add(Duration(hours: 19 + g)),
        ),
        abv: g == 2 ? 6.5 : null,
      ),
];

void _phone(WidgetTester tester) {
  debugDisableShadows = false;
  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.padding = const FakeViewPadding(top: 47 * 3, bottom: 34 * 3);
  addTearDown(tester.view.reset);
}

Future<void> _save(WidgetTester tester, GlobalKey frame, String name) async {
  await tester.runAsync(() async {
    final ui.Image image =
        await (frame.currentContext!.findRenderObject()!
                as RenderRepaintBoundary)
            .toImage(pixelRatio: 3);
    final ByteData? png = await image.toByteData(
      format: ui.ImageByteFormat.png,
    );
    await File('$_dir/$name.png').writeAsBytes(png!.buffer.asUint8List());
  });
  debugDisableShadows = true;
}

final GlobalKey<NavigatorState> _navigator = GlobalKey<NavigatorState>();

Widget _app(
  GlobalKey frame,
  Brightness brightness,
  List<Override> overrides,
  Widget home,
) => ProviderScope(
  overrides: <Override>[
    userProvider.overrideWith((ref) => Stream.value(FakeUser(ownerID))),
    offlineProvider.overrideWithValue(const AsyncData(false)),
    trackerWritesProvider.overrideWithValue(FakeTrackerWrites()),
    memoryJournal(),
    ...trendsOverrides(
      _habits,
      inRange(_journal),
      days: (DateTime day) => <ViceActivity>[
        for (final ViceActivity a in _journal)
          if (startOfDay(a.createdAt.toDate()) == day) a,
      ],
    ),
    ...overrides,
  ],
  child: RepaintBoundary(
    key: frame,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      navigatorKey: _navigator,
      theme: appTheme(brightness),
      home: home,
      onGenerateRoute: generateRoute,
    ),
  ),
);

void main() {
  setUpAll(loadRenderFonts);

  for (final Brightness brightness in Brightness.values) {
    final String tone = brightness.name;

    testWidgets('strength-habit-form-$tone', (WidgetTester tester) async {
      _phone(tester);
      final GlobalKey frame = GlobalKey();
      await tester.pumpWidget(
        _app(frame, brightness, const <Override>[], ViceForm(vice: _beer)),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text(ViceForm.lineLabel),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await _save(tester, frame, 'strength-habit-form-$tone');
    }, skip: _dir.isEmpty);

    for (final bool on in <bool>[false, true]) {
      final String name = 'strength-health-${on ? 'on' : 'off'}-$tone';
      testWidgets(name, (WidgetTester tester) async {
        _phone(tester);
        SharedPreferences.setMockInitialValues(<String, Object>{
          HealthWriteChoices.keyOf(ownerID): <String>[if (on) _beer.id],
        });
        final GlobalKey frame = GlobalKey();
        await tester.pumpWidget(
          _app(frame, brightness, <Override>[
            healthWriteSupportedProvider.overrideWithValue(true),
          ], ViceForm(vice: _beer)),
        );
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.byKey(ViceForm.healthWriteKey),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.drag(find.byType(Scrollable).first, const Offset(0, -160));
        await tester.pumpAndSettle();
        await _save(tester, frame, name);
      }, skip: _dir.isEmpty);
    }

    testWidgets('strength-amount-sheet-$tone', (WidgetTester tester) async {
      _phone(tester);
      final GlobalKey frame = GlobalKey();
      await tester.pumpWidget(
        _app(
          frame,
          brightness,
          const <Override>[],
          const Scaffold(body: SizedBox.expand()),
        ),
      );
      await tester.pump();
      RecordNewActivityDialog.show(
        _navigator.currentContext!,
        initialViceID: _beer.id,
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(StrengthField.fieldKey), '6.5');
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(StrengthField.fieldKey));
      await tester.pumpAndSettle();
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await _save(tester, frame, 'strength-amount-sheet-$tone');
    }, skip: _dir.isEmpty);

    testWidgets('strength-trends-units-$tone', (WidgetTester tester) async {
      _phone(tester);
      final GlobalKey frame = GlobalKey();
      await tester.pumpWidget(
        _app(
          frame,
          brightness,
          const <Override>[],
          const Scaffold(body: ViceTracker()),
        ),
      );
      await tester.pumpAndSettle();
      await openTrends(tester);
      Future<void> tap(Finder finder) async {
        final Finder target = inTrends(finder).first;
        await tester.ensureVisible(target);
        await tester.pumpAndSettle();
        await tester.tap(target);
        await tester.pumpAndSettle();
      }

      await tap(find.widgetWithText(PillToggle, 'Beer'));
      await tap(find.text(TrendsSheet.unitsLabel));
      await tester.ensureVisible(inTrends(find.text(TrendsSheet.title)).last);
      await tester.pumpAndSettle();
      await _save(tester, frame, 'strength-trends-units-$tone');
    }, skip: _dir.isEmpty);
  }
}
