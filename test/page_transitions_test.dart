import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/design/app_theme.dart';
import 'package:tracker/design/page_transitions.dart';
import 'package:tracker/main.dart' show generateRoute;

Future<NavigatorState> _pump(
  WidgetTester tester, {
  required bool reduced,
}) async {
  final GlobalKey<NavigatorState> navigator = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(disableAnimations: reduced),
      child: MaterialApp(
        navigatorKey: navigator,
        theme: appTheme(Brightness.light),
        home: const Scaffold(body: Text('Today')),
      ),
    ),
  );
  return navigator.currentState!;
}

void push(NavigatorState navigator) => navigator.push(
  MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('Habits'))),
);

void main() {
  testWidgets('every platform pushes pages with the fade-through', (
    WidgetTester tester,
  ) async {
    final PageTransitionsTheme theme = appTheme(
      Brightness.light,
    ).pageTransitionsTheme;
    for (final TargetPlatform platform in <TargetPlatform>[
      TargetPlatform.iOS,
      TargetPlatform.macOS,
    ]) {
      expect(theme.builders[platform], isA<DialPageTransitionsBuilder>());
    }
    expect(
      const DialPageTransitionsBuilder().transitionDuration,
      const Duration(milliseconds: 320),
    );
  });

  testWidgets('a push fades through over 320 ms', (WidgetTester tester) async {
    push(await _pump(tester, reduced: false));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 160));
    expect(find.byType(FadeThroughTransition), findsWidgets);
    await tester.pump(const Duration(milliseconds: 170));
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(find.text('Habits'), findsOneWidget);
  });

  testWidgets('under reduce motion a push only fades, over 150 ms', (
    WidgetTester tester,
  ) async {
    push(await _pump(tester, reduced: true));
    await tester.pump();
    expect(find.byType(FadeThroughTransition), findsNothing);
    final Finder fade = find.ancestor(
      of: find.text('Habits'),
      matching: find.byType(FadeTransition),
    );
    await tester.pump(const Duration(milliseconds: 75));
    expect(
      tester.widgetList<FadeTransition>(fade).first.opacity.value,
      inExclusiveRange(0.3, 0.7),
    );
    await tester.pump(const Duration(milliseconds: 80));
    expect(tester.widgetList<FadeTransition>(fade).first.opacity.value, 1);
    await tester.pumpAndSettle();
  });

  group('back swipe', () {
    final TargetPlatformVariant iOS = TargetPlatformVariant.only(
      TargetPlatform.iOS,
    );

    Future<NavigatorState> pushed(
      WidgetTester tester,
      Route<void> route, {
      bool reduced = false,
    }) async {
      final NavigatorState navigator = await _pump(tester, reduced: reduced);
      navigator.push(route);
      await tester.pumpAndSettle();
      return navigator;
    }

    Route<void> page(String text, {bool fullscreenDialog = false}) =>
        DialPageRoute<void>(
          fullscreenDialog: fullscreenDialog,
          builder: (_) => Scaffold(body: Center(child: Text(text))),
        );

    double left(WidgetTester tester, String text) => tester
        .getTopLeft(
          find.ancestor(of: find.text(text), matching: find.byType(Scaffold)),
        )
        .dx;

    testWidgets('a drag from the left edge pops a page, following the finger', (
      WidgetTester tester,
    ) async {
      await pushed(tester, page('Habits'));
      final TestGesture gesture = await tester.startGesture(
        const Offset(5, 300),
      );
      await gesture.moveBy(const Offset(20, 0));
      await gesture.moveBy(const Offset(200, 0));
      await tester.pump();
      expect(left(tester, 'Habits'), closeTo(220, 1));
      expect(find.text('Today'), findsOneWidget);
      await gesture.moveBy(const Offset(300, 0));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.text('Habits'), findsNothing);
      expect(find.text('Today'), findsOneWidget);
    }, variant: iOS);

    testWidgets('a short slow drag springs the page back', (
      WidgetTester tester,
    ) async {
      await pushed(tester, page('Habits'));
      final TestGesture gesture = await tester.startGesture(
        const Offset(5, 300),
      );
      await gesture.moveBy(const Offset(20, 0));
      await gesture.moveBy(const Offset(100, 0));
      await tester.pump(const Duration(seconds: 1));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.text('Habits'), findsOneWidget);
      expect(left(tester, 'Habits'), 0);
    }, variant: iOS);

    testWidgets('a quick flick pops the page before half way', (
      WidgetTester tester,
    ) async {
      await pushed(tester, page('Habits'));
      await tester.flingFrom(const Offset(5, 300), const Offset(150, 0), 1500);
      await tester.pumpAndSettle();
      expect(find.text('Habits'), findsNothing);
    }, variant: iOS);

    testWidgets('a drag starting mid-screen does not pop', (
      WidgetTester tester,
    ) async {
      await pushed(tester, page('Habits'));
      await tester.dragFrom(const Offset(300, 300), const Offset(450, 0));
      await tester.pumpAndSettle();
      expect(find.text('Habits'), findsOneWidget);
    }, variant: iOS);

    testWidgets('a MaterialPageRoute, such as the licences, pops too', (
      WidgetTester tester,
    ) async {
      final NavigatorState navigator = await _pump(tester, reduced: false);
      push(navigator);
      await tester.pumpAndSettle();
      await tester.dragFrom(const Offset(5, 300), const Offset(600, 0));
      await tester.pumpAndSettle();
      expect(find.text('Habits'), findsNothing);
      showLicensePage(context: navigator.context);
      await tester.pumpAndSettle();
      expect(find.byType(LicensePage), findsOneWidget);
      await tester.dragFrom(const Offset(5, 300), const Offset(600, 0));
      await tester.pumpAndSettle();
      expect(find.byType(LicensePage), findsNothing);
    }, variant: iOS);

    testWidgets('under reduce motion the drag still tracks the finger', (
      WidgetTester tester,
    ) async {
      await pushed(tester, page('Habits'), reduced: true);
      final TestGesture gesture = await tester.startGesture(
        const Offset(5, 300),
      );
      await gesture.moveBy(const Offset(20, 0));
      await gesture.moveBy(const Offset(200, 0));
      await tester.pump();
      expect(left(tester, 'Habits'), closeTo(220, 1));
      // The page below stays put: no parallax.
      expect(left(tester, 'Today'), 0);
      await gesture.moveBy(const Offset(300, 0));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.text('Habits'), findsNothing);
    }, variant: iOS);

    testWidgets('a page that would ask before closing is not swiped away', (
      WidgetTester tester,
    ) async {
      await pushed(
        tester,
        DialPageRoute<void>(
          builder: (_) => const PopScope<void>(
            canPop: false,
            child: Scaffold(body: Center(child: Text('Unsaved'))),
          ),
        ),
      );
      await tester.dragFrom(const Offset(5, 300), const Offset(600, 0));
      await tester.pumpAndSettle();
      expect(find.text('Unsaved'), findsOneWidget);
      expect(left(tester, 'Unsaved'), 0);
    }, variant: iOS);

    testWidgets('a fullscreen dialog is not swiped away', (
      WidgetTester tester,
    ) async {
      await pushed(tester, page('Form', fullscreenDialog: true));
      await tester.dragFrom(const Offset(5, 300), const Offset(600, 0));
      await tester.pumpAndSettle();
      expect(find.text('Form'), findsOneWidget);
    }, variant: iOS);

    testWidgets(
      'macOS has no edge swipe',
      (WidgetTester tester) async {
        await pushed(tester, page('Habits'));
        await tester.dragFrom(const Offset(5, 300), const Offset(600, 0));
        await tester.pumpAndSettle();
        expect(find.text('Habits'), findsOneWidget);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );

    testWidgets('the back button still fades through, with no slide', (
      WidgetTester tester,
    ) async {
      final NavigatorState navigator = await pushed(tester, page('Habits'));
      navigator.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(FadeThroughTransition), findsWidgets);
      expect(left(tester, 'Habits'), 0);
      await tester.pumpAndSettle();
    }, variant: iOS);

    test('only the forms open as fullscreen dialogs', () {
      for (final String name in <String>[
        '/vices/add',
        '/vices/v1/edit',
        '/vices/v1/activities/a1',
      ]) {
        expect(
          (generateRoute(RouteSettings(name: name)) as PageRoute<void>)
              .fullscreenDialog,
          isTrue,
          reason: name,
        );
      }
      for (final String name in <String>[
        '/vices/v1/activities',
        '/insights',
        '/manage-data',
        '/settings',
        '/settings/account',
        '/settings/appearance',
        '/settings/reduce-motion',
        '/settings/reminder',
        '/settings/recovery-key',
        '/nowhere',
      ]) {
        final Route<void> route = generateRoute(RouteSettings(name: name));
        expect(route, isA<DialPageRoute<void>>(), reason: name);
        expect((route as PageRoute<void>).fullscreenDialog, isFalse);
      }
    });
  });
}
