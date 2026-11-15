import 'dart:math';

import 'package:intl/intl.dart';
import 'package:tracker/ask/ask_query.dart';
import 'package:tracker/ask/describe_query.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/data/usage_series.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/formats.dart';

/// One bar of an answer's chart. [viceID] colours it with that habit's mark;
/// null draws it in ink (all habits together).
class AskBar {
  const AskBar(this.value, this.label, {this.viceID, this.marked = false});

  final double value;

  /// What the bar covers, for a screen reader and the axis ends.
  final String label;
  final String? viceID;

  /// The bar the headline names (the found week, say).
  final bool marked;
}

class AskAnswer {
  const AskAnswer({required this.headline, this.detail, this.bars});

  final String headline;
  final String? detail;
  final List<AskBar>? bars;
}

typedef DayRange = ({DateTime start, DateTime end});

/// The most bars a small chart draws: the newest ones.
const int maxBars = 24;

/// [query] run over [activities], every entry the device holds, with
/// [habits] the list sent with the question, so its indexes are the query's,
/// on [today]. Every day is a local day of the entry's `createdAt`.
AskAnswer runAskQuery(
  AskQuery query, {
  required List<Vice> habits,
  required List<ViceActivity> activities,
  required DateTime today,
}) => _Runner(query, habits, activities, startOfDay(today)).run();

/// [period]'s days as [start, end), end exclusive, ending no later than the
/// end of [today]. All time starts at [firstDay]; null when there is none.
DayRange? periodDays(AskPeriod period, DateTime today, DateTime? firstDay) {
  final DateTime t = startOfDay(today);
  final DateTime tomorrow = addDays(t, 1);
  final DateTime monday = addDays(t, 1 - t.weekday);
  return switch (period.type) {
    AskPeriodType.lastDays => (
      start: addDays(t, 1 - period.count!),
      end: tomorrow,
    ),
    AskPeriodType.lastWeeks => (
      start: addDays(t, 1 - 7 * period.count!),
      end: tomorrow,
    ),
    AskPeriodType.lastMonths => (
      start: DateTime(t.year, t.month - period.count!, t.day + 1),
      end: tomorrow,
    ),
    AskPeriodType.thisWeek => (start: monday, end: tomorrow),
    AskPeriodType.lastWeek => (start: addDays(monday, -7), end: monday),
    AskPeriodType.thisMonth => (start: DateTime(t.year, t.month), end: tomorrow),
    AskPeriodType.lastMonth => (
      start: DateTime(t.year, t.month - 1),
      end: DateTime(t.year, t.month),
    ),
    AskPeriodType.between => (
      start: period.from!,
      end: addDays(period.to!.isAfter(t) ? t : period.to!, 1),
    ),
    AskPeriodType.allTime =>
      firstDay == null ? null : (start: firstDay, end: tomorrow),
  };
}

/// Whether the query counts the absence of something, so that days before
/// the habit's first entry would count trivially and are left out.
bool countsAbsence(AskQuery q) =>
    q.measure == AskMeasure.daysWithout ||
    q.condition == AskCondition.none ||
    q.condition == AskCondition.below ||
    q.longest == AskLongest.runWithout ||
    q.longest == AskLongest.gap;

class _Side {
  _Side(this.side, this.habits, List<ViceActivity> all) {
    final Set<String> ids = habit == null
        ? habits.map((Vice v) => v.id).toSet()
        : <String>{habit!.id};
    for (final ViceActivity a in all) {
      if (!ids.contains(a.viceID)) continue;
      final DateTime at = a.createdAt.toDate();
      final DateTime day = startOfDay(at);
      if (firstDay == null || day.isBefore(firstDay!)) firstDay = day;
      if (!side.filter.holdsDay(day)) continue;
      if (!side.filter.holdsHour(at.hour)) continue;
      if (!side.filter.holdsTags(a.triggers)) continue;
      matching.add(a);
      final ({double amount, int entries}) old =
          byDay[day] ?? (amount: 0, entries: 0);
      byDay[day] = (
        amount: old.amount + a.measure,
        entries: old.entries + 1,
      );
    }
  }

  final AskSide side;
  final List<Vice> habits;
  final List<ViceActivity> matching = <ViceActivity>[];
  final Map<DateTime, ({double amount, int entries})> byDay =
      <DateTime, ({double amount, int entries})>{};

  /// The first day any entry of the side's habits was logged, filters aside.
  DateTime? firstDay;

  Vice? get habit => side.habit == null ? null : habits[side.habit!];
}

class _Runner {
  _Runner(this.q, this.habits, List<ViceActivity> activities, this.today)
    : a = _Side(q.side, habits, activities),
      b = q.versus == null ? null : _Side(q.versus!, habits, activities);

