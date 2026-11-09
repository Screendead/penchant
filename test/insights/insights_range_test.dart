import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/insights/insights_report.dart';

import '../dst.dart';
import '../fakes.dart';

void main() {
  group('insightsRange', () {
    test('runs from the journal floor through today, whatever the hour', () {
      final DateTime today = DateTime(2026, 11, 9);
      final ({DateTime start, DateTime end}) range = insightsRange(today);
      expect(range.start, DateTime(2000));
      expect(range.end, DateTime(2026, 11, 10));
      expect(insightsRange(today.add(const Duration(hours: 23))), range);
    });

    test(
      'ends at the next local midnight on a DST change day',
      () {
        final ({DateTime start, DateTime end}) range = insightsRange(
          transition!.add(const Duration(hours: 12)),
        );
        expect(range.end, addDays(transition!, 1));
        expect(range.end.hour, 0);
      },
      skip: transition == null ? noDstSkipReason : false,
    );
  });

  group('insightsHealthChunks', () {
    test('reads from HealthKit\'s launch in calendar years, oldest first, '
        'ending with today', () {
      final ({DateTime start, DateTime end}) range = insightsRange(
        DateTime(2026, 11, 9),
      );
      final List<({DateTime start, DateTime end})> chunks =
          insightsHealthChunks(range);
      expect(chunks.first, (start: insightsHealthStart, end: DateTime(2015)));
      expect(chunks.last, (start: DateTime(2026), end: DateTime(2026, 11, 10)));
      expect(chunks, hasLength(13));
      for (int i = 1; i < chunks.length; i++) {
        expect(chunks[i].start, chunks[i - 1].end);
        expect(chunks[i].start, DateTime(2014 + i));
      }
    });

    test('a range inside one year is one call', () {
      expect(
        insightsHealthChunks((
          start: DateTime(2026, 3, 1),
          end: DateTime(2026, 4, 1),
        )),
        <({DateTime start, DateTime end})>[
          (start: DateTime(2026, 3, 1), end: DateTime(2026, 4, 1)),
        ],
      );
    });

    test('on 1 January the year just begun is its own call', () {
      final List<({DateTime start, DateTime end})> chunks =
          insightsHealthChunks(insightsRange(DateTime(2027)));
      expect(chunks.last, (start: DateTime(2027), end: DateTime(2027, 1, 2)));
    });
  });

  group('insightsFirstDay', () {
    final List<ViceActivity> activities = <ViceActivity>[
      fakeActivity('coffee', 1, DateTime(2025, 6, 2, 8)),
      fakeActivity('tea', 1, DateTime(2024, 3, 9, 23, 59)),
      fakeActivity('coffee', 1, DateTime(2025, 1, 4, 7)),
      fakeActivity('water', 1, DateTime(2026, 1, 1)),
    ];

    test('is the local day of the earliest entry, in any order', () {
      expect(insightsFirstDays(activities), <String, DateTime>{
        'coffee': DateTime(2025, 1, 4),
        'tea': DateTime(2024, 3, 9),
        'water': DateTime(2026, 1, 1),
      });
      expect(
        insightsFirstDay(insightsFirstDays(activities), (_) => true),
        DateTime(2024, 3, 9),
      );
    });

    test('skips the habits the page leaves out', () {
      expect(
        insightsFirstDay(
          insightsFirstDays(activities),
          (String id) => id != 'tea',
        ),
        DateTime(2025, 1, 4),
      );
    });

    test('is null for an empty journal', () {
      expect(
        insightsFirstDay(
          insightsFirstDays(const <ViceActivity>[]),
          (_) => true,
        ),
        isNull,
      );
    });

    test(
      'an entry just after midnight on a DST change day starts that day',
      () {
        final DateTime at = transition!.add(const Duration(minutes: 30));
        expect(
          insightsFirstDays(<ViceActivity>[fakeActivity('coffee', 1, at)]),
          <String, DateTime>{'coffee': transition!},
        );
      },
      skip: transition == null ? noDstSkipReason : false,
    );
  });
}

final DateTime? transition = firstDstTransitionDay(2026);
