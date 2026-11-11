import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tracker/data/free_text_triggers.dart';
import 'package:tracker/data/limits.dart';
import 'package:tracker/data/trigger_usage.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/design/app_theme.dart';
import 'package:tracker/providers/tracker_writes_provider.dart';
import 'package:tracker/providers/unarchived_vice_list_provider.dart';
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/providers/vice_activity_history_provider.dart';
import 'package:tracker/widgets/record_new_activity_dialog.dart';
import 'package:tracker/widgets/trigger_picker.dart';

import 'fake_writes.dart';
import 'fakes.dart';

void main() {
  group('usualTriggers', () {
    test('ranks by frequency, then by the most recent use', () {
      final List<ViceActivity> recent = <ViceActivity>[
        fakeActivity(
          'coffee',
          1,
          DateTime(2026, 11, 6, 9),
          triggers: <String>['work/meeting'],
        ),
        fakeActivity(
          'coffee',
          1,
          DateTime(2026, 11, 5, 9),
          triggers: <String>['work/meeting', 'body/tired'],
        ),
        fakeActivity(
          'coffee',
          1,
          DateTime(2026, 11, 4, 9),
          triggers: <String>['social'],
        ),
        fakeActivity('coffee', 1, DateTime(2026, 11, 3, 9)),
      ];

      expect(usualTriggers(recent), <String>[
        'work/meeting',
        'body/tired',
        'social',
      ]);
      expect(usualTriggers(recent, max: 1), <String>['work/meeting']);
      expect(usualTriggers(const <ViceActivity>[]), isEmpty);
    });

    test('a trigger listed twice on one entry counts once', () {
      expect(
        usualTriggers(<ViceActivity>[
          fakeActivity(
            'coffee',
            1,
            DateTime(2026, 11, 6),
            triggers: <String>['a', 'a', 'a'],
          ),
          fakeActivity(
            'coffee',
            1,
            DateTime(2026, 11, 5),
            triggers: <String>['b'],
          ),
          fakeActivity(
            'coffee',
            1,
            DateTime(2026, 11, 4),
            triggers: <String>['b'],
          ),
        ]),
        <String>['b', 'a'],
      );
    });

    test('displays tree paths by label and free text as written', () {
      expect(triggerDisplay('work/meeting'), 'Work › Meeting');
      expect(triggerShortDisplay('work/meeting'), 'Meeting');
      expect(triggerDisplay('Pitch review'), 'Pitch review');
      expect(isFreeTextTrigger('work'), isFalse);
      expect(isFreeTextTrigger('Pitch review'), isTrue);
    });
  });

  group('FreeTextTriggers', () {
    setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

    test('promotes a label on its third use, per user', () async {
      const FreeTextTriggers store = FreeTextTriggers();
      await store.recordUses('a', <String>['Pitch review']);
      await store.recordUses('a', <String>['Pitch review', 'Pitch review']);
      expect(await store.promoted('a'), isEmpty);

      await store.recordUses('a', <String>['Pitch review']);
      expect(await store.promoted('a'), <String>['Pitch review']);
      expect(await store.promoted('b'), isEmpty);
    });

    test('reads a corrupt value as no uses', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        FreeTextTriggers.key('a'): 'not json',
      });
      expect(await const FreeTextTriggers().uses('a'), isEmpty);
    });
  });

  testWidgets('drills from an area to a child, which replaces the area', (
    tester,
  ) async {
    List<String>? done;
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(Brightness.light),
        home: Scaffold(
          body: TriggerPickerSheet(
            viceName: 'Coffee',
            onDone: (List<String> picked) => done = picked,
          ),
        ),
      ),
    );

    expect(find.text('Areas of life'), findsOneWidget);
    await tester.tap(find.text('Work'));
    await tester.pumpAndSettle();

    // Opening the area records it.
    expect(find.widgetWithText(InputChip, 'Work'), findsOneWidget);
    expect(find.widgetWithText(FilterChip, 'Meeting'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilterChip, 'Meeting'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(InputChip, 'Work'), findsNothing);
    expect(find.widgetWithText(InputChip, 'Work › Meeting'), findsOneWidget);

    await tester.tap(find.byTooltip('All areas'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Work, 1 picked'), findsOneWidget);

    await tester.tap(find.text('Done'));
    expect(done, <String>['work/meeting']);
  });

  testWidgets('refuses free text the rules would refuse, and says why', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(1179, 2556)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    List<String>? done;
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(Brightness.light),
        home: Scaffold(
          body: TriggerPickerSheet(
            viceName: 'Coffee',
            onDone: (List<String> picked) => done = picked,
          ),
        ),
      ),
    );

    await tester.tap(find.text('Your own words'));
    await tester.pumpAndSettle();
    // 31 characters for the field, 62 UTF-16 code units for the rules.
    final String emoji = '\u{1F44D}' * 31;
    await tester.enterText(
      find.widgetWithText(TextField, 'In your own words'),
      emoji,
    );
    await tester.tap(find.byTooltip('Add'));
    await tester.pumpAndSettle();
    expect(
      find.text('Keep each trigger to $maxTriggerLength characters or fewer'),
      findsOneWidget,
    );
    expect(find.byType(InputChip), findsNothing);

    await tester.enterText(find.byType(TextField), 'Pitch review');
    await tester.tap(find.byTooltip('Add'));
    await tester.pumpAndSettle();
    expect(find.textContaining('characters or fewer'), findsNothing);
    await tester.tap(find.text('Done'));
    expect(done, <String>['Pitch review']);
  });

  testWidgets('offers the habit\'s usual triggers first', (tester) async {
    List<String>? done;
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(Brightness.light),
        home: Scaffold(
          body: TriggerPickerSheet(
            viceName: 'Coffee',
            usual: const <String>['feeling/stressed'],
            onDone: (List<String> picked) => done = picked,
          ),
        ),
      ),
    );

    expect(find.text('Usual for Coffee'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilterChip, 'Feeling › Stressed'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    expect(done, <String>['feeling/stressed']);
  });

  testWidgets('free text saved a third time becomes a choice in the picker', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      FreeTextTriggers.key(ownerID): '{"Pitch review":2}',
    });
    // A phone, so the sheet shows the whole first level.
    tester.view
      ..physicalSize = const Size(1179, 2556)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final FakeTrackerWrites writes = FakeTrackerWrites();
    final vice = fakeVice('coffee');

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          userProvider.overrideWith((ref) => Stream.value(FakeUser(ownerID))),
          unarchivedViceListProvider.overrideWithValue(AsyncData([vice])),
          viceActivityHistoryProvider.overrideWith(
            (ref, query) => const AsyncData(<ViceActivity>[]),
          ),
          trackerWritesProvider.overrideWithValue(writes),
          memoryJournal(),
        ],
        child: MaterialApp(
          theme: appTheme(Brightness.light),
          home: Scaffold(
            // Keeps the signed-in user loaded, as the app's root does.
            body: Consumer(
              builder: (context, ref, _) {
                ref.watch(userProvider);
                return TextButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) =>
                        RecordNewActivityDialog(initialViceID: vice.id),
                  ),
                  child: const Text('open'),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    Future<void> openPicker() async {
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('What was going on? (optional)'));
      await tester.pumpAndSettle();
    }

    await openPicker();
    expect(find.text('What was going on?'), findsOneWidget);
    // The record sheet and editor share this picker; the editor has Delete.
    expect(find.text(undoLogLabel), findsNothing);
    expect(find.text('Your own words'), findsOneWidget);
    // Two uses so far: not yet a choice.
    expect(find.text('Your own'), findsNothing);
    await tester.tap(find.text('Your own words'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'In your own words'),
      'Pitch review',
    );
    await tester.tap(find.byTooltip('Add'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(InputChip, 'Pitch review'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextFormField, 'Quantity'), '1');
    await tester.tap(find.byKey(RecordNewActivityDialog.submitKey));
    await tester.pumpAndSettle();

    expect(writes.writes.single.fields['triggers'], <String>['Pitch review']);
    expect(await const FreeTextTriggers().uses(ownerID), <String, int>{
      'Pitch review': 3,
    });

    await openPicker();
    expect(find.text('Your own'), findsOneWidget);
    expect(find.widgetWithText(FilterChip, 'Pitch review'), findsOneWidget);
  });
}