  final AskQuery q;
  final List<Vice> habits;
  final DateTime today;
  final _Side a;
  final _Side? b;

  String get _none => a.habit == null
      ? 'No entries yet'
      : 'No ${a.habit!.name} entries yet';

  DayRange? _range(_Side s) {
    final DayRange? days = periodDays(s.side.period, today, s.firstDay);
    if (days == null) return null;
    if (!countsAbsence(q)) return days;
    final DateTime? first = s.firstDay;
    if (first == null) return null;
    final DateTime start = first.isAfter(days.start) ? first : days.start;
    return start.isBefore(days.end) ? (start: start, end: days.end) : null;
  }

  AskAnswer run() {
    if (q.measure == AskMeasure.spend) {
      for (final _Side s in <_Side>[a, ?b]) {
        if (s.habit!.costPerUnit == null) {
          return AskAnswer(
            headline: '${s.habit!.name} has no price',
            detail: 'Add one in the habit’s settings to count spend.',
          );
        }
      }
    }
    if (q.shape == AskShape.compare) return _compare();
    final DayRange? range = _range(a);
    if (range == null) return AskAnswer(headline: _none);
    return switch (q.shape) {
      AskShape.total => _total(range),
      AskShape.series => _series(range),
      AskShape.lastTime => _lastTime(range),
      AskShape.longest =>
        q.longest == AskLongest.gap ? _gap(range) : _run(range),
      AskShape.compare => _compare(),
    };
  }

  bool _eligible(_Side s, DateTime day) => s.side.filter.holdsDay(day);

  double _value(_Side s, DayRange r) {
    double amount = 0;
    int entries = 0;
    int withDays = 0;
    int eligible = 0;
    for (DateTime d = r.start; d.isBefore(r.end); d = addDays(d, 1)) {
      if (!_eligible(s, d)) continue;
      eligible++;
      final ({double amount, int entries})? day = s.byDay[d];
      if (day == null) continue;
      amount += day.amount;
      entries += day.entries;
      withDays++;
    }
    return switch (q.measure) {
      AskMeasure.amount => amount,
      AskMeasure.entries => entries.toDouble(),
      AskMeasure.daysWith => withDays.toDouble(),
      AskMeasure.daysWithout => (eligible - withDays).toDouble(),
      AskMeasure.spend => s.habit!.spendOf(amount)!,
    };
  }

  /// [r] in buckets, oldest first. Weeks are 7 days counted back from the
  /// range's last day, the oldest part week left out (as Trends does); months
  /// are calendar months cut to the range. A bucket with no day the weekday
  /// filter allows is left out.
  List<DayRange> _buckets(_Side s, DayRange r, AskBucket bucket) {
    final List<DayRange> out = <DayRange>[];
    switch (bucket) {
      case AskBucket.day:
        for (DateTime d = r.start; d.isBefore(r.end); d = addDays(d, 1)) {
          out.add((start: d, end: addDays(d, 1)));
        }
      case AskBucket.week:
        final int days = daysBetween(r.start, r.end);
        if (days < 7) {
          out.add(r);
        } else {
          final UsageRange weeks = usageRange(addDays(r.end, -1), days, 7);
          for (int i = 0; i < weeks.bucketCount; i++) {
            out.add((
              start: weeks.bucketStart(i),
              end: weeks.bucketStart(i + 1),
            ));
          }
        }
      case AskBucket.month:
        for (
          DateTime m = DateTime(r.start.year, r.start.month);
          m.isBefore(r.end);
          m = DateTime(m.year, m.month + 1)
        ) {
          final DateTime next = DateTime(m.year, m.month + 1);
          out.add((
            start: m.isBefore(r.start) ? r.start : m,
            end: next.isAfter(r.end) ? r.end : next,
          ));
        }
    }
    return <DayRange>[
      for (final DayRange b in out)
        if (_hasEligible(s, b)) b,
    ];
  }

  bool _hasEligible(_Side s, DayRange r) {
    if (s.side.filter.weekdays.isEmpty) return true;
    for (DateTime d = r.start; d.isBefore(r.end); d = addDays(d, 1)) {
      if (_eligible(s, d)) return true;
    }
    return false;
  }

  String _figure(double value, _Side s) {
    final double v = (value * 100).round() / 100;
    return switch (q.measure) {
      AskMeasure.amount => s.habit!.units.label(v),
      AskMeasure.entries =>
        '${formatCount(v)} ${pluralWord(v, one: 'entry', other: 'entries')}',
      AskMeasure.daysWith || AskMeasure.daysWithout =>
        '${formatCount(v)} ${pluralWord(v, one: 'day', other: 'days')}',
      AskMeasure.spend => formatMoney(v, s.habit!.currency),
    };
  }

