import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/account/account_copy.dart';
import 'package:tracker/authenticate.dart';
import 'package:tracker/providers/account_provider.dart';

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

Finder _field(String hint) => find.widgetWithText(TextFormField, hint);

double _top(WidgetTester tester, Finder finder) => tester.getTopLeft(finder).dy;

// The product of every fade above the field.
double _opacity(WidgetTester tester, Finder finder) => tester
    .widgetList<FadeTransition>(
      find.ancestor(of: finder, matching: find.byType(FadeTransition)),
    )
    .fold(1, (double o, FadeTransition f) => o * f.opacity.value);

void main() {
  testWidgets('switching modes holds the shared fields still and solid while '
      'the rest eases in and out', (WidgetTester tester) async {
    await _pump(tester);
    final double emailTop = _top(tester, _field('Email'));
    final double passwordTop = _top(tester, _field('Password'));
    final double guestBefore = _top(
      tester,
      find.byKey(Authenticate.guestStart),
    );
    await tester.enterText(_field('Email'), 'sam@example.com');
    await tester.tap(find.byKey(Authenticate.registerTab));
    final List<double> guest = <double>[];
    for (int i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      for (final Finder field in <Finder>[
        _field('Email'),
        _field('Password'),
      ]) {
        expect(field, findsOneWidget);
        expect(_opacity(tester, field), 1);
      }
      expect(_top(tester, _field('Email')), emailTop);
      expect(_top(tester, _field('Password')), passwordTop);
      guest.add(_top(tester, find.byKey(Authenticate.guestStart)));
    }
    await tester.pumpAndSettle();
    final double guestAfter = _top(tester, find.byKey(Authenticate.guestStart));
    // The button below glides down rather than jumping in one frame.
    expect(guest.first - guestBefore, lessThan((guestAfter - guestBefore) / 4));
    for (int i = 1; i < guest.length; i++) {
      expect(guest[i], greaterThanOrEqualTo(guest[i - 1]));
    }
    expect(guestAfter, greaterThan(guestBefore));
    expect(_field('Confirm password'), findsOneWidget);
    expect(find.text(AccountCopy.forgotPassword), findsNothing);
    expect(find.widgetWithText(ElevatedButton, 'Create account'), findsOne);
    // What was typed carries over.
    expect(find.text('sam@example.com'), findsOneWidget);

    await tester.tap(find.byKey(Authenticate.signInTab));
    for (int i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(_opacity(tester, _field('Email')), 1);
      expect(_top(tester, _field('Password')), passwordTop);
    }
    await tester.pumpAndSettle();
    expect(_field('Confirm password'), findsNothing);
    expect(find.text(AccountCopy.forgotPassword), findsOneWidget);
    expect(_top(tester, find.byKey(Authenticate.guestStart)), guestBefore);
  });

  testWidgets('under reduced motion the space changes at once', (
    WidgetTester tester,
  ) async {
    await _pump(tester, reduced: true);
    await tester.tap(find.byKey(Authenticate.registerTab));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    final double guest = tester
        .getTopLeft(find.byKey(Authenticate.guestStart))
        .dy;
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byKey(Authenticate.guestStart)).dy, guest);
  });
}
