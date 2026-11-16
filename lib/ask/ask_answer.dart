/// The server's answer to a question (functions/ask_journal.js), read and
/// checked whole against functions/ask_query_schema.json and the limits the
/// schema cannot carry, before any of its SQL runs. Everything in it is
/// model-written, so untrusted: SQL goes through [JournalDb]'s sandbox, the
/// chart spec is checked against the result, and text is shown plain.
library;

enum AskKind { answer, needsInsights, cannotAnswer }

enum AskReason { none, notAboutJournal, unknownHabit, notSupported, unclear }

enum AskChartType { number, bar, line, table }

enum AskXKind { day, week, month, year, hour, weekday, category, none }

const Map<String, AskKind> _kinds = <String, AskKind>{
  'answer': AskKind.answer,
  'needs_insights': AskKind.needsInsights,
  'cannot_answer': AskKind.cannotAnswer,
};

const Map<String, AskReason> _reasons = <String, AskReason>{
  'none': AskReason.none,
  'not_about_journal': AskReason.notAboutJournal,
  'unknown_habit': AskReason.unknownHabit,
  'not_supported': AskReason.notSupported,
  'unclear': AskReason.unclear,
};

String _wire<T>(Map<String, T> names, T value) =>
    names.entries.firstWhere((MapEntry<String, T> e) => e.value == value).key;

/// Limits shared with functions/ask_journal.js (a test compares them).
abstract final class AskLimits {
  static const int cards = 3;
  static const int title = 80;
  static const int explain = 240;
  static const int sql = 4000;
  static const int y = 4;
  static const int column = 64;
}

class AskChartSpec {
  const AskChartSpec({
    required this.type,
    this.x = '',
    this.y = const <String>[],
    this.series = '',
    this.xKind = AskXKind.none,
  });

  final AskChartType type;
  final String x;
  final List<String> y;
  final String series;
  final AskXKind xKind;

  Map<String, Object?> toJson() => <String, Object?>{
    'type': type.name,
    'x': x,
    'y': y,
    'series': series,
    'x_kind': xKind.name,
  };
}

class AskCard {
  const AskCard({
    required this.title,
    required this.explain,
    required this.sql,
    required this.chart,
  });

  final String title;
  final String explain;
  final String sql;
  final AskChartSpec chart;

  Map<String, Object?> toJson() => <String, Object?>{
    'title': title,
    'explain': explain,
    'sql': sql,
    'chart': chart.toJson(),
  };
}

class AskAnswer {
  const AskAnswer({
    required this.kind,
    this.reason = AskReason.none,
    this.cards = const <AskCard>[],
  });

  final AskKind kind;
  final AskReason reason;
  final List<AskCard> cards;

  /// The answer as the server sent it, for a follow-up's history.
  Map<String, Object?> toJson() => <String, Object?>{
    'kind': _wire(_kinds, kind),
    'reason': _wire(_reasons, reason),
    'cards': <Object?>[for (final AskCard c in cards) c.toJson()],
  };
}

bool _keysExactly(Map<Object?, Object?> map, Set<String> keys) =>
    map.length == keys.length && map.keys.every(keys.contains);

String? _text(Object? value, int min, int max) =>
    value is String && value.length >= min && value.length <= max
    ? value
    : null;

AskChartSpec? _chart(Object? value) {
  if (value is! Map ||
      !_keysExactly(value, <String>{'type', 'x', 'y', 'series', 'x_kind'})) {
    return null;
  }
  final AskChartType? type = AskChartType.values
      .where((AskChartType t) => t.name == value['type'])
      .firstOrNull;
  final AskXKind? xKind = AskXKind.values
      .where((AskXKind k) => k.name == value['x_kind'])
      .firstOrNull;
  final String? x = _text(value['x'], 0, AskLimits.column);
  final String? series = _text(value['series'], 0, AskLimits.column);
  final Object? y = value['y'];
  if (type == null || xKind == null || x == null || series == null) {
    return null;
  }
  if (y is! List || y.length > AskLimits.y) return null;
  final List<String> ys = <String>[];
  for (final Object? name in y) {
    final String? s = _text(name, 1, AskLimits.column);
    if (s == null) return null;
    ys.add(s);
  }
  return AskChartSpec(type: type, x: x, y: ys, series: series, xKind: xKind);
}

AskCard? _card(Object? value) {
  if (value is! Map ||
      !_keysExactly(value, <String>{'title', 'explain', 'sql', 'chart'})) {
    return null;
  }
  final String? title = _text(value['title'], 1, AskLimits.title);
  final String? explain = _text(value['explain'], 1, AskLimits.explain);
  final String? sql = _text(value['sql'], 1, AskLimits.sql);
  final AskChartSpec? chart = _chart(value['chart']);
  if (title == null || explain == null || sql == null || chart == null) {
    return null;
  }
  return AskCard(title: title, explain: explain, sql: sql, chart: chart);
}

/// The answer, or null unless [value] fits the schema exactly: no missing or
/// extra key, every enum known, every text within its bounds, and the cards
/// the kind calls for (1 to 3 for an answer, none otherwise; a reason only
/// when it cannot answer).
AskAnswer? parseAskAnswer(Object? value) {
  if (value is! Map || !_keysExactly(value, <String>{'kind', 'reason', 'cards'})) {
    return null;
  }
  final AskKind? kind = _kinds[value['kind']];
  final AskReason? reason = _reasons[value['reason']];
  final Object? rawCards = value['cards'];
  if (kind == null || reason == null || rawCards is! List) return null;
  final List<AskCard> cards = <AskCard>[];
  for (final Object? raw in rawCards) {
    final AskCard? card = _card(raw);
    if (card == null) return null;
    cards.add(card);
  }
  final bool fits = switch (kind) {
    AskKind.answer =>
      reason == AskReason.none &&
          cards.isNotEmpty &&
          cards.length <= AskLimits.cards,
    AskKind.needsInsights => reason == AskReason.none && cards.isEmpty,
    AskKind.cannotAnswer => reason != AskReason.none && cards.isEmpty,
  };
  return fits ? AskAnswer(kind: kind, reason: reason, cards: cards) : null;
}

/// What a query produced on this device: column names in order and rows of
/// int, double, String or null. Never leaves the device.
class AskRows {
  const AskRows(this.columns, this.rows);

  final List<String> columns;
  final List<List<Object?>> rows;
}