  bool _current(DayRange b) => !b.end.isBefore(addDays(today, 1));

  /// A bucket named for a headline: "The week of 12 October", "3 November".
  String _bucketName(DayRange b, AskBucket bucket, {bool capital = true}) {
    final bool thisYear = b.start.year == today.year;
    final DateFormat dayFormat = thisYear
        ? DateFormat.MMMMd(formatLocale)
        : DateFormat.yMMMMd(formatLocale);
    final String name = switch (bucket) {
      AskBucket.day when b.start == today => 'today',
      AskBucket.day when b.start == addDays(today, -1) => 'yesterday',
      AskBucket.day => dayFormat.format(b.start),
      AskBucket.week when _current(b) => 'the last 7 days',
      AskBucket.week => 'the week of ${dayFormat.format(b.start)}',
      AskBucket.month when _current(b) => 'this month',
      AskBucket.month => formatMonth(b.start),
    };
    return capital ? name[0].toUpperCase() + name.substring(1) : name;
  }

  String _barLabel(DayRange b, AskBucket bucket) => switch (bucket) {
    AskBucket.day when b.start == today => 'today',
    AskBucket.day => formatShortDay(b.start),
    AskBucket.week when _current(b) => 'this week',
    AskBucket.week => formatShortDay(b.start),
    AskBucket.month when _current(b) => 'this month',
    AskBucket.month => DateFormat.MMM(formatLocale).format(b.start),
  };

  String _unitWord(AskBucket bucket, int n) => switch (bucket) {
    AskBucket.day => pluralWord(n, one: 'day', other: 'days'),
    AskBucket.week => pluralWord(n, one: 'week', other: 'weeks'),
    AskBucket.month => pluralWord(n, one: 'month', other: 'months'),
  };

  List<AskBar> _bars(
    List<DayRange> buckets,
    List<double> values,
    AskBucket bucket, {
    int? marked,
  }) {
    final int from = max(0, buckets.length - maxBars);
    return <AskBar>[
      for (int i = from; i < buckets.length; i++)
        AskBar(
          values[i],
          _barLabel(buckets[i], bucket),
          viceID: a.habit?.id,
          marked: i == marked,
        ),
    ];
  }

  AskBucket _autoBucket(DayRange r) {
    final int days = daysBetween(r.start, r.end);
    if (days <= 31) return AskBucket.day;
    if (days <= 7 * maxBars) return AskBucket.week;
    return AskBucket.month;
  }

  AskAnswer _total(DayRange r) {
    final AskBucket bucket = _autoBucket(r);
    final List<DayRange> buckets = _buckets(a, r, bucket);
    return AskAnswer(
      headline: _figure(_value(a, r), a),
      bars: buckets.length < 2
          ? null
          : _bars(buckets, <double>[
              for (final DayRange b in buckets) _value(a, b),
            ], bucket),
    );
  }

  AskAnswer _series(DayRange r) {
    final AskBucket bucket = q.bucket!;
    final List<DayRange> buckets = _buckets(a, r, bucket);
    if (buckets.isEmpty) return AskAnswer(headline: _none);
    final List<double> values = <double>[
      for (final DayRange b in buckets) _value(a, b),
    ];
    int most = 0;
    for (int i = 1; i < values.length; i++) {
      if (values[i] >= values[most]) most = i;
    }
    final double total = values.fold(0, (double x, double y) => x + y);
    return AskAnswer(
      headline: _figure(total, a),
      detail: values[most] == 0
          ? null
          : 'Most: ${_bucketName(buckets[most], bucket, capital: false)}, '
                '${_figure(values[most], a)}.',
      bars: _bars(buckets, values, bucket, marked: most),
    );
  }

  bool _holds(double value) => switch (q.condition!) {
    AskCondition.none => value == 0,
    AskCondition.any => value > 0,
    AskCondition.above => value > q.threshold!,
    AskCondition.below => value < q.threshold!,
  };

