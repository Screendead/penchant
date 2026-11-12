import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/design/app_theme.dart';
import 'package:tracker/insights/after_event.dart';
import 'package:tracker/insights/calendar_source.dart';
import 'package:tracker/insights/calendar_suggestion.dart';
import 'package:tracker/providers/calendar_provider.dart';
import 'package:tracker/providers/tracker_writes_provider.dart';
import 'package:tracker/providers/unarchived_vice_list_provider.dart';
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/providers/vice_activity_history_provider.dart';
import 'package:tracker/widgets/record_new_activity_dialog.dart';
import 'package:tracker/widgets/trigger_picker.dart';

import 'fake_writes.dart';
import 'fakes.dart';

class _FakeCalendar implements CalendarSource {
  _FakeCalendar(this.state, [this.answer = const <CalendarEvent>[]]);

  final CalendarAccess state;
  final List<CalendarEvent> answer;
  bool fail = false;
  int asked = 0;
  int reads = 0;

  @override
  Future<CalendarAccess> access() async => state;

  @override
  Future<bool> requestAccess() async {
    asked++;
    return false;
  }

  @override
  Future<List<CalendarEvent>> events(DateTime start, DateTime end) async {
    reads++;
    if (fail) throw Exception('EventKit');
    return answer;
  }
}

void main() {
  final DateTime at = DateTime(2026, 11, 12, 15);
  CalendarEvent ending(int minutesBefore, {int length = 30}) {
    final DateTime end = at.subtract(Duration(minutes: minutesBefore));
    return CalendarEvent(end.subtract(Duration(minutes: length)), end);
  }

  group('calendarSuggestions', () {
    test('offers Work › Meeting in the hour after an event ends', () {
      expect(calendarSuggestions(at, <CalendarEvent>[ending(0)]), <String>[
        meetingTrigger,
      ]);
      expect(calendarSuggestions(at, <CalendarEvent>[ending(59)]), <String>[
        meetingTrigger,
      ]);
    });

    test(
      'offers nothing an hour on, before the end, or after a short hold',
      () {
        expect(calendarSuggestions(at, <CalendarEvent>[ending(60)]), isEmpty);
        expect(calendarSuggestions(at, <CalendarEvent>[ending(-10)]), isEmpty);
        expect(
          calendarSuggestions(at, <CalendarEvent>[ending(5, length: 10)]),
          isEmpty,
        );
        expect(calendarSuggestions(at, const <CalendarEvent>[]), isEmpty);
      },
    );
  });

  group('readCalendarSuggestions', () {
    test('reads no events without full access, and never prompts', () async {
      for (final CalendarAccess state in <CalendarAccess>[
        CalendarAccess.notDetermined,
        CalendarAccess.denied,
        CalendarAccess.writeOnly,
        CalendarAccess.restricted,
      ]) {
        final _FakeCalendar calendar = _FakeCalendar(state, <CalendarEvent>[
          ending(10),
        ]);
        expect(await readCalendarSuggestions(calendar, at), isEmpty);
        expect(calendar.reads, 0);
        expect(calendar.asked, 0);
      }
      expect(await readCalendarSuggestions(null, at), isEmpty);
    });

    test('a failed read offers nothing', () async {
      final _FakeCalendar calendar = _FakeCalendar(CalendarAccess.full)
        ..fail = true;
      expect(await readCalendarSuggestions(calendar, at), isEmpty);
    });

    test('with full access, an event just ended suggests a meeting', () async {
      final _FakeCalendar calendar = _FakeCalendar(
        CalendarAccess.full,
        <CalendarEvent>[ending(10)],
      );
      expect(await readCalendarSuggestions(calendar, at), <String>[
        meetingTrigger,
      ]);
      expect(calendar.asked, 0);
    });
  });

  testWidgets('the sheet offers the suggestion first, unpicked', (
    tester,
  ) async {
    List<String>? done;
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(Brightness.light),
        home: Scaffold(
          body: TriggerPickerSheet(
            viceName: 'Coffee',
            usual: const <String>['feeling/stressed', meetingTrigger],
            suggested: const <String>[meetingTrigger],
            onDone: (List<String> picked) => done = picked,
          ),
        ),
      ),
    );

    expect(find.text(TriggerPickerSheet.calendarLabel), findsOneWidget);
    final Finder chip = find.widgetWithText(FilterChip, 'Work › Meeting');
    expect(chip, findsOneWidget);
    expect(tester.widget<FilterChip>(chip).selected, isFalse);
    expect(
      tester.getTopLeft(chip).dy,
      lessThan(tester.getTopLeft(find.text('Usual for Coffee')).dy),
    );

    await tester.tap(find.text('Done'));
    expect(done, isEmpty);

    await tester.tap(chip);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    expect(done, <String>[meetingTrigger]);
  });

  testWidgets('the record sheet\'s picker suggests from the calendar', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    tester.view
      ..physicalSize = const Size(1179, 2556)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final FakeTrackerWrites writes = FakeTrackerWrites();
    final vice = fakeVice('coffee');
    final DateTime now = DateTime.now();
    final _FakeCalendar calendar =
        _FakeCalendar(CalendarAccess.full, <CalendarEvent>[
          CalendarEvent(
            now.subtract(const Duration(minutes: 70)),
            now.subtract(const Duration(minutes: 10)),
          ),
        ]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          userProvider.overrideWith((ref) => Stream.value(FakeUser(ownerID))),
          unarchivedViceListProvider.overrideWithValue(AsyncData([vice])),
          viceActivityHistoryProvider.overrideWith(
            (ref, query) => const AsyncData(<ViceActivity>[]),
          ),
          trackerWritesProvider.overrideWithValue(writes),
          calendarSourceProvider.overrideWithValue(calendar),
          memoryJournal(),
        ],
        child: MaterialApp(
          theme: appTheme(Brightness.light),
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) {
                ref.watch(userProvider);
                return TextButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) =>
                        RecordNewActivityDialog(initialViceID: vice.id),
                  ),
                  child: const Text('open'),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('What was going on? (optional)'));
    await tester.pumpAndSettle();

    expect(calendar.reads, 1);
    expect(find.text(TriggerPickerSheet.calendarLabel), findsOneWidget);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(InputChip, 'Work › Meeting'), findsNothing);
  });
}
