// Writes sample reports as PDFs and, through poppler's pdftoppm, as PNGs of
// each page, then the options and preview screens at 390x844 in light and
// dark, for a look at the real layout. Skipped unless a directory is given:
//   flutter test test/report_render_test.dart --dart-define=RENDER_DIR=<dir>
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:tracker/account/account.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/design/app_theme.dart';
import 'package:tracker/design/tokens.dart';
import 'package:tracker/providers/account_provider.dart';
import 'package:tracker/providers/today_provider.dart';
import 'package:tracker/providers/vice_list_provider.dart';
import 'package:tracker/report/report_page.dart';
import 'package:tracker/report/report_data.dart';
import 'package:tracker/report/report_output.dart';
import 'package:tracker/report/report_pdf.dart';

import 'fake_account.dart';
import 'insights_harness.dart' show FixedToday;
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

  for (final Brightness brightness in Brightness.values) {
    for (final String screen in <String>['options', 'preview']) {
      testWidgets('$screen screen, ${brightness.name}', (
        WidgetTester tester,
      ) async {
        await tester.runAsync(_loadFonts);
        tester.view.physicalSize = const Size(390 * 3, 844 * 3);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        final AccountData journal = sampleJournal();
        final List<ui.Image> pages = <ui.Image>[];
        if (screen == 'preview') {
          await tester.runAsync(() async {
            final ui.Codec codec = await ui.instantiateImageCodec(
              await File('$_dir/one-habit-3-months-a4-1.png').readAsBytes(),
            );
            pages.add((await codec.getNextFrame()).image);
          });
        }
        final GlobalKey frame = GlobalKey();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              accountProvider.overrideWithValue(FakeAccount()..data = journal),
              viceListProvider.overrideWithValue(
                AsyncValue.data(<Vice>[
                  for (final StoredDocument doc in journal.vices)
                    Vice.fromJson(id: doc.id, json: doc.data),
                ]),
              ),
              reportOutputProvider.overrideWithValue(FakeReportOutput(pages)),
              todayProvider.overrideWith(() => FixedToday(reportNow)),
            ],
            child: RepaintBoundary(
              key: frame,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: appTheme(brightness),
                home: screen == 'options'
                    ? const ReportOptionsPage(
                        initialOptions: ReportOptions(
                          viceIDs: <String>{'wine'},
                        ),
                      )
                    : ReportPreviewPage(
                        pdf: Uint8List(0),
                        name: 'penchant-report.pdf',
                      ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          final ui.Image image =
              await (frame.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage(pixelRatio: 3);
          final ByteData? png = await image.toByteData(
            format: ui.ImageByteFormat.png,
          );
          await File(
            '$_dir/screen-$screen-${brightness.name}.png',
          ).writeAsBytes(png!.buffer.asUint8List());
        });
      }, skip: _dir.isEmpty);
    }
  }
}

Future<void> _loadFonts() async {
  for (final (String family, String file) in <(String, String)>[
    (DialFonts.display, 'RedHatDisplay'),
    (DialFonts.text, 'RedHatText'),
    (DialFonts.mono, 'RedHatMono'),
  ]) {
    await (FontLoader(
      family,
    )..addFont(rootBundle.load('assets/fonts/$file-Variable.ttf'))).load();
  }
}
