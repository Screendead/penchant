import 'dart:convert';
import 'dart:typed_data';

import 'package:tracker/insights/after_event.dart';
import 'package:tracker/insights/before_use.dart';
import 'package:tracker/insights/habit_follows.dart';
import 'package:tracker/insights/health_source.dart';
import 'package:tracker/insights/insights_report.dart';
import 'package:tracker/insights/measure_shifts.dart';
import 'package:tracker/insights/payoff.dart';
import 'package:tracker/insights/recovery.dart';
import 'package:tracker/insights/replacement.dart';
import 'package:tracker/insights/stats.dart';
import 'package:tracker/insights/step_changes.dart';
import 'package:tracker/insights/what_follows.dart';
import 'package:tracker/providers/insights_provider.dart';

// Health values and findings stay on the device: this is written only through
// SealedFiles, never logged or reported.

/// Raise with any change to what is written below or to the report's types,
/// so a file an older build wrote reads as absent.
const int insightsViewFormat = 2;

/// [view] as bytes to seal; null for a view with no computed report, which is
/// never kept. Throws only on a value JSON cannot hold.
Uint8List? encodeInsightsView(InsightsView view) {
  final HealthState health = view.health;
  final InsightsResult? result = view.result;
  if (health is! HealthReady || result is! InsightsComputed) return null;
  return utf8.encode(
    jsonEncode(<String, Object?>{
      'version': insightsViewFormat,
      'hoursPending': view.hoursPending,
      'health': <List<Object>>[
        for (final DailyOutcome o in health.values)
          <Object>[_time(o.date), o.metricId, _d(o.value)],
      ],
      'firstDays': <String, int>{
        for (final MapEntry<String, DateTime> e in result.firstDays.entries)
          e.key: _time(e.value),
      },
      'report': _report(result.report),
    }),
  );
}

/// The view [encodeInsightsView] wrote, never [InsightsView.updating]; null
/// for anything else, whole or nothing. Never throws.
InsightsView? decodeInsightsView(List<int> bytes) {
  try {
    final Object? json = jsonDecode(utf8.decode(bytes));
    final Map<String, Object?> m = _map(json);
    if (m['version'] != insightsViewFormat) return null;
    final List<DailyOutcome> values = _list(m, 'health', (Object? row) {
      if (row case [final int at, final String metricId, final Object? v]) {
        return DailyOutcome(_at(at), metricId, _toDouble(v));
      }
      throw const _Bad();
    });
    if (values.isEmpty) return null;
    final Map<String, DateTime> firstDays = <String, DateTime>{
      for (final MapEntry<String, Object?> e in _map(
        _req(m, 'firstDays'),
      ).entries)
        e.key: _at(_asInt(e.value)),
    };
    return (
      health: HealthReady(values),
      result: InsightsComputed(
        _readReport(_map(_req(m, 'report'))),
        firstDays: firstDays,
      ),
      hoursPending: _bool(m, 'hoursPending'),
      updating: false,
    );
  } catch (_) {
    return null;
  }
}

class _Bad implements Exception {
  const _Bad();
}

int _time(DateTime t) => t.microsecondsSinceEpoch;

DateTime _at(int micros) => DateTime.fromMicrosecondsSinceEpoch(micros);

// JSON holds no NaN or infinity.
Object _d(double v) => v.isFinite
    ? v
    : v.isNaN
    ? 'NaN'
    : v > 0
    ? 'Infinity'
    : '-Infinity';

Object? _od(double? v) => v == null ? null : _d(v);

double _toDouble(Object? v) => switch (v) {
  final num n => n.toDouble(),
  'NaN' => double.nan,
  'Infinity' => double.infinity,
  '-Infinity' => double.negativeInfinity,
  _ => throw const _Bad(),
};

Map<String, Object?> _map(Object? v) =>
    v is Map<String, Object?> ? v : throw const _Bad();

Object? _req(Map<String, Object?> m, String key) =>
    m.containsKey(key) ? m[key] : throw const _Bad();

int _asInt(Object? v) => v is int ? v : throw const _Bad();

String _str(Map<String, Object?> m, String key) => switch (_req(m, key)) {
  final String s => s,
  _ => throw const _Bad(),
};

String? _ostr(Map<String, Object?> m, String key) => switch (_req(m, key)) {
  null => null,
  final String s => s,
  _ => throw const _Bad(),
};

