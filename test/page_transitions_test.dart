import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/design/app_theme.dart';
import 'package:tracker/design/page_transitions.dart';

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
}
