// Renders reading a drink's label as PNGs, light and dark, at 390x844: the
// habit form's Read a label button, the sheet with what it read, and the
// sheet when a photo holds nothing to fill in:
//   flutter test test/label_camera_render_test.dart --dart-define=RENDER_DIR=<dir>
@Tags(<String>['render'])
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/category.dart';
import 'package:tracker/data/unit.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/design/app_theme.dart';
import 'package:tracker/label/label_sheet.dart';
import 'package:tracker/label/label_source.dart';
import 'package:tracker/providers/tracker_writes_provider.dart';
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/providers/vice_list_provider.dart';
import 'package:tracker/vice_form.dart';

import 'fake_writes.dart';
import 'fakes.dart';
import 'render_fonts.dart';

const String _dir = String.fromEnvironment('RENDER_DIR');

final Vice _beer = Vice(
  id: 'beer',
  name: 'Beer',
  unit: Unit.drink,
  ownerID: ownerID,
  createdAt: Timestamp.fromDate(DateTime.utc(2026, 1, 1)),
  archived: false,
  category: ViceCategory.alcohol,
  unitLabel: 'cans',
  unitSingular: 'can',
);

const List<String> _can = <String>[
  'HOP STAR',
  'Session IPA',
  'BREWED AND CANNED IN LONDON',
  '440ml / 14.9 FL OZ',
  'ALC 5.2% VOL',
  'Also try our 4.5% pale',
  'Recycle me 100%',
];

const List<String> _blank = <String>['Best before', 'see base', 'L2731'];

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
    await Directory(_dir).create(recursive: true);
    await File('$_dir/$name.png').writeAsBytes(png!.buffer.asUint8List());
  });
  debugDisableShadows = true;
}

Future<void> _form(
  WidgetTester tester,
  GlobalKey frame,
  Brightness brightness,
  List<String> lines,
) async {
  _phone(tester);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        userProvider.overrideWith((ref) => Stream.value(FakeUser(ownerID))),
        trackerWritesProvider.overrideWithValue(FakeTrackerWrites()),
        memoryJournal(),
        viceListProvider.overrideWith((ref) => AsyncData(<Vice>[_beer])),
        labelSourceProvider.overrideWithValue(FakeLabelSource(lines)),
      ],
      child: RepaintBoundary(
        key: frame,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: appTheme(brightness),
          home: ViceForm(vice: _beer),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    find.text(ViceForm.lineLabel),
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

Future<void> _read(WidgetTester tester) async {
  await tester.tap(find.byKey(ViceForm.readLabelKey));
  await tester.pumpAndSettle();
  await tester.tap(find.text(LabelSheet.takeLabel));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadRenderFonts);

  for (final Brightness brightness in Brightness.values) {
    final String tone = brightness.name;

    testWidgets('label-entry-$tone', (WidgetTester tester) async {
      final GlobalKey frame = GlobalKey();
      await _form(tester, frame, brightness, _can);
      await _save(tester, frame, 'label-entry-$tone');
    }, skip: _dir.isEmpty);

    testWidgets('label-start-$tone', (WidgetTester tester) async {
      final GlobalKey frame = GlobalKey();
      await _form(tester, frame, brightness, _can);
      await tester.tap(find.byKey(ViceForm.readLabelKey));
      await tester.pumpAndSettle();
      await _save(tester, frame, 'label-start-$tone');
    }, skip: _dir.isEmpty);

    testWidgets('label-result-$tone', (WidgetTester tester) async {
      final GlobalKey frame = GlobalKey();
      await _form(tester, frame, brightness, _can);
      await _read(tester);
      await _save(tester, frame, 'label-result-$tone');
    }, skip: _dir.isEmpty);

    testWidgets('label-filled-$tone', (WidgetTester tester) async {
      final GlobalKey frame = GlobalKey();
      await _form(tester, frame, brightness, _can);
      await _read(tester);
      await tester.tap(find.text(LabelSheet.fillLabel));
      await tester.pumpAndSettle();
      await _save(tester, frame, 'label-filled-$tone');
    }, skip: _dir.isEmpty);

    testWidgets('label-nothing-$tone', (WidgetTester tester) async {
      final GlobalKey frame = GlobalKey();
      await _form(tester, frame, brightness, _blank);
      await _read(tester);
      await _save(tester, frame, 'label-nothing-$tone');
    }, skip: _dir.isEmpty);
  }
}