int _int(Map<String, Object?> m, String key) => _asInt(_req(m, key));

bool _bool(Map<String, Object?> m, String key) => switch (_req(m, key)) {
  final bool b => b,
  _ => throw const _Bad(),
};

double _dbl(Map<String, Object?> m, String key) => _toDouble(_req(m, key));

double? _odbl(Map<String, Object?> m, String key) => switch (_req(m, key)) {
  null => null,
  final Object v => _toDouble(v),
};

T _enum<T extends Enum>(List<T> values, Map<String, Object?> m, String key) {
  final String name = _str(m, key);
  for (final T v in values) {
    if (v.name == name) return v;
  }
  throw const _Bad();
}

T? _oenum<T extends Enum>(List<T> values, Map<String, Object?> m, String key) =>
    _req(m, key) == null ? null : _enum(values, m, key);

List<T> _list<T>(
  Map<String, Object?> m,
  String key,
  T Function(Object? item) read,
) => switch (_req(m, key)) {
  final List<Object?> items => <T>[for (final Object? i in items) read(i)],
  _ => throw const _Bad(),
};

T? _opt<T>(
  Map<String, Object?> m,
  String key,
  T Function(Map<String, Object?> m) read,
) => switch (_req(m, key)) {
  null => null,
  final Object v => read(_map(v)),
};

T Function(Object?) _each<T>(T Function(Map<String, Object?> m) read) =>
    (Object? v) => read(_map(v));

Map<String, Object?>? _ointerval(Interval? i) =>
    i == null ? null : _interval(i);

Map<String, Object?> _interval(Interval i) => <String, Object?>{
  'low': _d(i.low),
  'high': _d(i.high),
};

Interval _readInterval(Map<String, Object?> m) =>
    Interval(_dbl(m, 'low'), _dbl(m, 'high'));

Map<String, Object?> _report(InsightsReport r) => <String, Object?>{
  'findings': <Object?>[for (final HabitFinding f in r.findings) _insight(f)],
  'refused': <Object?>[for (final HabitRefusal f in r.refused) _insight(f)],
  'hoursAfterChecks': r.hoursAfterChecks,
  'floors': <String, Object>{
    for (final MapEntry<String, double> e in r.floors.entries)
      e.key: _d(e.value),
  },
  'follows': <Object?>[for (final HabitFollows f in r.follows) _follows(f)],
  'beforeUse': <Object?>[for (final BeforeUse b in r.beforeUse) _before(b)],
  'payoffs': <Object?>[for (final Payoff p in r.payoffs) _payoff(p)],
  'replacements': <Object?>[
    for (final Replacement x in r.replacements) _replacement(x),
  ],
  'shifts': <Object?>[for (final MeasureShift s in r.shifts) _shift(s)],
  'afterEvent': <Object?>[for (final AfterEvent a in r.afterEvent) _after(a)],
  'recovery': <Object?>[for (final Recovery x in r.recovery) _recovery(x)],
};

InsightsReport _readReport(Map<String, Object?> m) => InsightsReport(
  findings: _list(m, 'findings', (Object? v) {
    final HabitInsight i = _readInsight(_map(v));
    return i is HabitFinding ? i : throw const _Bad();
  }),
  refused: _list(m, 'refused', (Object? v) {
    final HabitInsight i = _readInsight(_map(v));
    return i is HabitRefusal ? i : throw const _Bad();
  }),
  hoursAfterChecks: _int(m, 'hoursAfterChecks'),
  floors: <String, double>{
    for (final MapEntry<String, Object?> e in _map(_req(m, 'floors')).entries)
      e.key: _toDouble(e.value),
  },
  follows: _list(m, 'follows', _each(_readFollows)),
  beforeUse: _list(m, 'beforeUse', _each(_readBefore)),
  payoffs: _list(m, 'payoffs', _each(_readPayoff)),
  replacements: _list(m, 'replacements', _each(_readReplacement)),
  shifts: _list(m, 'shifts', _each(_readShift)),
  afterEvent: _list(m, 'afterEvent', _each(_readAfter)),
  recovery: _list(m, 'recovery', _each(_readRecovery)),
);

Map<String, Object?> _comparison(Comparison c) => <String, Object?>{
  'exposedMean': _d(c.exposedMean),
  'unexposedMean': _d(c.unexposedMean),
  'exposedDays': c.exposedDays,
  'unexposedDays': c.unexposedDays,
  'interval': _interval(c.interval),
};

