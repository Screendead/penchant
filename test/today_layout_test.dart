import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/design/app_theme.dart';
import 'package:tracker/homepage.dart';
import 'package:tracker/providers/offline_provider.dart';
import 'package:tracker/providers/sync_status_provider.dart';
import 'package:tracker/providers/tracker_writes_provider.dart';
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/trends/trends_sheet.dart';
import 'package:tracker/widgets/day_dial.dart';
import 'package:tracker/widgets/day_picker.dart';
import 'package:tracker/widgets/log_fan.dart';
import 'package:tracker/widgets/tally_row.dart';

import 'fake_writes.dart';
import 'fakes.dart';
import 'trends_harness.dart';

// Today on a 390 x 844 pt phone (status bar 47, home indicator 34) is laid
// out to the Day Dial mock-up's measurements, so five habits fit above the
// Log button without scrolling.
void main() {
  final List<Vice> five = <Vice>[for (int i = 0; i < 5; i++) fakeVice('h$i')];

  Future<void> pump(WidgetTester tester) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.padding = const FakeViewPadding(top: 47 * 3, bottom: 34 * 3);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          userProvider.overrideWith((ref) => Stream.value(FakeUser(ownerID))),
          offlineProvider.overrideWith((ref) => Stream.value(false)),
          trackerWritesProvider.overrideWithValue(FakeTrackerWrites()),
          pendingWritesWaiterProvider.overrideWithValue(() async {}),
          ...trendsOverrides(
            five,
            (_) => const AsyncData<List<ViceActivity>>(<ViceActivity>[]),
          ),
        ],
        child: MaterialApp(
          theme: appTheme(Brightness.light),
          home: const Homepage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the blocks sit where the mock-up has them', (
    WidgetTester tester,
  ) async {
    await pump(tester);

    expect(
      tester.getTopLeft(find.byKey(Homepage.menuKey)),
      const Offset(14, 54),
    );
    expect(tester.getRect(find.byType(DayPicker)).top, 104);
    expect(tester.getRect(find.byType(DayPicker)).height, 44);
    expect(
      tester.getRect(find.byType(DayDial)),
      const Rect.fromLTWH(35, 154, 320, 320),
    );
    final List<Rect> rows = <Rect>[
      for (final Element e in find.byType(TallyRow).evaluate())
        tester.getRect(find.byWidget(e.widget)),
    ];
    expect(rows, hasLength(5));
    expect(rows.first.top, 484);
    for (final Rect row in rows) {
      expect(row.height, 38);
    }
    expect(tester.getRect(find.byType(LogButton)).top, 685);
    expect(TrendsSheet.peekHeight(tester.element(find.byType(LogButton))), 127);
  });

  testWidgets('every tally sits above the Log button and its halo', (
    WidgetTester tester,
  ) async {
    await pump(tester);
    final double logTop = tester.getRect(find.byType(LogButton)).top - 6;
    for (final Element e in find.byType(TallyRow).evaluate()) {
      expect(tester.getRect(find.byWidget(e.widget)).bottom, lessThan(logTop));
    }
  });

  testWidgets("the menu's rows are the mock-up's 44 pt", (
    WidgetTester tester,
  ) async {
    await pump(tester);
    await tester.tap(find.byKey(Homepage.menuKey));
    await tester.pumpAndSettle();
    for (final Element e in find.byType(MenuItemButton).evaluate()) {
      expect(tester.getRect(find.byWidget(e.widget)).height, 44);
    }
    expect(find.byType(MenuItemButton), findsNWidgets(3));
    final Rect card = tester.getRect(
      find
          .ancestor(
            of: find.byType(MenuItemButton).first,
            matching: find.byType(Container),
          )
          .first,
    );
    expect(card.topLeft, const Offset(15, 100));
  });
}
