import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/claude/claude_working.dart';
import 'package:tracker/design/app_theme.dart';

void main() {
  const String writing = 'Claude is writing a query';
  const String sent = 'Sent your question';
  const Object tag = ('test', 1);

  Widget app({bool still = false, required Widget home}) => ProviderScope(
    overrides: <Override>[
      claudeWorkingMarksProvider.overrideWithValue(const <JournalMark>[]),
    ],
    child: MaterialApp(
      theme: appTheme(Brightness.light),
      builder: (BuildContext context, Widget? child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: still),
        child: child!,
      ),
      home: home,
    ),
  );

  // A page with a button that starts [work] and, once answered, a result
  // under [tag].
  Widget page(ClaudeWork work, {VoidCallback? onStop}) => Scaffold(
    body: ListenableBuilder(
      listenable: work,
      builder: (BuildContext context, _) => Column(
        children: <Widget>[
          Builder(
            builder: (BuildContext context) => TextButton(
              onPressed: () => showClaudeWorking(
                context,
                work,
                resultTag: tag,
                onStop: onStop,
                marks: const <JournalMark>[],
              ),
              child: const Text('Ask'),
            ),
          ),
          if (work.end == ClaudeWorkEnd.answered)
            const ClaudeWorkingResult(
              tag: tag,
              child: SizedBox(height: 80, child: Text('The answer')),
            ),
        ],
      ),
    ),
  );

  ClaudeWork work() => ClaudeWork(status: writing, detail: sent);

  bool showing(WidgetTester tester) =>
      find.text(ClaudeWorking.label.toUpperCase()).evaluate().isNotEmpty;

  testWidgets('a call answered before the delay never leaves the page', (
    WidgetTester tester,
  ) async {
    final ClaudeWork w = work();
    await tester.pumpWidget(app(home: page(w)));
    await tester.tap(find.text('Ask'));
    await tester.pump(ClaudeWorking.delay ~/ 2);
    w.finish(ClaudeWorkEnd.answered);
    await tester.pump(ClaudeWorking.delay);
    await tester.pumpAndSettle();
    expect(showing(tester), isFalse);
    expect(find.text('The answer'), findsOneWidget);
  });

  testWidgets('a longer call goes fullscreen, says what is happening, holds '
      'its minimum time and resolves into the result', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    final ClaudeWork w = work();
    await tester.pumpWidget(app(home: page(w)));
    await tester.tap(find.text('Ask'));
    await tester.pump(ClaudeWorking.delay);
    await tester.pump(ClaudeWorking.grow);
    expect(showing(tester), isTrue);
    expect(find.text(writing), findsOneWidget);
    expect(
      tester.getSemantics(find.bySemanticsLabel('$writing. $sent')),
      matchesSemantics(label: '$writing. $sent', isLiveRegion: true),
    );

    w.finish(ClaudeWorkEnd.answered);
    await tester.pump(const Duration(milliseconds: 100));
    expect(showing(tester), isTrue);
    await tester.pump(ClaudeWorking.minShown);
    await tester.pump(ClaudeWorking.resolve);
    for (int i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(showing(tester), isFalse);
    expect(find.text('The answer'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('Stop abandons the call and returns to the page', (
    WidgetTester tester,
  ) async {
    final ClaudeWork w = work();
    int stops = 0;
    await tester.pumpWidget(app(home: page(w, onStop: () => stops++)));
    await tester.tap(find.text('Ask'));
    await tester.pump(ClaudeWorking.delay);
    await tester.pump(ClaudeWorking.grow);
    await tester.tap(find.text(ClaudeWorking.stop));
    await tester.pump();
    expect(stops, 1);
    expect(w.end, ClaudeWorkEnd.stopped);
    await tester.pump(ClaudeWorking.minShown);
    for (int i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(showing(tester), isFalse);
    expect(find.text('Ask'), findsOneWidget);
  });

  testWidgets('under reduce motion the screen and the card settle', (
    WidgetTester tester,
  ) async {
    final ClaudeWork w = work();
    await tester.pumpWidget(
      app(
        still: true,
        home: Scaffold(
          body: Column(
            children: <Widget>[
              const ClaudeWorkingCard(status: writing),
              Expanded(child: page(w)),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(writing), findsOneWidget);
    await tester.tap(find.text('Ask'));
    await tester.pump(ClaudeWorking.delay);
    await tester.pumpAndSettle();
    expect(showing(tester), isTrue);
    w.finish(ClaudeWorkEnd.answered);
    await tester.pump(ClaudeWorking.minShown);
    await tester.pumpAndSettle();
    expect(showing(tester), isFalse);
    expect(find.text('The answer'), findsOneWidget);
  });
}