  AskAnswer _lastTime(DayRange r) {
    final AskBucket bucket = q.bucket!;
    final List<DayRange> buckets = _buckets(a, r, bucket);
    final List<double> values = <double>[
      for (final DayRange b in buckets) _value(a, b),
    ];
    int? found;
    for (int i = buckets.length - 1; i >= 0; i--) {
      if (_holds(values[i])) {
        found = i;
        break;
      }
    }
    if (found == null) {
      return AskAnswer(
        headline: q.side.period.type == AskPeriodType.allTime
            ? 'Not since your first entry'
            : 'Not in this period',
      );
    }
    final int since = buckets.length - 1 - found;
    final String name = a.habit?.name ?? 'an entry';
    final String? detail = since == 0
        ? null
        : switch (q.condition!) {
            AskCondition.none =>
              '${formatCount(since)} ${_unitWord(bucket, since)} with $name '
                  'since then.',
            AskCondition.any =>
              '${formatCount(since)} ${_unitWord(bucket, since)} without '
                  '$name since then.',
            _ => '${formatCount(since)} ${_unitWord(bucket, since)} since then.',
          };
    // The newest 8 when they hold the found bucket, else it and the 7 after.
    final int from = since < 8 ? max(0, buckets.length - 8) : found;
    final int to = min(buckets.length, from + 8);
    return AskAnswer(
      headline: _bucketName(buckets[found], bucket),
      detail: detail,
      bars: _bars(
        buckets.sublist(from, to),
        values.sublist(from, to),
        bucket,
        marked: found - from,
      ),
    );
  }

  String _span(DayRange first, DayRange last, {required bool ongoing}) {
    final DateFormat f = DateFormat.yMMMMd(formatLocale);
    final DateTime end = addDays(last.end, -1);
    if (ongoing) return 'Since ${f.format(first.start)}, and counting.';
    if (first.start == end) return 'On ${f.format(end)}.';
    return 'From ${f.format(first.start)} to ${f.format(end)}.';
  }

  AskAnswer _run(DayRange r) {
    final AskBucket bucket = q.bucket!;
    final List<DayRange> buckets = _buckets(a, r, bucket);
    final bool want = q.longest == AskLongest.runWith;
    // Counted in entries, so any measure finds the same buckets.
    int best = 0;
    int bestEnd = -1;
    int run = 0;
    for (int i = 0; i < buckets.length; i++) {
      final bool has = _entries(a, buckets[i]) > 0;
      run = has == want ? run + 1 : 0;
      if (run > 0 && run >= best) {
        best = run;
        bestEnd = i;
      }
    }
    if (best == 0) return const AskAnswer(headline: 'None in this period');
    return AskAnswer(
      headline: '${formatCount(best)} ${_unitWord(bucket, best)}',
      detail: _span(
        buckets[bestEnd - best + 1],
        buckets[bestEnd],
        ongoing: bestEnd == buckets.length - 1 && _current(buckets[bestEnd]),
      ),
    );
  }

  int _entries(_Side s, DayRange r) {
    int n = 0;
    for (DateTime d = r.start; d.isBefore(r.end); d = addDays(d, 1)) {
      if (_eligible(s, d)) n += s.byDay[d]?.entries ?? 0;
    }
    return n;
  }

  AskAnswer _gap(DayRange r) {
    final List<DateTime> days =
        a.byDay.keys
            .where((DateTime d) => !d.isBefore(r.start) && d.isBefore(r.end))
            .toList()
          ..sort();
    if (days.isEmpty) return const AskAnswer(headline: 'No entries in this period');
    int best = 0;
    DayRange? span;
    bool ongoing = false;
    for (int i = 1; i < days.length; i++) {
      final int empty = daysBetween(days[i - 1], days[i]) - 1;
      if (empty > 0 && empty >= best) {
        best = empty;
        span = (start: addDays(days[i - 1], 1), end: days[i]);
        ongoing = false;
      }
    }
    final int sinceLast = daysBetween(days.last, addDays(r.end, -1));
    if (sinceLast > 0 && sinceLast >= best) {
      best = sinceLast;
      span = (start: addDays(days.last, 1), end: r.end);
      ongoing = _current(span);
    }
    if (span == null) {
      return const AskAnswer(headline: 'No gap: an entry every day');
    }
    return AskAnswer(
      headline: '${formatCount(best)} ${_unitWord(AskBucket.day, best)}',
      detail: _span(span, span, ongoing: ongoing),
    );
  }

  AskAnswer _compare() {
    final _Side second = b!;
    final DayRange? ra = _range(a);
    final DayRange? rb = _range(second);
    final double va = ra == null ? 0 : _value(a, ra);
    final double vb = rb == null ? 0 : _value(second, rb);
    final (String la, String lb) = compareLabels(q, habits);
    return AskAnswer(
      headline: '${_figure(va, a)} against ${_figure(vb, second)}',
      detail: '${_upper(la)}: ${_figure(va, a)}. '
          '${_upper(lb)}: ${_figure(vb, second)}.',
      bars: <AskBar>[
        AskBar(va, la, viceID: a.habit?.id),
        AskBar(vb, lb, viceID: second.habit?.id),
      ],
    );
  }
}

String _upper(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
