import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/ask/ask_answer.dart';
import 'package:tracker/ask/ask_chart.dart';
import 'package:tracker/ask/ask_journal.dart';
import 'package:tracker/ask/ask_page.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/firebase_init.dart';
import 'package:tracker/homepage.dart';

import 'support.dart';

// Answers every question with the same cards, as the server would: real SQL
// over the device's tables, one of them a statement the sandbox refuses.
class _FakeAsk implements AskJournal {
  @override
  Future<AskAnswer> ask(
    String question, {
    required List<({int id, Vice vice})> habits,
    required DateTime today,
    List<AskTurn> history = const <AskTurn>[],
  }) async => const AskAnswer(
    kind: AskKind.answer,
    cards: <AskCard>[
      AskCard(
        title: 'Entries',
        explain: 'Every entry of every habit, counted.',
        sql: 'SELECT count(*) AS entries FROM entries',
        chart: AskChartSpec(type: AskChartType.number, y: <String>['entries']),
      ),
      AskCard(
        title: 'By habit',
        explain: 'Entries of each habit.',
        sql:
            'SELECT h.name AS habit, count(*) AS logged FROM entries e '
            'JOIN habits h ON h.id = e.habit_id GROUP BY h.id ORDER BY h.id',
        chart: AskChartSpec(
          type: AskChartType.bar,
          x: 'habit',
          y: <String>['logged'],
          xKind: AskXKind.category,
        ),
      ),
      AskCard(
        title: 'Forbidden',
        explain: 'A statement the sandbox must refuse.',
        sql: 'DROP TABLE entries',
        chart: AskChartSpec(type: AskChartType.table),
      ),
    ],
  );
}

void main() {
  ensureE2EBinding();

  setUpAll(() async {
    requireEmulators();
    await initializeFirebase();
    await clearEmulators();
  });

  testWidgets('a question is answered by SQL run on the device over the '
      'journal, with a chart read-out and a refused statement', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      e2eApp(
        overrides: <Override>[askJournalProvider.overrideWithValue(_FakeAsk())],
      ),
    );
    await register(tester, 'e2e-ask@example.com');
    await addVicesThroughManageData(tester, const <String>['Coffee', 'Tea']);
    await logOne(tester, 'Coffee');
    await logOne(tester, 'Coffee');
    await logOne(tester, 'Tea');

    Navigator.of(
      tester.element(find.byType(Homepage)),
    ).pushNamed(AskPage.route);
    await pumpUntilRouteSettled(tester, find.byType(AskPage));
    await tester.enterText(find.byType(TextField), 'How many entries?');
    await tap(tester, find.widgetWithText(FilledButton, AskPage.ask));

    // 3 entries, from the SQL over what this device read and sealed.
    await pumpUntil(tester, find.text('3'));
    await pumpUntil(tester, find.byType(BarChart));
    expect(find.text(AskPage.couldNotRun), findsOneWidget);
    expect(find.text(AskPage.onDevice.toUpperCase()), findsNWidgets(3));

    // The read-out starts on the last bar; a tap on the first moves it.
    final String logged = humaniseColumn('logged');
    expect(find.text('$logged 1'), findsOneWidget);
    // The question field still holds focus; with the keyboard gone the page
    // holds still under the touch.
    FocusManager.instance.primaryFocus?.unfocus();
    await pumpFor(tester, const Duration(seconds: 1));
    await scrollIntoView(tester, find.byType(BarChart));
    final Rect chart = tester.getRect(find.byType(BarChart));
    await tester.timedDragFrom(
      Offset(chart.left + chart.width * 0.5, chart.center.dy),
      Offset(-chart.width * 0.4, 0),
      const Duration(milliseconds: 400),
    );
    await pumpUntil(tester, find.text('$logged 2'));
    expect(find.text('Coffee'), findsWidgets);

    // The refused card still offers its query.
    await scrollIntoView(tester, find.text(AskPage.couldNotRun));
    await tap(tester, find.text(AskPage.showQuery).last);
    await pumpUntil(tester, find.text('DROP TABLE entries'));
  });
}
