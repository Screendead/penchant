import 'dart:math';

import 'package:clock/clock.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tracker/account/account.dart';
import 'package:tracker/account/export.dart';
import 'package:tracker/data/check_in.dart';
import 'package:tracker/data/sealed.dart';
import 'package:tracker/design/app_theme.dart';
import 'package:tracker/providers/tracker_writes_provider.dart';
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/reminder/check_ins.dart';
import 'package:tracker/reminder/daily_nudge.dart';
import 'package:tracker/widgets/check_in_sheet.dart';

import 'fake_writes.dart';
import 'fakes.dart';

class FakeCheckInScheduler implements NudgeScheduler {
  bool grant = true;
  List<CheckInPrompt> scheduled = <CheckInPrompt>[];
  int cancelled = 0;
  final List<String> withdrawn = <String>[];

  @override
  Future<void> scheduleCheckIns(List<CheckInPrompt> prompts) async =>
      scheduled = List<CheckInPrompt>.of(prompts);

  @override
  Future<void> cancelCheckIns() async {
    cancelled++;
    scheduled = <CheckInPrompt>[];
  }

  @override
  Future<void> withdrawCheckIn(String id) async => withdrawn.add(id);

  @override
  Future<bool> requestPermission() async => grant;

  @override
  Future<bool> isPermitted() async => grant;

  @override
  Future<NudgeTap?> launchAction() async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}

const CheckInWindow _window = CheckInWindow(
  TimeOfDay(hour: 9, minute: 0),
  TimeOfDay(hour: 21, minute: 0),
);