Comparison _readComparison(Map<String, Object?> m) => Comparison(
  exposedMean: _dbl(m, 'exposedMean'),
  unexposedMean: _dbl(m, 'unexposedMean'),
  exposedDays: _int(m, 'exposedDays'),
  unexposedDays: _int(m, 'unexposedDays'),
  interval: _readInterval(_map(_req(m, 'interval'))),
);

Map<String, Object?> _insight(HabitInsight i) => <String, Object?>{
  'type': switch (i) {
    HabitFinding() => 'finding',
    HabitRefusal() => 'refusal',
  },
  'habitId': i.habitId,
  'metricId': i.metricId,
  'lagDays': i.lagDays,
  'usableDays': i.usableDays,
  'exposedDays': i.exposedDays,
  'raw': i.raw == null ? null : _comparison(i.raw!),
  'kind': i.kind.name,
  'step': _d(i.step),
  'window': switch (i.window) {
    null => null,
    final HourWindow w => <String, int>{'start': w.start, 'end': w.end},
  },
  'cut': _od(i.cut),
  ...switch (i) {
    final HabitFinding f => <String, Object?>{
      'effect': _d(f.effect),
      'interval': _interval(f.interval),
      'standardized': _d(f.standardized),
      'pValue': _d(f.pValue),
      'spread': _od(f.spread),
      'sameBedtime': f.sameBedtime == null ? null : _insight(f.sameBedtime!),
      'heldFixed': (f.heldFixed.toList()..sort()),
    },
    final HabitRefusal r => <String, Object?>{
      'reason': r.reason.name,
      'entangledWith': r.entangledWith,
      'effect': _od(r.effect),
      'interval': _ointerval(r.interval),
      'pValue': _od(r.pValue),
      'shortfall': r.shortfall?.name,
    },
  },
};

HabitInsight _readInsight(Map<String, Object?> m) {
  final String habitId = _str(m, 'habitId');
  final String metricId = _str(m, 'metricId');
  final int lagDays = _int(m, 'lagDays');
  final int usableDays = _int(m, 'usableDays');
  final int exposedDays = _int(m, 'exposedDays');
  final Comparison? raw = _opt(m, 'raw', _readComparison);
  final InsightKind kind = _enum(InsightKind.values, m, 'kind');
  final double step = _dbl(m, 'step');
  final HourWindow? window = _opt(
    m,
    'window',
    (Map<String, Object?> w) => (start: _int(w, 'start'), end: _int(w, 'end')),
  );
  final double? cut = _odbl(m, 'cut');
  return switch (_str(m, 'type')) {
    'finding' => HabitFinding(
      habitId: habitId,
      metricId: metricId,
      lagDays: lagDays,
      usableDays: usableDays,
      exposedDays: exposedDays,
      raw: raw,
      kind: kind,
      step: step,
      window: window,
      cut: cut,
      effect: _dbl(m, 'effect'),
      interval: _readInterval(_map(_req(m, 'interval'))),
      standardized: _dbl(m, 'standardized'),
      pValue: _dbl(m, 'pValue'),
      spread: _odbl(m, 'spread'),
      sameBedtime: _opt(m, 'sameBedtime', _readInsight),
      heldFixed: _list(m, 'heldFixed', (Object? id) {
        if (id is String) return id;
        throw const _Bad();
      }).toSet(),
    ),
    'refusal' => HabitRefusal(
      habitId: habitId,
      metricId: metricId,
      lagDays: lagDays,
      usableDays: usableDays,
      exposedDays: exposedDays,
      raw: raw,
      kind: kind,
      step: step,
      window: window,
      cut: cut,
      reason: _enum(RefusalReason.values, m, 'reason'),
      entangledWith: _ostr(m, 'entangledWith'),
      effect: _odbl(m, 'effect'),
      interval: _opt(m, 'interval', _readInterval),
      pValue: _odbl(m, 'pValue'),
      shortfall: _oenum(HoursAfterShortfall.values, m, 'shortfall'),
    ),
    _ => throw const _Bad(),
  };
}

Map<String, Object?> _follows(HabitFollows f) => <String, Object?>{
  'leadId': f.leadId,
  'followerId': f.followerId,
  'days': f.days,
  'followedDays': f.followedDays,
  'uses': f.uses,
  'share': _d(f.share),
  'chance': _d(f.chance),
  'pValue': _od(f.pValue),
  'verdict': f.verdict?.name,
};

