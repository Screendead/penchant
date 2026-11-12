import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tracker/app_lock/app_lock.dart';
import 'package:tracker/app_lock/app_lock_gate.dart';
import 'package:tracker/app_lock/device_auth.dart';
import 'package:tracker/design/app_theme.dart';

import 'fake_device_auth.dart';

const String _journal = 'Coffee, 3 today';

void main() {
  late FakeDeviceAuth auth;
  late DateTime now;

  Future<void> pumpGate(WidgetTester tester, {bool saved = false}) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      if (saved) AppLock.key: true,
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          deviceAuthProvider.overrideWithValue(auth),
          appLockClockProvider.overrideWithValue(() => now),
        ],
        child: MaterialApp(
          theme: appTheme(Brightness.light),
          builder: (BuildContext context, Widget? child) =>
              AppLockGate(child: child!),
          home: const Scaffold(body: Center(child: Text(_journal))),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> leaveAndReturn(WidgetTester tester, Duration away) async {
    for (final AppLifecycleState s in <AppLifecycleState>[
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(s);
    }
    await tester.pump();
    now = now.add(away);
    for (final AppLifecycleState s in <AppLifecycleState>[
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(s);
    }
    await tester.pumpAndSettle();
  }

  setUp(() {
    auth = FakeDeviceAuth();
    now = DateTime(2026, 11, 12, 9);
  });

  testWidgets('off by default: nothing covers the journal', (
    WidgetTester tester,
  ) async {
    await pumpGate(tester);
    expect(find.byType(LockScreen), findsNothing);
    expect(find.semantics.byLabel(_journal), findsOneWidget);
    await leaveAndReturn(tester, const Duration(hours: 1));
    expect(find.byType(LockScreen), findsNothing);
    expect(auth.asked, 0);
  });

  testWidgets('on: locks at launch, asks once, and opens on success', (
    WidgetTester tester,
  ) async {
    auth.outcomes.add(AuthOutcome.success);
    await pumpGate(tester, saved: true);
    expect(auth.asked, 1);
    expect(find.byType(LockScreen), findsNothing);
    expect(find.semantics.byLabel(_journal), findsOneWidget);
  });

  testWidgets('a cancel stays locked, hides the journal, and the button '
      'asks again', (WidgetTester tester) async {
    auth.outcomes.addAll(<AuthOutcome>[
      AuthOutcome.cancelled,
      AuthOutcome.failed,
    ]);
    await pumpGate(tester, saved: true);
    expect(auth.asked, 1);
    expect(find.text(LockScreen.title), findsOneWidget);
    expect(find.semantics.byLabel(_journal), findsNothing);

    final Finder button = find.text(LockScreen.unlockLabel(Biometry.faceID));
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(auth.asked, 2);
    expect(find.text(LockScreen.title), findsOneWidget);

    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(auth.asked, 3);
    expect(find.byType(LockScreen), findsNothing);
  });

  testWidgets('a return within the grace period stays open; after it, locks', (
    WidgetTester tester,
  ) async {
    await pumpGate(tester, saved: true);
    expect(auth.asked, 1);

    await leaveAndReturn(tester, const Duration(seconds: 30));
    expect(find.byType(LockScreen), findsNothing);
    expect(auth.asked, 1);

    auth.outcomes.add(AuthOutcome.cancelled);
    await leaveAndReturn(tester, AppLock.grace);
    expect(auth.asked, 2);
    expect(find.text(LockScreen.title), findsOneWidget);
  });

  testWidgets('covers the journal while inactive, for the app switcher', (
    WidgetTester tester,
  ) async {
    await pumpGate(tester, saved: true);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(find.semantics.byLabel(_journal), findsNothing);
    expect(find.byType(LockScreen), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.semantics.byLabel(_journal), findsOneWidget);
  });

  group('turning it on', () {
    ProviderContainer container() {
      final ProviderContainer c = ProviderContainer(
        overrides: [deviceAuthProvider.overrideWithValue(auth)],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('needs a successful authentication, and is saved', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      auth.outcomes.add(AuthOutcome.cancelled);
      final ProviderContainer c = container();
      final AppLock lock = c.read(appLockProvider.notifier);

      expect(await lock.setEnabled(true), LockToggleResult.notConfirmed);
      expect(c.read(appLockProvider).enabled, isNot(isTrue));

      expect(await lock.setEnabled(true), LockToggleResult.done);
      expect(c.read(appLockProvider).enabled, isTrue);
      expect(c.read(appLockProvider).locked, isFalse);
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(AppLock.key), isTrue);
    });

    test('is refused without a device passcode', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      auth.available = false;
      final ProviderContainer c = container();
      expect(
        await c.read(appLockProvider.notifier).setEnabled(true),
        LockToggleResult.unavailable,
      );
      expect(auth.asked, 0);
    });
  });

  testWidgets('a device with no passcode left opens and turns the lock off', (
    WidgetTester tester,
  ) async {
    auth.outcomes.add(AuthOutcome.unavailable);
    await pumpGate(tester, saved: true);
    expect(find.byType(LockScreen), findsNothing);
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(AppLock.key), isFalse);
  });
}
