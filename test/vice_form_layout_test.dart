import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/design/app_theme.dart';
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/vice_form.dart';

import 'fakes.dart';

void main() {
  // An iPhone on its side with the keyboard up leaves the form well under
  // the 200 pt its fields take; it must scroll, not overflow.
  testWidgets('Add Habit scrolls rather than overflows above the keyboard', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(874, 402) * 3;
    tester.view.viewInsets = const FakeViewPadding(bottom: 210 * 3);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          userProvider.overrideWith((ref) => Stream.value(FakeUser('u'))),
        ],
        child: MaterialApp(
          theme: appTheme(Brightness.light),
          home: const ViceForm(),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Habit Name'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Category'),
      50,
      scrollable: find.byType(Scrollable).first,
    );
    expect(tester.takeException(), isNull);
  });
}
