import 'package:tracker/data/day.dart';
import 'package:tracker/data/trigger_tree.dart';

// The query language the server's model fills in (functions/ask_query_schema.json,
// which test/ask_query_test.dart compares with these enums). The device checks
// every query here before running it; anything that fails is cannot_answer.

enum AskMeasure { amount, entries, daysWith, daysWithout, spend }

enum AskPeriodType {
  lastDays,
  lastWeeks,
  lastMonths,
  thisWeek,
  lastWeek,
  thisMonth,
  lastMonth,
  between,
  allTime,
}

enum AskShape { total, series, lastTime, longest, compare }

enum AskBucket { day, week, month }

enum AskCondition { none, any, above, below }

enum AskLongest { gap, runWith, runWithout }

enum AskReason { notAboutJournal, unknownHabit, notSupported, unclear }

/// An enum value's name as the schema spells it: `daysWith` is `days_with`.
String wireName(Enum value) => value.name.replaceAllMapped(
  RegExp('[A-Z]'),
  (Match m) => '_${m[0]!.toLowerCase()}',
);

T? _enumOf<T extends Enum>(List<T> values, Object? wire) {
  for (final T value in values) {
    if (wireName(value) == wire) return value;
  }
  return null;
}

/// The most of each kind of period the language allows: about ten years.
const int maxLastDays = 3660;
const int maxLastWeeks = 520;
const int maxLastMonths = 120;
final DateTime askEarliest = DateTime(2000);

class AskPeriod {
  const AskPeriod(this.type, {this.count, this.from, this.to});

  final AskPeriodType type;
  final int? count;
  final DateTime? from;
  // Inclusive, never after today.
  final DateTime? to;

  @override
  bool operator ==(Object other) =>
      other is AskPeriod &&
      other.type == type &&
      other.count == count &&
      other.from == from &&
      other.to == to;

  @override
  int get hashCode => Object.hash(type, count, from, to);
}

class AskFilter {
  const AskFilter({
    this.weekdays = const <int>{},
    this.fromHour,
    this.toHour,
    this.tag,
  });

  /// DateTime.monday (1) to DateTime.sunday (7); empty is every day.
  final Set<int> weekdays;

  /// Both null for any hour, else the entry's local hour h with fromHour <= h
  /// < toHour, wrapping past midnight when fromHour > toHour.
  final int? fromHour;
  final int? toHour;

  /// A starter-tree path; an area covers every tag under it.
  final String? tag;

  bool get hasHours => fromHour != null;

  bool holdsHour(int hour) {
    final int? from = fromHour;
    final int? to = toHour;
    if (from == null || to == null) return true;
    return from < to ? hour >= from && hour < to : hour >= from || hour < to;
  }

  bool holdsTags(List<String> triggers) {
    final String? tag = this.tag;
    if (tag == null) return true;
    return triggers.any(
      (String t) => t == tag || t.startsWith('$tag$triggerPathSeparator'),
    );
  }

  bool holdsDay(DateTime day) =>
      weekdays.isEmpty || weekdays.contains(day.weekday);

  @override
  bool operator ==(Object other) =>
      other is AskFilter &&
      other.weekdays.length == weekdays.length &&
      other.weekdays.containsAll(weekdays) &&
      other.fromHour == fromHour &&
      other.toHour == toHour &&
      other.tag == tag;

  @override
  int get hashCode =>
      Object.hash(Object.hashAllUnordered(weekdays), fromHour, toHour, tag);
}

/// One side of a query: which habit (an index into the list sent, null for
/// all), over what period, filtered how.
class AskSide {
  const AskSide({
    required this.habit,
    required this.period,
    this.filter = const AskFilter(),
  });

  final int? habit;
  final AskPeriod period;
  final AskFilter filter;
}

class AskQuery {
  const AskQuery({
    required this.side,
    required this.measure,
    required this.shape,
    this.bucket,
    this.condition,
    this.threshold,
    this.longest,
    this.versus,
  });

  final AskSide side;
  final AskMeasure measure;
  final AskShape shape;

