import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/authenticate.dart';
import 'package:tracker/firebase_init.dart';
import 'package:tracker/homepage.dart';
import 'package:tracker/widgets/log_fan.dart';
import 'package:tracker/widgets/record_new_activity_dialog.dart';
import 'package:tracker/widgets/trigger_picker.dart';
import 'package:tracker/widgets/urge_note_fields.dart';
import 'package:tracker/writes/what_was_going_on.dart';

import 'support.dart';

// Not in all_test.dart: it hands text input back to iOS so that the
// simulator's own keyboard rises, and its timing is the simulator's. Run it
// with tools/e2e-screenshots.sh to keep a still of each field.

double _keyboardTop(WidgetTester tester) =>
    (tester.view.physicalSize.height - tester.view.viewInsets.bottom) /
    tester.view.devicePixelRatio;

// Until iOS reports a keyboard and it has stopped rising.
Future<void> _keyboardUp(WidgetTester tester) async {
  double last = -1;
  await pumpUntilTrue(tester, () {
    final double inset = tester.view.viewInsets.bottom;
    final bool settled = inset > 0 && inset == last;
    last = inset;
    return settled;
  }, () => 'the simulator keyboard to rise');
  await pumpFor(tester, const Duration(milliseconds: 500));
}

Future<void> _expectAbove(
  WidgetTester tester,
  Finder target,
  String what,
) async {
  expect(
    tester.getRect(target).bottom,
    lessThanOrEqualTo(_keyboardTop(tester)),
    reason: '$what is under the keyboard',
  );
}

Future<void> _focus(WidgetTester tester, Finder field) async {
  await scrollIntoViewOf(tester, field);
  await tap(tester, field);
  await _keyboardUp(tester);
}

Future<void> scrollIntoViewOf(WidgetTester tester, Finder finder) async {
  await pumpUntil(tester, finder);
  await Scrollable.ensureVisible(finder.evaluate().first);
  await tester.pump();
}

void main() {
  ensureE2EBinding();

  setUpAll(() async {
    requireEmulators();
    await initializeFirebase();
    await clearEmulators();
  });

  testWidgets('the fields of the entry sheets stay above the real keyboard', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(e2eApp());
    await FirebaseAuth.instance.signOut();
    await tap(tester, find.byKey(Authenticate.guestStart));
    await pumpUntil(tester, find.byType(Homepage));
    await skipTheOnboarding(tester);
    await addVicesThroughManageData(tester, <String>['Coffee']);

    tester.testTextInput.unregister();
    addTearDown(tester.testTextInput.register);

    await tester.pump();
    await tap(tester, find.byType(LogButton));
    final Finder wedge = fanWedge('Coffee');
    await pumpUntil(tester, wedge.hitTestable());
    await pumpFor(tester, const Duration(milliseconds: 800));
    await tester.longPress(wedge);
    await tester.pump();
    final Finder sheet = find.byType(RecordNewActivityDialog);
    await pumpUntilRouteSettled(tester, sheet);

    final Finder quantity = find.descendant(
      of: find.widgetWithText(TextFormField, 'Quantity'),
      matching: find.byType(EditableText),
    );
    await _focus(tester, quantity);
    await _expectAbove(tester, quantity, 'Quantity');
    await screenshot(tester, 'amount-quantity');

    final Finder note = find.byKey(NoteField.fieldKey);
    await _focus(tester, note);
    await _expectAbove(tester, note, 'the amount sheet\'s note');
    await screenshot(tester, 'amount-note');

    final Finder openPicker = find.text('What was going on? (optional)');
    await scrollIntoViewOf(tester, openPicker);
    await tap(tester, openPicker);
    final Finder picker = find.byType(TriggerPickerSheet);
    await pumpUntilRouteSettled(tester, picker);
    final Finder ownWords = find.descendant(
      of: picker,
      matching: find.text('Your own words'),
    );
    await scrollIntoViewOf(tester, ownWords);
    await tap(tester, ownWords);
    await _keyboardUp(tester);
    final Finder done = find.descendant(
      of: picker,
      matching: find.text('Done'),
    );
    await _expectAbove(
      tester,
      find.descendant(of: picker, matching: find.byType(EditableText)),
      'the picker\'s own-words field',
    );
    await _expectAbove(tester, done, 'the picker\'s Done');
    await screenshot(tester, 'picker-own-words');
    await tap(tester, done);
    await pumpUntil(tester, picker, present: false);
    await tap(tester, find.byKey(RecordNewActivityDialog.submitKey));
    await pumpUntil(tester, sheet, present: false);

    await logOne(tester, 'Coffee');
    await tap(tester, find.text(whatWasGoingOnLabel));
    await pumpUntilRouteSettled(tester, picker);
    await _focus(tester, find.descendant(of: picker, matching: note));
    await _expectAbove(tester, note, 'the picker\'s note');
    await _expectAbove(tester, done, 'the picker\'s Done');
    await screenshot(tester, 'picker-note');
  });
}
