import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/design/app_theme.dart';

void main() {
  for (final Brightness brightness in Brightness.values) {
    testWidgets(
      'a page push fills with the $brightness canvas mid-transition',
      (WidgetTester tester) async {
        final ThemeData theme = appTheme(brightness);
        final GlobalKey<NavigatorState> nav = GlobalKey<NavigatorState>();
        await tester.pumpWidget(
          MaterialApp(navigatorKey: nav, theme: theme, home: const Scaffold()),
        );
        nav.currentState!.push(
          MaterialPageRoute<void>(builder: (_) => const Scaffold()),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        final Iterable<Color> fills = find
            .byType(ColoredBox)
            .evaluate()
            .map((Element e) => (e.widget as ColoredBox).color);
        expect(fills, isNotEmpty);
        expect(fills, everyElement(theme.canvasColor));
      },
    );
  }
}
