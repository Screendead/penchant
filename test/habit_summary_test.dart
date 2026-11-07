import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/habit_summary.dart';
import 'package:tracker/providers/habit_summary_provider.dart';

void main() {
  group('HabitSummary.fromData', () {
    test('reads each habit\'s typical', () {
      expect(
        HabitSummary.fromData(<String, dynamic>{
          'windowDays': 90,
          'vices': <String, dynamic>{
            'a': <String, dynamic>{'typical': 2, 'count': 14},
            'b': <String, dynamic>{'typical': 1.5, 'count': 2},
          },
        }).typicals,
        <String, double>{'a': 2, 'b': 1.5},
      );
    });

    test('is empty for a summary never written', () {
      expect(HabitSummary.fromData(null).typicals, isEmpty);
      expect(HabitSummary.fromData(<String, dynamic>{}).typicals, isEmpty);
      expect(
        HabitSummary.fromData(<String, dynamic>{'vices': 'x'}).typicals,
        isEmpty,
      );
    });

    test(
      'skips a habit whose typical is missing, mistyped or not positive',
      () {
        expect(
          HabitSummary.fromData(<String, dynamic>{
            'vices': <String, dynamic>{
              'ok': <String, dynamic>{'typical': 3},
              'zero': <String, dynamic>{'typical': 0},
              'text': <String, dynamic>{'typical': '3'},
              'nan': <String, dynamic>{'typical': double.nan},
              'none': <String, dynamic>{'count': 3},
              'flat': 3,
            },
          }).typicals,
          <String, double>{'ok': 3},
        );
      },
    );
  });

  group('storedTypicalsProvider', () {
    Map<String, double> read(AsyncValue<HabitSummary> summary) {
      final ProviderContainer c = ProviderContainer(
        overrides: [habitSummaryProvider.overrideWithValue(summary)],
      );
      addTearDown(c.dispose);
      return c.read(storedTypicalsProvider);
    }

    test('hands on the summary\'s typicals', () {
      expect(
        read(
          const AsyncData<HabitSummary>(
            HabitSummary(typicals: <String, double>{'a': 2}),
          ),
        ),
        <String, double>{'a': 2},
      );
    });

    test(
      'is empty while loading or after an error, so the dial falls back',
      () {
        expect(read(const AsyncLoading<HabitSummary>()), isEmpty);
        expect(
          read(AsyncError<HabitSummary>(Exception('denied'), StackTrace.empty)),
          isEmpty,
        );
      },
    );
  });
}
