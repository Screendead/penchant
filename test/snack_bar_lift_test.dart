import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/design/app_theme.dart';
import 'package:tracker/widgets/undo_bar.dart';

void main() {
  testWidgets('the lift raises bars on its own Scaffold only, and follows '
      'its height as it changes', (tester) async {
    final ValueNotifier<double> lift = ValueNotifier<double>(100);
    final GlobalKey<NavigatorState> nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: nav,
        theme: appTheme(Brightness.light),
        home: ValueListenableBuilder<double>(
          valueListenable: lift,
          builder: (BuildContext context, double h, Widget? _) => Scaffold(
            floatingActionButton: SnackBarLift(
              height: (BuildContext c, double w) => h,
            ),
            floatingActionButtonLocation: SnackBarLift.location,
            body: const SizedBox.expand(),
          ),
        ),
      ),
    );
    final ScaffoldMessengerState messenger = tester.state(
      find.byType(ScaffoldMessenger),
    );
    double barBottom() => tester.getBottomLeft(find.byType(SnackBar).last).dy;

    showUndoBar(messenger, const TextSpan(text: 'Logged'), onUndo: () {});
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    final double height = tester.getSize(find.byType(Scaffold)).height;
    expect(barBottom(), closeTo(height - 100, 1));

    lift.value = 200;
    await tester.pump();
    expect(barBottom(), closeTo(height - 200, 1));

    nav.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: SizedBox.expand()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(barBottom(), closeTo(height, 1));
  });

  testWidgets('the lift takes no taps', (tester) async {
    int taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          floatingActionButton: SnackBarLift(
            height: (BuildContext c, double w) => 300,
          ),
          floatingActionButtonLocation: SnackBarLift.location,
          body: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => taps++,
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
    await tester.tapAt(tester.getCenter(find.byType(SnackBarLift)));
    expect(taps, 1);
  });
}
