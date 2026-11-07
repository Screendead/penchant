import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/keychain_probe.dart';

import 'fake_keychain.dart';

void main() {
  const (String, bool) synced = (KeychainProbe.itemName, true);
  const (String, bool) local = (KeychainProbe.itemName, false);

  Future<void> pumpProbe(WidgetTester tester, FakeKeychain keychain) async {
    await tester.pumpWidget(
      MaterialApp(
        home: KeychainProbeScreen(
          probe: KeychainProbe(keychain, Random(1)),
          deviceKind: 'iPhone',
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  test('normal builds leave the probe off', () {
    expect(keychainProbe, isFalse);
  });

  testWidgets('writes a synced code and shows it', (WidgetTester tester) async {
    final FakeKeychain keychain = FakeKeychain();
    await pumpProbe(tester, keychain);

    expect(find.text('This device: iPhone'), findsOneWidget);
    expect(find.text('No test value on this device.'), findsOneWidget);
    expect(find.text('Delete test value'), findsNothing);

    await tester.tap(find.text('Write test value'));
    await tester.pumpAndSettle();

    final Map<String, dynamic> stored =
        jsonDecode(keychain.items[synced]!) as Map<String, dynamic>;
    expect(stored['code'], matches(RegExp(r'^[A-HJ-NP-Z2-9]{8}$')));
    expect(stored['on'], 'iPhone');
    expect(keychain.items.containsKey(local), isFalse);
    expect(find.text(stored['code'] as String), findsOneWidget);
    expect(find.text('Stored synced (iCloud Keychain).'), findsOneWidget);
    expect(find.text('Write test value'), findsNothing);
    expect(find.text('Delete test value'), findsOneWidget);
  });

  testWidgets('falls back to this device and shows the refusal', (
    WidgetTester tester,
  ) async {
    final FakeKeychain keychain = FakeKeychain(
      refuseSynced: true,
      refuseSyncedReads: true,
    );
    await pumpProbe(tester, keychain);

    expect(
      find.text('Synced keychain error: -34018: errSecMissingEntitlement'),
      findsOneWidget,
    );

    await tester.tap(find.text('Write test value'));
    await tester.pumpAndSettle();

    expect(keychain.items.containsKey(synced), isFalse);
    expect(keychain.items.containsKey(local), isTrue);
    expect(
      find.text('Stored on this device only: the synced keychain refused it.'),
      findsOneWidget,
    );
    expect(
      find.text('Synced keychain error: -34018: errSecMissingEntitlement'),
      findsOneWidget,
    );
  });

  testWidgets('reads a value another device wrote, then deletes it', (
    WidgetTester tester,
  ) async {
    final FakeKeychain keychain = FakeKeychain();
    await pumpProbe(tester, keychain);
    expect(find.text('No test value on this device.'), findsOneWidget);

    keychain.items[synced] = jsonEncode(<String, String>{
      'code': 'K7QF2M9X',
      'on': 'Mac',
      'at': '2026-11-07T19:50:00Z',
    });
    await tester.tap(find.text('Read again'));
    await tester.pumpAndSettle();

    expect(find.text('K7QF2M9X'), findsOneWidget);
    expect(find.textContaining('Written on Mac at '), findsOneWidget);

    await tester.tap(find.text('Delete test value'));
    await tester.pumpAndSettle();

    expect(keychain.items, isEmpty);
    expect(find.text('No test value on this device.'), findsOneWidget);
  });
}
