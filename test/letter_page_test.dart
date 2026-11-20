import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/crypto/sealed_files.dart';
import 'package:tracker/data/day_note.dart';
import 'package:tracker/data/unit.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/design/app_theme.dart';
import 'package:tracker/letter/letter_checks.dart';
import 'package:tracker/letter/letter_journal.dart';
import 'package:tracker/letter/letter_page.dart';
import 'package:tracker/letter/letter_payload.dart';
import 'package:tracker/letter/letter_setting.dart';
import 'package:tracker/letter/letter_store.dart';
import 'package:tracker/letter/letter_writer.dart';
import 'package:tracker/notes/follow_up.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tracker/providers/account_provider.dart';
import 'package:tracker/providers/device_files_provider.dart';
import 'package:tracker/providers/today_provider.dart';
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/providers/vice_list_provider.dart';

import 'fake_account.dart';
import 'fake_sealer.dart';
import 'fakes.dart';
import 'insights_harness.dart';

final DateTime today = DateTime(2026, 11, 16);

class FakeJournal implements LetterJournal {
  final List<(DateTime, DateTime)> reads = <(DateTime, DateTime)>[];

  @override
  Future<LetterJournalData> read(DateTime start, DateTime end) async {
    reads.add((start, end));
    return (
      activities: <ViceActivity>[
        ViceActivity(
          id: 'a1',
          viceID: 'v1',
          quantity: 2,
          ownerID: ownerID,
          createdAt: Timestamp.fromDate(DateTime(2026, 10, 2, 21)),
          note: 'needed it after the meeting',
          followUp: const FollowUp(
            question: 'What made it hard?',
            answer: 'it ran late again',
          ),
        ),
        ViceActivity(
          id: 'a2',
          viceID: 'v1',
          quantity: 1,
          ownerID: ownerID,
          createdAt: Timestamp.fromDate(DateTime(2026, 11, 1, 20)),
          note: 'walk home with Sam',
        ),
      ],
      dayNotes: <DayNote>[
        DayNote(
          id: 'n1',
          ownerID: ownerID,
          day: '2026-09-14',
          createdAt: Timestamp.fromDate(DateTime(2026, 9, 14)),
          text: 'A quiet Sunday.',
        ),
      ],
    );
  }
}

class FakeWriter implements LetterWriter {
  final List<LetterPayload> sent = <LetterPayload>[];

  @override
  Future<CheckedLetter> write(LetterPayload payload) async {
    sent.add(payload);
    return const CheckedLetter(
      sections: <LetterSection>[
        LetterSection('What you wrote about most', 'Work, in the evenings.'),
        LetterSection('What shifted', 'Later in the period, walks.'),
      ],
      toTest: <LetterTest>[
        LetterTest('Walks home', 'Your notes mention the walk home.'),
      ],
      withheld: 1,
    );
  }
}

