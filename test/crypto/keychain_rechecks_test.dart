import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/crypto/key_wiring.dart';

void main() {
  testWidgets('ticks every interval until cancelled', (
    WidgetTester tester,
  ) async {
    int ticks = 0;
    final StreamSubscription<void> sub = keychainRechecks(
      every: const Duration(seconds: 5),
    ).listen((_) => ticks++);

    await tester.pump(const Duration(seconds: 4));
    expect(ticks, 0);
    await tester.pump(const Duration(seconds: 1));
    expect(ticks, 1);

    unawaited(sub.cancel());
    await tester.pump(const Duration(seconds: 20));
    expect(ticks, 1);
  });

  testWidgets('ticks on resume until cancelled', (WidgetTester tester) async {
    int ticks = 0;
    final StreamSubscription<void> sub = keychainRechecks().listen(
      (_) => ticks++,
    );

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(ticks, 1);

    unawaited(sub.cancel());
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(ticks, 1);
  });
}
