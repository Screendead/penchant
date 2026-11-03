// Renders the trigger-picker candidates to docs/pitch/mockups/trigger-tree/.
// Regenerate with:
//   flutter test test/mockups/trigger_tree_mockup_test.dart --update-goldens
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/mockups/trigger_tree/recent_triggers.dart';
import 'package:tracker/mockups/trigger_tree/starter_trees.dart';
import 'package:tracker/mockups/trigger_tree/trigger_picker_sheet.dart';
import 'package:tracker/mockups/trigger_tree/trigger_tree.dart';

const String outDir = '../../docs/pitch/mockups/trigger-tree';
final DateTime now = DateTime(2026, 11, 3, 14, 32);
const String entry = 'Coffee · 1 cup · 14:32';
const Map<String, String> customLabels = <String, String>{
  'custom/school-run': 'School run',
};

String flutterRoot() {
  final String? env = Platform.environment['FLUTTER_ROOT'];

  if (env != null) {
    return env;
  }

  final String which =
      (Process.runSync('which', <String>['flutter']).stdout as String).trim();

  return File(which).resolveSymbolicLinksSync().replaceAll('/bin/flutter', '');
}

Future<void> loadFonts() async {
  final String dir = '${flutterRoot()}/bin/cache/artifacts/material_fonts';
  Future<ByteData> font(String name) async =>
      ByteData.sublistView(File('$dir/$name').readAsBytesSync());

  final FontLoader roboto = FontLoader('Roboto');
  for (final String weight in <String>['Regular', 'Medium', 'Bold']) {
    roboto.addFont(font('Roboto-$weight.ttf'));
  }
  await roboto.load();

  await (FontLoader(
    'MaterialIcons',
  )..addFont(font('MaterialIcons-Regular.otf'))).load();
}

ThemeData appTheme() => ThemeData(
  fontFamily: 'Roboto',
  colorScheme: ColorScheme.fromSeed(
    seedColor: Colors.pink,
    brightness: Brightness.dark,
  ),
  useMaterial3: true,
  inputDecorationTheme: const InputDecorationTheme(
    floatingLabelBehavior: FloatingLabelBehavior.always,
    floatingLabelAlignment: FloatingLabelAlignment.center,
    border: OutlineInputBorder(),
    focusedBorder: OutlineInputBorder(
      borderSide: BorderSide(color: Colors.pink),
    ),
  ),
);

/// Each tree's usual paths for coffee, with how often each was used.
const Map<String, List<(String, int)>> histories =
    <String, List<(String, int)>>{
      'areas': <(String, int)>[
        ('work/meeting', 9),
        ('body/tired', 7),
        ('routine/morning', 8),
        ('custom/school-run', 3),
        ('feeling/stressed', 3),
        ('social/friends', 1),
      ],
      'reasons': <(String, int)>[
        ('pressure/meeting', 9),
        ('body/tired', 7),
        ('habit/time', 8),
        ('custom/school-run', 3),
        ('body/focus', 3),
        ('occasion/meal', 1),
      ],
      'feelings': <(String, int)>[
        ('tired/poor-sleep', 9),
        ('stressed/work', 7),
        ('neutral/morning', 8),
        ('custom/school-run', 3),
        ('tired/focus', 3),
        ('good/friends', 1),
      ],
    };

List<TriggerUse> historyFor(TriggerTree tree) {
  final List<TriggerUse> uses = <TriggerUse>[];
  final List<(String, int)> paths = histories[tree.id]!;

  for (int i = 0; i < paths.length; i++) {
    final (String path, int count) = paths[i];

    for (int k = 0; k < count; k++) {
      // Mornings are logged at 08:00, the rest near the current hour.
      final int hour = path.contains('morning') || path.endsWith('time')
          ? 8
          : 14;
      uses.add(
        TriggerUse(
          path,
          DateTime(now.year, now.month, now.day - (k * 3 + i), hour, 10),
        ),
      );
    }
  }

  return uses;
}

const Map<String, String> drillRoot = <String, String>{
  'areas': 'work',
  'reasons': 'pressure',
  'feelings': 'stressed',
};

class Scene extends StatelessWidget {
  const Scene({super.key, required this.sheet});

  final Widget sheet;

  @override
  Widget build(BuildContext context) {
    // The sheet stops below the app bar so the screen behind stays legible.
    final double height =
        MediaQuery.sizeOf(context).height -
        MediaQuery.paddingOf(context).top -
        kToolbarHeight -
        8;

    return Stack(
      children: [
        Scaffold(
          appBar: AppBar(title: const Text('Today')),
          body: const Center(child: Icon(Icons.radar, size: 160)),
        ),
        const ModalBarrier(color: Colors.black54, dismissible: false),
        Align(
          alignment: Alignment.bottomCenter,
          child: SizedBox(height: height, child: sheet),
        ),
      ],
    );
  }
}

Future<void> render(
  WidgetTester tester,
  TriggerPickerSheet sheet,
  String name,
) async {
  tester.view
    ..physicalSize = const Size(393 * 3, 852 * 3)
    ..devicePixelRatio = 3
    ..padding = const FakeViewPadding(top: 59 * 3, bottom: 34 * 3);
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: appTheme(),
      home: Scene(sheet: sheet),
    ),
  );
  await tester.pumpAndSettle();
  await expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile('$outDir/$name.png'),
  );
}

void main() {
  setUpAll(loadFonts);

  test('the ranking puts frequent, recent, same-hour paths first', () {
    final List<RankedTrigger> ranked = rankRecent(historyFor(areasTree), now);

    expect(ranked.first.path, 'work/meeting');
    expect(ranked.map((r) => r.path), isNot(contains('social/friends')));
  });

  for (final TriggerTree tree in starterTrees) {
    final String id = tree.id;
    final String letter = tree.name.substring(0, 1).toLowerCase();

    testWidgets('$id: level 1, first use', (WidgetTester tester) async {
      await render(
        tester,
        TriggerPickerSheet(tree: tree, entryLabel: entry, viceName: 'coffee'),
        '$letter-$id-1-level-one',
      );
    });

    testWidgets('$id: level 2', (WidgetTester tester) async {
      final String root = drillRoot[id]!;

      await render(
        tester,
        TriggerPickerSheet(
          tree: tree,
          entryLabel: entry,
          viceName: 'coffee',
          initialRoot: root,
          initialSelected: <String>{'$root/deadline'},
          initialFreeText: 'Quarterly review',
        ),
        '$letter-$id-2-level-two',
      );
    });

    testWidgets('$id: recent', (WidgetTester tester) async {
      final List<String> recent = rankRecent(
        historyFor(tree),
        now,
        limit: 4,
      ).map((r) => r.path).toList();

      await render(
        tester,
        TriggerPickerSheet(
          tree: tree,
          entryLabel: entry,
          viceName: 'coffee',
          recent: recent,
          customLabels: customLabels,
          initialSelected: <String>{recent.first},
          suggestion: 'custom/school-run',
        ),
        '$letter-$id-3-recent',
      );
    });
  }

  testWidgets('tapping a root drills in and records it', (tester) async {
    Set<String>? done;

    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        home: Scaffold(
          body: TriggerPickerSheet(
            tree: areasTree,
            entryLabel: entry,
            viceName: 'coffee',
            onDone: (s) => done = s,
          ),
        ),
      ),
    );

    await tester.tap(find.text('Work'));
    await tester.pump();
    await tester.tap(find.text('Meeting'));
    await tester.pump();
    await tester.tap(find.text('Done'));

    expect(done, <String>{'work/meeting'});
  });
}
