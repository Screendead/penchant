import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/widgets/pill_drop.dart';
import 'package:tracker/widgets/rejected_writes_banner.dart';
import 'package:tracker/writes/rejected_writes.dart';

class _Rejected extends RejectedWrites {
  @override
  List<RejectedWrite> build() => const <RejectedWrite>[];

  void show(List<RejectedWrite> rejected) => state = rejected;
}

const double _inset = 47;

void main() {
  group('a pill lifting away', () {
    int taps = 0;

    Widget pill({required bool shown}) => MaterialApp(
      home: Scaffold(
        body: Column(
          children: <Widget>[
            PillDrop(
              shown: shown,
              child: TextButton(
                onPressed: () => taps++,
                child: const Text('Dismiss'),
              ),
            ),
          ],
        ),
      ),
    );

    double y(WidgetTester tester) => tester
        .widget<Transform>(
          find.ancestor(
            of: find.text('Dismiss'),
            matching: find.byType(Transform),
          ),
        )
        .transform
        .getTranslation()
        .y;

    setUp(() => taps = 0);

    testWidgets('takes no taps and is not announced', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(pill(shown: true));
      await tester.pumpAndSettle();
      await tester.pumpWidget(pill(shown: false));
      await tester.pump(const Duration(milliseconds: 30));

      await tester.tap(find.text('Dismiss'), warnIfMissed: false);
      expect(taps, 0);
      expect(
        find.ancestor(
          of: find.text('Dismiss'),
          matching: find.byWidgetPredicate(
            (Widget w) => w is ExcludeSemantics && w.excluding,
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets('drops back from where it had got to when shown again', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(pill(shown: true));
      await tester.pumpAndSettle();
      await tester.pumpWidget(pill(shown: false));
      await tester.pump(const Duration(milliseconds: 150));
      final double lifted = y(tester);
      expect(lifted, inExclusiveRange(PillDrop.liftTo, 0));

      await tester.pumpWidget(pill(shown: true));
      await tester.pump(const Duration(milliseconds: 16));

      expect(y(tester), greaterThan(lifted - 10));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dismiss'));
      expect(taps, 1);
    });
  });

  testWidgets('a refusal moves the screen below it frame by frame', (
    WidgetTester tester,
  ) async {
    final GlobalKey screen = GlobalKey();
    final ProviderContainer container = ProviderContainer(
      overrides: [rejectedWritesProvider.overrideWith(_Rejected.new)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          builder: (BuildContext context, Widget? child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(padding: const EdgeInsets.only(top: _inset)),
            child: Builder(
              builder: (BuildContext context) =>
                  rejectedWritesBuilder(context, child),
            ),
          ),
          home: Scaffold(
            body: SafeArea(child: SizedBox.expand(key: screen)),
          ),
        ),
      ),
    );
    double top() => tester.getTopLeft(find.byKey(screen)).dy;
    expect(top(), _inset);

    Future<List<double>> frames() async {
      final List<double> tops = <double>[top()];
      for (int i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        tops.add(top());
      }
      return tops;
    }

    void expectEased(List<double> tops) {
      for (int i = 1; i < tops.length; i++) {
        expect(
          (tops[i] - tops[i - 1]).abs(),
          lessThan(16),
          reason: 'frame $i moved from ${tops[i - 1]} to ${tops[i]}',
        );
      }
      expect(tops.reduce((double a, double b) => a < b ? a : b), _inset);
    }

    (container.read(rejectedWritesProvider.notifier) as _Rejected).show(
      const <RejectedWrite>[RejectedWrite('Coffee, 1 cup', null)],
    );
    await tester.pump();
    final List<double> down = await frames();
    expectEased(down);
    expect(down.last, greaterThan(_inset + 30));

    await tester.tap(find.text(RejectedWritesBanner.dismissLabel));
    await tester.pump();
    final List<double> up = await frames();
    expectEased(up);
    expect(up.last, _inset);
  });
}
