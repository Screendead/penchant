// Renders the brand-and-icon mock-ups to docs/pitch/mockups/brand-and-icon/.
// flutter test test/mockups/brand_and_icon_test.dart --update-goldens
// current-icon-1024.png there is assets/icon.webp converted to PNG
// (sips -s format png assets/icon.webp --out <it>), since that is what the
// comparison tiles read.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/mockups/brand/brand_icons.dart';
import 'package:tracker/mockups/brand/home_screen.dart';
import 'package:tracker/mockups/brand/store_listing.dart';

const String _outDir = 'docs/pitch/mockups/brand-and-icon';

Future<void> _loadFonts() async {
  final String flutterRoot =
      Platform.environment['FLUTTER_ROOT'] ??
      File(
        Platform.resolvedExecutable,
      ).parent.parent.parent.parent.parent.parent.path;
  final String fonts = '$flutterRoot/bin/cache/artifacts/material_fonts';

  Future<ByteData> read(String name) async =>
      ByteData.sublistView(await File('$fonts/$name').readAsBytes());

  final FontLoader roboto = FontLoader('Roboto');
  for (final String weight in const [
    'Regular',
    'Medium',
    'Bold',
    'Light',
    'Black',
  ]) {
    roboto.addFont(read('Roboto-$weight.ttf'));
  }
  await roboto.load();
  await (FontLoader(
    'MaterialIcons',
  )..addFont(read('MaterialIcons-Regular.otf'))).load();
}

final GlobalKey _capture = GlobalKey();

Future<void> _render(
  WidgetTester tester,
  Widget child,
  String file, {
  Size size = const Size(393, 852),
  double pixelRatio = 3,
  Future<void> Function()? beforeCapture,
}) async {
  tester.view.physicalSize = size * pixelRatio;
  tester.view.devicePixelRatio = pixelRatio;
  addTearDown(tester.view.reset);
  // flutter_test draws shadows as outlines unless this is off, and checks
  // that it is back on before the test ends.
  debugDisableShadows = false;

  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(fontFamily: 'Roboto', useMaterial3: true),
      home: RepaintBoundary(
        key: _capture,
        child: MediaQuery(
          data: MediaQueryData(size: size, devicePixelRatio: pixelRatio),
          child: Material(type: MaterialType.transparency, child: child),
        ),
      ),
    ),
  );
  await beforeCapture?.call();
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(seconds: 1));

  await expectLater(find.byKey(_capture), matchesGoldenFile(file));
  debugDisableShadows = true;
}

void main() {
  late MemoryImage currentIcon;

  setUpAll(() async {
    await _loadFonts();
    goldenFileComparator = LocalFileComparator(
      Uri.file('${Directory.current.path}/$_outDir/golden.dart'),
    );
    currentIcon = MemoryImage(
      File('$_outDir/current-icon-1024.png').readAsBytesSync(),
    );
  });

  Future<void> precacheCurrent(WidgetTester tester) async {
    await tester.runAsync(
      () => precacheImage(currentIcon, tester.element(find.byKey(_capture))),
    );
  }

  for (final IconCandidate candidate in IconCandidate.values) {
    testWidgets('${candidate.id} at 1024 px', (WidgetTester tester) async {
      await _render(
        tester,
        IconArt(candidate, size: 1024),
        '${candidate.id}-1024.png',
        size: const Size(1024, 1024),
        pixelRatio: 1,
      );
    });
  }

  for (final Brand brand in Brand.values) {
    testWidgets('${brand.name} on the home screen', (
      WidgetTester tester,
    ) async {
      await _render(
        tester,
        HomeScreenMock(brand: brand, currentIcon: currentIcon),
        '${brand.name}-home.png',
        beforeCapture: () => precacheCurrent(tester),
      );
    });

    testWidgets('${brand.name} App Store listing', (WidgetTester tester) async {
      await _render(
        tester,
        StoreListingMock(
          name: brand.label,
          icon: IconArt(brand.lead, size: 118),
        ),
        '${brand.name}-store.png',
      );
    });

    testWidgets('${brand.name} first screenshot', (WidgetTester tester) async {
      await _render(
        tester,
        StoreScreenshot(
          width: 393,
          caption: 'Your day,\nat a glance',
          screen: BrandedTodayScreen(title: brand.label),
        ),
        '${brand.name}-screenshot-1.png',
        size: const Size(393, 854),
      );
    });
  }

  testWidgets('every candidate side by side', (WidgetTester tester) async {
    await _render(
      tester,
      IconOverview(currentIcon: currentIcon),
      'overview.png',
      beforeCapture: () => precacheCurrent(tester),
    );
  });

  testWidgets('current icon on an App Store listing', (
    WidgetTester tester,
  ) async {
    await _render(
      tester,
      StoreListingMock(
        name: 'Vice Tracker',
        icon: Image(image: currentIcon, fit: BoxFit.cover),
      ),
      'current-store.png',
      beforeCapture: () => precacheCurrent(tester),
    );
  });
}