  /// Series, last_time and runs: day, week or month (runs: day or week).
  final AskBucket? bucket;
  final AskCondition? condition;
  final double? threshold;
  final AskLongest? longest;

  /// The second side of a comparison.
  final AskSide? versus;
}

/// Whether the query counts the absence of something, so that days before
/// the habit's first entry would count trivially and are left out.
bool countsAbsence(AskQuery q) =>
    q.measure == AskMeasure.daysWithout ||
    q.condition == AskCondition.none ||
    q.condition == AskCondition.below ||
    q.longest == AskLongest.runWithout ||
    q.longest == AskLongest.gap;

/// What the server's answer asks the page to show.
sealed class AskParsed {
  const AskParsed();
}

class AskRun extends AskParsed {
  const AskRun(this.query);
  final AskQuery query;
}

/// A why or cause question: Insights answers those, by comparison.
class AskNeedsInsights extends AskParsed {
  const AskNeedsInsights();
}

class AskCannotAnswer extends AskParsed {
  const AskCannotAnswer(this.reason);

  /// Null when the query failed a check rather than the model declining.
  final AskReason? reason;
}

DateTime? _date(Object? value) {
  if (value is! String) return null;
  final RegExpMatch? m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
  if (m == null) return null;
  final int y = int.parse(m[1]!);
  final int mo = int.parse(m[2]!);
  final int d = int.parse(m[3]!);
  final DateTime date = DateTime(y, mo, d);
  // 2026-02-30 would roll into March.
  if (date.year != y || date.month != mo || date.day != d) return null;
  return date;
}

// Callable answers carry numbers as int or double.
int? _int(Object? value) {
  if (value is int) return value;
  if (value is double && value == value.roundToDouble() && value.isFinite) {
    return value.toInt();
  }
  return null;
}

class _Invalid implements Exception {
  const _Invalid();
}

Never _invalid() => throw const _Invalid();

final Set<String> _tagPaths = triggerPaths().toSet();

AskPeriod _period(Object? json, DateTime today) {
  if (json is! Map) _invalid();
  final AskPeriodType type =
      _enumOf(AskPeriodType.values, json['type']) ?? _invalid();
  switch (type) {
    case AskPeriodType.lastDays ||
        AskPeriodType.lastWeeks ||
        AskPeriodType.lastMonths:
      final int count = _int(json['count']) ?? _invalid();
      final int max = switch (type) {
        AskPeriodType.lastDays => maxLastDays,
        AskPeriodType.lastWeeks => maxLastWeeks,
        _ => maxLastMonths,
      };
      if (count < 1 || count > max) _invalid();
      return AskPeriod(type, count: count);
    case AskPeriodType.between:
      final DateTime from = _date(json['from']) ?? _invalid();
      final DateTime to = _date(json['to']) ?? _invalid();
      if (from.isBefore(askEarliest) || from.isAfter(today)) _invalid();
      if (to.isBefore(from)) _invalid();
      return AskPeriod(type, from: from, to: to.isAfter(today) ? today : to);
    default:
      return AskPeriod(type);
  }
}

AskFilter _filter(Object? json) {
  if (json is! Map) _invalid();
  final Object? days = json['weekdays'];
  if (days is! List) _invalid();
  final Set<int> weekdays = <int>{};
  for (final Object? day in days) {
    final int d = _int(day) ?? _invalid();
    if (d < 1 || d > 7) _invalid();
    weekdays.add(d);
  }
  final Object? fromJson = json['from_hour'];
  final Object? toJson = json['to_hour'];
  int? from = fromJson == null ? null : _int(fromJson) ?? _invalid();
  int? to = toJson == null ? null : _int(toJson) ?? _invalid();
  if (from != null || to != null) {
    from ??= 0;
    to ??= 24;
    if (from < 0 || from > 23 || to < 1 || to > 24 || from == to) _invalid();
    if (from == 0 && to == 24) from = to = null;
  }
  final Object? tag = json['tag'];
  if (tag != null && (tag is! String || !_tagPaths.contains(tag))) _invalid();
  return AskFilter(
    weekdays: weekdays.length == 7 ? const <int>{} : weekdays,
    fromHour: from,
    toHour: to,
    tag: tag as String?,
  );
}

