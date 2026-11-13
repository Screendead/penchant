import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

const String _team = '8N575942RT';

const String _iconSet = 'ios/Runner/Assets.xcassets/AppIcon.appiconset';

Map<String, dynamic> _json(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

// The buildSettings of every target-level configuration: project-level ones
// set none of these keys.
List<String> _targetBuildSettings(String pbxproj) {
  final String source = File(pbxproj).readAsStringSync();
  return RegExp(
        r'isa = XCBuildConfiguration;.*?buildSettings = \{(.*?)\n\t\t\t\};',
        dotAll: true,
      )
      .allMatches(source)
      .map((RegExpMatch m) => m.group(1)!)
      .where(
        (String s) =>
            s.contains('PRODUCT_NAME') ||
            s.contains('PRODUCT_BUNDLE_IDENTIFIER') ||
            s.contains('INFOPLIST_FILE'),
      )
      .toList();
}

// App Store Connect rejects an app icon that has an alpha channel, and the
// plain copy no longer strips one the way flutter_launcher_icons'
// remove_alpha_ios did. Returns the width, height and whether the PNG can
// carry transparency (colour type 4 or 6, or a tRNS chunk).
({int width, int height, bool alpha}) _png(String path) {
  final ByteData b = File(path).readAsBytesSync().buffer.asByteData();
  var alpha = <int>{4, 6}.contains(b.getUint8(25));
  for (var at = 8; at + 8 <= b.lengthInBytes;) {
    final int length = b.getUint32(at);
    if (b.getUint32(at + 4) == 0x74524E53) alpha = true; // tRNS
    at += 12 + length;
  }
  return (width: b.getUint32(16), height: b.getUint32(20), alpha: alpha);
}

String _hex(Map<String, dynamic> colour) {
  final Map<String, dynamic> c =
      (colour['color'] as Map<String, dynamic>)['components']
          as Map<String, dynamic>;
  return '#${<String>['red', 'green', 'blue'].map((String k) => (c[k] as String).substring(2)).join()}';
}

void main() {
  test('the iOS icon is one 1024 pt image, a copy of assets/icon.png', () {
    final List<dynamic> images = _json('$_iconSet/Contents.json')['images'];
    expect(images, hasLength(1));
    final Map<String, dynamic> image = images.single as Map<String, dynamic>;
    expect(image['size'], '1024x1024');
    expect(image['idiom'], 'universal');
    expect(image['platform'], 'ios');
    // Hidden files (Finder's .DS_Store) are git-ignored and never built.
    expect(
      Directory(_iconSet)
          .listSync()
          .map((FileSystemEntity f) => f.uri.pathSegments.last)
          .where((String name) => !name.startsWith('.'))
          .toSet(),
      <String>{'Contents.json', image['filename'] as String},
    );
    expect(
      File('$_iconSet/${image['filename']}').readAsBytesSync(),
      File('assets/icon.png').readAsBytesSync(),
    );
    expect(_png('assets/icon.png'), (width: 1024, height: 1024, alpha: false));
  });

  test('the iOS launch screen is the theme background, light and dark', () {
    final Map<String, dynamic> tokens =
        _json('lib/design/tokens.json')['color'] as Map<String, dynamic>;
    final List<dynamic> colours = _json(
      'ios/Runner/Assets.xcassets/LaunchBackground.colorset/Contents.json',
    )['colors'];
    final Map<String, dynamic> light = colours
        .cast<Map<String, dynamic>>()
        .singleWhere((Map<String, dynamic> c) => c['appearances'] == null);
    final Map<String, dynamic> dark = colours
        .cast<Map<String, dynamic>>()
        .singleWhere(
          (Map<String, dynamic> c) =>
              (c['appearances'] as List<dynamic>?)?.any(
                (dynamic a) => (a as Map<String, dynamic>)['value'] == 'dark',
              ) ??
              false,
        );
    expect(_hex(light), (tokens['light'] as Map<String, dynamic>)['bg']);
    expect(_hex(dark), (tokens['dark'] as Map<String, dynamic>)['bg']);
    expect(
      File('ios/Runner/Base.lproj/LaunchScreen.storyboard').readAsStringSync(),
      contains('<color key="backgroundColor" name="LaunchBackground"/>'),
    );
  });

  for (final String platform in <String>['ios', 'macos']) {
    test('every $platform target signs automatically for team $_team', () {
      final String pbxproj = '$platform/Runner.xcodeproj/project.pbxproj';
      final List<String> configs = _targetBuildSettings(pbxproj);
      // Runner and PenchantWidgets (and macOS's RunnerTests, Flutter
      // Assemble and PenchantMenuBar), three configurations each.
      expect(configs, hasLength(platform == 'ios' ? 6 : 15));
      for (final String settings in configs) {
        expect(settings, contains('CODE_SIGN_STYLE = Automatic;'));
        expect(settings, contains('DEVELOPMENT_TEAM = $_team;'));
        // Runner and RunnerTests, not Flutter Assemble, which builds no
        // bundle. The macOS project-level default is "-", ad hoc, no team.
        if (platform == 'macos' && settings.contains('INFOPLIST_FILE')) {
          expect(
            settings,
            contains('CODE_SIGN_IDENTITY = "Apple Development";'),
          );
        }
      }
      expect(File(pbxproj).readAsStringSync(), isNot(contains('Manual')));
    });

    // Crashlytics processes dSYMs only from the target's last build phase.
    test('the $platform Runner uploads Crashlytics symbols last', () {
      final String source = File(
        '$platform/Runner.xcodeproj/project.pbxproj',
      ).readAsStringSync();
      final String runner = RegExp(
        r'/\* Runner \*/ = \{\s*isa = PBXNativeTarget;.*?buildPhases = \((.*?)\);',
        dotAll: true,
      ).firstMatch(source)!.group(1)!;
      expect(
        runner.trim().split('\n').last.trim(),
        endsWith('/* Upload Crashlytics symbols */,'),
      );
      expect(source, contains('tools/crashlytics-upload-symbols.sh'));
    });
  }

  // The Mac's tag picker suggests Meeting after a calendar event; nothing
  // else on the Mac reads the calendar.
  test('the macOS Runner alone may read Calendar', () {
    const String calendars =
        'com.apple.security.personal-information.calendars';
    for (final String config in <String>['DebugProfile', 'Release']) {
      expect(
        File('macos/Runner/$config.entitlements').readAsStringSync(),
        contains('<key>$calendars</key>'),
      );
    }
    for (final FileSystemEntity f in Directory(
      'macos',
    ).listSync(recursive: true)) {
      if (f.path.endsWith('.entitlements') &&
          !f.path.startsWith('macos/Runner/')) {
        expect(File(f.path).readAsStringSync(), isNot(contains(calendars)));
      }
    }
    final String plist = File('macos/Runner/Info.plist').readAsStringSync();
    expect(plist, contains('<key>NSCalendarsFullAccessUsageDescription</key>'));
    expect(plist, contains('<key>NSCalendarsUsageDescription</key>'));
    final String source = File(
      'macos/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();
    final String runnerSources = RegExp(
      r'33CC10E92044A3C60003C045 /\* Sources \*/ = \{(.*?)\};',
      dotAll: true,
    ).firstMatch(source)!.group(1)!;
    expect(runnerSources, contains('CalendarChannel.swift in Sources'));
  });
}