void main() {
  late Directory support;
  late FakeJournal journal;
  late FakeWriter writer;
  late ProviderContainer container;

  setUp(() async {
    support = await Directory.systemTemp.createTemp('letter-page-test');
    journal = FakeJournal();
    writer = FakeWriter();
    final SealedFiles files = DeviceFiles(
      caches: () async => support,
      support: () async => support,
    ).keptForUser(ownerID, FakeFileSealer());
    container = ProviderContainer(
      overrides: [
        userProvider.overrideWith((ref) => Stream.value(FakeUser(ownerID))),
        todayProvider.overrideWith(() => FixedToday(today)),
        viceListProvider.overrideWithValue(
          AsyncData<List<Vice>>(<Vice>[
            fakeVice('v1', name: 'Wine', unit: Unit.drink),
          ]),
        ),
        letterJournalProvider.overrideWithValue(journal),
        letterWriterProvider.overrideWithValue(writer),
        keptSealedFilesProvider.overrideWithValue(files),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    if (await support.exists()) await support.delete(recursive: true);
  });

  Future<void> open(WidgetTester tester) async {
    await tester.runAsync(() async {
      container.listen(userProvider, (_, _) {});
      container.listen(letterRunProvider, (_, _) {});
      await container.read(lettersProvider.future);
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: appTheme(Brightness.light),
          home: const LetterPage(),
          onGenerateRoute: (RouteSettings settings) => MaterialPageRoute<void>(
            builder: (_) => Text('route ${settings.name}'),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> toPreview(WidgetTester tester) async {
    await tester.tap(find.text(LetterPage.write));
    await tester.pump();
    expect(find.text(LetterPage.months(3)), findsOneWidget);
    await tester.tap(find.text(LetterPage.next));
    await tester.pump();
    await tester.pump();
  }

  Future<void> scrollTo(WidgetTester tester, Finder finder) =>
      tester.scrollUntilVisible(
        finder,
        200,
        scrollable: find.byType(Scrollable).first,
      );

  testWidgets('the preview shows every note to be sent; Cancel sends none', (
    WidgetTester tester,
  ) async {
    await open(tester);
    expect(find.text(LetterPage.none), findsOneWidget);
    await toPreview(tester);
    expect(journal.reads.single.$1, DateTime(2026, 8, 17));
    expect(find.text(LetterPage.previewTitle), findsOneWidget);
    expect(find.text(LetterPage.disclosure), findsOneWidget);
    expect(find.textContaining('2 entries, 2 notes, 1 day note'), findsOne);
    for (final String text in <String>[
      'needed it after the meeting',
      'What made it hard?',
      'it ran late again',
      'walk home with Sam',
      'A quiet Sunday.',
    ]) {
      await scrollTo(tester, find.text(text));
      expect(find.text(text), findsOneWidget);
    }
    await scrollTo(tester, find.text(LetterPage.cancel));
    await tester.tap(find.text(LetterPage.cancel));
    await tester.pump();
    expect(writer.sent, isEmpty);
    await tester.scrollUntilVisible(
      find.text(LetterPage.write),
      -200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text(LetterPage.write), findsOneWidget);
  });

  testWidgets('Send writes the letter, keeps it sealed and lists it', (
    WidgetTester tester,
  ) async {
    await open(tester);
    await toPreview(tester);
    await scrollTo(tester, find.text(LetterPage.send));
    await tester.runAsync(() async {
      await tester.tap(find.text(LetterPage.send));
      for (int i = 0; i < 50; i++) {
        if (container.read(letterRunProvider) is LetterWritten) break;
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    await tester.pump();
    expect(writer.sent, hasLength(1));
    expect(
      jsonEncode(writer.sent.single.json),
      contains('needed it after the meeting'),
    );
    expect(find.text('What you wrote about most'), findsOneWidget);
    expect(find.text(LetterPage.worthTesting), findsOneWidget);
    expect(find.text(LetterPage.withheld(1)), findsOneWidget);

    final List<File> onDisk = support
        .listSync(recursive: true)
        .whereType<File>()
        .toList();
    expect(onDisk, hasLength(1));
    expect(onDisk.single.path, endsWith('/${LetterFile.name}'));
    final String raw = latin1.decode(onDisk.single.readAsBytesSync());
    expect(raw, isNot(contains('What shifted')));

    await tester.runAsync(() async {
      container.invalidate(lettersProvider);
      await container.read(lettersProvider.future);
    });
    expect(container.read(lettersProvider).value, hasLength(1));
    expect(
      container.read(lettersProvider).value!.single.sections.first.heading,
      'What you wrote about most',
    );

    final SavedLetter saved = container.read(lettersProvider).value!.single;
    await scrollTo(tester, find.text(LetterPage.back));
    await tester.tap(find.text(LetterPage.back));
    await tester.pump();
    expect(find.text(LetterPage.write), findsOneWidget);

    await tester.tap(find.text(letterPeriodLabel(saved.from, saved.to)));
    await tester.pump();
    await scrollTo(tester, find.text(LetterPage.delete));
    await tester.tap(find.text(LetterPage.delete));
    await tester.pumpAndSettle();
    await tester.tap(find.text(LetterPage.delete).last);
    for (int i = 0; i < 10; i++) {
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
    }
    await tester.pump();
    expect(container.read(lettersProvider).value, isEmpty);
    expect(find.text(LetterPage.none), findsOneWidget);
  });

  testWidgets('the setting says what is sent before it turns on', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final FakeUser user = FakeUser(ownerID, emailVerified: true);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          userProvider.overrideWith((ref) => Stream.value(user)),
          userProfileProvider.overrideWith((ref) => Stream.value(user)),
          accountProvider.overrideWithValue(FakeAccount()),
        ],
        child: MaterialApp(
          theme: appTheme(Brightness.light),
          home: const Scaffold(body: LetterSetting()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(find.text(LetterSetting.disclosure), findsOneWidget);
    expect(find.textContaining('within 30 days'), findsOneWidget);
    await tester.tap(find.text(LetterSetting.turnOn));
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
  });
}
