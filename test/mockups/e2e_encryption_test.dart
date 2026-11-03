// Renders the end-to-end encryption key screens to
// docs/pitch/mockups/e2e-encryption/.
// flutter test test/mockups/e2e_encryption_test.dart --update-goldens

import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/crypto/recovery_key.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/journal_key/screens.dart';
import 'package:tracker/providers/unarchived_vice_list_provider.dart';
import 'package:tracker/providers/vice_activity_day_provider.dart';
import 'package:tracker/theme.dart';
import 'package:tracker/vice_tracker.dart';
import 'package:tracker/widgets/record_new_activity_button.dart';

import '../fakes.dart';

const String _out = '../../docs/pitch/mockups/e2e-encryption';
const Key _frame = ValueKey('frame');

final String key = RecoveryKey.format(RecoveryKey.generate(Random(42)));

Future<void> _loadFont(String family, List<String> files) async {
  final String dir =
      '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts';
  final FontLoader loader = FontLoader(family);
  for (final String file in files) {
    final Uint8List bytes = File('$dir/$file').readAsBytesSync();
    loader.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  await loader.load();
}

Future<void> _render(
  WidgetTester tester,
  Widget screen,
  String name, {
  List<Override> overrides = const [],
  Future<void> Function()? interact,
}) async {
  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = const Size(393 * 3, 852 * 3);
  tester.view.padding = const FakeViewPadding(top: 59 * 3, bottom: 34 * 3);
  addTearDown(tester.view.reset);
  debugDisableShadows = false;

  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: RepaintBoundary(
        key: _frame,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: appTheme(),
          home: screen,
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  if (interact != null) {
    await interact();
    await tester.pump(const Duration(seconds: 1));
  }

  try {
    await expectLater(find.byKey(_frame), matchesGoldenFile('$_out/$name.png'));
  } finally {
    debugDisableShadows = true;
  }
}

// Typed as a person would: groups separated by spaces, one character off.
String _typo(String formatted, int position) {
  final String plain = RecoveryKey.normalise(formatted);
  final String wrong = plain[position - 1] == 'X' ? 'Y' : 'X';
  final String typed = plain.replaceRange(position - 1, position, wrong);
  return [for (int g = 0; g < 8; g++) typed.substring(g * 4, g * 4 + 4)].join(' ');
}

void main() {
  setUpAll(() async {
    await _loadFont('Roboto', [
      'Roboto-Light.ttf',
      'Roboto-Regular.ttf',
      'Roboto-Medium.ttf',
      'Roboto-Bold.ttf',
    ]);
    await _loadFont('MaterialIcons', ['MaterialIcons-Regular.otf']);
  });

  testWidgets('B: recovery key step at sign-up, with Later', (tester) async {
    await _render(
      tester,
      RecoveryKeyIntroScreen(formatted: key, onSave: () {}, onLater: () {}),
      'b-signup-recovery-step',
    );
  });

  testWidgets('A: deferred card on Today', (tester) async {
    final DateTime today = startOfDay(DateTime.now());
    final vices = [fakeVice('coffee', name: 'Coffee'), fakeVice('wine', name: 'Wine'), fakeVice('cigs', name: 'Cigarettes')];
    await _render(
      tester,
      Scaffold(
        appBar: AppBar(
          title: const Text('Vice Tracker'),
          leading: const Icon(Icons.menu),
          actions: const [RecordNewActivityButton()],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: DeferredRecoveryCard(
                entries: 41,
                days: 7,
                onSave: () {},
                onDismiss: () {},
              ),
            ),
            const Expanded(child: ViceTracker()),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: 0,
          destinations: const [
            NavigationDestination(icon: Icon(Icons.today), label: 'Today'),
            NavigationDestination(icon: Icon(Icons.show_chart_outlined), label: 'Graph'),
          ],
        ),
      ),
      'a-today-deferred-card',
      overrides: [
        unarchivedViceListProvider.overrideWith((ref) => Stream.value(vices)),
        viceActivityDayProvider.overrideWith(
          (ref, DateTime day) => Stream.value([
            fakeActivity('coffee', 3, today.add(const Duration(hours: 8))),
            fakeActivity('wine', 2, today.add(const Duration(hours: 19))),
            fakeActivity('cigs', 4, today.add(const Duration(hours: 12))),
          ]),
        ),
      ],
    );
  });

  testWidgets('save sheet over the sign-up step', (tester) async {
    await _render(
      tester,
      Builder(
        builder: (context) => RecoveryKeyIntroScreen(
          formatted: key,
          onLater: () {},
          onSave: () => showModalBottomSheet<void>(
            context: context,
            showDragHandle: true,
            isScrollControlled: true,
            builder: (_) => SaveRecoveryKeySheet(formatted: key, onSaved: () {}),
          ),
        ),
      ),
      'save-sheet',
      interact: () async {
        await tester.tap(find.text('Save recovery key'));
        await tester.pump();
      },
    );
  });

  for (final bool wrong in [false, true]) {
    testWidgets('confirm a group${wrong ? ', wrong' : ''}', (tester) async {
      final String group3 = RecoveryKey.groupsOf(key)[2];
      await _render(
        tester,
        ConfirmGroupScreen(
          group: 3,
          controller: TextEditingController(
            text: wrong ? '${group3.substring(0, 3)}${group3[3] == 'Q' ? 'R' : 'Q'}' : '',
          ),
          onConfirm: () {},
          onShowAgain: () {},
          wrong: wrong,
        ),
        wrong ? 'confirm-group-wrong' : 'confirm-group',
      );
    });
  }

  testWidgets('opening your journal', (tester) async {
    await _render(tester, const OpeningJournalScreen(), 'opening-journal');
  });

  testWidgets('enter recovery key, empty', (tester) async {
    await _render(
      tester,
      EnterRecoveryKeyScreen(
        controller: TextEditingController(),
        onUnlock: () {},
        onNoKey: () {},
      ),
      'enter-key',
    );
  });

  testWidgets('enter recovery key, one typo located', (tester) async {
    final String typed = _typo(key, 14);
    final RecoveryKeyParse parse = RecoveryKey.parse(typed);
    expect((parse as RecoveryKeyTypo).position, 14);
    await _render(
      tester,
      EnterRecoveryKeyScreen(
        controller: TextEditingController(text: typed),
        onUnlock: () {},
        onNoKey: () {},
        error: recoveryKeyError(parse),
      ),
      'enter-key-typo',
    );
  });

  testWidgets('enter recovery key, valid but another journal', (tester) async {
    await _render(
      tester,
      EnterRecoveryKeyScreen(
        controller: TextEditingController(
          text: RecoveryKey.format(RecoveryKey.generate(Random(5))),
        ),
        onUnlock: () {},
        onNoKey: () {},
        error: recoveryKeyError(null, wrongJournal: true),
      ),
      'enter-key-wrong-journal',
    );
  });

  testWidgets('start a new journal, destructive confirm', (tester) async {
    await _render(
      tester,
      Builder(
        builder: (context) => EnterRecoveryKeyScreen(
          controller: TextEditingController(),
          onUnlock: () {},
          onNoKey: () => showDialog<void>(
            context: context,
            builder: (_) => StartNewJournalDialog(
              vices: 6,
              entries: 1284,
              onCancel: () {},
              onConfirm: () {},
            ),
          ),
        ),
      ),
      'start-new-journal',
      interact: () async {
        await tester.tap(find.text("I don't have my recovery key"));
        await tester.pump();
      },
    );
  });

  testWidgets('Settings > Recovery key', (tester) async {
    await _render(
      tester,
      RecoveryKeySettingsScreen(
        formatted: key,
        confirmed: 'on 3 November 2026',
        onSave: () {},
        onReplace: () {},
      ),
      'settings-recovery-key',
    );
  });
}
