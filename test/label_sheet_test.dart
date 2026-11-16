import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/design/app_theme.dart';
import 'package:tracker/label/label_sheet.dart';
import 'package:tracker/label/label_source.dart';

import 'fakes.dart';

Future<void> _pump(WidgetTester tester, LabelSource source) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: appTheme(Brightness.light),
      home: Scaffold(
        body: LabelSheet(source: source, one: 'glass'),
      ),
    ),
  );
}

Future<void> _take(WidgetTester tester) async {
  await tester.tap(find.text(LabelSheet.takeLabel));
  await tester.pumpAndSettle();
}

FilledButton _fill(WidgetTester tester) => tester.widget<FilledButton>(
  find.widgetWithText(FilledButton, LabelSheet.fillLabel),
);

void main() {
  testWidgets('says on the first screen that nothing leaves the phone', (
    WidgetTester tester,
  ) async {
    await _pump(tester, const FakeLabelSource(<String>[]));
    expect(find.text(LabelSheet.privacy), findsOneWidget);
  });

  testWidgets('a photo with nothing to read says so', (
    WidgetTester tester,
  ) async {
    await _pump(tester, const FakeLabelSource(<String>['Best before']));
    await _take(tester);
    expect(find.text(LabelSheet.nothingTitle), findsOneWidget);
    expect(find.text(LabelSheet.takeLabel), findsOneWidget);
    expect(find.text(LabelSheet.privacy), findsOneWidget);
  });

  testWidgets('a bare percentage is offered, not picked', (
    WidgetTester tester,
  ) async {
    await _pump(tester, const FakeLabelSource(<String>['Pale ale', '5.2%']));
    await _take(tester);
    expect(find.text('5.2%'), findsOneWidget);
    expect(_fill(tester).onPressed, isNull);
    await tester.tap(find.text('5.2%'));
    await tester.pump();
    expect(_fill(tester).onPressed, isNotNull);
  });

  testWidgets('two sizes are both offered and neither picked', (
    WidgetTester tester,
  ) async {
    await _pump(
      tester,
      const FakeLabelSource(<String>['330 ml', '500 ml', 'ALC 5% VOL']),
    );
    await _take(tester);
    expect(find.text('330 ml'), findsOneWidget);
    expect(find.text('500 ml'), findsOneWidget);
    expect(
      find.text('The label gives more than one: pick one, or leave it.'),
      findsOneWidget,
    );
  });

  testWidgets('no camera and a failed read are said', (
    WidgetTester tester,
  ) async {
    await _pump(
      tester,
      const FakeLabelSource(<String>[], status: LabelScanStatus.noCamera),
    );
    await _take(tester);
    expect(find.text(LabelSheet.noCamera), findsOneWidget);
    await _pump(
      tester,
      const FakeLabelSource(<String>[], status: LabelScanStatus.failed),
    );
    await _take(tester);
    expect(find.text(LabelSheet.failed), findsOneWidget);
  });
}
