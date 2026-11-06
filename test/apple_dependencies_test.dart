import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/firebase_init.dart';

// The Swift packages Xcode resolves, one per workspace. `flutter build` builds
// Runner.xcworkspace; Flutter's package prefetch writes the project's own.
const List<String> _resolvedFiles = <String>[
  'ios/Runner.xcworkspace/xcshareddata/swiftpm/Package.resolved',
  'ios/Runner.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved',
  'macos/Runner.xcworkspace/xcshareddata/swiftpm/Package.resolved',
  'macos/Runner.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved',
];

// 12.19.3 carries the eMudhra CA fix (HANDOVER.md, #56).
const List<int> _firebaseFloor = <int>[12, 19, 3];

List<int> _firebaseVersion(String path) {
  final Map<String, dynamic> resolved =
      jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
  final Map<String, dynamic> pin = (resolved['pins'] as List<dynamic>)
      .cast<Map<String, dynamic>>()
      .firstWhere(
        (Map<String, dynamic> pin) => pin['identity'] == 'firebase-ios-sdk',
      );
  final String version =
      (pin['state'] as Map<String, dynamic>)['version'] as String;
  return version.split('.').map(int.parse).toList();
}

bool _atLeast(List<int> version, List<int> floor) {
  for (int i = 0; i < floor.length; i++) {
    if (version[i] != floor[i]) return version[i] > floor[i];
  }
  return true;
}

// FIRInstallations' validateAPIKey: in firebase-ios-sdk, which firebase_core's
// Swift package links, an API key of another shape aborts the app at
// FirebaseApp.configure.
bool _installationsAcceptsKey(String key) =>
    RegExp(r'^A[A-Za-z0-9_-]{38}$').hasMatch(key);

void main() {
  test('every resolved Firebase Apple SDK is at least 12.19.3', () {
    for (final String path in _resolvedFiles) {
      expect(
        _atLeast(_firebaseVersion(path), _firebaseFloor),
        isTrue,
        reason: '$path pins firebase-ios-sdk ${_firebaseVersion(path)}',
      );
    }
  });

  test("each platform's two Package.resolved files match", () {
    for (final String platform in <String>['ios', 'macos']) {
      final List<String> pair = _resolvedFiles
          .where((String path) => path.startsWith('$platform/'))
          .toList();
      expect(
        File(pair[1]).readAsStringSync(),
        File(pair[0]).readAsStringSync(),
        reason: '${pair[1]} differs from ${pair[0]}',
      );
    }
  });

  test('neither platform has a Podfile', () {
    for (final String platform in <String>['ios', 'macos']) {
      expect(
        File('$platform/Podfile').existsSync(),
        isFalse,
        reason:
            'Flutter writes a Podfile when a plugin has no Package.swift; '
            'name that plugin in CLAUDE.md before changing this test',
      );
    }
  });

  test('the emulator API key passes FirebaseInstallations validation', () {
    expect(_installationsAcceptsKey(emulatorOptions.apiKey), isTrue);
    expect(_installationsAcceptsKey('demo-api-key'), isFalse);
  });
}