HabitFollows _readFollows(Map<String, Object?> m) => HabitFollows(
  leadId: _str(m, 'leadId'),
  followerId: _str(m, 'followerId'),
  days: _int(m, 'days'),
  followedDays: _int(m, 'followedDays'),
  uses: _int(m, 'uses'),
  share: _dbl(m, 'share'),
  chance: _dbl(m, 'chance'),
  pValue: _odbl(m, 'pValue'),
  verdict: _oenum(FollowsVerdict.values, m, 'verdict'),
);

Map<String, Object?> _before(BeforeUse b) => <String, Object?>{
  'habitId': b.habitId,
  'metricId': b.metricId,
  'kind': b.kind.name,
  'usableDays': b.usableDays,
  'exposedDays': b.exposedDays,
  'step': _d(b.step),
  'effect': _od(b.effect),
  'interval': _ointerval(b.interval),
  'pValue': _od(b.pValue),
  'spread': _od(b.spread),
  'refusal': b.refusal?.name,
  'shortfall': b.shortfall?.name,
};

BeforeUse _readBefore(Map<String, Object?> m) => BeforeUse(
  habitId: _str(m, 'habitId'),
  metricId: _str(m, 'metricId'),
  kind: _enum(BeforeUseKind.values, m, 'kind'),
  usableDays: _int(m, 'usableDays'),
  exposedDays: _int(m, 'exposedDays'),
  step: _dbl(m, 'step'),
  effect: _odbl(m, 'effect'),
  interval: _opt(m, 'interval', _readInterval),
  pValue: _odbl(m, 'pValue'),
  spread: _odbl(m, 'spread'),
  refusal: _oenum(RefusalReason.values, m, 'refusal'),
  shortfall: _oenum(HoursAfterShortfall.values, m, 'shortfall'),
);

Map<String, Object?> _fall(HabitFall f) => <String, Object?>{
  'habitId': f.habitId,
  'day': _time(f.day),
  'from': _time(f.from),
  'before': _d(f.before),
  'since': _d(f.since),
  'sinceDays': f.sinceDays,
};

HabitFall _readFall(Map<String, Object?> m) => HabitFall(
  habitId: _str(m, 'habitId'),
  day: _at(_int(m, 'day')),
  from: _at(_int(m, 'from')),
  before: _dbl(m, 'before'),
  since: _dbl(m, 'since'),
  sinceDays: _int(m, 'sinceDays'),
);

Map<String, Object?> _payoff(Payoff p) => <String, Object?>{
  'fall': _fall(p.fall),
  'metricId': p.metricId,
  'baselineValues': p.baselineValues,
  'sinceValues': p.sinceValues,
  'capped': p.capped,
  'effect': _od(p.effect),
  'interval': _ointerval(p.interval),
  'pValue': _od(p.pValue),
  'autocorrelation': _od(p.autocorrelation),
  'refusal': p.refusal?.name,
  'otherHabitId': p.otherHabitId,
};

Payoff _readPayoff(Map<String, Object?> m) => Payoff(
  fall: _readFall(_map(_req(m, 'fall'))),
  metricId: _str(m, 'metricId'),
  baselineValues: _int(m, 'baselineValues'),
  sinceValues: _int(m, 'sinceValues'),
  capped: _bool(m, 'capped'),
  effect: _odbl(m, 'effect'),
  interval: _opt(m, 'interval', _readInterval),
  pValue: _odbl(m, 'pValue'),
  autocorrelation: _odbl(m, 'autocorrelation'),
  refusal: _oenum(PayoffRefusal.values, m, 'refusal'),
  otherHabitId: _ostr(m, 'otherHabitId'),
);

Map<String, Object?> _replacement(Replacement r) => <String, Object?>{
  'fall': _fall(r.fall),
  'riserId': r.riserId,
  'before': _d(r.before),
  'since': _d(r.since),
  'baselineDays': r.baselineDays,
  'sinceDays': r.sinceDays,
  'effect': _od(r.effect),
  'interval': _ointerval(r.interval),
  'pValue': _od(r.pValue),
  'refusal': r.refusal?.name,
  'began': r.began,
};

