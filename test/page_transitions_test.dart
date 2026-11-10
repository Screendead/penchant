import 'package:animations/animations.dart';
import 'package:flutter/foundation.dart';
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
  test('every platform pushes pages with the fade-through', () {
    final PageTransitionsTheme theme = appTheme(
      Brightness.light,
    ).pageTransitionsTheme;
    for (final TargetPlatform platform in TargetPlatform.values) {
      expect(
        theme.builders[platform],
        isA<DialPageTransitionsBuilder>(),
        reason: platform.name,
      );
    }
  });

  testWidgets('a push fades through over 320 ms', (WidgetTester tester) async {
    push(await _pump(tester, reduced: false));
    await tester.pump();
    final Finder fade = find.ancestor(
      of: find.text('Habits'),
      matching: find.byType(FadeThroughTransition),
    );
    await tester.pump(const Duration(milliseconds: 160));
    expect(fade, findsOneWidget);
    await tester.pump(const Duration(milliseconds: 150));
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pump(const Duration(milliseconds: 20));
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

    // What a viewer sees of a page: where it sits, how opaque and how scaled.
    (double, double, double)? seen(WidgetTester tester, String text) {
      final Finder found = find.text(text);
      if (found.evaluate().isEmpty) {
        return null;
      }
      double opacity = 1;
      for (final FadeTransition fade in tester.widgetList<FadeTransition>(
        find.ancestor(of: found, matching: find.byType(FadeTransition)),
      )) {
        opacity *= fade.opacity.value;
      }
      double scale = 1;
      for (final ScaleTransition zoom in tester.widgetList<ScaleTransition>(
        find.ancestor(of: found, matching: find.byType(ScaleTransition)),
      )) {
        scale *= zoom.scale.value;
      }
      double round(double value) => (value * 1000).roundToDouble() / 1000;
      return (round(left(tester, text)), round(opacity), round(scale));
    }

    Future<void> swipeAndRelease(WidgetTester tester, double by) async {
      final TestGesture gesture = await tester.startGesture(
        const Offset(5, 300),
      );
      await gesture.moveBy(const Offset(20, 0));
      await gesture.moveBy(Offset(by, 0));
      await tester.pump(const Duration(seconds: 1));
      await gesture.up();
      await tester.pumpAndSettle();
    }

    Future<List<Object?>> frames(
      WidgetTester tester,
      List<String> pages,
    ) async {
      final List<Object?> seenFrames = <Object?>[];
      await tester.pump();
      for (int frame = 0; frame < 6; frame++) {
        seenFrames.add(<Object?>[
          for (final String text in pages) seen(tester, text),
        ]);
        await tester.pump(const Duration(milliseconds: 55));
      }
      await tester.pumpAndSettle();
      return seenFrames;
    }

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
      // The page below shows whole, a third of the way back in.
      final (double, double, double) today = seen(tester, 'Today')!;
      expect(today.$1, closeTo(-(1 - 220 / 800) * 800 / 3, 1));
      expect((today.$2, today.$3), (1, 1));
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

    testWidgets('macOS has no edge swipe', (WidgetTester tester) async {
      await pushed(tester, page('Habits'));
      await tester.dragFrom(const Offset(5, 300), const Offset(600, 0));
      await tester.pumpAndSettle();
      expect(find.text('Habits'), findsOneWidget);
    }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

    testWidgets('the back button still fades through, with no slide', (
      WidgetTester tester,
    ) async {
      final NavigatorState navigator = await pushed(tester, page('Habits'));
      navigator.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      final (double, double, double) habits = seen(tester, 'Habits')!;
      expect(habits.$1, 0);
      expect(habits.$2, inExclusiveRange(0, 1));
      expect(seen(tester, 'Today')!.$1, isNot(lessThan(0)));
      await tester.pumpAndSettle();
    }, variant: iOS);

    // After a drag the transitions switch back to their fixed animations;
    // whatever moves next must move exactly as if no drag had happened.
    for (final bool reduced in <bool>[false, true]) {
      final String motion = reduced ? ', under reduce motion' : '';

      testWidgets('after a cancelled drag the back button fades as before'
          '$motion', (WidgetTester tester) async {
        NavigatorState navigator = await pushed(
          tester,
          page('Habits'),
          reduced: reduced,
        );
        navigator.pop();
        final List<Object?> fresh = await frames(tester, <String>[
          'Habits',
          'Today',
        ]);

        navigator = await pushed(tester, page('Habits'), reduced: reduced);
        await swipeAndRelease(tester, 100);
        expect(seen(tester, 'Habits'), (0, 1, 1));
        expect(find.text('Today'), findsNothing);
        navigator.pop();
        expect(await frames(tester, <String>['Habits', 'Today']), fresh);
      }, variant: iOS);

      testWidgets('after a cancelled drag a push fades as before$motion', (
        WidgetTester tester,
      ) async {
        NavigatorState navigator = await pushed(
          tester,
          page('Habits'),
          reduced: reduced,
        );
        navigator.push(page('Entries'));
        final List<Object?> fresh = await frames(tester, <String>[
          'Entries',
          'Habits',
        ]);

        navigator = await pushed(tester, page('Habits'), reduced: reduced);
        await swipeAndRelease(tester, 100);
        navigator.push(page('Entries'));
        expect(await frames(tester, <String>['Entries', 'Habits']), fresh);
      }, variant: iOS);

      testWidgets('after a drag pops a page, the next push fades as before'
          '$motion', (WidgetTester tester) async {
        NavigatorState navigator = await _pump(tester, reduced: reduced);
        navigator.push(page('Habits'));
        final List<Object?> fresh = await frames(tester, <String>[
          'Habits',
          'Today',
        ]);

        navigator = await pushed(tester, page('Habits'), reduced: reduced);
        await swipeAndRelease(tester, 600);
        expect(find.text('Habits'), findsNothing);
        expect(seen(tester, 'Today'), (0, 1, 1));
        navigator.push(page('Habits'));
        expect(await frames(tester, <String>['Habits', 'Today']), fresh);
      }, variant: iOS);
    }

    testWidgets('a page keeps its state through a drag', (
      WidgetTester tester,
    ) async {
      await pushed(
        tester,
        DialPageRoute<void>(
          builder: (_) => const Scaffold(
            body: Center(child: SizedBox(width: 200, child: TextField())),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), 'typed');
      final State before = tester.state(find.byType(EditableText));
      final TestGesture gesture = await tester.startGesture(
        const Offset(5, 300),
      );
      await gesture.moveBy(const Offset(20, 0));
      await gesture.moveBy(const Offset(100, 0));
      await tester.pump();
      expect(tester.state(find.byType(EditableText)), same(before));
      await tester.pump(const Duration(seconds: 1));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(EditableText)), same(before));
      expect(find.text('typed'), findsOneWidget);
    }, variant: iOS);

    testWidgets('a pop in code mid drag pops one page', (
      WidgetTester tester,
    ) async {
      final NavigatorState navigator = await pushed(tester, page('Habits'));
      navigator.push(page('Entries'));
      await tester.pumpAndSettle();
      final TestGesture gesture = await tester.startGesture(
        const Offset(5, 300),
      );
      await gesture.moveBy(const Offset(20, 0));
      await gesture.moveBy(const Offset(50, 0));
      await tester.pump();
      navigator.pop();
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.text('Entries'), findsNothing);
      expect(seen(tester, 'Habits'), (0, 1, 1));
    }, variant: iOS);

    testWidgets('a licence swipes back to the list, not out of the licences', (
      WidgetTester tester,
    ) async {
      LicenseRegistry.reset();
      addTearDown(LicenseRegistry.reset);
      LicenseRegistry.addLicense(
        () => Stream<LicenseEntry>.value(
          const LicenseEntryWithLineBreaks(<String>['a_package'], 'Terms'),
        ),
      );
      final NavigatorState navigator = await _pump(tester, reduced: false);
      showLicensePage(context: navigator.context);
      await tester.pumpAndSettle();
      await tester.tap(find.text('a_package'));
      await tester.pumpAndSettle();
      expect(find.text('Terms'), findsOneWidget);
      await tester.dragFrom(const Offset(5, 300), const Offset(600, 0));
      await tester.pumpAndSettle();
      expect(find.text('Terms'), findsNothing);
      expect(find.text('a_package'), findsOneWidget);
    }, variant: iOS);
  });

  test('every route but the entry sheet is a DialPageRoute, so the '
      'transition clock applies', () {
    expect(
      generateRoute(const RouteSettings(name: '/vices/v1/activities/a1')),
      isA<ModalBottomSheetRoute<void>>(),
    );
    for (final String name in <String>[
      '/vices/add',
      '/vices/v1/edit',
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
      expect(
        generateRoute(RouteSettings(name: name)),
        isA<DialPageRoute<void>>(),
        reason: name,
      );
    }
  });
}
