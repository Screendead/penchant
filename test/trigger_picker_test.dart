import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
      expect(triggerDisplay('work/meeting'), 'Work or study › Meeting');
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
    await tester.tap(find.text('Work or study'));
    await tester.pumpAndSettle();

    // Opening the area records it.
    expect(find.widgetWithText(InputChip, 'Work or study'), findsOneWidget);
    expect(find.widgetWithText(FilterChip, 'Meeting'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilterChip, 'Meeting'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(InputChip, 'Work or study'), findsNothing);
    expect(
      find.widgetWithText(InputChip, 'Work or study › Meeting'),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('All areas'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Work or study, 1 picked'), findsOneWidget);

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

    // 31 characters for the field, 62 UTF-16 code units for the rules.
    final String emoji = '\u{1F44D}' * 31;
    await tester.enterText(
      find.widgetWithText(TextField, TriggerChoices.searchHint),
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
    // Two uses so far: not yet a choice.
    expect(find.text('Your own'), findsNothing);
    await tester.enterText(
      find.widgetWithText(TextField, TriggerChoices.searchHint),
      'Pitch review',
    );
    await tester.tap(find.byTooltip('Add'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(InputChip, 'Pitch review'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextFormField, 'Quantity'), '1');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.ensureVisible(find.byKey(RecordNewActivityDialog.submitKey));
    await tester.pump(const Duration(seconds: 1));
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

  group('search', () {
    Future<Future<List<String>?> Function()> pumpSheet(
      WidgetTester tester, {
      List<String> initial = const <String>[],
    }) async {
      List<String>? done;
      tester.view
        ..physicalSize = const Size(1179, 2556)
        ..devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(Brightness.light),
          home: Scaffold(
            body: TriggerPickerSheet(
              viceName: 'Coffee',
              initial: initial,
              onDone: (List<String> picked) => done = picked,
            ),
          ),
        ),
      );
      return () async {
        await tester.tap(find.text('Done'));
        return done;
      };
    }

    final Finder field = find.widgetWithText(
      TextField,
      TriggerChoices.searchHint,
    );

    testWidgets('matches across areas and picks from the results', (
      tester,
    ) async {
      final done = await pumpSheet(tester);
      await tester.enterText(field, 'work');
      await tester.pump();

      expect(find.text('Areas of life'), findsNothing);
      expect(
        find.widgetWithText(FilterChip, 'Place · At work'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(FilterChip, 'Work or study · Meeting'),
        findsOneWidget,
      );
      expect(find.textContaining('in your own words'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilterChip, 'Place · At work'));
      await tester.pump();
      expect(find.widgetWithText(InputChip, 'Place › At work'), findsOneWidget);
      expect(await done(), <String>['place/at-work']);
    });

    testWidgets('a tag picked from the results replaces its bare area', (
      tester,
    ) async {
      final done = await pumpSheet(tester, initial: const <String>['body']);
      await tester.enterText(field, 'tired');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(tester.widget<TextField>(field).controller!.text, isEmpty);
      expect(await done(), <String>['body/tired']);
    });

    testWidgets('a label under two areas waits for a tap', (tester) async {
      final done = await pumpSheet(tester);
      await tester.enterText(field, 'Hard conversation');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(find.textContaining('in your own words'), findsNothing);
      expect(find.byType(InputChip), findsNothing);
      await tester.tap(
        find.widgetWithText(FilterChip, 'Between people · Hard conversation'),
      );
      await tester.pump();
      expect(await done(), <String>['people/hard-talk']);
    });

    testWidgets('no match adds the text in your own words', (tester) async {
      final done = await pumpSheet(tester);
      await tester.enterText(field, 'Late train');
      await tester.pump();
      expect(find.text('No tag matches'), findsOneWidget);
      await tester.tap(find.text('Add "Late train" in your own words'));
      await tester.pump();
      expect(find.widgetWithText(InputChip, 'Late train'), findsOneWidget);
      expect(find.text('Areas of life'), findsOneWidget);
      expect(await done(), <String>['Late train']);
    });

    testWidgets('clearing the field brings the areas back', (tester) async {
      await pumpSheet(tester);
      await tester.enterText(field, 'sad');
      await tester.pump();
      expect(find.text('Areas of life'), findsNothing);
      await tester.tap(find.byTooltip('Clear'));
      await tester.pump();
      expect(find.text('Areas of life'), findsOneWidget);
      expect(find.text('Something happened'), findsOneWidget);
    });

    testWidgets('stops at $maxTriggers tags', (tester) async {
      final done = await pumpSheet(
        tester,
        initial: <String>[for (int i = 0; i < maxTriggers; i++) 'own $i'],
      );
      await tester.enterText(field, 'tired');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilterChip, 'Body · Tired'));
      await tester.pump();
      expect(await done(), hasLength(maxTriggers));
    });
  });

  for (final double scale in <double>[1, 2]) {
    testWidgets('every area fits a phone at text scale $scale', (tester) async {
      tester.view
        ..physicalSize = const Size(1170, 2532)
        ..devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(Brightness.light),
          home: MediaQuery.withClampedTextScaling(
            minScaleFactor: scale,
            maxScaleFactor: scale,
            child: Scaffold(
              body: TriggerPickerSheet(viceName: 'Coffee', onDone: (_) {}),
            ),
          ),
        ),
      );
      final Finder list = find.byType(Scrollable).first;
      for (final String label in <String>[
        'Something happened',
        'What I was doing',
        'Time and routine',
      ]) {
        await tester.scrollUntilVisible(
          find.text(label),
          100,
          scrollable: list,
        );
        final Text text = tester.widget<Text>(find.text(label));
        final RenderParagraph p = tester.renderObject<RenderParagraph>(
          find.text(label),
        );
        expect(p.didExceedMaxLines, isFalse, reason: label);
        expect(text.maxLines, 2);
      }
      await tester.tap(find.text('Time and routine'));
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(FilterChip, 'Middle of the night'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