Replacement _readReplacement(Map<String, Object?> m) => Replacement(
  fall: _readFall(_map(_req(m, 'fall'))),
  riserId: _str(m, 'riserId'),
  before: _dbl(m, 'before'),
  since: _dbl(m, 'since'),
  baselineDays: _int(m, 'baselineDays'),
  sinceDays: _int(m, 'sinceDays'),
  effect: _odbl(m, 'effect'),
  interval: _opt(m, 'interval', _readInterval),
  pValue: _odbl(m, 'pValue'),
  refusal: _oenum(ReplacementRefusal.values, m, 'refusal'),
  began: _bool(m, 'began'),
);

Map<String, Object?> _shift(MeasureShift s) => <String, Object?>{
  'metricId': s.metricId,
  'shift': <String, Object?>{
    'at': _time(s.shift.at),
    'before': _d(s.shift.before),
    'after': _d(s.shift.after),
    'daysBefore': s.shift.daysBefore,
    'daysAfter': s.shift.daysAfter,
    'pValue': _d(s.shift.pValue),
  },
  'habits': <Object?>[
    for (final HabitChange h in s.habits)
      <String, Object?>{
        'habitId': h.habitId,
        'before': _d(h.before),
        'after': _d(h.after),
      },
  ],
  'found': s.found,
};

MeasureShift _readShift(Map<String, Object?> m) {
  final Map<String, Object?> shift = _map(_req(m, 'shift'));
  return MeasureShift(
    metricId: _str(m, 'metricId'),
    shift: LevelShift(
      at: _at(_int(shift, 'at')),
      before: _dbl(shift, 'before'),
      after: _dbl(shift, 'after'),
      daysBefore: _int(shift, 'daysBefore'),
      daysAfter: _int(shift, 'daysAfter'),
      pValue: _dbl(shift, 'pValue'),
    ),
    habits: _list(
      m,
      'habits',
      _each(
        (Map<String, Object?> h) => HabitChange(
          habitId: _str(h, 'habitId'),
          before: _dbl(h, 'before'),
          after: _dbl(h, 'after'),
        ),
      ),
    ),
    found: _bool(m, 'found'),
  );
}

Map<String, Object?> _after(AfterEvent a) => <String, Object?>{
  'habitId': a.habitId,
  'eventDays': a.eventDays,
  'controlDays': a.controlDays,
  'eventRate': _d(a.eventRate),
  'controlRate': _d(a.controlRate),
  'effect': _od(a.effect),
  'interval': _ointerval(a.interval),
  'pValue': _od(a.pValue),
  'refusal': a.refusal?.name,
};

AfterEvent _readAfter(Map<String, Object?> m) => AfterEvent(
  habitId: _str(m, 'habitId'),
  eventDays: _int(m, 'eventDays'),
  controlDays: _int(m, 'controlDays'),
  eventRate: _dbl(m, 'eventRate'),
  controlRate: _dbl(m, 'controlRate'),
  effect: _odbl(m, 'effect'),
  interval: _opt(m, 'interval', _readInterval),
  pValue: _odbl(m, 'pValue'),
  refusal: _oenum(RefusalReason.values, m, 'refusal'),
);

Map<String, Object?> _recovery(Recovery r) => <String, Object?>{
  'habitId': r.habitId,
  'metricId': r.metricId,
  'usableDays': r.usableDays,
  'heavyDays': r.heavyDays,
  'cut': _od(r.cut),
  'floor': _od(r.floor),
  'nights': <Object?>[
    for (final RecoveryNight n in r.nights)
      <String, Object?>{
        'effect': _d(n.effect),
        'interval': _interval(n.interval),
        'pValue': _d(n.pValue),
        'off': n.off,
        'back': n.back,
      },
  ],
  'refusal': r.refusal?.name,
};

Recovery _readRecovery(Map<String, Object?> m) => Recovery(
  habitId: _str(m, 'habitId'),
  metricId: _str(m, 'metricId'),
  usableDays: _int(m, 'usableDays'),
  heavyDays: _int(m, 'heavyDays'),
  cut: _odbl(m, 'cut'),
  floor: _odbl(m, 'floor'),
  nights: _list(
    m,
    'nights',
    _each(
      (Map<String, Object?> n) => RecoveryNight(
        effect: _dbl(n, 'effect'),
        interval: _readInterval(_map(_req(n, 'interval'))),
        pValue: _dbl(n, 'pValue'),
        off: _bool(n, 'off'),
        back: _bool(n, 'back'),
      ),
    ),
  ),
  refusal: _oenum(RefusalReason.values, m, 'refusal'),
);
