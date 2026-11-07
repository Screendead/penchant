import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/account/account_copy.dart';
import 'package:tracker/account/guest_expiry.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/providers/offline_provider.dart';
import 'package:tracker/providers/today_provider.dart';
import 'package:tracker/providers/tracker_writes_provider.dart';
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/providers/vice_activity_day_provider.dart';
import 'package:tracker/vice_tracker.dart';
import 'package:tracker/widgets/guest_expiry_banner.dart';

import 'fake_writes.dart';
import 'fakes.dart';

class _FixedToday extends Today {
  _FixedToday(this._day);

  final DateTime _day;

  @override
  DateTime build() => _day;
}

void main() {
  group('GuestExpiry', () {
    test('counts 30 days from creation, or from when clean-up began', () {
      final DateTime late = DateTime.utc(2026, 12, 1, 10);
      expect(GuestExpiry.eraseFrom(late), DateTime.utc(2026, 12, 31, 10));
      final DateTime early = DateTime.utc(2026, 10, 1);
      expect(GuestExpiry.eraseFrom(early), DateTime.utc(2026, 12, 7));
    });

    test('days left are local days from today to the erase day', () {
      final DateTime created = DateTime(2027, 1, 1, 12);
      expect(GuestExpiry.daysLeft(created, DateTime(2027, 1, 1)), 30);
      expect(GuestExpiry.daysLeft(created, DateTime(2027, 1, 21)), 10);
      expect(GuestExpiry.daysLeft(created, DateTime(2027, 1, 31)), 0);
      expect(GuestExpiry.daysLeft(created, DateTime(2027, 2, 2)), -2);
    });

    ProviderContainer container(FakeUser? user, DateTime today) {
      final ProviderContainer c = ProviderContainer(
        overrides: <Override>[
          userProfileProvider.overrideWith((ref) => Stream.value(user)),
          todayProvider.overrideWith(() => _FixedToday(today)),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('the provider counts down for a guest alone', () async {
      final DateTime created = DateTime(2027, 1, 1, 12);
      final DateTime today = DateTime(2027, 1, 21);
      for (final (FakeUser? user, int? expected) in <(FakeUser?, int?)>[
        (FakeUser('g', email: null, isAnonymous: true, created: created), 10),
        (FakeUser('m', created: created), null),
        (null, null),
      ]) {
        final ProviderContainer c = container(user, today);
        c.listen(guestDaysLeftProvider, (_, _) {});
        await c.read(userProfileProvider.future);
        expect(c.read(guestDaysLeftProvider), expected);
      }
    });
  });

  group('Today warns a guest', () {
    final List<String> pushed = <String>[];

    setUp(pushed.clear);

    List<Override> overrides(int? daysLeft) => <Override>[
      ...habitOverrides(<Vice>[fakeVice('coffee')]),
      userProvider.overrideWith((ref) => Stream.value(FakeUser(ownerID))),
      offlineProvider.overrideWith((ref) => Stream.value(false)),
      trackerWritesProvider.overrideWithValue(FakeTrackerWrites()),
      memoryJournal(),
      viceActivityDayProvider.overrideWith(
        (ref, DateTime day) => const AsyncData([]),
      ),
      guestDaysLeftProvider.overrideWithValue(daysLeft),
    ];

    Future<void> pump(WidgetTester tester, int? daysLeft) async {
      tester.view.physicalSize = Size(
        tester.view.physicalSize.width,
        1000 * tester.view.devicePixelRatio,
      );
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(
        ProviderScope(
          overrides: overrides(daysLeft),
          child: MaterialApp(
            home: const Scaffold(body: ViceTracker()),
            onGenerateRoute: (RouteSettings settings) {
              pushed.add(settings.name!);
              return MaterialPageRoute<void>(
                builder: (_) => const Scaffold(body: Text('account')),
              );
            },
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
    }

    testWidgets('not before day 20, nor once saved', (tester) async {
      for (final int? days in <int?>[11, 30, null]) {
        await pump(tester, days);
        expect(find.byType(GuestExpiryBanner), findsNothing);
        expect(find.byType(GuestExpirySheet), findsNothing);
      }
    });

    testWidgets('from day 20 a banner leads to linking', (tester) async {
      await pump(tester, 10);
      expect(find.text(AccountCopy.guestExpiry(10)), findsOneWidget);
      expect(
        AccountCopy.guestExpiry(10),
        'Your guest journal will be erased in 10 days. Save it to an email '
        'to keep it.',
      );
      expect(find.byType(GuestExpirySheet), findsNothing);
      await tester.tap(find.text(AccountCopy.guestExpiryAction));
      await tester.pumpAndSettle();
      expect(pushed, <String>['/settings/account']);
    });

    testWidgets('in the last 3 days a sheet blocks Today', (tester) async {
      await pump(tester, 3);
      await tester.pumpAndSettle();
      expect(find.byType(GuestExpirySheet), findsOneWidget);
      // Neither the barrier nor a drag closes it.
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(find.byType(GuestExpirySheet), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byType(GuestExpirySheet),
          matching: find.text(AccountCopy.guestExpiryAction),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(GuestExpirySheet), findsNothing);
      expect(pushed, <String>['/settings/account']);
    });

    testWidgets('Not now closes it for the day', (tester) async {
      await pump(tester, 1);
      await tester.pumpAndSettle();
      await tester.tap(find.text(AccountCopy.guestExpiryLater));
      await tester.pumpAndSettle();
      expect(find.byType(GuestExpirySheet), findsNothing);
      expect(pushed, isEmpty);
      expect(find.byType(GuestExpiryBanner), findsOneWidget);
    });

    test('the copy past the deadline and on its eve', () {
      expect(AccountCopy.guestExpiry(1), contains('in 1 day.'));
      expect(AccountCopy.guestExpiry(0), contains('at any moment'));
      expect(AccountCopy.guestExpiry(-3), contains('at any moment'));
    });
  });
}
