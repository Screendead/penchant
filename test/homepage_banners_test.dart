import 'package:firebase_core/firebase_core.dart';
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
import 'package:tracker/vice_tracker.dart';
import 'package:tracker/widgets/day_picker.dart';
import 'package:tracker/widgets/rejected_writes_banner.dart';
import 'package:tracker/widgets/sync_status.dart';
import 'package:tracker/writes/rejected_writes.dart';

import 'fake_writes.dart';
import 'fakes.dart';
import 'trends_harness.dart';

// Today on a 402 x 874 pt phone (status bar 62, home indicator 34) with both
// banners up and the largest text: Homepage is a column whose banners sit
// above Today, so a banner that grows with the text must not take Today's
// room.
void main() {
  final List<Vice> three = <Vice>[for (int i = 0; i < 3; i++) fakeVice('h$i')];
  const double height = 874;

  Future<ProviderContainer> pump(WidgetTester tester, double scale) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(402 * 3, height * 3);
    tester.view.padding = const FakeViewPadding(top: 62 * 3, bottom: 34 * 3);
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          userProvider.overrideWith((ref) => Stream.value(FakeUser(ownerID))),
          offlineProvider.overrideWith((ref) => Stream.value(true)),
          trackerWritesProvider.overrideWithValue(FakeTrackerWrites()),
          pendingWritesWaiterProvider.overrideWithValue(() async {}),
          memoryJournal(),
          ...trendsOverrides(
            three,
            (_) => const AsyncData<List<ViceActivity>>(<ViceActivity>[]),
          ),
        ],
        child: MaterialApp(
          theme: appTheme(Brightness.light),
          builder: rejectedWritesBuilder,
          home: const Homepage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(tester.element(find.byType(Homepage)));
  }

  void refuse(ProviderContainer container, int count) {
    for (int i = 0; i < count; i++) {
      container
          .read(rejectedWritesProvider.notifier)
          .reporter('Not saved: coffee $i, 2 drinks, today at 12:00')(
        FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'),
      );
    }
  }

  for (final double scale in <double>[1, 2, 3]) {
    testWidgets('at ${scale}x text the offline banner leaves Today its day '
        'row', (WidgetTester tester) async {
      await pump(tester, scale);
      expect(tester.takeException(), isNull);

      expect(find.text(OfflineBanner.message), findsOneWidget);
      expect(
        tester.getRect(find.byType(OfflineBanner)).height,
        lessThanOrEqualTo(height / 3),
      );
      expect(find.byType(DayPicker).hitTestable(), findsOneWidget);

      await tester.tap(find.byTooltip(DayPicker.chooseDay));
      await tester.pumpAndSettle();
      expect(find.byType(CalendarSheet), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('at ${scale}x text both banners together leave Today room', (
      WidgetTester tester,
    ) async {
      final ProviderContainer container = await pump(tester, scale);
      refuse(container, 4);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      expect(
        tester.getRect(find.byType(OfflineBanner)).height,
        lessThanOrEqualTo(height / 3),
      );
      // Its third of the screen, under the status bar.
      expect(
        tester.getRect(find.byType(RejectedWritesBanner)).height,
        lessThanOrEqualTo(height / 3 + 62),
      );
      expect(tester.getRect(find.byType(ViceTracker)).height, greaterThan(0));
    });
  }
}
