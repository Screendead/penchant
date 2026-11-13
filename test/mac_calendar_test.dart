import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tracker/insights/after_event.dart';
import 'package:tracker/insights/calendar_source.dart';
import 'package:tracker/insights/calendar_suggestion.dart';
import 'package:tracker/providers/calendar_provider.dart';
import 'package:tracker/providers/mac_calendar_provider.dart';
import 'package:tracker/providers/package_info_provider.dart';
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/settings.dart';

class _FakeCalendar implements CalendarSource {
  _FakeCalendar(this.state, {this.grant = CalendarAccess.full});

  CalendarAccess state;
  final CalendarAccess grant;
  int asked = 0;
  int reads = 0;

  @override
  Future<CalendarAccess> access() async => state;

  @override
  Future<bool> requestAccess() async {
    asked++;
    if (state == CalendarAccess.notDetermined) state = grant;
    return state == CalendarAccess.full;
  }

  @override
  Future<List<CalendarEvent>> events(DateTime start, DateTime end) async {
    reads++;
    return <CalendarEvent>[
      CalendarEvent(
        end.subtract(const Duration(minutes: 50)),
        end.subtract(const Duration(minutes: 10)),
      ),
    ];
  }
}

// The framework fails a test that leaves the override set.
Future<void> onMac(Future<void> Function() body) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
  try {
    await body();
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}

void main() {
  final DateTime at = DateTime(2026, 11, 13, 15);

  group('pickerCalendarSourceProvider', () {
    test('off macOS is the source Insights reads', () {
      final _FakeCalendar calendar = _FakeCalendar(CalendarAccess.full);
      final ProviderContainer container = ProviderContainer(
        overrides: [calendarSourceProvider.overrideWithValue(calendar)],
      );
      addTearDown(container.dispose);
      expect(container.read(pickerCalendarSourceProvider), same(calendar));
      expect(container.read(macCalendarSourceProvider), isNull);
    });

    test('on macOS Insights gets no calendar', () async {
      await onMac(() async {
        final ProviderContainer container = ProviderContainer();
        addTearDown(container.dispose);
        expect(container.read(calendarSourceProvider), isNull);
        expect(container.read(macCalendarSourceProvider), isNotNull);
      });
    });

    test('on macOS reads nothing until suggestions are turned on', () async {
      await onMac(() async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final _FakeCalendar calendar = _FakeCalendar(CalendarAccess.full);
        final ProviderContainer container = ProviderContainer(
          overrides: [macCalendarSourceProvider.overrideWithValue(calendar)],
        );
        addTearDown(container.dispose);
        expect(
          await readCalendarSuggestions(
            container.read(pickerCalendarSourceProvider),
            at,
          ),
          isEmpty,
        );
        expect(calendar.reads, 0);
      });
    });

    test('on macOS suggests Meeting from the first ask once turned on, '
        'before the Settings choice has loaded', () async {
      await onMac(() async {
        SharedPreferences.setMockInitialValues(<String, Object>{
          CalendarSuggestions.key: true,
        });
        final _FakeCalendar calendar = _FakeCalendar(CalendarAccess.full);
        final ProviderContainer container = ProviderContainer(
          overrides: [macCalendarSourceProvider.overrideWithValue(calendar)],
        );
        addTearDown(container.dispose);
        expect(
          await readCalendarSuggestions(
            container.read(pickerCalendarSourceProvider),
            at,
          ),
          <String>[meetingTrigger],
        );
        expect(calendar.asked, 0);
      });
    });
  });

  group('Settings calendar row', () {
    Future<void> pumpSettings(WidgetTester tester, _FakeCalendar calendar) =>
        tester.pumpWidget(
          ProviderScope(
            overrides: [
              userProvider.overrideWith((ref) => Stream.value(null)),
              userProfileProvider.overrideWith((ref) => Stream.value(null)),
              packageInfoProvider.overrideWith(
                (ref) async => PackageInfo(
                  appName: 'tracker',
                  packageName: 'tracker',
                  version: '0.1.0',
                  buildNumber: '1',
                ),
              ),
              macCalendarSourceProvider.overrideWithValue(calendar),
            ],
            child: const MaterialApp(home: Settings()),
          ),
        );

    Switch calendarSwitch(WidgetTester tester) => tester.widget<Switch>(
      find.descendant(
        of: find.ancestor(
          of: find.text(Settings.calendarLabel),
          matching: find.byType(MergeSemantics),
        ),
        matching: find.byType(Switch),
      ),
    );

    testWidgets('is not shown off macOS', (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await pumpSettings(tester, _FakeCalendar(CalendarAccess.notDetermined));
      await tester.pumpAndSettle();
      expect(find.text(Settings.calendarLabel), findsNothing);
    });

    testWidgets('starts off and turning it on asks for access', (tester) async {
      await onMac(() async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final _FakeCalendar calendar = _FakeCalendar(
          CalendarAccess.notDetermined,
        );
        await pumpSettings(tester, calendar);
        await tester.pumpAndSettle();
        expect(find.text(Settings.calendarBody), findsOneWidget);
        expect(calendarSwitch(tester).value, isFalse);
        expect(calendar.asked, 0);

        await tester.tap(find.text(Settings.calendarLabel));
        await tester.pumpAndSettle();
        expect(calendar.asked, 1);
        expect(calendarSwitch(tester).value, isTrue);
        expect(
          (await SharedPreferences.getInstance()).getBool(
            CalendarSuggestions.key,
          ),
          isTrue,
        );

        await tester.tap(find.text(Settings.calendarLabel));
        await tester.pumpAndSettle();
        expect(calendarSwitch(tester).value, isFalse);
        expect(
          (await SharedPreferences.getInstance()).getBool(
            CalendarSuggestions.key,
          ),
          isFalse,
        );
        await tester.pumpWidget(const SizedBox());
      });
    });

    testWidgets('says to allow it in System Settings when refused', (
      tester,
    ) async {
      await onMac(() async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final _FakeCalendar calendar = _FakeCalendar(
          CalendarAccess.notDetermined,
          grant: CalendarAccess.denied,
        );
        await pumpSettings(tester, calendar);
        await tester.pumpAndSettle();
        await tester.tap(find.text(Settings.calendarLabel));
        await tester.pumpAndSettle();
        expect(calendar.asked, 1);
        expect(calendarSwitch(tester).value, isFalse);
        expect(find.text(Settings.calendarDenied), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
      });
    });
  });
}
