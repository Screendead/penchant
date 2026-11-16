import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
import 'package:tracker/design/app_theme.dart';
import 'package:tracker/insights/experiment.dart';
import 'package:tracker/main.dart';
import 'package:tracker/providers/package_info_provider.dart';
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/reminder/check_ins.dart';
import 'package:tracker/reminder/daily_nudge.dart';
import 'package:tracker/reminder/heavy_day.dart';
import 'package:tracker/reminder/heavy_day_nudge.dart';
import 'package:tracker/reminder_settings.dart';
import 'package:tracker/settings.dart';

class _FakeScheduler implements NudgeScheduler {
  _FakeScheduler({this.grant = true, this.launched}) : permitted = grant;

  final bool grant;
  final NudgeTap? launched;
  bool permitted;
  void Function(NudgeTap tap)? onAction;
  int permissionRequests = 0;
  final List<TimeOfDay> scheduled = <TimeOfDay>[];
  int cancels = 0;

  @override
  Future<void> start(void Function(NudgeTap tap) onTap) async =>
      onAction = onTap;

  @override
  Future<NudgeTap?> launchAction() async => launched;

  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    return grant;
  }

  @override
  Future<bool> isPermitted() async => permitted;

  @override
  Future<void> scheduleDaily(TimeOfDay time) async => scheduled.add(time);

  @override
  Future<void> cancel() async => cancels++;

  int reviewSchedules = 0;
  int reviewCancels = 0;

  @override
  Future<void> scheduleWeeklyReview() async => reviewSchedules++;

  @override
  Future<void> cancelWeeklyReview() async => reviewCancels++;

  @override
  Future<void> scheduleExperiment(List<ExperimentNotice> notices) async {}

  @override
  Future<void> cancelExperiment() async {}

  final List<HeavyPrompt> heavyScheduled = <HeavyPrompt>[];
  int heavyCancels = 0;

  @override
  Future<void> scheduleHeavyDay(HeavyPrompt prompt) async =>
      heavyScheduled.add(prompt);

  @override
  Future<void> cancelHeavyDay() async => heavyCancels++;

  @override
  Future<void> scheduleUrgeCheck(String urgeID, DateTime at) async {}

  @override
  Future<void> cancelUrgeCheck(String urgeID) async {}

  @override
  Future<void> cancelUrgeChecks() async {}

  @override
  Future<void> scheduleCheckIns(List<CheckInPrompt> prompts) async {}

  @override
  Future<void> cancelCheckIns() async {}

  @override
  Future<void> withdrawCheckIn(String id) async {}
}

// The heavy-day row's switch; random check-ins' sits below it.
final Finder _heavySwitch = find.descendant(
  of: find.ancestor(
    of: find.text(ReminderSettings.heavyLabel),
    matching: find.byType(MergeSemantics),
  ),
  matching: find.byType(Switch),
);

