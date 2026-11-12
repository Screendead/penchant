import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/insights/after_event.dart';
import 'package:tracker/insights/after_event_copy.dart';
import 'package:tracker/insights/calendar_source.dart';
import 'package:tracker/insights/daily_series.dart';
import 'package:tracker/insights/what_follows.dart';

import 'after_event_synthetic.dart';

AfterEvent coffee(EventDays d) => afterEvent(
  uses: d.uses,
  events: d.events,
  through: d.through,
).singleWhere((a) => a.habitId == 'Coffee');

void main() {
  test('blocks join overlapping and back-to-back events, dropping short '
      'ones', () {
    final DateTime nine = DateTime(2025, 3, 3, 9);
    final List<CalendarEvent> blocks = eventBlocks(<CalendarEvent>[
      CalendarEvent(
        nine.add(const Duration(minutes: 65)),
        nine.add(const Duration(hours: 2)),
      ),
      CalendarEvent(nine, nine.add(const Duration(hours: 1))),
      CalendarEvent(
        nine.add(const Duration(hours: 4)),
        nine.add(const Duration(hours: 4, minutes: 5)),
      ),
      CalendarEvent(
        nine.add(const Duration(hours: 5)),
        nine.add(const Duration(hours: 6)),
      ),
    ]);
    expect(blocks.map((b) => (b.start, b.end)), <(DateTime, DateTime)>[
      (nine, nine.add(const Duration(hours: 2))),
      (nine.add(const Duration(hours: 5)), nine.add(const Duration(hours: 6))),
    ]);
  });

  test('a habit that follows its meetings is found, with the rates', () {
    final AfterEvent a = coffee(eventDays(1, follow: 0.6));
    expect(a.found, isTrue);
    expect(a.effect, greaterThan(afterEventFloor));
    expect(a.eventRate, greaterThan(a.controlRate));
    expect(afterEventSentence(a, 'Coffee', 'en_GB'), contains('of the time'));
    expect(afterEventRange(a, 'en_GB'), endsWith('points more often'));
  });

  test('a habit independent of meetings in the same hours is not found', () {
    expect(coffee(eventDays(2)).refusal, isNotNull);
  });

  test('a short span is refused as too few days', () {
    expect(
      coffee(eventDays(3, days: 14, follow: 0.6)).refusal,
      RefusalReason.tooFewDays,
    );
  });

  test('no calendar, no comparison', () {
    expect(
      afterEvent(
        uses: <HabitUse>[
          HabitUse(habitId: 'Coffee', at: DateTime(2025), amount: 1),
        ],
        events: const <CalendarEvent>[],
        through: DateTime(2025, 2),
      ),
      isEmpty,
    );
  });

  test('a finding the family makes chance is refused as chance', () {
    final AfterEvent a = coffee(eventDays(1, follow: 0.6));
    final List<AfterEvent> judged = judgeAfterEvent(
      <AfterEvent>[a],
      alongside: List<double>.filled(2000, 0.9),
      gates: const InsightGates(falseDiscoveryRate: 1e-12),
    );
    expect(judged.single.refusal, RefusalReason.chance);
  });

  test('the channel answer parses into events and reads stay under a '
      'year', () {
    final DateTime s = DateTime(2025, 3, 3, 9), e = DateTime(2025, 3, 3, 10);
    final List<CalendarEvent> got = calendarEventsFrom(
      Float64List.fromList(<double>[
        s.microsecondsSinceEpoch.toDouble(),
        e.microsecondsSinceEpoch.toDouble(),
        6,
      ]),
    );
    expect(got.single.start, s);
    expect(got.single.end, e);
    expect(got.single.attendees, 6);
    final chunks = calendarChunks(DateTime(2019, 6, 1), DateTime(2026, 11, 11));
    expect(chunks.first.start, DateTime(2019, 6, 1));
    expect(chunks.last.end, DateTime(2026, 11, 11));
    for (final c in chunks) {
      expect(c.end.difference(c.start).inDays, lessThanOrEqualTo(366));
    }
  });
}
