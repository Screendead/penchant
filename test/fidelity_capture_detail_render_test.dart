// Renders the amount sheet, the entry editor and the "What was going on?"
// picker with the urge and note rows, light theme, at the capture-detail
// mock-up's size, for side-by-side comparison with
// docs/pitch/round-17/capture-detail/optionC.html:
//   flutter test test/fidelity_capture_detail_render_test.dart --dart-define=RENDER_DIR=<dir>
import 'dart:io';
import 'dart:ui' as ui;

import 'package:clock/clock.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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
import 'package:tracker/providers/tracker_writes_provider.dart';
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/providers/vice_activity_day_provider.dart';
import 'package:tracker/providers/vice_activity_history_provider.dart';
import 'package:tracker/vice_activity_editor_page.dart';
import 'package:tracker/widgets/record_new_activity_dialog.dart';
import 'package:tracker/widgets/time_dial.dart';
import 'package:tracker/widgets/trigger_picker.dart';
import 'package:tracker/widgets/urge_note_fields.dart';

import 'fake_writes.dart';
import 'fakes.dart';

const String _dir = String.fromEnvironment('RENDER_DIR');
final DateTime _now = DateTime(2026, 11, 12, 21, 45);
const String _note = 'Long day, finished the bottle from Sunday';

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
  final List<Vice> habits = <Vice>[
    for (final (int i, String id, String name) in <(int, String, String)>[
      (1, 'coffee', 'Coffee'),
      (2, 'takeaway', 'Takeaway'),
      (3, 'wine', 'Wine'),
    ])
      Vice(
        id: id,
        name: name,
        unit: Unit.drink,
        ownerID: ownerID,
        createdAt: Timestamp.fromDate(DateTime.utc(2026, 1, i)),
        archived: false,
      ),
  ];
  final DateTime at = DateTime(2026, 11, 12, 21, 40);
  final ViceActivity edited = ViceActivity(
    id: 'wine-entry',
    viceID: 'wine',
    quantity: 1,
    ownerID: ownerID,
    createdAt: Timestamp.fromDate(at),
    triggers: const <String>['routine/wind-down', 'place/home'],
    urge: 3,
    note: _note,
  );

  for (final String name in <String>['sheet', 'editor', 'picker']) {
    testWidgets('fidelity capture-detail-$name', (WidgetTester tester) async {
      await withClock(Clock.fixed(_now), () async {
        debugDisableShadows = false;
        debugFormatLocales = const <Locale>[Locale('en', 'GB')];
        addTearDown(() => debugFormatLocales = null);
        tester.view.devicePixelRatio = 3;
        tester.view.physicalSize = const Size(390 * 3, 844 * 3);
        tester.view.padding = const FakeViewPadding(
          top: 47 * 3,
          bottom: 34 * 3,
        );
        addTearDown(tester.view.reset);
        final GlobalKey frame = GlobalKey();
        final GlobalKey<NavigatorState> navigator = GlobalKey<NavigatorState>();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              ...habitOverrides(habits),
              trackerWritesProvider.overrideWithValue(FakeTrackerWrites()),
              userProvider.overrideWith(
                (ref) => Stream.value(FakeUser(ownerID)),
              ),
              viceActivityProvider.overrideWith(
                (ref, String id) => AsyncData(edited),
              ),
              viceActivityDayProvider.overrideWith(
                (ref, DateTime day) =>
                    AsyncData(<ViceActivity>[if (name == 'editor') edited]),
              ),
            ],
            child: RepaintBoundary(
              key: frame,
              child: MaterialApp(
                navigatorKey: navigator,
                debugShowCheckedModeBanner: false,
                theme: appTheme(Brightness.light),
                builder: (BuildContext context, Widget? child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(alwaysUse24HourFormat: true),
                  child: child!,
                ),
                home: const Scaffold(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final BuildContext context = navigator.currentContext!;
        switch (name) {
          case 'sheet':
            RecordNewActivityDialog.show(context, initialViceID: 'wine');
            await tester.pumpAndSettle();
            tester
                    .widget<EntryTimeField>(find.byType(EntryTimeField))
                    .controller
                    .at =
                at;
            await tester.tap(find.byKey(UrgeField.keyFor(3)));
            await tester.enterText(find.byKey(NoteField.fieldKey), _note);
          case 'editor':
            navigator.currentState!.push(
              ViceActivityEditorPage.route(
                const RouteSettings(),
                const ViceActivityEditorPage(
                  viceID: 'wine',
                  activityID: 'wine-entry',
                ),
              ),
            );
          default:
            showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              useSafeArea: true,
              builder: (_) => TriggerPickerSheet(
                viceName: 'Wine',
                usual: const <String>[
                  'routine/wind-down',
                  'routine/meal',
                  'place/home',
                  'social/friends',
                  'feeling/stressed',
                ],
                initial: const <String>['routine/wind-down', 'place/home'],
                answers: (urge: null, note: null),
                onDone: (_) {},
                onAnswered: (_, _) {},
                onUndoLog: () {},
              ),
            );
        }
        await tester.pumpAndSettle();
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.runAsync(() async {
          final ui.Image image =
              await (frame.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage(pixelRatio: 3);
          final ByteData? png = await image.toByteData(
            format: ui.ImageByteFormat.png,
          );
          await File(
            '$_dir/capture-detail-$name-light.png',
          ).writeAsBytes(png!.buffer.asUint8List());
        });
        debugDisableShadows = true;
      });
    }, skip: _dir.isEmpty);
  }
}
