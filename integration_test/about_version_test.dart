import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:tracker/homepage.dart';
import 'package:tracker/main.dart' as app;

import 'support.dart';

void main() {
  ensureE2EBinding();

  setUpAll(() async {
    requireEmulators();
    await clearEmulators();
  });

  testWidgets('Settings shows the version the binary was built with', (
    WidgetTester tester,
  ) async {
    app.startApp();
    // MyApp is built only once Bootstrap has started Firebase.
    await pumpUntil(tester, find.byType(app.MyApp));
    await register(tester, 'about@example.com');

    await openFromMenu(tester, Homepage.settingsItem);
    final PackageInfo info = await PackageInfo.fromPlatform();
    expect(info.version, matches(RegExp(r'^\d+\.\d+\.\d+$')));
    await pumpUntil(
      tester,
      find.text('${info.version} (${info.buildNumber})'),
    );
  });
}
