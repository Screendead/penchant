import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:tracker/report/report_pdf.dart';

Future<ReportFonts> loadReportFonts() async {
  final List<ByteData> bytes = <ByteData>[
    for (final String asset in ReportFonts.assets) await rootBundle.load(asset),
  ];
  return ReportFonts(
    display: bytes[0],
    text: bytes[1],
    textBold: bytes[2],
    mono: bytes[3],
    monoBold: bytes[4],
  );
}

final reportOutputProvider = Provider<ReportOutput>(
  (ref) => const ReportOutput(),
);

// The finished PDF's way off the device, behind a provider so tests can see
// what would be drawn and shared.
class ReportOutput {
  const ReportOutput();

  // Each page as an image, drawn by the system's own PDF renderer.
  Future<List<ui.Image>> pages(Uint8List pdf) async => <ui.Image>[
    await for (final PdfRaster page in Printing.raster(pdf, dpi: 144))
      await page.toImage(),
  ];

  // The only place the PDF is ever written: its own folder in the app's
  // temporary directory, which [discard] removes.
  Future<File> write(Uint8List pdf, String name) async {
    await discard();
    final Directory dir = await _folder();
    await dir.create(recursive: true);
    final File file = File('${dir.path}/$name');
    await file.writeAsBytes(pdf, flush: true);
    return file;
  }

  // On macOS the share call returns once a service is chosen, before it has
  // read the file, so this waits until the preview is left.
  Future<void> discard() async {
    final Directory dir = await _folder();
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  Future<void> share(File file, {ui.Rect? origin}) async {
    await SharePlus.instance.share(
      ShareParams(
        files: <XFile>[XFile(file.path, mimeType: 'application/pdf')],
        sharePositionOrigin: origin,
      ),
    );
  }

  Future<Directory> _folder() async =>
      Directory('${(await getTemporaryDirectory()).path}/penchant-report');
}
