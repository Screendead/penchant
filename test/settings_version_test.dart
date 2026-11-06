import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:tracker/providers/package_info_provider.dart';
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/settings.dart';

void main() {
  testWidgets('About shows the app version and build number', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          userProvider.overrideWith((ref) => Stream.value(null)),
          packageInfoProvider.overrideWith(
            (ref) async => PackageInfo(
              appName: 'tracker',
              packageName: 'tracker',
              version: '0.1.0',
              buildNumber: '212',
            ),
          ),
        ],
        child: const MaterialApp(home: Settings()),
      ),
    );
    await tester.pump();

    expect(find.text('0.1.0 (212)'), findsOneWidget);

    await tester.tap(find.text('About'));
    await tester.pumpAndSettle();
    expect(find.byType(AboutDialog), findsOneWidget);
    expect(find.text('Version 0.1.0 (212)'), findsOneWidget);
  });
}
