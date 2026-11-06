import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/design/app_theme.dart';
import 'package:tracker/design/dial_theme.dart';
import 'package:tracker/widgets/circle_button.dart';

void main() {
  for (final Brightness brightness in Brightness.values) {
    testWidgets('a circle button keeps its line at rest and takes the accent '
        'ring when focused ($brightness)', (WidgetTester tester) async {
      final FocusNode focus = FocusNode();
      addTearDown(focus.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(brightness),
          home: Scaffold(
            body: Center(
              child: CircleButton(
                icon: Icons.keyboard_arrow_down,
                tooltip: 'Close',
                focusNode: focus,
                onPressed: () {},
              ),
            ),
          ),
        ),
      );
      final BuildContext context = tester.element(find.byType(CircleButton));
      final ColorScheme scheme = Theme.of(context).colorScheme;
      BorderSide edge() =>
          (tester
                      .widget<Material>(
                        find.descendant(
                          of: find.byType(IconButton),
                          matching: find.byType(Material),
                        ),
                      )
                      .shape!
                  as OutlinedBorder)
              .side;

      expect(edge().color, DialColors.of(context).line);

      focus.requestFocus();
      await tester.pumpAndSettle();
      expect(edge().color, scheme.primary);
      expect(edge().width, 2);
    });
  }
}
