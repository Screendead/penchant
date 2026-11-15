import 'package:intl/intl.dart';
import 'package:tracker/ask/ask_query.dart';
import 'package:tracker/data/trigger_tree.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/formats.dart';

// The query restated in plain words under every answer, so that a misread
// question shows: "The last week with no Wine entries, in weeks of 7 days
// counted back from today, since your first entry."

String _habitName(int? index, List<Vice> habits) =>
    index == null ? 'any habit' : habits[index].name;

String _units(int? index, List<Vice> habits) =>
    index == null ? 'entries' : habits[index].units.plural;

/// The measure as a noun phrase: "glasses of Wine", "Wine entries".
String _measured(AskMeasure m, int? habit, List<Vice> habits) {
  final String name = _habitName(habit, habits);
  return switch (m) {
    AskMeasure.amount => '${_units(habit, habits)} of $name',
    AskMeasure.entries => habit == null ? 'entries' : '$name entries',
    AskMeasure.daysWith => 'days with $name',
    AskMeasure.daysWithout => 'days with no $name',
    AskMeasure.spend => 'money spent on $name',
  };
}

String _date(DateTime day) => DateFormat.yMMMMd(formatLocale).format(day);

/// The period as a phrase that follows a noun: "in the last 30 days".
String describePeriod(AskPeriod p) {
  final int n = p.count ?? 0;
  return switch (p.type) {
    AskPeriodType.lastDays =>
      n == 1 ? 'today' : 'in the last ${formatCount(n)} days',
    AskPeriodType.lastWeeks =>
      'in the last ${formatCount(n)} ${pluralWord(n, one: 'week', other: 'weeks')} '
          '(${formatCount(7 * n)} days)',
    AskPeriodType.lastMonths =>
      'in the last ${formatCount(n)} ${pluralWord(n, one: 'month', other: 'months')}',
    AskPeriodType.thisWeek => 'this week, from Monday',
    AskPeriodType.lastWeek => 'last week, Monday to Sunday',
    AskPeriodType.thisMonth => 'this month',
    AskPeriodType.lastMonth => 'last month',
    AskPeriodType.between =>
      p.from == p.to
          ? 'on ${_date(p.from!)}'
          : 'from ${_date(p.from!)} to ${_date(p.to!)}',
    AskPeriodType.allTime => 'since your first entry',
  };
}

const List<String> _dayNames = <String>[
  'Mondays',
  'Tuesdays',
  'Wednesdays',
  'Thursdays',
  'Fridays',
  'Saturdays',
  'Sundays',
];

String _list(List<String> items) => items.length < 2
    ? items.join()
    : '${items.sublist(0, items.length - 1).join(', ')} and ${items.last}';

String _hour(int h) =>
    h == 24 || h == 0 ? 'midnight' : '${'$h'.padLeft(2, '0')}:00';

/// The filters as phrases: "on Fridays", "from 20:00 to midnight",
/// "tagged Work › Meeting". Empty when nothing filters.
List<String> describeFilter(AskFilter f) {
  final List<int> days = f.weekdays.toList()..sort();
  return <String>[
    if (days.isNotEmpty)
      switch (days.join()) {
        '67' => 'on weekends',
        '12345' => 'on weekdays',
        _ =>
          'on ${_list(<String>[for (final int d in days) _dayNames[d - 1]])}',
      },
    if (f.hasHours) 'from ${_hour(f.fromHour!)} to ${_hour(f.toHour!)}',
    if (f.tag != null)
      'tagged ${(triggerLabels(f.tag!) ?? <String>[f.tag!]).join(' › ')}',
  ];
}

String _bucketWord(AskBucket b) => switch (b) {
  AskBucket.day => 'day',
  AskBucket.week => 'week',
  AskBucket.month => 'month',
};

String _scope(AskSide side) => <String>[
  describePeriod(side.period),
  ...describeFilter(side.filter),
].join(', ');

bool _endsToday(AskPeriod p) => switch (p.type) {
  AskPeriodType.lastWeek ||
  AskPeriodType.lastMonth ||
  AskPeriodType.between => false,
  _ => true,
};

String _weeksNote(AskBucket? b, AskSide side) => b == AskBucket.week
    ? ', in weeks of 7 days counted back from '
          '${_endsToday(side.period) ? 'today' : 'its last day'}'
    : '';

/// [q] in plain words, the habit indexes resolved against [habits], the list
/// sent with the question.
String describeQuery(AskQuery q, List<Vice> habits) {
  final int? h = q.side.habit;
  final String measured = _measured(q.measure, h, habits);
  final String scope = _scope(q.side);
  final String name = _habitName(h, habits);
  final String sentence = switch (q.shape) {
    AskShape.total => switch (q.measure) {
      AskMeasure.amount || AskMeasure.spend => 'Total $measured, $scope',
      _ => 'Number of $measured, $scope',
    },
    AskShape.series =>
      '${_upper(measured)} per ${_bucketWord(q.bucket!)}, $scope'
          '${_weeksNote(q.bucket, q.side)}',
    AskShape.lastTime =>
      'The last ${_bucketWord(q.bucket!)} with ${_condition(q, h, habits)}, '
          '$scope${_weeksNote(q.bucket, q.side)}',
    AskShape.longest => switch (q.longest!) {
      AskLongest.gap => 'The longest gap between $name entries, $scope',
      AskLongest.runWith =>
        'The most ${_bucketWord(q.bucket!)}s in a row with $name, $scope'
            '${_weeksNote(q.bucket, q.side)}',
      AskLongest.runWithout =>
        'The most ${_bucketWord(q.bucket!)}s in a row with no $name, $scope'
            '${_weeksNote(q.bucket, q.side)}',
    },
    AskShape.compare => () {
      final AskSide v = q.versus!;
      final String right = v.habit == h
          ? _scope(v)
          : '${_measured(q.measure, v.habit, habits)}, ${_scope(v)}';
      return '$measured, $scope, against $right';
    }(),
  };
  return '${_upper(sentence)}.';
}

String _condition(AskQuery q, int? h, List<Vice> habits) {
  final String name = _habitName(h, habits);
  final String t = formatCount(q.threshold ?? 0);
  return switch (q.condition!) {
    AskCondition.none => 'no $name entries',
    AskCondition.any => h == null ? 'an entry' : 'a $name entry',
    AskCondition.above => 'more than $t ${_measured(q.measure, h, habits)}',
    AskCondition.below => 'fewer than $t ${_measured(q.measure, h, habits)}',
  };
}

/// Short names for a comparison's two sides: the habits when they differ,
/// else the periods, else the filters.
(String, String) compareLabels(AskQuery q, List<Vice> habits) {
  final AskSide a = q.side;
  final AskSide b = q.versus!;
  if (a.habit != b.habit) {
    return (_habitName(a.habit, habits), _habitName(b.habit, habits));
  }
  if (a.period != b.period) {
    return (describePeriod(a.period), describePeriod(b.period));
  }
  String filterName(AskFilter f) {
    final List<String> parts = describeFilter(f);
    return parts.isEmpty ? 'every day' : parts.join(', ');
  }

  return (filterName(a.filter), filterName(b.filter));
}

String _upper(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
