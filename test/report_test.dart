import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:tracker/account/account.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/design/app_theme.dart';
import 'package:tracker/providers/account_provider.dart';
import 'package:tracker/providers/today_provider.dart';
import 'package:tracker/providers/vice_list_provider.dart';
import 'package:tracker/report/report_data.dart';
import 'package:tracker/report/report_output.dart';
import 'package:tracker/report/report_page.dart';
import 'package:tracker/report/report_pdf.dart';

import 'fake_account.dart';
import 'insights_harness.dart' show FixedToday;
import 'report_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ReportData report(ReportOptions options) =>
      buildReport(sampleJournal(), options, now: reportNow);

  group('buildReport', () {
    test('three months are three whole calendar months to today', () {
      final ReportData data = report(
        const ReportOptions(viceIDs: <String>{'wine'}),
      );
      expect(data.window.start, DateTime(2026, 9));
      expect(data.window.end, DateTime(2026, 11, 17));
      expect(data.dayCount, 77);
      expect(data.habits.single.days, hasLength(77));
    });

    test('days, weeks and the period agree', () {
      for (final int months in ReportOptions.monthChoices) {
        final HabitReport wine = report(
          ReportOptions(viceIDs: const <String>{'wine'}, months: months),
        ).habits.single;
        final double weeks = wine.weeks.fold<double>(
          0,
          (double a, ReportWeek w) => a + w.total,
        );
        expect(weeks, closeTo(wine.total, 1e-9));
        expect(
          wine.weeks.fold<int>(0, (int a, ReportWeek w) => a + w.days),
          wine.days.length,
        );
        expect(wine.weeks.first.start, DateTime(2026, 12 - months));
      }
    });

    test('weeks start on the given weekday, short at the ends', () {
      final List<ReportWeek> weeks = report(
        const ReportOptions(
          viceIDs: <String>{'wine'},
          firstWeekday: DateTime.sunday,
        ),
      ).habits.single.weeks;
      // 1 September 2026 is a Tuesday; 16 November a Monday.
      expect(weeks.first.days, 5);
      expect(weeks[1].start.weekday, DateTime.sunday);
      expect(weeks.last.days, 2);
    });

    test('units are the strength of each entry, week by week', () {
      final HabitReport wine = report(
        const ReportOptions(viceIDs: <String>{'wine'}),
      ).habits.single;
      // 175 ml at 13% is 2.275 UK units a glass.
      expect(wine.unitsTotal, closeTo(wine.total * 2.275, 1e-9));
      expect(wine.unitsWithout, 0);
    });

    test('notes, day notes and own-words tags only when ticked', () {
      final ReportData off = report(
        const ReportOptions(viceIDs: <String>{'wine'}, months: 12),
      );
      expect(off.notesIncluded, isFalse);
      expect(off.dayNotes, isEmpty);
      expect(off.habits.single.notes, isEmpty);
      expect(
        off.habits.single.tags.map((ReportTag t) => t.label),
        isNot(contains('cheese night')),
      );

      final ReportData on = report(
        const ReportOptions(
          viceIDs: <String>{'wine'},
          months: 12,
          includeNotes: true,
        ),
      );
      expect(on.dayNotes.single.text, 'Long week, slept badly.');
      expect(on.habits.single.notes, isNotEmpty);
      expect(
        on.habits.single.tags.map((ReportTag t) => t.label),
        contains('cheese night'),
      );
    });

    test('entries and habits that would not open are only counted', () {
      final ReportData data = report(
        const ReportOptions(viceIDs: <String>{'wine'}),
      );
      expect(data.lockedEntries, 1);
      final AccountData journal = sampleJournal();
      final ReportData lockedHabit = buildReport(
        AccountData(
          vices: <StoredDocument>[
            ...journal.vices,
            (
              id: 'sealed',
              data: <String, dynamic>{
                'ownerID': 'owner',
                'archived': false,
                'sealed': 'x',
              },
            ),
          ],
          activities: journal.activities,
        ),
        const ReportOptions(viceIDs: <String>{'wine', 'sealed'}),
        now: reportNow,
      );
      expect(lockedHabit.lockedHabits, 1);
      expect(lockedHabit.habits.map((HabitReport h) => h.name), <String>[
        'Wine',
      ]);
    });

    test('the hour profile says when it covers less than the period', () {
      expect(
        report(
          const ReportOptions(viceIDs: <String>{'wine'}, months: 12),
        ).habits.single.hourDays,
        90,
      );
    });
  });

  group('dayScores', () {
    test('standard deviations among days with use; none is null', () {
      final List<double?> scores = dayScores(<double>[0, 1, 2, 3, 4, 5, 0]);
      expect(scores.first, isNull);
      expect(scores.last, isNull);
      // Mean 3, sample SD sqrt(2.5).
      expect(scores[3], 0);
      expect(scores[5]!, closeTo(2 / sqrt(2.5), 1e-9));
      expect(scores[1]!, closeTo(-2 / sqrt(2.5), 1e-9));
    });

    test('too few days with use, or all alike, are all usual', () {
      expect(dayScores(<double>[0, 1, 5, 9, 0]), <double?>[
        null,
        0,
        0,
        0,
        null,
      ]);
      expect(
        dayScores(List<double>.filled(10, 2)),
        List<double?>.filled(10, 0),
      );
    });
  });

  group('the PDF', () {
    Future<int> pages(ReportOptions options, PdfPageFormat format) async {
      final pw.Document doc = reportDocument(
        report(options),
        await loadReportFonts(),
        format: format,
      );
      await doc.save();
      return doc.document.pdfPageList.pages.length;
    }

    test('one habit over three months is one page, A4 or Letter', () async {
      for (final PdfPageFormat format in <PdfPageFormat>[
        PdfPageFormat.a4,
        PdfPageFormat.letter,
      ]) {
        expect(
          await pages(const ReportOptions(viceIDs: <String>{'wine'}), format),
          1,
        );
      }
    });

    test('each habit starts a page; a year flows on', () async {
      expect(
        await pages(
          const ReportOptions(viceIDs: <String>{'wine', 'coffee'}),
          PdfPageFormat.a4,
        ),
        2,
      );
      expect(
        await pages(
          const ReportOptions(viceIDs: <String>{'wine'}, months: 12),
          PdfPageFormat.letter,
        ),
        greaterThan(1),
      );
    });

    test('paper follows the region', () {
      expect(reportPaper(const Locale('en', 'US')), PdfPageFormat.letter);
      expect(reportPaper(const Locale('en', 'GB')), PdfPageFormat.a4);
      expect(reportPaper(const Locale('de')), PdfPageFormat.a4);
    });
  });

  testWidgets('choose, make, preview, share; the file goes on leaving', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final FakeAccount account = FakeAccount()..data = sampleJournal();
    final FakeReportOutput output = FakeReportOutput();
    final List<Vice> vices = <Vice>[
      for (final StoredDocument doc in account.data.vices)
        Vice.fromJson(id: doc.id, json: doc.data),
    ];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountProvider.overrideWithValue(account),
          viceListProvider.overrideWithValue(AsyncValue.data(vices)),
          reportOutputProvider.overrideWithValue(output),
          todayProvider.overrideWith(() => FixedToday(reportNow)),
        ],
        child: MaterialApp(
          theme: appTheme(Brightness.light),
          home: const Scaffold(body: SizedBox()),
          routes: <String, WidgetBuilder>{
            '/report': (_) => const ReportOptionsPage(),
          },
        ),
      ),
    );
    tester.state<NavigatorState>(find.byType(Navigator)).pushNamed('/report');
    await tester.pumpAndSettle();

    final Finder make = find.widgetWithText(
      FilledButton,
      ReportOptionsPage.make,
    );
    expect(tester.widget<FilledButton>(make).onPressed, isNull);
    expect(
      tester.widget<Switch>(find.byType(Switch)).value,
      isFalse,
      reason: 'notes are off by default',
    );

    await tester.tap(find.text('Wine'));
    await tester.pump();
    await tester.ensureVisible(make);
    await tester.runAsync(() async {
      await tester.tap(make);
      for (
        int i = 0;
        i < 50 && find.byType(ReportPreviewPage).evaluate().isEmpty;
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump();
      }
    });
    await tester.pumpAndSettle();

    expect(account.ops, contains('fetchData'));
    expect(find.text(ReportPreviewPage.warning), findsOneWidget);
    expect(output.rastered!.sublist(0, 5), '%PDF-'.codeUnits);

    await tester.tap(find.text(ReportPreviewPage.share));
    await tester.pumpAndSettle();
    // The page stamps the file with the clock, not the overridden today.
    expect(output.shared, reportFileName(DateTime.now()));
    expect(output.discarded, 0);

    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    // The page that made the report resumes outside the fake clock.
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    expect(output.discarded, 1);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
