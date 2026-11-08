import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/authenticate.dart';
import 'package:tracker/providers/account_provider.dart';
import 'package:tracker/register.dart';
import 'package:tracker/sign_in.dart';

import 'fake_account.dart';

Future<void> _pump(WidgetTester tester, {bool reduced = false}) async {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [accountProvider.overrideWithValue(FakeAccount())],
      child: MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduced),
          child: const Authenticate(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

double _top(WidgetTester tester, Type form) => tester
    .getTopLeft(
      find
          .descendant(
            of: find.byType(form),
            matching: find.byType(TextFormField),
          )
          .first,
    )
    .dy;

double _guestTop(WidgetTester tester) =>
    tester.getTopLeft(find.byKey(Authenticate.guestStart)).dy;

void main() {
  testWidgets('switching forms keeps the old form in place and eases the '
      'height', (WidgetTester tester) async {
    await _pump(tester);
    final double emailTop = _top(tester, SignIn);
    final double guestBefore = _guestTop(tester);
    await tester.tap(find.byKey(Authenticate.registerTab));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    // The outgoing form is not re-centred against the taller incoming one.
    expect(_top(tester, SignIn), emailTop);
    await tester.pump(const Duration(milliseconds: 100));
    final double guestMid = _guestTop(tester);
    await tester.pumpAndSettle();
    final double guestAfter = _guestTop(tester);
    expect(guestAfter, greaterThan(guestBefore));
    expect(guestMid, greaterThan(guestBefore));
    expect(guestMid, lessThan(guestAfter));
    expect(find.byType(SignIn), findsNothing);
    expect(_top(tester, Register), closeTo(emailTop, 0.01));
  });

  testWidgets('under reduced motion the height changes at once', (
    WidgetTester tester,
  ) async {
    await _pump(tester, reduced: true);
    await tester.tap(find.byKey(Authenticate.registerTab));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    final double guest = _guestTop(tester);
    await tester.pumpAndSettle();
    expect(_guestTop(tester), guest);
  });
}
