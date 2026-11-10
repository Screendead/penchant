import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/design/app_theme.dart';
import 'package:tracker/vice_tracker.dart';
import 'package:tracker/widgets/keyboard_inset_clamp.dart';
import 'package:tracker/widgets/undo_bar.dart';

void main() {
  // An iPhone 17 Pro, as the e2e simulator.
  void iPhone(WidgetTester tester) {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(402 * 3, 874 * 3);
    tester.view.padding = const FakeViewPadding(top: 62 * 3, bottom: 34 * 3);
    addTearDown(tester.view.reset);
  }

  // Two pages of the stack, as when the record sheet or a pushed page leaves
  // the one below on stage: the messenger shows its bar in both.
  Future<ScaffoldMessengerState> pumpApp(
    WidgetTester tester, {
    required bool clamped,
  }) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(Brightness.light),
        builder: (BuildContext _, Widget? child) =>
            clamped ? KeyboardInsetClamp(child: child!) : child!,
        home: Scaffold(
          floatingActionButton: SnackBarLift(
            height: (BuildContext c, double _) => ViceTracker.logClearance(c),
          ),
          floatingActionButtonLocation: SnackBarLift.location,
          body: Builder(
            builder: (BuildContext c) {
              context = c;
              return const SizedBox.expand();
            },
          ),
        ),
      ),
    );
    return ScaffoldMessenger.of(context);
  }

  // The frame the iOS keyboard spring reports when evaluated at a negative
  // time: an inset three keyboards tall.
  const FakeViewPadding overshoot = FakeViewPadding(bottom: 1000 * 3);

  Future<Object?> showBarsUnder(
    WidgetTester tester,
    ScaffoldMessengerState messenger,
  ) async {
    messenger.showSnackBar(const SnackBar(content: Text('Not saved')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    tester.view.viewInsets = overshoot;
    await tester.pump();
    final Object? plain = tester.takeException();
    if (plain != null) {
      return plain;
    }
    showUndoBar(
      messenger,
      const TextSpan(text: 'Activity recorded'),
      onUndo: () {},
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    return tester.takeException();
  }

  testWidgets('without the clamp, an inset taller than the view puts a '
      'floating bar off screen', (tester) async {
    iPhone(tester);
    final ScaffoldMessengerState messenger = await pumpApp(
      tester,
      clamped: false,
    );
    expect(
      await showBarsUnder(tester, messenger),
      isA<FlutterError>().having(
        (FlutterError e) => e.message,
        'message',
        contains('Floating SnackBar presented off screen'),
      ),
    );
  });

  testWidgets('with the clamp, the plain bar and the undo bar lifted over Log '
      'stay on screen above an inset taller than the view', (tester) async {
    iPhone(tester);
    final ScaffoldMessengerState messenger = await pumpApp(
      tester,
      clamped: true,
    );
    expect(await showBarsUnder(tester, messenger), isNull);
    expect(find.text('Activity recorded'), findsOneWidget);
  });

  test('a real keyboard passes through; a negative or overshot inset is '
      'clamped', () {
    // A portrait iPhone keyboard, and a landscape one with its suggestions.
    expect(KeyboardInsetClamp.clamp(336, 874), 336);
    expect(KeyboardInsetClamp.clamp(240, 402), 240);
    expect(KeyboardInsetClamp.clamp(-120, 874), 0);
    expect(KeyboardInsetClamp.clamp(3000, 874), closeTo(582.67, 0.01));
  });
}