int? _habit(Object? json, int habitCount) {
  if (json == null) return null;
  final int index = _int(json) ?? _invalid();
  if (index < 0 || index >= habitCount) _invalid();
  return index;
}

AskSide _side(
  Object? habit,
  Object? period,
  Object? filter,
  int n,
  DateTime t,
) => AskSide(
  habit: _habit(habit, n),
  period: _period(period, t),
  filter: _filter(filter),
);

/// The server's `query` checked against [habitCount] habits (the list sent
/// with the question) and [today]. Never throws: anything malformed, out of
/// range or meaningless is [AskCannotAnswer] with no reason.
AskParsed parseAskQuery(
  Object? json, {
  required int habitCount,
  required DateTime today,
}) {
  try {
    return _parse(json, habitCount, startOfDay(today));
  } on _Invalid {
    return const AskCannotAnswer(null);
  }
}

AskParsed _parse(Object? json, int habitCount, DateTime today) {
  if (json is! Map) _invalid();
  switch (json['kind']) {
    case 'needs_insights':
      return const AskNeedsInsights();
    case 'cannot_answer':
      return AskCannotAnswer(_enumOf(AskReason.values, json['reason']));
    case 'query':
      break;
    default:
      _invalid();
  }
  final AskSide side = _side(
    json['habit'],
    json['period'],
    json['filter'],
    habitCount,
    today,
  );
  AskMeasure measure =
      _enumOf(AskMeasure.values, json['measure']) ?? _invalid();
  final AskShape shape = _enumOf(AskShape.values, json['shape']) ?? _invalid();
  // "Nothing logged" and "something logged" are about entries whatever
  // measure came with them: days_without with none would find a week with
  // the habit every day.
  if (shape == AskShape.lastTime &&
      (json['condition'] == 'none' || json['condition'] == 'any')) {
    measure = AskMeasure.entries;
  }
  // An amount or spend over several habits would add unlike units or
  // currencies.
  bool oneHabit(AskSide s) => s.habit != null;
  final bool summable =
      measure == AskMeasure.entries ||
      measure == AskMeasure.daysWith ||
      measure == AskMeasure.daysWithout;
  if (!summable && !oneHabit(side)) _invalid();

  AskBucket? bucket;
  AskCondition? condition;
  double? threshold;
  AskLongest? longest;
  AskSide? versus;
  switch (shape) {
    case AskShape.total:
      break;
    case AskShape.series:
      bucket = _enumOf(AskBucket.values, json['bucket']) ?? _invalid();
    case AskShape.lastTime:
      bucket = _enumOf(AskBucket.values, json['bucket']) ?? _invalid();
      condition = _enumOf(AskCondition.values, json['condition']) ?? _invalid();
      if (condition == AskCondition.above || condition == AskCondition.below) {
        final Object? t = json['threshold'];
        if (t is! num || !t.isFinite || t < 0) _invalid();
        threshold = t.toDouble();
        if (condition == AskCondition.below && threshold == 0) _invalid();
      }
    case AskShape.longest:
      longest = _enumOf(AskLongest.values, json['longest']) ?? _invalid();
      if (longest != AskLongest.gap) {
        bucket = json['bucket'] == null
            ? AskBucket.day
            : _enumOf(AskBucket.values, json['bucket']) ?? _invalid();
        if (bucket == AskBucket.month) _invalid();
      }
    case AskShape.compare:
      final Object? v = json['versus'];
      if (v is! Map) _invalid();
      versus = _side(v['habit'], v['period'], v['filter'], habitCount, today);
      if (!summable && !oneHabit(versus)) _invalid();
  }
  return AskRun(
    AskQuery(
      side: side,
      measure: measure,
      shape: shape,
      bucket: bucket,
      condition: condition,
      threshold: threshold,
      longest: longest,
      versus: versus,
    ),
  );
}