void main() {
  group('drawing', () {
    test('one moment in each third of the window, every day', () {
      final Random random = Random(7);
      for (int d = 0; d < 400; d++) {
        final DateTime day = DateTime(2026, 1, 1 + d);
        final List<DateTime> times = drawCheckInTimes(day, _window, random);
        expect(times, hasLength(checkInsPerDay));
        for (int i = 0; i < times.length; i++) {
          final DateTime blockStart = DateTime(
            day.year,
            day.month,
            day.day,
            9 + i * 4,
          );
          expect(times[i].isBefore(blockStart), isFalse);
          expect(
            times[i].isBefore(blockStart.add(const Duration(hours: 4))),
            isTrue,
          );
        }
      }
    });

    test('is spread across each block, not bunched at its start', () {
      final Random random = Random(11);
      final List<int> minutesIn = <int>[
        for (int d = 0; d < 600; d++)
          drawCheckInTimes(
                DateTime(2026, 3, 1 + d),
                _window,
                random,
              ).first.difference(DateTime(2026, 3, 1 + d, 9)).inMinutes ~/
              60,
      ];
      for (int hour = 0; hour < 4; hour++) {
        final int n = minutesIn.where((int m) => m == hour).length;
        expect(n, inInclusiveRange(100, 200), reason: 'hour $hour: $n');
      }
    });

    test('a window under three hours is refused', () {
      expect(
        const CheckInWindow(
          TimeOfDay(hour: 21, minute: 0),
          TimeOfDay(hour: 9, minute: 0),
        ).valid,
        isFalse,
      );
      expect(
        const CheckInWindow(
          TimeOfDay(hour: 9, minute: 0),
          TimeOfDay(hour: 11, minute: 59),
        ).valid,
        isFalse,
      );
      expect(_window.valid, isTrue);
    });
  });

  group('the notification', () {
    final CheckInPrompt prompt = CheckInPrompt(
      id: 'abc123',
      at: DateTime(2026, 11, 16, 14, 7, 33),
      notificationId: 5004,
    );

    test('its payload carries only the answer id and the prompt time', () {
      final String payload = checkInPayload(prompt);
      expect(payload, 'check-in:abc123:${prompt.at.millisecondsSinceEpoch}');
      expect(checkInOfPayload(payload), (id: 'abc123', promptedAt: prompt.at));
      expect(urgeOfPayload(payload), isNull);
      expect(checkInOfPayload(urgePayload('u1')), isNull);
      expect(CheckInPrompt.decode(prompt.encode()), prompt);
    });

    test('a button is the answer; a tap on the body opens the sheet', () {
      final String payload = checkInPayload(prompt);
      final NudgeTap? three = nudgeTapFor(checkInActionId(3), payload: payload);
      expect(three?.action, NudgeAction.checkInAnswer);
      expect(three?.checkInStrength, 3);
      expect(three?.checkIn?.id, 'abc123');
      expect(
        nudgeTapFor(checkInActionId(0), payload: payload)?.checkInStrength,
        0,
      );
      final NudgeTap? body = nudgeTapFor(null, payload: payload);
      expect(body?.action, NudgeAction.checkIn);
      expect(body?.checkInStrength, isNull);
      expect(
        nudgeTapFor('check-in-6', payload: payload)?.checkInStrength,
        null,
      );
    });

    test('its words name no habit', () {
      expect(NudgeCopy.checkInBody, 'Any urge right now?');
      expect(
        <String>[for (int n = 0; n <= 5; n++) NudgeCopy.checkInAnswer(n)],
        <String>['0 · none', '1', '2', '3', '4', '5 · couldn’t not'],
      );
    });
  });

  group('content', () {
    test('round-trips, and every field is a sealed one', () {
      final DateTime at = DateTime(2026, 11, 16, 14, 7);
      final CheckInContent c = CheckInContent(
        strength: 0,
        promptedAt: at,
        zone: 'Europe/London',
        via: CheckInVia.notification,
      );
      final CheckInContent back = CheckInContent.read(c.toMap());
      expect(back.strength, 0);
      expect(back.promptedAt, at);
      expect(back.zone, 'Europe/London');
      expect(back.via, CheckInVia.notification);
      expect(c.toMap().keys, everyElement(isIn(checkInContentFields)));
      expect(bornSealedCollections, contains(checkInsCollection));
    });

    test('reads out-of-range or mistyped values as absent', () {
      for (final Object? v in <Object?>[-1, 6, '3', 2.0, null]) {
        expect(
          CheckInContent.read(<String, Object?>{'strength': v}).strength,
          isNull,
        );
      }
      expect(
        CheckInContent.read(const <String, Object?>{'answeredVia': 'x'}).via,
        isNull,
      );
    });
  });

  test('the export lists check-ins oldest first', () {
    final AccountData data = AccountData(
      vices: const <StoredDocument>[],
      activities: const <StoredDocument>[],
      checkIns: <StoredDocument>[
        (
          id: 'b',
          data: <String, dynamic>{
            'createdAt': Timestamp.fromDate(DateTime.utc(2026, 11, 15, 14)),
            'strength': 2,
            'answeredVia': 'sheet',
          },
        ),
        (
          id: 'a',
          data: <String, dynamic>{
            'createdAt': Timestamp.fromDate(DateTime.utc(2026, 11, 14, 9)),
            'strength': 0,
            'promptedAt': DateTime.utc(
              2026,
              11,
              14,
              8,
              55,
            ).millisecondsSinceEpoch,
            'answeredVia': 'notification',
          },
        ),
      ],
    );
    final List<String> lines = exportCheckInsCsv(data).trim().split('\n');
    expect(lines.first.trim(), checkInsCsvHeader.join(','));
    expect(
      lines[1].trim(),
      '2026-11-14T09:00:00.000Z,a,0,2026-11-14T08:55:00.000Z,notification,',
    );
    expect(lines[2], contains(',b,2,,sheet'));
    expect(
      exportFiles(
        data,
        DateTime.utc(2026, 11, 16),
      ).map((ExportFile f) => f.name),
      contains('penchant-check-ins-2026-11-16.csv'),
    );
  });

  group('scheduling', () {
    late FakeCheckInScheduler scheduler;
    late ProviderContainer container;

    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      scheduler = FakeCheckInScheduler();
      container = ProviderContainer(
        overrides: <Override>[
          nudgeSchedulerProvider.overrideWithValue(scheduler),
          checkInRandomProvider.overrideWithValue(Random(3)),
        ],
      );
      addTearDown(container.dispose);
    });

    CheckIns notifier() => container.read(checkInsProvider.notifier);

    test('off by default, asking for nothing', () async {
      await notifier().topUp();
      expect(container.read(checkInsProvider).enabled, isFalse);
      expect(scheduler.scheduled, isEmpty);
    });

    test('a refusal leaves it off', () async {
      scheduler.grant = false;
      expect(await notifier().turnOn(), isFalse);
      expect(container.read(checkInsProvider).enabled, isFalse);
      expect(scheduler.scheduled, isEmpty);
    });

    test('turning on draws five days ahead, all inside the window', () async {
      final DateTime now = DateTime(2026, 11, 16, 7);
      await withClock(Clock.fixed(now), () async {
        expect(await notifier().turnOn(), isTrue);
      });
      expect(scheduler.scheduled, hasLength(checkInsPerDay * checkInDaysAhead));
      for (final CheckInPrompt p in scheduler.scheduled) {
        expect(p.at.isAfter(now), isTrue);
        expect(p.at.hour, inInclusiveRange(9, 20));
        expect(
          p.notificationId,
          inInclusiveRange(
            checkInNoticeBase,
            checkInNoticeBase + checkInNoticeCount - 1,
          ),
        );
      }
      expect(
        scheduler.scheduled.map((CheckInPrompt p) => p.id).toSet(),
        hasLength(scheduler.scheduled.length),
      );
    });

    test(
      'a later launch adds days and never redraws a waiting prompt',
      () async {
        await withClock(Clock.fixed(DateTime(2026, 11, 16, 7)), () async {
          await notifier().turnOn();
        });
        final List<CheckInPrompt> first = scheduler.scheduled;
        // Same day, later: nothing new to draw, nothing redrawn.
        await withClock(Clock.fixed(DateTime(2026, 11, 16, 8)), () async {
          await notifier().topUp();
        });
        expect(scheduler.scheduled, first);
        // Two days on: the passed prompts go, the waiting ones stay, two days
        // are added.
        final DateTime later = DateTime(2026, 11, 18, 6);
        await withClock(Clock.fixed(later), () async {
          await notifier().topUp();
        });
        final List<CheckInPrompt> kept = first
            .where((CheckInPrompt p) => p.at.isAfter(later))
            .toList();
        expect(scheduler.scheduled.take(kept.length), kept);
        expect(
          scheduler.scheduled,
          hasLength(checkInsPerDay * checkInDaysAhead),
        );
        expect(
          scheduler.scheduled.last.at.isAfter(DateTime(2026, 11, 22)),
          isTrue,
        );
      },
    );

    test('turning on mid-day draws only what is still ahead today', () async {
      final DateTime now = DateTime(2026, 11, 16, 20, 59);
      await withClock(Clock.fixed(now), () async {
        await notifier().turnOn();
      });
      expect(
        scheduler.scheduled.every((CheckInPrompt p) => p.at.isAfter(now)),
        isTrue,
      );
      expect(
        scheduler.scheduled.length,
        lessThanOrEqualTo(checkInsPerDay * checkInDaysAhead),
      );
    });

    test('a new window redraws; a short one is refused', () async {
      await withClock(Clock.fixed(DateTime(2026, 11, 16, 7)), () async {
        await notifier().turnOn();
        expect(
          await notifier().setWindow(
            const CheckInWindow(
              TimeOfDay(hour: 10, minute: 0),
              TimeOfDay(hour: 12, minute: 0),
            ),
          ),
          isFalse,
        );
        expect(container.read(checkInsProvider).window, _window);
        expect(
          await notifier().setWindow(
            const CheckInWindow(
              TimeOfDay(hour: 12, minute: 0),
              TimeOfDay(hour: 18, minute: 0),
            ),
          ),
          isTrue,
        );
      });
      for (final CheckInPrompt p in scheduler.scheduled) {
        expect(p.at.hour, inInclusiveRange(12, 17));
      }
    });

    test('turning off and signing out withdraw every prompt', () async {
      await withClock(Clock.fixed(DateTime(2026, 11, 16, 7)), () async {
        await notifier().turnOn();
      });
      await notifier().turnOff();
      expect(scheduler.scheduled, isEmpty);
      expect(scheduler.cancelled, 1);
      await withClock(Clock.fixed(DateTime(2026, 11, 16, 7)), () async {
        await notifier().turnOn();
      });
      await notifier().forget();
      expect(scheduler.scheduled, isEmpty);
      expect(container.read(checkInsProvider), CheckInSettings.off);
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getKeys().where((String k) => k.startsWith('checkIns.')),
        isEmpty,
      );
    });

    test('a press heard twice is answered once', () {
      final PendingCheckInNotifier pending = container.read(
        pendingCheckInProvider.notifier,
      );
      final DateTime at = DateTime(2026, 11, 16, 14);
      pending.request('x', at, strength: 2);
      expect(container.read(pendingCheckInProvider)?.strength, 2);
      pending.clear();
      pending.request('x', at, strength: 2);
      expect(container.read(pendingCheckInProvider), isNull);
    });
  });

  group('the sheet', () {
    Future<(FakeTrackerWrites, FakeCheckInScheduler)> pump(
      WidgetTester tester,
    ) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final FakeTrackerWrites writes = FakeTrackerWrites();
      final FakeCheckInScheduler scheduler = FakeCheckInScheduler();
      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            userProvider.overrideWith((ref) => Stream.value(FakeUser(ownerID))),
            trackerWritesProvider.overrideWithValue(writes),
            nudgeSchedulerProvider.overrideWithValue(scheduler),
            memoryJournal(),
          ],
          child: MaterialApp(
            theme: appTheme(Brightness.light),
            home: Scaffold(
              body: Consumer(
                builder: (BuildContext context, WidgetRef ref, _) {
                  ref.watch(userProvider);
                  return Center(
                    child: TextButton(
                      onPressed: () => CheckInSheet.show(
                        context,
                        checkInID: 'abc',
                        promptedAt: DateTime(2026, 11, 16, 14, 7),
                      ),
                      child: const Text('open'),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return (writes, scheduler);
    }

    testWidgets('one tap answers, names no habit, and offers Undo', (
      WidgetTester tester,
    ) async {
      final (FakeTrackerWrites writes, FakeCheckInScheduler scheduler) =
          await pump(tester);
      expect(find.text(CheckInSheet.question), findsOneWidget);
      expect(find.bySemanticsLabel('0, no urge'), findsOneWidget);
      for (int n = 0; n <= 5; n++) {
        final Size size = tester.getSize(find.byKey(CheckInSheet.keyFor(n)));
        expect(size.height, greaterThanOrEqualTo(44));
        expect(size.width, greaterThanOrEqualTo(44));
      }
      await tester.tap(find.byKey(CheckInSheet.keyFor(0)));
      await tester.pumpAndSettle();
      expect(find.text(CheckInSheet.question), findsNothing);
      final Write write = writes.writes.single;
      expect(write.op, 'recordCheckIn');
      expect(write.id, 'abc');
      expect(write.fields['strength'], 0);
      expect(write.fields['answeredVia'], 'sheet');
      expect(scheduler.withdrawn, <String>['abc']);
      expect(find.textContaining('Check-in noted'), findsOneWidget);
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(writes.writes.last.op, 'deleteCheckIn');
    });

    testWidgets('without the journal key nothing is written', (
      WidgetTester tester,
    ) async {
      final (FakeTrackerWrites writes, _) = await pump(tester);
      writes.canCreate = false;
      await tester.tap(find.byKey(CheckInSheet.keyFor(4)));
      await tester.pumpAndSettle();
      expect(writes.writes, isEmpty);
      expect(find.textContaining('Not saved.'), findsOneWidget);
    });

    testWidgets('Turn off check-ins turns them off from the sheet', (
      WidgetTester tester,
    ) async {
      final (_, FakeCheckInScheduler scheduler) = await pump(tester);
      await tester.tap(find.byKey(CheckInSheet.turnOffKey));
      await tester.pumpAndSettle();
      expect(scheduler.cancelled, 1);
      expect(find.text(CheckInSheet.turnedOffMessage), findsOneWidget);
    });
  });
}