Widget _app(_FakeScheduler scheduler, {Widget home = const Settings()}) =>
    ProviderScope(
      overrides: [
        nudgeSchedulerProvider.overrideWithValue(scheduler),
        userProvider.overrideWith((ref) => Stream.value(null)),
        userProfileProvider.overrideWith((ref) => Stream.value(null)),
        packageInfoProvider.overrideWith(
          (ref) async => PackageInfo(
            appName: 'Penchant',
            packageName: 'penchant',
            version: '0.2.0',
            buildNumber: '212',
          ),
        ),
      ],
      child: MaterialApp(
        theme: appTheme(Brightness.light),
        onGenerateRoute: generateRoute,
        home: home,
      ),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  testWidgets('the reminder is off by default and asks nothing until on', (
    WidgetTester tester,
  ) async {
    final _FakeScheduler scheduler = _FakeScheduler();
    await tester.pumpWidget(_app(scheduler));
    await tester.pumpAndSettle();

    expect(find.text('Reminder'), findsOneWidget);
    expect(find.text('Off'), findsOneWidget);

    await tester.tap(find.text('Reminder'));
    await tester.pumpAndSettle();
    expect(find.byType(ReminderSettings), findsOneWidget);
    expect(find.text('9:00 PM'), findsWidgets);
    expect(scheduler.permissionRequests, 0);
    expect(scheduler.scheduled, isEmpty);
  });

  testWidgets('turning it on asks for permission and schedules it daily', (
    WidgetTester tester,
  ) async {
    final _FakeScheduler scheduler = _FakeScheduler();
    await tester.pumpWidget(_app(scheduler));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reminder'));
    await tester.pumpAndSettle();

    await tester.tap(find.text(ReminderSettings.switchLabel));
    await tester.pumpAndSettle();

    expect(scheduler.permissionRequests, 1);
    expect(scheduler.scheduled, <TimeOfDay>[NudgeSettings.defaultTime]);
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(DailyNudge.enabledKey), isTrue);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Off'), findsNothing);
    expect(find.text('9:00 PM'), findsOneWidget);

    await tester.tap(find.text('Reminder'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(ReminderSettings.switchLabel));
    await tester.pumpAndSettle();
    expect(scheduler.cancels, 1);
    expect(prefs.getBool(DailyNudge.enabledKey), isFalse);
  });

  testWidgets('a refused permission leaves it off and says where to go', (
    WidgetTester tester,
  ) async {
    final _FakeScheduler scheduler = _FakeScheduler(grant: false);
    await tester.pumpWidget(_app(scheduler, home: const ReminderSettings()));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();

    expect(tester.widget<Switch>(find.byType(Switch).first).value, isFalse);
    expect(find.text(NudgeCopy.permissionDenied), findsOneWidget);
    expect(scheduler.scheduled, isEmpty);
  });

  testWidgets('a new time reschedules it, and only while it is on', (
    WidgetTester tester,
  ) async {
    final _FakeScheduler scheduler = _FakeScheduler();
    await tester.pumpWidget(_app(scheduler, home: const ReminderSettings()));
    await tester.pumpAndSettle();
    final ProviderContainer container = ProviderScope.containerOf(
      tester.element(find.byType(ReminderSettings)),
    );
    final DailyNudge nudge = container.read(dailyNudgeProvider.notifier);

    await nudge.setTime(const TimeOfDay(hour: 7, minute: 30));
    expect(scheduler.scheduled, isEmpty);
    await nudge.turnOn();
    await nudge.setTime(const TimeOfDay(hour: 22, minute: 15));
    await tester.pumpAndSettle();

    expect(scheduler.scheduled, const <TimeOfDay>[
      TimeOfDay(hour: 7, minute: 30),
      TimeOfDay(hour: 22, minute: 15),
    ]);
    expect(find.text('10:15 PM'), findsOneWidget);
  });

  test('a saved reminder is scheduled again at launch', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      DailyNudge.enabledKey: true,
      DailyNudge.minutesKey: 20 * 60 + 45,
    });
    final _FakeScheduler scheduler = _FakeScheduler();
    final ProviderContainer container = ProviderContainer(
      overrides: [nudgeSchedulerProvider.overrideWithValue(scheduler)],
    );
    addTearDown(container.dispose);

    container.read(dailyNudgeProvider);
    await pumpEventQueue();

    expect(
      container.read(dailyNudgeProvider),
      const NudgeSettings(enabled: true, time: TimeOfDay(hour: 20, minute: 45)),
    );
    expect(scheduler.scheduled, const <TimeOfDay>[
      TimeOfDay(hour: 20, minute: 45),
    ]);
    expect(scheduler.permissionRequests, 0);
  });

  test('turning it on before the saved time is read keeps that time', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      DailyNudge.enabledKey: false,
      DailyNudge.minutesKey: 7 * 60 + 30,
    });
    final _FakeScheduler scheduler = _FakeScheduler();
    final ProviderContainer container = ProviderContainer(
      overrides: [nudgeSchedulerProvider.overrideWithValue(scheduler)],
    );
    addTearDown(container.dispose);

    expect(await container.read(dailyNudgeProvider.notifier).turnOn(), isTrue);

    expect(scheduler.scheduled, const <TimeOfDay>[
      TimeOfDay(hour: 7, minute: 30),
    ]);
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt(DailyNudge.minutesKey), 7 * 60 + 30);
    expect(prefs.getBool(DailyNudge.enabledKey), isTrue);
  });

  testWidgets('notifications turned off in system Settings show it off', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      DailyNudge.enabledKey: true,
    });
    final _FakeScheduler scheduler = _FakeScheduler()..permitted = false;
    await tester.pumpWidget(_app(scheduler, home: const ReminderSettings()));
    await tester.pumpAndSettle();

    expect(tester.widget<Switch>(find.byType(Switch).first).value, isFalse);
    expect(find.text(NudgeCopy.permissionWithdrawn), findsOneWidget);

    // Back from the system Settings with notifications on again.
    scheduler.permitted = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(tester.widget<Switch>(find.byType(Switch).first).value, isTrue);
    expect(find.text(ReminderSettings.foot), findsOneWidget);
  });

  test(
    'Log something asks Today for the Log; Clean day asks nothing',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final _FakeScheduler scheduler = _FakeScheduler(
        launched: const NudgeTap(NudgeAction.log),
      );
      final ProviderContainer container = ProviderContainer(
        overrides: [nudgeSchedulerProvider.overrideWithValue(scheduler)],
      );
      addTearDown(container.dispose);

      // The press that launched the app.
      await container.read(dailyNudgeStartupProvider.future);
      expect(container.read(pendingNudgeLogProvider), isTrue);

      container.read(pendingNudgeLogProvider.notifier).clear();
      scheduler.onAction!(const NudgeTap(NudgeAction.clean));
      expect(container.read(pendingNudgeLogProvider), isFalse);

      // A press while the app runs.
      scheduler.onAction!(const NudgeTap(NudgeAction.log));
      expect(container.read(pendingNudgeLogProvider), isTrue);
      expect(scheduler.permissionRequests, 0);
    },
  );

  test('each action id maps to its action', () {
    expect(nudgeActionFor('log'), NudgeAction.log);
    expect(nudgeActionFor('clean'), NudgeAction.clean);
    expect(nudgeActionFor(null), isNull);
    expect(nudgeActionFor(null, payload: 'weekly-review'), NudgeAction.review);
    expect(nudgeActionFor('log', payload: 'weekly-review'), NudgeAction.log);
    expect(
      nudgeTapFor(null, payload: heavyDayPayload(DateTime(2026, 11, 14))),
      NudgeTap(NudgeAction.dayNote, day: DateTime(2026, 11, 14)),
    );
    expect(nudgeTapFor(null, payload: 'heavy-day:nonsense'), isNull);
  });

  test('a heavy-day tap asks Today for that day\'s note', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final _FakeScheduler scheduler = _FakeScheduler(
      launched: NudgeTap(NudgeAction.dayNote, day: DateTime(2026, 11, 14)),
    );
    final ProviderContainer container = ProviderContainer(
      overrides: [nudgeSchedulerProvider.overrideWithValue(scheduler)],
    );
    addTearDown(container.dispose);
    await container.read(dailyNudgeStartupProvider.future);
    expect(container.read(pendingDayNoteProvider), DateTime(2026, 11, 14));
    expect(container.read(pendingNudgeLogProvider), isFalse);
  });

  testWidgets('heavy days: off by default, asks permission when on', (
    WidgetTester tester,
  ) async {
    final _FakeScheduler scheduler = _FakeScheduler();
    await tester.pumpWidget(_app(scheduler, home: const ReminderSettings()));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text(ReminderSettings.heavyFoot), 100);
    expect(tester.widget<Switch>(_heavySwitch).value, isFalse);
    expect(find.text(ReminderSettings.heavyTimeLabel), findsOneWidget);
    expect(scheduler.permissionRequests, 0);

    await tester.tap(find.text(ReminderSettings.heavyLabel));
    await tester.pumpAndSettle();
    expect(scheduler.permissionRequests, 1);
    expect(tester.widget<Switch>(_heavySwitch).value, isTrue);
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(HeavyDayNudge.enabledKey), isTrue);
    expect(prefs.getBool(DailyNudge.enabledKey), isNull);

    await tester.tap(find.text(ReminderSettings.heavyLabel));
    await tester.pumpAndSettle();
    expect(prefs.getBool(HeavyDayNudge.enabledKey), isFalse);
  });

  testWidgets('heavy days: a refusal leaves it off and says where to go', (
    WidgetTester tester,
  ) async {
    final _FakeScheduler scheduler = _FakeScheduler(grant: false);
    await tester.pumpWidget(_app(scheduler, home: const ReminderSettings()));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text(ReminderSettings.heavyFoot), 100);
    await tester.tap(find.text(ReminderSettings.heavyLabel));
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(_heavySwitch).value, isFalse);
    expect(find.text(NudgeCopy.permissionDenied), findsOneWidget);
  });

  testWidgets('heavy days: the time row opens the picker and saves', (
    WidgetTester tester,
  ) async {
    final _FakeScheduler scheduler = _FakeScheduler();
    await tester.pumpWidget(_app(scheduler, home: const ReminderSettings()));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text(ReminderSettings.heavyFoot), 100);
    expect(find.text('9:00 PM'), findsNWidgets(2));
    await tester.tap(find.text(ReminderSettings.heavyTimeLabel));
    await tester.pumpAndSettle();
    expect(find.byType(TimePickerDialog), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt(HeavyDayNudge.minutesKey), 21 * 60);
    expect(prefs.getInt(DailyNudge.minutesKey), isNull);
  });

  testWidgets('the weekly review notification is off until turned on', (
    WidgetTester tester,
  ) async {
    final _FakeScheduler scheduler = _FakeScheduler();
    await tester.pumpWidget(_app(scheduler, home: const ReminderSettings()));
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(find.byType(Switch).at(1)).value, isFalse);
    expect(scheduler.reviewSchedules, 0);

    await tester.tap(find.text(ReminderSettings.reviewLabel));
    await tester.pumpAndSettle();
    expect(scheduler.permissionRequests, 1);
    expect(scheduler.reviewSchedules, 1);
    expect(scheduler.scheduled, isEmpty);
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(WeeklyReviewReminder.enabledKey), isTrue);

    await tester.tap(find.text(ReminderSettings.reviewLabel));
    await tester.pumpAndSettle();
    expect(scheduler.reviewCancels, 1);
    expect(scheduler.cancels, 0);
    expect(prefs.getBool(WeeklyReviewReminder.enabledKey), isFalse);
  });

  test('a saved review notification is scheduled again at launch', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    SharedPreferences.setMockInitialValues(<String, Object>{
      WeeklyReviewReminder.enabledKey: true,
    });
    final _FakeScheduler scheduler = _FakeScheduler();
    final ProviderContainer container = ProviderContainer(
      overrides: [nudgeSchedulerProvider.overrideWithValue(scheduler)],
    );
    addTearDown(container.dispose);
    await container.read(dailyNudgeStartupProvider.future);
    await pumpEventQueue();
    expect(container.read(weeklyReviewReminderProvider), isTrue);
    expect(scheduler.reviewSchedules, 1);

    scheduler.onAction!(const NudgeTap(NudgeAction.review));
    expect(container.read(pendingWeeklyReviewProvider), isTrue);
    expect(container.read(pendingNudgeLogProvider), isFalse);
  });

  group('nextWeekday', () {
    setUpAll(tz_data.initializeTimeZones);

    test('is the next Monday at the time, or today before it', () {
      final tz.Location london = tz.getLocation('Europe/London');
      // Tuesday 10 November 2026.
      final tz.TZDateTime tuesday = tz.TZDateTime(london, 2026, 11, 10, 8);
      expect(
        nextWeekday(tuesday, DateTime.monday, reviewTime),
        tz.TZDateTime(london, 2026, 11, 16, 9),
      );
      final tz.TZDateTime mondayEarly = tz.TZDateTime(london, 2026, 11, 16, 8);
      expect(
        nextWeekday(mondayEarly, DateTime.monday, reviewTime),
        tz.TZDateTime(london, 2026, 11, 16, 9),
      );
      final tz.TZDateTime mondayLate = tz.TZDateTime(london, 2026, 11, 16, 10);
      expect(
        nextWeekday(mondayLate, DateTime.monday, reviewTime),
        tz.TZDateTime(london, 2026, 11, 23, 9),
      );
    });
  });

  group('nextOccurrence', () {
    setUpAll(tz_data.initializeTimeZones);

    test('is today while the time is ahead, else tomorrow', () {
      final tz.Location london = tz.getLocation('Europe/London');
      final tz.TZDateTime now = tz.TZDateTime(london, 2026, 11, 8, 13, 5);

      expect(
        nextOccurrence(now, const TimeOfDay(hour: 21, minute: 0)),
        tz.TZDateTime(london, 2026, 11, 8, 21),
      );
      expect(
        nextOccurrence(now, const TimeOfDay(hour: 13, minute: 5)),
        tz.TZDateTime(london, 2026, 11, 9, 13, 5),
      );
    });

    test('keeps the wall-clock time across a change of clocks', () {
      final tz.Location london = tz.getLocation('Europe/London');
      // The clocks went back at 02:00 on 25 October 2026.
      final tz.TZDateTime now = tz.TZDateTime(london, 2026, 10, 24, 22);

      final tz.TZDateTime next = nextOccurrence(
        now,
        const TimeOfDay(hour: 21, minute: 0),
      );
      expect(next.hour, 21);
      expect(next.day, 25);
    });
  });
}
