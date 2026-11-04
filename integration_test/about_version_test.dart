import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:tracker/main.dart' as app;

import 'support.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  WidgetController.hitTestWarningShouldBeFatal = true;

  setUpAll(() async {
    requireEmulators();
    await clearEmulators();
  });

  testWidgets('Settings shows the version the binary was built with', (
    WidgetTester tester,
  ) async {
    app.startApp();
    await register(tester, 'about@example.com');

    await openFromDrawer(tester, 'Settings');
    final PackageInfo info = await PackageInfo.fromPlatform();
    expect(info.version, matches(RegExp(r'^\d+\.\d+\.\d+$')));
    await pumpUntil(
      tester,
      find.text('Version ${info.version} (${info.buildNumber})'),
    );
  });
}
