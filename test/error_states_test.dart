import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/account/account_copy.dart';
import 'package:tracker/account_settings.dart';
import 'package:tracker/authenticate.dart';
import 'package:tracker/bootstrap.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/errors/firestore_errors.dart';
import 'package:tracker/errors/report_error.dart';
import 'package:tracker/main.dart';
import 'package:tracker/manage_data.dart';
import 'package:tracker/providers/account_provider.dart';
import 'package:tracker/providers/firestore_retry.dart';
import 'package:tracker/providers/offline_provider.dart';
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/providers/vice_activity_day_provider.dart';
import 'package:tracker/providers/vice_activity_history_provider.dart';
import 'package:tracker/providers/vice_list_provider.dart';
import 'package:tracker/vice_activity_editor_page.dart';
import 'package:tracker/vice_activity_history_page.dart';
import 'package:tracker/vice_tracker.dart';
import 'package:tracker/vice_form.dart';
import 'package:tracker/widgets/record_new_activity_dialog.dart';

import 'fake_account.dart';
import 'fakes.dart';
import 'trends_harness.dart';

FirebaseException _firestoreError(String code) => FirebaseException(
  plugin: 'cloud_firestore',
  code: code,
  message: 'Firestore says $code about /activities/some-document',
);

final FirebaseException _denied = _firestoreError('permission-denied');

// The first listen fails with [error]; every later one delivers [data].
class _FailsOnce<T> {
  _FailsOnce(this.error, this.data);

  final Object error;
  final T data;
  int listens = 0;

  Stream<T> listen() {
    listens++;
    return listens == 1 ? Stream<T>.error(error) : Stream<T>.value(data);
  }
}

final Finder _retry = find.widgetWithText(TextButton, 'Retry');

Future<void> _pump(
  WidgetTester tester,
  List<Override> overrides,
  Widget home,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        userProvider.overrideWith((ref) => Stream.value(FakeUser(ownerID))),
        offlineProvider.overrideWithValue(const AsyncData(false)),
        ...overrides,
      ],
      child: MaterialApp(home: home),
    ),
  );
  await tester.pump();
  await tester.pump();
}

// Riverpod retries a failed provider by default; a denied read must wait for
// Retry instead, so time passing alone opens no second listener.
Future<void> _expectNoAutomaticRetry(
  WidgetTester tester,
  _FailsOnce<Object?> source,
) async {
  await tester.pump(const Duration(seconds: 10));
  expect(source.listens, 1);
}

Future<void> _tapRetry(WidgetTester tester) async {
  await tester.tap(_retry);
  await tester.pump();
  await tester.pump();
}

