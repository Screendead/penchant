import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/add_vice.dart';
import 'package:tracker/data/limits.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/providers/unarchived_vice_list_provider.dart';
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/providers/vice_activity_history_provider.dart';
import 'package:tracker/providers/vice_list_provider.dart';
import 'package:tracker/vice_activity_editor_page.dart';
import 'package:tracker/widgets/record_new_activity_dialog.dart';

import 'fakes.dart';

Future<void> _pump(
  WidgetTester tester,
  List<Override> overrides,
  Widget home,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(home: Scaffold(body: home)),
    ),
  );
  await tester.pump();
}

Finder _field(String label) => find.widgetWithText(TextFormField, label);

void main() {
  group('viceNameError', () {
    test('accepts 1 to 60 characters', () {
      expect(viceNameError('x'), isNull);
      expect(viceNameError('x' * maxViceNameLength), isNull);
    });

    test('refuses an empty name and one over 60', () {
      expect(viceNameError(''), 'Please enter a name');
      expect(viceNameError(null), 'Please enter a name');
      expect(viceNameError('x' * 61), 'Use 60 characters or fewer');
    });

    test('counts UTF-16 code units, as the rules do', () {
      expect(viceNameError('😀' * 30), isNull);
      expect(viceNameError('😀' * 31), isNotNull);
    });
  });

  group('quantityError', () {
    test('accepts a positive whole number', () {
      expect(quantityError('1'), isNull);
      expect(quantityError('250'), isNull);
    });

    test('refuses zero, negatives, and non-numbers', () {
      expect(quantityError('0'), 'Please enter at least 1');
      expect(quantityError('-3'), 'Please enter at least 1');
      expect(quantityError('1.5'), 'Please enter a valid number');
      expect(quantityError(''), 'Please enter a quantity');
    });

    test("accepts a legacy activity's unchanged out-of-range quantity", () {
      expect(quantityError('0', unchanged: 0), isNull);
      expect(quantityError('-1', unchanged: 0), 'Please enter at least 1');
    });
  });

  testWidgets('Add Vice shows the length message inline', (tester) async {
    await _pump(tester, [
      userProvider.overrideWith((ref) => Stream.value(FakeUser(ownerID))),
    ], const AddVice());

    await tester.enterText(_field('Vice Name'), 'x' * 61);
    // No unit is selected, so validation runs but nothing is written.
    await tester.tap(find.text('Save'));
    await tester.pump();

    expect(find.text('Use 60 characters or fewer'), findsOneWidget);
  });

  testWidgets('the record dialog refuses a zero quantity inline', (
    tester,
  ) async {
    final Vice vice = fakeVice('coffee');
    await _pump(tester, [
      userProvider.overrideWith((ref) => Stream.value(FakeUser(ownerID))),
      unarchivedViceListProvider.overrideWithValue(AsyncData([vice])),
    ], const RecordNewActivityDialog());

    await tester.enterText(_field('Quantity'), '0');
    // No vice is selected, so validation runs but nothing is written.
    await tester.tap(find.text('Record'));
    await tester.pump();

    expect(find.text('Please enter at least 1'), findsOneWidget);
  });

  group('the activity editor', () {
    final Vice vice = fakeVice('coffee');

    Future<void> pumpEditor(WidgetTester tester, int quantity) => _pump(
      tester,
      [
        viceListProvider.overrideWithValue(AsyncData([vice])),
        viceActivityProvider.overrideWith(
          (ref, String activityID) => AsyncData(
            fakeActivity(vice.id, quantity, DateTime(2026, 1, 2, 8, 30)),
          ),
        ),
      ],
      ViceActivityEditorPage(
        viceID: vice.id,
        activityID: fakeActivity(
          vice.id,
          quantity,
          DateTime(2026, 1, 2, 8, 30),
        ).id,
      ),
    );

    testWidgets('refuses changing a quantity to zero inline', (tester) async {
      await pumpEditor(tester, 2);

      await tester.enterText(_field('Quantity'), '0');
      await tester.tap(find.text('Save'));
      await tester.pump();

      expect(find.text('Please enter at least 1'), findsOneWidget);
    });

    testWidgets("lets a legacy zero quantity stand while other fields change", (
      tester,
    ) async {
      await pumpEditor(tester, 0);

      final FormState form = tester.state<FormState>(find.byType(Form));
      expect(form.validate(), isTrue);
    });
  });
}
