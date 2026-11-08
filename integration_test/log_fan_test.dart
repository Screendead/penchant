import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/firebase_init.dart';
import 'package:tracker/main.dart';
import 'package:tracker/widgets/log_fan.dart';
import 'package:tracker/widgets/record_new_activity_dialog.dart';

import 'support.dart';

// A wedge's name, which sits at its label point: inside the wedge's shape,
// where the wedge widget's own box (the whole fan) need not be.
Finder _wedgeName(String viceName) =>
    find.descendant(of: fanWedge(viceName), matching: find.text(viceName));

// A wedge's node: the tally's + under the fan reads the same label, and only
// the wedge carries the hold hint.
SemanticsFinder _wedgeNode(String label) => find.semantics.byPredicate(
  (SemanticsNode node) =>
      node.label == label && node.hint == 'Hold to set amount and time',
  describeMatch: (_) => 'the wedge "$label"',
);

Future<void> _startApp(WidgetTester tester, String email) async {
  await tester.pumpWidget(const ProviderScope(child: MyApp()));
  await register(tester, email);
  await addVicesThroughManageData(tester);
}

void main() {
  ensureE2EBinding();

  setUpAll(() async {
    requireEmulators();
    await initializeFirebase();
    await clearEmulators();
  });

  testWidgets('a press on Log dragged onto a wedge logs one on release; '
      'released off the fan it logs nothing, and Escape closes the fan', (
    WidgetTester tester,
  ) async {
    await _startApp(tester, 'e2e-fan-drag@example.com');
    await expectTallies(tester, const <String>{
      'Coffee (0 drinks)',
      'Tea (0 drinks)',
      'Water (0 drinks)',
    });

    // The fan opens on the press, before any release.
    await pumpUntil(tester, find.byType(LogButton).hitTestable());
    final Offset log = tester.getCenter(find.byType(LogButton));
    final TestGesture drag = await tester.startGesture(log);
    await pumpUntil(tester, _wedgeName('Tea'));
    await pumpFor(tester, const Duration(milliseconds: 800));
    await drag.moveTo(tester.getCenter(_wedgeName('Tea')));
    await tester.pump();
    await drag.up();
    await tester.pump();
    await pumpUntil(tester, find.textContaining('Logged 1 drink of Tea at'));
    await pumpUntil(tester, fanWedge('Tea'), present: false);
    await expectTallies(tester, const <String>{
      'Coffee (0 drinks)',
      'Tea (1 drink)',
      'Water (0 drinks)',
    });
    expect(await storedActivities('Tea'), hasLength(1));

    // Above the fan's reach: the fan stays open and nothing is logged.
    final TestGesture away = await tester.startGesture(log);
    await pumpUntil(tester, _wedgeName('Coffee'));
    await pumpFor(tester, const Duration(milliseconds: 800));
    await away.moveTo(Offset(log.dx, 4));
    await tester.pump();
    await away.up();
    await pumpFor(tester, const Duration(milliseconds: 500));
    expect(_wedgeName('Coffee').hitTestable(), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await pumpUntil(tester, fanWedge('Coffee'), present: false);
    await pumpUntil(tester, find.byType(LogButton).hitTestable());
    expect(await storedActivities('Coffee'), isEmpty);
    await expectTallies(tester, const <String>{
      'Coffee (0 drinks)',
      'Tea (1 drink)',
      'Water (0 drinks)',
    });
  });

  testWidgets("a screen reader logs one from Log's actions and from a wedge, "
      'and a wedge held opens the record dialog on its habit', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    await _startApp(tester, 'e2e-fan-reader@example.com');
    await expectTallies(tester, const <String>{
      'Coffee (0 drinks)',
      'Tea (0 drinks)',
      'Water (0 drinks)',
    });

    // Log's custom actions log one without opening the fan.
    await pumpUntil(tester, find.byType(LogButton).hitTestable());
    tester.semantics.customAction(
      find.semantics.byLabel(LogButton.label),
      const CustomSemanticsAction(label: 'Log 1 drink of Coffee'),
    );
    await tester.pump();
    await pumpUntil(tester, find.textContaining('Logged 1 drink of Coffee at'));
    expect(fanWedge('Coffee'), findsNothing);
    await expectTallies(tester, const <String>{
      'Coffee (1 drink)',
      'Tea (0 drinks)',
      'Water (0 drinks)',
    });
    // The dial reads the entry out as a bead.
    await pumpUntil(
      tester,
      find.bySemanticsLabel(RegExp('^Coffee, 1 drink at ')),
    );

    // Tapping Log opens the fan; a wedge's tap logs one.
    tester.semantics.tap(find.semantics.byLabel(LogButton.label));
    await tester.pump();
    await pumpUntil(tester, _wedgeName('Water'));
    await pumpFor(tester, const Duration(milliseconds: 800));
    tester.semantics.tap(_wedgeNode('Log 1 drink of Water'));
    await tester.pump();
    await pumpUntil(tester, find.textContaining('Logged 1 drink of Water at'));
    await expectTallies(tester, const <String>{
      'Coffee (1 drink)',
      'Tea (0 drinks)',
      'Water (1 drink)',
    });

    // A wedge's long press opens the record dialog with its habit chosen.
    tester.semantics.tap(find.semantics.byLabel(LogButton.label));
    await tester.pump();
    await pumpUntil(tester, _wedgeName('Tea'));
    await pumpFor(tester, const Duration(milliseconds: 800));
    tester.semantics.longPress(_wedgeNode('Log 1 drink of Tea'));
    await tester.pump();
    final Finder dialog = find.byType(RecordNewActivityDialog);
    await pumpUntil(tester, dialog);
    expect(
      find.descendant(
        of: find.descendant(
          of: dialog,
          matching: find.byType(DropdownButtonFormField<String>),
        ),
        matching: find.text('Tea'),
      ),
      findsOneWidget,
    );
    await tap(
      tester,
      find.descendant(of: dialog, matching: find.text('Cancel')),
    );
    await pumpUntil(tester, dialog, present: false);
    expect(await storedActivities('Tea'), isEmpty);
    semantics.dispose();
  });
}
