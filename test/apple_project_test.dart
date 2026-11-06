import 'dart:convert';
import 'dart:io';

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
    expect(
      Directory(
        _iconSet,
      ).listSync().map((FileSystemEntity f) => f.uri.pathSegments.last).toSet(),
      <String>{'Contents.json', image['filename'] as String},
    );
    expect(
      File('$_iconSet/${image['filename']}').readAsBytesSync(),
      File('assets/icon.png').readAsBytesSync(),
    );
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
      // Runner and RunnerTests (and macOS's Flutter Assemble), three
      // configurations each.
      expect(configs, hasLength(platform == 'ios' ? 6 : 9));
      for (final String settings in configs) {
        expect(settings, contains('CODE_SIGN_STYLE = Automatic;'));
        expect(settings, contains('DEVELOPMENT_TEAM = $_team;'));
      }
      expect(File(pbxproj).readAsStringSync(), isNot(contains('Manual')));
    });
  }
}
