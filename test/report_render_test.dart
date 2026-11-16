// Writes sample reports as PDFs and, through poppler's pdftoppm, as PNGs of
// each page, for a look at the real layout. Skipped unless a directory is
// given:
//   flutter test test/report_render_test.dart --dart-define=RENDER_DIR=<dir>
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:tracker/report/report_data.dart';
import 'package:tracker/report/report_pdf.dart';

import 'report_fakes.dart';

const String _dir = String.fromEnvironment('RENDER_DIR');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> render(
    String name,
    ReportOptions options,
    PdfPageFormat format,
  ) async {
    final ReportData data = buildReport(
      sampleJournal(),
      options,
      now: reportNow,
    );
    final File pdf = File('$_dir/$name.pdf');
    await pdf.writeAsBytes(
      await reportPdf(data, await loadReportFonts(), format: format),
    );
    final ProcessResult result = await Process.run('pdftoppm', <String>[
      '-r',
      '110',
      '-png',
      pdf.path,
      '$_dir/$name',
    ]);
    expect(result.exitCode, 0, reason: '${result.stderr}');
  }

  test('report pages', () async {
    await Directory(_dir).create(recursive: true);
    await render(
      'one-habit-3-months-a4',
      const ReportOptions(viceIDs: <String>{'wine'}),
      PdfPageFormat.a4,
    );
    await render(
      'one-habit-3-months-letter',
      const ReportOptions(viceIDs: <String>{'wine'}),
      PdfPageFormat.letter,
    );
    await render(
      'two-habits-12-months-notes-a4',
      const ReportOptions(
        viceIDs: <String>{'wine', 'coffee'},
        months: 12,
        includeNotes: true,
      ),
      PdfPageFormat.a4,
    );
  }, skip: _dir.isEmpty);
}
