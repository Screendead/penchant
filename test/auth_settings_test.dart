import 'dart:ui' show CheckedState;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/authenticate.dart';
import 'package:tracker/design/app_theme.dart';
import 'package:tracker/design/tokens.dart';
import 'package:tracker/widgets/auth_parts.dart';
import 'package:tracker/widgets/settings_card.dart';

import 'fake_account.dart';
import 'package:tracker/providers/account_provider.dart';

Future<void> _pumpAuth(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [accountProvider.overrideWithValue(FakeAccount())],
      child: MaterialApp(
        theme: appTheme(Brightness.light),
        home: const Authenticate(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

bool _checked(WidgetTester tester, String rule) =>
    tester
        .getSemantics(find.bySemanticsLabel(rule))
        .flagsCollection
        .isChecked ==
    CheckedState.isTrue;

void main() {
  group('the sign-in screen', () {
    testWidgets('switches between signing in and creating an account', (
      WidgetTester tester,
    ) async {
      await _pumpAuth(tester);
      expect(find.text(PasswordRules.length), findsNothing);
      expect(find.widgetWithText(ElevatedButton, 'Sign in'), findsOneWidget);

      await tester.tap(find.byKey(Authenticate.registerTab));
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(ElevatedButton, 'Create account'),
        findsOneWidget,
      );
      expect(find.text(PasswordRules.length), findsOneWidget);
      expect(find.text('Forgot password?'), findsNothing);
    });

    testWidgets('ticks each password rule as it is met and enables Create '
        'account only when all are', (WidgetTester tester) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      await _pumpAuth(tester);
      await tester.tap(find.byKey(Authenticate.registerTab));
      await tester.pumpAndSettle();

      ElevatedButton button() => tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Create account'),
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Email'),
        'sam@example.com',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'),
        'Morning7',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Confirm password'),
        'Morning',
      );
      await tester.pumpAndSettle();
      for (final String rule in <String>[
        PasswordRules.length,
        PasswordRules.upper,
        PasswordRules.lower,
        PasswordRules.digit,
      ]) {
        expect(_checked(tester, rule), isTrue, reason: rule);
      }
      expect(_checked(tester, PasswordRules.match), isFalse);
      expect(button().onPressed, isNull);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Confirm password'),
        'Morning7',
      );
      await tester.pumpAndSettle();
      expect(_checked(tester, PasswordRules.match), isTrue);
      expect(button().onPressed, isNotNull);
      semantics.dispose();
    });

    testWidgets('rings the segment focused from the keyboard in accent', (
      WidgetTester tester,
    ) async {
      await _pumpAuth(tester);
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTraditional;
      addTearDown(
        () => FocusManager.instance.highlightStrategy =
            FocusHighlightStrategy.automatic,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      final Finder ring = find.descendant(
        of: find.byKey(Authenticate.signInTab),
        matching: find.byWidgetPredicate(
          (Widget w) =>
              w is Container &&
              w.decoration is ShapeDecoration &&
              ((w.decoration! as ShapeDecoration).shape as StadiumBorder)
                      .side
                      .color ==
                  DialPalette.light.accent,
        ),
      );
      expect(ring, findsOneWidget);
    });
  });

  testWidgets('a card row focused from the keyboard draws a 2 pt accent '
      'ring, and none without focus', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(Brightness.light),
        home: Scaffold(
          body: DialCard(
            children: <Widget>[
              CardRow(label: 'Account', onTap: () {}),
              CardRow(label: 'About', onTap: () {}),
            ],
          ),
        ),
      ),
    );
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
    addTearDown(
      () => FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.automatic,
    );
    Finder rings() => find.byWidgetPredicate(
      (Widget w) =>
          w is Container &&
          w.decoration is BoxDecoration &&
          (w.decoration! as BoxDecoration).border ==
              Border.all(color: DialPalette.light.accent, width: 2),
    );
    expect(rings(), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(rings(), findsOneWidget);
    expect(
      find.ancestor(of: rings(), matching: find.byType(CardRow)),
      findsOneWidget,
    );
  });
}
