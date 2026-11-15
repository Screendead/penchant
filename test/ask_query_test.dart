import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/ask/ask_query.dart';

final DateTime today = DateTime(2026, 11, 15);

Map<String, Object?> period(
  String type, {
  int? count,
  String? from,
  String? to,
}) => <String, Object?>{'type': type, 'count': count, 'from': from, 'to': to};

Map<String, Object?> filter({
  List<Object?> weekdays = const <Object?>[],
  Object? fromHour,
  Object? toHour,
  Object? tag,
}) => <String, Object?>{
  'weekdays': weekdays,
  'from_hour': fromHour,
  'to_hour': toHour,
  'tag': tag,
};

Map<String, Object?> query({
  Object? habit = 0,
  String measure = 'amount',
  Map<String, Object?>? p,
  Map<String, Object?>? f,
  String shape = 'total',
  String? bucket,
  String? condition,
  Object? threshold,
  String? longest,
  Map<String, Object?>? versus,
}) => <String, Object?>{
  'kind': 'query',
  'reason': 'none',
  'habit': habit,
  'measure': measure,
  'period': p ?? period('last_days', count: 30),
  'filter': f ?? filter(),
  'shape': shape,
  'bucket': bucket,
  'condition': condition,
  'threshold': threshold,
  'longest': longest,
  'versus': versus,
};

AskParsed parse(Object? json) =>
    parseAskQuery(json, habitCount: 3, today: today);

AskQuery run(Object? json) {
  final AskParsed parsed = parse(json);
  expect(parsed, isA<AskRun>());
  return (parsed as AskRun).query;
}

void expectInvalid(Object? json) {
  final AskParsed parsed = parse(json);
  expect(parsed, isA<AskCannotAnswer>());
  expect((parsed as AskCannotAnswer).reason, isNull);
}

