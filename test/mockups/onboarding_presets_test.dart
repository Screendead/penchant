// Renders the onboarding variants to PNGs for the pitch page:
//   flutter test --update-goldens test/mockups/onboarding_presets_test.dart
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/data/unit.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/homepage.dart';
import 'package:tracker/onboarding/onboarding_screens.dart';
import 'package:tracker/onboarding/onboarding_variant.dart';
import 'package:tracker/providers/unarchived_vice_list_provider.dart';
import 'package:tracker/providers/vice_activity_day_provider.dart';
import 'package:tracker/providers/vice_activity_history_provider.dart';
import 'package:tracker/providers/vice_list_provider.dart';
import 'package:tracker/theme.dart';

const String _out = '../../docs/pitch/mockups/onboarding-presets';

String _materialFonts() {
  final String? root = Platform.environment['FLUTTER_ROOT'];
  if (root != null) {
    return '$root/bin/cache/artifacts/material_fonts';
  }
  // flutter_tester lives in <root>/bin/cache/artifacts/engine/<arch>/.
  return '${File(Platform.resolvedExecutable).parent.parent.parent.path}'
      '/material_fonts';
}

Future<void> _loadFonts() async {
  final String dir = _materialFonts();
  Future<ByteData> read(String name) async =>
      ByteData.sublistView(await File('$dir/$name').readAsBytes());

  await (FontLoader('Roboto')
        ..addFont(read('Roboto-Regular.ttf'))
        ..addFont(read('Roboto-Medium.ttf'))
        ..addFont(read('Roboto-Bold.ttf')))
      .load();
  await (FontLoader(
    'MaterialIcons',
  )..addFont(read('MaterialIcons-Regular.otf'))).load();
}

Future<void> _render(
  WidgetTester tester,
  String name,
  Widget screen, {
  List<Override> overrides = const [],
}) async {
  tester.view.physicalSize = const Size(393 * 3, 852 * 3);
  tester.view.devicePixelRatio = 3;
  tester.view.padding = const FakeViewPadding(top: 59 * 3, bottom: 34 * 3);
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: appTheme(fontFamily: 'Roboto'),
        home: screen,
      ),
    ),
  );
  await tester.pump(const Duration(seconds: 1));

  // The root view is the only repaint boundary captured at the device pixel
  // ratio; any inner one comes out at 1x.
  await expectLater(
    find.byType(ProviderScope),
    matchesGoldenFile('$_out/$name.png'),
  );

  // Lets the chart animations finish before the tree is torn down.
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 10));
}

Vice _vice(VicePreset preset) => Vice(
  id: preset.name,
  name: preset.name,
  unit: preset.unit,
  ownerID: 'owner',
  createdAt: Timestamp.fromMillisecondsSinceEpoch(0),
  archived: false,
);

Future<void> _renderToday(
  WidgetTester tester,
  String name,
  List<VicePreset> picked,
  VicePreset logged,
) async {
  final List<Vice> vices = [for (final VicePreset p in picked) _vice(p)];
  final DateTime now = DateTime.now();
  final List<ViceActivity> activities = [
    ViceActivity(
      id: 'first',
      viceID: logged.name,
      quantity: 1,
      ownerID: 'owner',
      createdAt: Timestamp.fromDate(now),
    ),
  ];

  await _render(
    tester,
    name,
    const Homepage(),
    overrides: [
      unarchivedViceListProvider.overrideWith((ref) => Stream.value(vices)),
      viceListProvider.overrideWith((ref) => Stream.value(vices)),
      viceActivityDayProvider.overrideWith(
        (ref, DateTime day) => Stream.value(
          daysBetween(day, startOfDay(now)) == 0
              ? activities
              : const <ViceActivity>[],
        ),
      ),
      viceActivityGraphProvider.overrideWith(
        (ref, ViceActivityGraphQuery query) => Stream.value(activities),
      ),
    ],
  );
}

VicePreset _preset(OnboardingVariant variant, String name) =>
    variant.presets.firstWhere((VicePreset p) => p.name == name);

void main() {
  setUpAll(_loadFonts);

  final Map<OnboardingVariant, List<String>> picks = {
    plainNames: ['Coffee', 'Vape'],
    everydayHabits: ['Coffee', 'Social media'],
  };

  for (final MapEntry(key: OnboardingVariant variant, value: names)
      in picks.entries) {
    final String id = variant.id;
    final List<VicePreset> picked = [
      for (final String n in names) _preset(variant, n),
    ];

    testWidgets('$id intro', (WidgetTester tester) async {
      await _render(tester, '$id-1-intro', IntroScreen(variant: variant));
    });

    testWidgets('$id picker', (WidgetTester tester) async {
      await _render(
        tester,
        '$id-2-picker',
        PresetPickerScreen(variant: variant, initialSelection: {...names}),
      );
    });

    testWidgets('$id disclaimer', (WidgetTester tester) async {
      await _render(
        tester,
        '$id-3-disclaimer',
        DisclaimerScreen(variant: variant),
      );
    });

    testWidgets('$id first log', (WidgetTester tester) async {
      await _render(
        tester,
        '$id-4-first-log',
        FirstLogScreen(variant: variant, entries: picked),
      );
    });

    testWidgets('$id today', (WidgetTester tester) async {
      await _renderToday(tester, '$id-5-today', picked, picked.first);
    });
  }

  const VicePreset written = VicePreset(
    'Wine',
    Unit.drink,
    Icons.edit_note_outlined,
  );
  final String id = ownWords.id;

  testWidgets('$id intro', (WidgetTester tester) async {
    await _render(tester, '$id-1-intro', const IntroScreen(variant: ownWords));
  });

  testWidgets('$id picker', (WidgetTester tester) async {
    await _render(
      tester,
      '$id-2-picker',
      NameYourOwnScreen(
        variant: ownWords,
        initialName: written.name,
        initialUnit: written.unit,
      ),
    );
  });

  testWidgets('$id disclaimer', (WidgetTester tester) async {
    await _render(
      tester,
      '$id-3-disclaimer',
      const DisclaimerScreen(variant: ownWords),
    );
  });

  testWidgets('$id first log', (WidgetTester tester) async {
    await _render(
      tester,
      '$id-4-first-log',
      const FirstLogScreen(variant: ownWords, entries: [written]),
    );
  });

  testWidgets('$id today', (WidgetTester tester) async {
    await _renderToday(tester, '$id-5-today', [written], written);
  });
}