void main() {
  final Vice coffee = fakeVice('coffee');

  group('startup', () {
    testWidgets('shows a spinner while Firebase starts, not an error', (
      WidgetTester tester,
    ) async {
      final Completer<void> started = Completer<void>();
      await tester.pumpWidget(
        Bootstrap(
          initialize: () => started.future,
          child: const MaterialApp(home: Text('ready')),
        ),
      );
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text(Bootstrap.failedMessage), findsNothing);

      started.complete();
      await tester.pump();

      expect(find.text('ready'), findsOneWidget);
    });

    testWidgets('a failed start shows an error with a retry that starts '
        'again', (WidgetTester tester) async {
      int attempts = 0;
      await tester.pumpWidget(
        Bootstrap(
          initialize: () async {
            attempts++;
            if (attempts == 1) {
              throw FirebaseException(plugin: 'core', code: 'no-app');
            }
          },
          child: const MaterialApp(home: Text('ready')),
        ),
      );
      await tester.pump();

      expect(find.text(Bootstrap.failedMessage), findsOneWidget);
      expect(find.text('ready'), findsNothing);

      await tester.tap(_retry);
      await tester.pump();
      await tester.pump();

      expect(attempts, 2);
      expect(find.text('ready'), findsOneWidget);
    });

    testWidgets('a failed start is written to the device log', (
      WidgetTester tester,
    ) async {
      final List<String> logged = <String>[];
      final void Function(String?, {int? wrapWidth}) original = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) =>
          logged.add('$message');
      try {
        await tester.pumpWidget(
          Bootstrap(
            initialize: () async => throw StateError('bad options'),
            child: const SizedBox(),
          ),
        );
        await tester.pump();
      } finally {
        debugPrint = original;
      }

      final String log = logged.join('\n');
      expect(log, contains('while starting Firebase'));
      expect(log, contains('bad options'));
    });
  });

  group('the sign-in state', () {
    testWidgets('an auth stream error shows an error with a retry, not the '
        'sign-in screen', (WidgetTester tester) async {
      final _FailsOnce<User?> auth = _FailsOnce<User?>(
        FirebaseAuthException(code: 'internal-error'),
        null,
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            userProvider.overrideWith((ref) => auth.listen()),
            accountProvider.overrideWithValue(FakeAccount()),
          ],
          child: const MyApp(),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text(AuthStateFailure.message), findsOneWidget);
      expect(find.byType(Authenticate), findsNothing);

      await _tapRetry(tester);

      expect(auth.listens, 2);
      expect(find.byType(Authenticate), findsOneWidget);
    });
  });

  group('Today', () {
    testWidgets('a failed vice list shows a readable error, not a spinner, and '
        'Retry listens again', (WidgetTester tester) async {
      final _FailsOnce<List<Vice>> vices = _FailsOnce<List<Vice>>(_denied, [
        coffee,
      ]);
      await _pump(tester, [
        viceListForUserProvider.overrideWith((ref, uid) => vices.listen()),
        viceActivityDayForUserProvider.overrideWith(
          (ref, key) => Stream.value(<ViceActivity>[]),
        ),
      ], const Scaffold(body: ViceTracker()));

      expect(find.text(loadErrorMessage('this day', _denied)), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.textContaining('/activities/'), findsNothing);
      await _expectNoAutomaticRetry(tester, vices);

      await _tapRetry(tester);

      expect(vices.listens, 2);
      expect(find.text(loadErrorMessage('this day', _denied)), findsNothing);
    });

    testWidgets("a failed day's query shows the error", (
      WidgetTester tester,
    ) async {
      final _FailsOnce<List<ViceActivity>> day = _FailsOnce<List<ViceActivity>>(
        _denied,
        <ViceActivity>[],
      );
      await _pump(tester, [
        viceListForUserProvider.overrideWith(
          (ref, uid) => Stream.value([coffee]),
        ),
        viceActivityDayForUserProvider.overrideWith((ref, key) => day.listen()),
      ], const Scaffold(body: ViceTracker()));

      expect(find.text(loadErrorMessage('this day', _denied)), findsOneWidget);

      await _tapRetry(tester);

      expect(day.listens, 2);
      expect(find.text(loadErrorMessage('this day', _denied)), findsNothing);
    });
  });

  group('the Trends sheet', () {
    testWidgets("a failed range query shows the error in the chart's place", (
      WidgetTester tester,
    ) async {
      final _FailsOnce<List<ViceActivity>> range =
          _FailsOnce<List<ViceActivity>>(_denied, <ViceActivity>[]);
      await _pump(tester, [
        ...habitOverrides([coffee]),
        viceActivityDayProvider.overrideWith(
          (ref, DateTime day) => const AsyncData(<ViceActivity>[]),
        ),
        viceActivityGraphForUserProvider.overrideWith(
          (ref, key) => range.listen(),
        ),
      ], const Scaffold(body: ViceTracker()));
      await openTrends(tester);

      expect(
        find.text(loadErrorMessage('coffee for this range', _denied)),
        findsOneWidget,
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);

      await _tapRetry(tester);

      expect(range.listens, 2);
      expect(find.text('No entries for coffee in this range'), findsOneWidget);
    });
  });

  group('Manage Data', () {
    testWidgets('a failed vice list shows the error and Retry recovers', (
      WidgetTester tester,
    ) async {
      final _FailsOnce<List<Vice>> vices = _FailsOnce<List<Vice>>(
        _denied,
        <Vice>[],
      );
      await _pump(tester, [
        viceListForUserProvider.overrideWith((ref, uid) => vices.listen()),
      ], const ManageData());

      expect(
        find.text(loadErrorMessage('your habits', _denied)),
        findsOneWidget,
      );
      await _expectNoAutomaticRetry(tester, vices);

      await _tapRetry(tester);

      expect(find.text('No habits yet. Tap + to add one.'), findsOneWidget);
    });
  });

  group('Edit Habit', () {
    testWidgets('a failed vice list shows the error and Retry opens the form', (
      WidgetTester tester,
    ) async {
      final _FailsOnce<List<Vice>> vices = _FailsOnce<List<Vice>>(_denied, [
        coffee,
      ]);
      await _pump(tester, [
        viceListForUserProvider.overrideWith((ref, uid) => vices.listen()),
      ], EditVice(viceID: coffee.id));

      expect(
        find.text(loadErrorMessage('your habits', _denied)),
        findsOneWidget,
      );

      await _tapRetry(tester);

      expect(find.byType(ViceForm), findsOneWidget);
    });
  });

  group('the history page', () {
    testWidgets('a failed history shows the error, not a spinner, and Retry '
        'recovers', (WidgetTester tester) async {
      final _FailsOnce<List<ViceActivity>> history =
          _FailsOnce<List<ViceActivity>>(_denied, <ViceActivity>[]);
      await _pump(tester, [
        viceListForUserProvider.overrideWith(
          (ref, uid) => Stream.value([coffee]),
        ),
        viceActivityHistoryForUserProvider.overrideWith(
          (ref, key) => history.listen(),
        ),
      ], ViceActivityHistoryPage(viceID: coffee.id));

      expect(
        find.text(loadErrorMessage('this history', _denied)),
        findsOneWidget,
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await _expectNoAutomaticRetry(tester, history);

      await _tapRetry(tester);

      expect(history.listens, 2);
      expect(find.text('No activities found for this habit'), findsOneWidget);
    });

    testWidgets('a list still loading is a spinner, not an error', (
      WidgetTester tester,
    ) async {
      await _pump(tester, [
        viceListProvider.overrideWithValue(const AsyncLoading()),
        viceActivityHistoryProvider.overrideWith(
          (ref, query) => const AsyncLoading(),
        ),
      ], ViceActivityHistoryPage(viceID: coffee.id));

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(_retry, findsNothing);
    });
  });

  group('the activity editor', () {
    final ViceActivity activity = fakeActivity(
      coffee.id,
      2,
      DateTime(2026, 11, 2, 9, 30),
    );

    testWidgets('a failed vice list shows the error and Retry opens the '
        'form', (WidgetTester tester) async {
      final _FailsOnce<List<Vice>> vices = _FailsOnce<List<Vice>>(_denied, [
        coffee,
      ]);
      await _pump(tester, [
        viceListForUserProvider.overrideWith((ref, uid) => vices.listen()),
        viceActivityForUserProvider.overrideWith(
          (ref, key) => Stream.value(activity),
        ),
      ], ViceActivityEditorPage(viceID: coffee.id, activityID: activity.id));

      expect(
        find.text(loadErrorMessage('this activity', _denied)),
        findsOneWidget,
      );

      await _tapRetry(tester);

      expect(find.text('Edit coffee activity'), findsOneWidget);
    });

    testWidgets('an activity read that fails for another reason than a '
        'denial shows the error, not "not found"', (WidgetTester tester) async {
      final FirebaseException index = _firestoreError('failed-precondition');
      await _pump(tester, [
        viceListForUserProvider.overrideWith(
          (ref, uid) => Stream.value([coffee]),
        ),
        viceActivityForUserProvider.overrideWith(
          (ref, key) => Stream<ViceActivity?>.error(index),
        ),
      ], ViceActivityEditorPage(viceID: coffee.id, activityID: activity.id));

      expect(
        find.text(loadErrorMessage('this activity', index)),
        findsOneWidget,
      );
      expect(find.text('Activity not found'), findsNothing);
    });
  });

  group('the record dialog', () {
    testWidgets('a failed vice list shows the error with Cancel, and Retry '
        'shows the form', (WidgetTester tester) async {
      final _FailsOnce<List<Vice>> vices = _FailsOnce<List<Vice>>(_denied, [
        coffee,
      ]);
      await _pump(tester, [
        viceListForUserProvider.overrideWith((ref, uid) => vices.listen()),
      ], const Scaffold(body: RecordNewActivityDialog()));

      expect(
        find.text(loadErrorMessage('your habits', _denied)),
        findsOneWidget,
      );
      expect(find.widgetWithText(TextButton, 'Cancel'), findsOneWidget);

      await _tapRetry(tester);

      expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
    });
  });

  group('Account Settings', () {
    testWidgets('a failed profile stream shows the error and Retry shows the '
        'form', (WidgetTester tester) async {
      final _FailsOnce<User?> profile = _FailsOnce<User?>(
        FirebaseAuthException(code: 'internal-error'),
        FakeUser(ownerID),
      );
      await _pump(tester, [
        userProfileProvider.overrideWith((ref) => profile.listen()),
        accountProvider.overrideWithValue(FakeAccount()),
      ], const AccountSettings());

      expect(find.text(AccountCopy.profileLoadFailed), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      await _tapRetry(tester);

      expect(profile.listens, 2);
      expect(find.text('Update Profile'), findsOneWidget);
    });
  });

  group('error copy', () {
    test("never shows Firestore's own message", () {
      for (final String code in <String>[
        'permission-denied',
        'unavailable',
        'failed-precondition',
        'internal',
      ]) {
        expect(
          firestoreErrorMessage(_firestoreError(code)),
          isNot(contains('Firestore says')),
        );
      }
      expect(
        firestoreErrorMessage(TypeError()),
        'Something went wrong. Try again.',
      );
    });
  });

  group('retry policy', () {
    test('a denied, unauthenticated or index-less read is not retried', () {
      for (final String code in <String>[
        'permission-denied',
        'unauthenticated',
        'failed-precondition',
      ]) {
        expect(firestoreRetry(0, _firestoreError(code)), isNull);
      }
    });

    test('a transient failure is retried with backoff', () {
      expect(
        firestoreRetry(0, _firestoreError('unavailable')),
        const Duration(milliseconds: 200),
      );
      expect(firestoreRetry(10, _firestoreError('unavailable')), isNull);
    });
  });

  group('the provider error log', () {
    testWidgets('writes each failed provider to the device log', (
      WidgetTester tester,
    ) async {
      final List<String> logged = <String>[];
      final void Function(String?, {int? wrapWidth}) original = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) =>
          logged.add('$message');
      final ProviderContainer container = ProviderContainer(
        observers: const [ReportProviderErrors()],
        overrides: [
          viceListForUserProvider.overrideWith(
            (ref, uid) => Stream<List<Vice>>.error(_denied),
          ),
        ],
      );
      try {
        final ProviderSubscription<AsyncValue<List<Vice>>> subscription =
            container.listen(viceListForUserProvider(ownerID), (_, _) {});
        await tester.pump();
        subscription.close();
      } finally {
        container.dispose();
        debugPrint = original;
      }

      expect(logged.join('\n'), contains('in StreamProvider'));
      expect(logged.join('\n'), contains('permission-denied'));
    });
  });
}