void main() {
  test('the enums are the schema the server sends to the model', () {
    final Map<String, Object?> schema =
        jsonDecode(File('functions/ask_query_schema.json').readAsStringSync())
            as Map<String, Object?>;
    final Map<String, Object?> props =
        schema['properties']! as Map<String, Object?>;
    final Map<String, Object?> defs = schema[r'$defs']! as Map<String, Object?>;
    List<Object?> enumOf(Object? node) {
      final Map<String, Object?> n = node! as Map<String, Object?>;
      if (n['enum'] != null) return n['enum']! as List<Object?>;
      return enumOf(
        (n['anyOf']! as List<Object?>).firstWhere(
          (Object? s) => (s! as Map<String, Object?>)['type'] != 'null',
        ),
      );
    }

    List<String> names(List<Enum> values) => values.map(wireName).toList();
    expect(enumOf(props['kind']), <String>[
      'query',
      'needs_insights',
      'cannot_answer',
    ]);
    expect(enumOf(props['reason']), <String>[
      'none',
      ...names(AskReason.values),
    ]);
    expect(enumOf(props['measure']), names(AskMeasure.values));
    expect(enumOf(props['shape']), names(AskShape.values));
    expect(enumOf(props['bucket']), names(AskBucket.values));
    expect(enumOf(props['condition']), names(AskCondition.values));
    expect(enumOf(props['longest']), names(AskLongest.values));
    final Map<String, Object?> p = defs['period']! as Map<String, Object?>;
    expect(
      enumOf((p['properties']! as Map<String, Object?>)['type']),
      names(AskPeriodType.values),
    );
    // Every key the device reads is a key the schema requires, and no more.
    expect((schema['required']! as List<Object?>).toSet(), query().keys.toSet());
    expect(
      ((defs['filter']! as Map<String, Object?>)['required']! as List<Object?>)
          .toSet(),
      filter().keys.toSet(),
    );
    expect((p['required']! as List<Object?>).toSet(), period('x').keys.toSet());
    expect(
      ((defs['side']! as Map<String, Object?>)['required']! as List<Object?>)
          .toSet(),
      <String>{'habit', 'period', 'filter'},
    );
  });

  group('accepts', () {
    test('a total with every filter', () {
      final AskQuery q = run(
        query(
          f: filter(weekdays: <Object?>[5, 6.0], fromHour: 20, toHour: 24, tag: 'work/meeting'),
        ),
      );
      expect(q.shape, AskShape.total);
      expect(q.side.habit, 0);
      expect(q.side.period, const AskPeriod(AskPeriodType.lastDays, count: 30));
      expect(q.side.filter.weekdays, <int>{5, 6});
      expect(q.side.filter.holdsHour(21), isTrue);
      expect(q.side.filter.holdsHour(19), isFalse);
      expect(q.side.filter.holdsTags(<String>['work/meeting']), isTrue);
      expect(q.side.filter.holdsTags(<String>['work/long-day']), isFalse);
    });

    test('an area tag, wrapping hours and all habits for entries', () {
      final AskQuery q = run(
        query(
          habit: null,
          measure: 'entries',
          f: filter(fromHour: 22, toHour: 5, tag: 'work'),
        ),
      );
      expect(q.side.habit, isNull);
      expect(q.side.filter.holdsHour(23), isTrue);
      expect(q.side.filter.holdsHour(3), isTrue);
      expect(q.side.filter.holdsHour(12), isFalse);
      expect(q.side.filter.holdsTags(<String>['work/meeting']), isTrue);
      expect(q.side.filter.holdsTags(<String>['workout']), isFalse);
    });

    test('a series, a last time, a longest run and a comparison', () {
      expect(run(query(shape: 'series', bucket: 'week')).bucket, AskBucket.week);
      final AskQuery last = run(
        query(
          shape: 'last_time',
          bucket: 'day',
          condition: 'above',
          threshold: 4,
        ),
      );
      expect(last.condition, AskCondition.above);
      expect(last.threshold, 4);
      final AskQuery longest = run(
        query(shape: 'longest', longest: 'run_without', bucket: null),
      );
      expect(longest.bucket, AskBucket.day);
      expect(run(query(shape: 'longest', longest: 'gap')).longest, AskLongest.gap);
      final AskQuery compare = run(
        query(
          shape: 'compare',
          p: period('this_month'),
          versus: <String, Object?>{
            'habit': 0,
            'period': period('last_month'),
            'filter': filter(),
          },
        ),
      );
      expect(compare.versus!.period, const AskPeriod(AskPeriodType.lastMonth));
    });

    test('a between period, its end cut to today', () {
      final AskQuery q = run(
        query(p: period('between', from: '2026-10-01', to: '2026-12-31')),
      );
      expect(q.side.period.from, DateTime(2026, 10));
      expect(q.side.period.to, today);
    });

    test('the escapes', () {
      expect(parse(<String, Object?>{'kind': 'needs_insights'}), isA<AskNeedsInsights>());
      final AskParsed cannot = parse(<String, Object?>{
        'kind': 'cannot_answer',
        'reason': 'unknown_habit',
      });
      expect((cannot as AskCannotAnswer).reason, AskReason.unknownHabit);
    });
  });

  group('rejects', () {
    test('malformed answers', () {
      expectInvalid(null);
      expectInvalid('query');
      expectInvalid(<String, Object?>{'kind': 'answer'});
      expectInvalid(query()..remove('period'));
      expectInvalid(query(measure: 'mood'));
      expectInvalid(query(shape: 'why'));
    });

    test('a habit out of range, or several habits added in unlike units', () {
      expectInvalid(query(habit: 3));
      expectInvalid(query(habit: -1));
      expectInvalid(query(habit: 1.5));
      expectInvalid(query(habit: null));
      expectInvalid(query(habit: null, measure: 'spend'));
    });

    test('periods out of bounds', () {
      expectInvalid(query(p: period('last_days', count: 0)));
      expectInvalid(query(p: period('last_days', count: maxLastDays + 1)));
      expectInvalid(query(p: period('last_weeks')));
      expectInvalid(query(p: period('last_months', count: 121)));
      expectInvalid(query(p: period('between', from: '2026-02-30', to: '2026-03-01')));
      expectInvalid(query(p: period('between', from: '2026-11-10', to: '2026-11-01')));
      expectInvalid(query(p: period('between', from: '1999-12-31', to: '2026-11-01')));
      expectInvalid(query(p: period('between', from: '2026-12-01', to: '2026-12-31')));
      expectInvalid(query(p: period('next_week')));
    });

    test('filters out of range', () {
      expectInvalid(query(f: filter(weekdays: <Object?>[0])));
      expectInvalid(query(f: filter(weekdays: <Object?>[8])));
      expectInvalid(query(f: filter(fromHour: 24)));
      expectInvalid(query(f: filter(fromHour: 5, toHour: 5)));
      expectInvalid(query(f: filter(toHour: 25)));
      expectInvalid(query(f: filter(tag: 'work/made-up')));
      expectInvalid(query(f: filter(tag: 3)));
    });

    test('a shape missing what it needs', () {
      expectInvalid(query(shape: 'series'));
      expectInvalid(query(shape: 'last_time', bucket: 'week'));
      expectInvalid(query(shape: 'last_time', bucket: 'day', condition: 'above'));
      expectInvalid(
        query(shape: 'last_time', bucket: 'day', condition: 'above', threshold: -1),
      );
      expectInvalid(
        query(shape: 'last_time', bucket: 'day', condition: 'below', threshold: 0),
      );
      expectInvalid(query(shape: 'longest'));
      expectInvalid(query(shape: 'longest', longest: 'run_with', bucket: 'month'));
      expectInvalid(query(shape: 'compare'));
      expectInvalid(
        query(
          shape: 'compare',
          versus: <String, Object?>{'habit': 9, 'period': period('all_time'), 'filter': filter()},
        ),
      );
    });
  });
}
