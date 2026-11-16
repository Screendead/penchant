import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tracker/ask/ask_answer.dart';
import 'package:tracker/design/dial_theme.dart';
import 'package:tracker/design/habit_mark.dart';
import 'package:tracker/design/tokens.dart';
import 'package:tracker/widgets/chart_text.dart';

/// How a checked answer is drawn. The spec and rows are untrusted, so the
/// plan only ever narrows them: anything that does not fit becomes a table.
enum AskChartKind { number, bar, line, table }

abstract final class AskChartLimits {
  static const int rows = 500;
  static const int tableRows = 100;
  static const int pivotSeries = 6;
  static const int columnSeries = 4;
  static const int label = 40;
}

/// One x value, in the words the axis, read-out and Today button use.
class AskPoint {
  const AskPoint({
    required this.axis,
    required this.axisWithYear,
    required this.full,
    this.year,
    this.day,
    this.openLabel,
  });

  final String axis;
  final String axisWithYear;
  final String full;

  /// For dates: the year the axis label omits.
  final int? year;

  /// For day, week and month points: the day Today opens.
  final DateTime? day;
  final String? openLabel;
}

class AskSeries {
  const AskSeries({
    required this.key,
    required this.name,
    required this.values,
  });

  /// The column name or series value as the result gave it.
  final String key;
  final String name;
  final List<double?> values;
}

class AskChartPlan {
  const AskChartPlan._({
    required this.kind,
    this.xKind = AskXKind.none,
    this.points = const <AskPoint>[],
    this.series = const <AskSeries>[],
    this.number,
    this.numberLabel = '',
    this.columns = const <String>[],
    this.cells = const <List<String>>[],
    this.totalRows = 0,
  });

  final AskChartKind kind;
  final AskXKind xKind;
  final List<AskPoint> points;
  final List<AskSeries> series;
  final num? number;
  final String numberLabel;

  /// For a table: humanised headers and formatted cells, at most
  /// [AskChartLimits.tableRows] of [totalRows].
  final List<String> columns;
  final List<List<String>> cells;
  final int totalRows;

  /// "First 100 of 340 rows", or null when the table shows every row.
  String? get tableNote => totalRows > cells.length
      ? 'First ${cells.length} of $totalRows rows'
      : null;
}

String _bound(String text) => text.length <= AskChartLimits.label
    ? text
    : '${text.substring(0, AskChartLimits.label - 1)}…';

/// "glasses_total" as "Glasses total".
String humaniseColumn(String name) {
  final String spaced = name
      .replaceAll('_', ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (spaced.isEmpty) return _bound(name);
  return _bound(spaced[0].toUpperCase() + spaced.substring(1));
}

/// Integers without decimals, anything else to at most 2.
String formatAskNumber(num value) {
  if (value is int) return '$value';
  if (!value.isFinite) return '$value';
  if (value == value.roundToDouble() && value.abs() < 1e15) {
    return '${value.toInt()}';
  }
  String fixed = value.toStringAsFixed(2);
  fixed = fixed
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
  return fixed == '-0' ? '0' : fixed;
}

String formatAskValue(Object? value) => switch (value) {
  null => '–',
  final num n => formatAskNumber(n),
  final String s => _bound(s),
  final Object o => _bound('$o'),
};

const List<String> _monthShort = <String>[
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];
const List<String> _monthFull = <String>[
  'January', 'February', 'March', 'April', 'May', 'June', //
  'July', 'August', 'September', 'October', 'November', 'December',
];
const List<String> _weekdayShort = <String>[
  'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun', //
];
const List<String> _weekdayFull = <String>[
  'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', //
  'Sunday',
];

DateTime? _date(Object? value) {
  if (value is! String) return null;
  final RegExpMatch? m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
  if (m == null) return null;
  final int y = int.parse(m[1]!), mo = int.parse(m[2]!), d = int.parse(m[3]!);
  final DateTime date = DateTime(y, mo, d);
  return date.year == y && date.month == mo && date.day == d ? date : null;
}

int? _wholeIn(Object? value, int low, int high, {RegExp? text}) {
  int? n;
  if (value is int) {
    n = value;
  } else if (value is double && value == value.roundToDouble()) {
    n = value.isFinite ? value.toInt() : null;
  } else if (value is String && text != null && text.hasMatch(value)) {
    n = int.parse(value);
  }
  return n != null && n >= low && n <= high ? n : null;
}

String _dayMonth(DateTime d) => '${d.day} ${_monthShort[d.month - 1]}';

/// The point for one x value and its sort key, or null if it does not fit.
(Object, AskPoint)? _point(AskXKind kind, Object? value) {
  switch (kind) {
    case AskXKind.day:
    case AskXKind.week:
      final DateTime? d = _date(value);
      if (d == null) return null;
      if (kind == AskXKind.week && d.weekday != DateTime.monday) return null;
      final String short = _dayMonth(d);
      final String withYear = '$short ${d.year}';
      final String weekdayDay = '${_weekdayShort[d.weekday - 1]} $withYear';
      final bool week = kind == AskXKind.week;
      return (
        d.year * 10000 + d.month * 100 + d.day,
        AskPoint(
          axis: week ? 'w/c $short' : short,
          axisWithYear: week ? 'w/c $withYear' : withYear,
          full: week ? 'Week of $weekdayDay' : weekdayDay,
          year: d.year,
          day: d,
          openLabel: week ? 'week of $withYear' : weekdayDay,
        ),
      );
    case AskXKind.month:
      if (value is! String) return null;
      final RegExpMatch? m = RegExp(r'^(\d{4})-(\d{2})$').firstMatch(value);
      if (m == null) return null;
      final int y = int.parse(m[1]!), mo = int.parse(m[2]!);
      if (mo < 1 || mo > 12) return null;
      final String full = '${_monthFull[mo - 1]} $y';
      return (
        y * 100 + mo,
        AskPoint(
          axis: _monthShort[mo - 1],
          axisWithYear: '${_monthShort[mo - 1]} $y',
          full: full,
          year: y,
          day: DateTime(y, mo),
          openLabel: full,
        ),
      );
    case AskXKind.year:
      final int? y = _wholeIn(value, 1000, 9999, text: RegExp(r'^\d{4}$'));
      if (y == null) return null;
      return (y, AskPoint(axis: '$y', axisWithYear: '$y', full: '$y'));
    case AskXKind.hour:
      final int? h = _wholeIn(value, 0, 23, text: RegExp(r'^\d{1,2}$'));
      if (h == null) return null;
      String two(int n) => n.toString().padLeft(2, '0');
      return (
        h,
        AskPoint(
          axis: two(h),
          axisWithYear: two(h),
          full: '${two(h)}:00–${two((h + 1) % 24)}:00',
        ),
      );
    case AskXKind.weekday:
      final int? w = _wholeIn(value, 1, 7, text: RegExp(r'^\d$'));
      if (w == null) return null;
      return (
        w,
        AskPoint(
          axis: _weekdayShort[w - 1],
          axisWithYear: _weekdayShort[w - 1],
          full: _weekdayFull[w - 1],
        ),
      );
    case AskXKind.category:
      if (value == null) return null;
      final String label = formatAskValue(value);
      return (
        '${value.runtimeType}:$value',
        AskPoint(axis: label, axisWithYear: label, full: label),
      );
    case AskXKind.none:
      return null;
  }
}

AskChartPlan _table(AskRows rows) {
  final int width = rows.columns.length;
  return AskChartPlan._(
    kind: AskChartKind.table,
    columns: <String>[for (final String c in rows.columns) humaniseColumn(c)],
    cells: <List<String>>[
      for (final List<Object?> row in rows.rows.take(AskChartLimits.tableRows))
        <String>[
          for (int i = 0; i < width; i++)
            formatAskValue(i < row.length ? row[i] : null),
        ],
    ],
    totalRows: rows.rows.length,
  );
}

bool _numericOrNull(Object? v) =>
    v == null || v is int || (v is double && v.isFinite);

/// Checks [spec] against [rows] and says how to draw them. Never throws:
/// whatever does not fit is a table.
AskChartPlan planAskChart(AskChartSpec spec, AskRows rows) {
  final List<String> columns = rows.columns;
  final AskChartPlan table = _table(rows);
  if (rows.rows.length > AskChartLimits.rows ||
      rows.rows.any((List<Object?> r) => r.length != columns.length) ||
      columns.toSet().length != columns.length) {
    return table;
  }
  Object? cell(List<Object?> row, String column) =>
      row[columns.indexOf(column)];
  bool numericColumn(String c) =>
      rows.rows.every((List<Object?> r) => _numericOrNull(cell(r, c)));
  if (spec.type == AskChartType.table) return table;

  List<String> ys = spec.y;
  if (ys.any((String y) => !columns.contains(y))) return table;
  if (ys.isEmpty) {
    final List<String> candidates = <String>[
      for (final String c in columns)
        if (c != spec.x &&
            c != spec.series &&
            numericColumn(c) &&
            rows.rows.any((List<Object?> r) => cell(r, c) != null))
          c,
    ];
    if (candidates.length != 1) return table;
    ys = candidates;
  }
  if (!ys.every(numericColumn)) return table;

  if (spec.type == AskChartType.number) {
    if (rows.rows.length != 1 || ys.length != 1) return table;
    return AskChartPlan._(
      kind: AskChartKind.number,
      number: cell(rows.rows.single, ys.single) as num?,
      numberLabel: humaniseColumn(ys.single),
    );
  }

  if (spec.x.isEmpty ||
      !columns.contains(spec.x) ||
      ys.contains(spec.x) ||
      spec.xKind == AskXKind.none ||
      rows.rows.isEmpty) {
    return table;
  }
  final bool pivot = spec.series.isNotEmpty;
  if (pivot &&
      (!columns.contains(spec.series) ||
          spec.series == spec.x ||
          ys.length != 1 ||
          ys.contains(spec.series))) {
    return table;
  }
  if (!pivot && ys.length > AskChartLimits.columnSeries) return table;

  final Map<Object, (Object, AskPoint)> byKey = <Object, (Object, AskPoint)>{};
  final List<Object> order = <Object>[];
  final List<Object> rowKeys = <Object>[];
  for (final List<Object?> row in rows.rows) {
    final (Object, AskPoint)? p = _point(spec.xKind, cell(row, spec.x));
    if (p == null) return table;
    if (!byKey.containsKey(p.$1)) {
      byKey[p.$1] = p;
      order.add(p.$1);
    } else if (!pivot) {
      return table;
    }
    rowKeys.add(p.$1);
  }
  if (spec.xKind != AskXKind.category) {
    order.sort((Object a, Object b) => (a as int).compareTo(b as int));
  }
  final Map<Object, int> index = <Object, int>{
    for (int i = 0; i < order.length; i++) order[i]: i,
  };
  final int n = order.length;

  final List<AskSeries> series;
  if (pivot) {
    final Map<String, List<double?>> values = <String, List<double?>>{};
    final Set<(String, int)> seen = <(String, int)>{};
    for (int r = 0; r < rows.rows.length; r++) {
      final String name = formatAskValue(cell(rows.rows[r], spec.series));
      final List<double?> list = values.putIfAbsent(
        name,
        () => List<double?>.filled(n, null),
      );
      if (values.length > AskChartLimits.pivotSeries) return table;
      final int i = index[rowKeys[r]]!;
      if (!seen.add((name, i))) return table;
      list[i] = (cell(rows.rows[r], ys.single) as num?)?.toDouble();
    }
    series = <AskSeries>[
      for (final MapEntry<String, List<double?>> e in values.entries)
        AskSeries(key: e.key, name: e.key, values: e.value),
    ];
  } else {
    series = <AskSeries>[
      for (final String y in ys)
        AskSeries(
          key: y,
          name: humaniseColumn(y),
          values: <double?>[for (int i = 0; i < n; i++) null],
        ),
    ];
    for (int r = 0; r < rows.rows.length; r++) {
      for (int s = 0; s < ys.length; s++) {
        series[s].values[index[rowKeys[r]]!] =
            (cell(rows.rows[r], ys[s]) as num?)?.toDouble();
      }
    }
  }

  return AskChartPlan._(
    kind: spec.type == AskChartType.line && n >= 2
        ? AskChartKind.line
        : AskChartKind.bar,
    xKind: spec.xKind,
    points: <AskPoint>[for (final Object k in order) byKey[k]!.$2],
    series: series,
  );
}

/// Which of [count] points to label, at most [maxLabels], first and last
/// always among them.
List<int> askLabelIndices(int count, int maxLabels) {
  if (count <= 0) return const <int>[];
  if (count <= max(2, maxLabels)) {
    return <int>[for (int i = 0; i < count; i++) i];
  }
  if (maxLabels <= 2) return <int>[0, count - 1];
  final int step = ((count - 1) / (maxLabels - 1)).ceil();
  final List<int> picked = <int>[for (int i = 0; i < count - 1; i += step) i];
  // Too close to the last label to sit beside it.
  if (count - 1 - picked.last < step / 2 && picked.length > 1) {
    picked.removeLast();
  }
  return <int>[...picked, count - 1];
}

/// The axis label of each point, null where none fits: dates carry the year
/// at the first and last label and wherever it changes from the label before.
List<String?> askAxisLabels(AskChartPlan plan, int maxLabels) {
  final List<String?> labels = List<String?>.filled(plan.points.length, null);
  final List<int> shown = askLabelIndices(plan.points.length, maxLabels);
  int? previousYear;
  for (int k = 0; k < shown.length; k++) {
    final AskPoint p = plan.points[shown[k]];
    final bool withYear =
        p.year != null &&
        (k == 0 || k == shown.length - 1 || p.year != previousYear);
    labels[shown[k]] = withYear ? p.axisWithYear : p.axis;
    previousYear = p.year;
  }
  return labels;
}

String _valueText(double? v) => v == null ? '–' : formatAskNumber(v);

/// What the read-out says at [index]: "December 2025: Wine 12, Beer 4".
String askReadout(AskChartPlan plan, int index) {
  final String values = <String>[
    for (final AskSeries s in plan.series)
      '${s.name} ${_valueText(s.values[index])}',
  ].join(', ');
  return '${plan.points[index].full}: $values';
}

/// The chart's spoken summary: its kind, the span of x, and each series'
/// highest and lowest point.
String askChartSummary(AskChartPlan plan) {
  if (plan.points.isEmpty) return '';
  final String kind = plan.kind == AskChartKind.line ? 'Line' : 'Bar';
  final String span = plan.points.length == 1
      ? plan.points.single.full
      : 'from ${plan.points.first.full} to ${plan.points.last.full}';
  final List<String> parts = <String>['$kind chart, $span.'];
  for (final AskSeries s in plan.series) {
    int? hi, lo;
    for (int i = 0; i < s.values.length; i++) {
      final double? v = s.values[i];
      if (v == null) continue;
      if (hi == null || v > s.values[hi]!) hi = i;
      if (lo == null || v < s.values[lo]!) lo = i;
    }
    if (hi == null || lo == null) {
      parts.add('${s.name}: no values.');
    } else {
      parts.add(
        '${s.name}: highest ${_valueText(s.values[hi])} at '
        '${plan.points[hi].full}, lowest ${_valueText(s.values[lo])} at '
        '${plan.points[lo].full}.',
      );
    }
  }
  return parts.join(' ');
}

({double low, double high, double step}) _scale(AskChartPlan plan) {
  double hi = 0, lo = 0;
  for (final AskSeries s in plan.series) {
    for (final double? v in s.values) {
      if (v == null) continue;
      hi = max(hi, v);
      lo = min(lo, v);
    }
  }
  final double span = hi - lo;
  if (span <= 0) return (low: 0, high: 1, step: 0.25);
  final double raw = span * 1.1 / 4;
  final double magnitude = pow(10, (log(raw) / ln10).floor()).toDouble();
  final double step = <double>[
    1,
    2,
    2.5,
    5,
    10,
  ].map((double f) => f * magnitude).firstWhere((double s) => s >= raw);
  return (
    low: lo < 0 ? -((-lo * 1.1) / step).ceil() * step : 0,
    high: hi > 0 ? ((hi * 1.1) / step).ceil() * step : 0,
    step: step,
  );
}

class AskChart extends StatefulWidget {
  const AskChart({
    super.key,
    required this.spec,
    required this.rows,
    this.marksByName = const <String, HabitMark>{},
    this.onOpenDay,
  });

  final AskChartSpec spec;
  final AskRows rows;

  /// Habit marks by habit name, for series named after a habit.
  final Map<String, HabitMark> marksByName;
  final ValueChanged<DateTime>? onOpenDay;

  static const double plotHeight = 200;
  static const String focusLabel = 'Ask chart';

  @override
  State<AskChart> createState() => _AskChartState();
}

class _AskChartState extends State<AskChart> {
  late AskChartPlan _plan;
  late int _cursor;
  final FocusNode _focus = FocusNode(debugLabel: AskChart.focusLabel);

  static const double _labelGap = 6;

  @override
  void initState() {
    super.initState();
    _replan();
  }

  @override
  void didUpdateWidget(AskChart old) {
    super.didUpdateWidget(old);
    if (old.spec != widget.spec || old.rows != widget.rows) _replan();
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _replan() {
    _plan = planAskChart(widget.spec, widget.rows);
    _cursor = max(0, _plan.points.length - 1);
  }

  void _moveTo(int index) {
    final int clamped = index.clamp(0, max(0, _plan.points.length - 1));
    if (clamped != _cursor) setState(() => _cursor = clamped);
  }

  @override
  Widget build(BuildContext context) => switch (_plan.kind) {
    AskChartKind.number => _number(context),
    AskChartKind.table => _tableView(context),
    AskChartKind.bar || AskChartKind.line => _chart(context),
  };

  Widget _number(BuildContext context) {
    final DialType type = DialType.of(context);
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final num? value = _plan.number;
    return MergeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            value == null ? '–' : formatAskNumber(value),
            style: type.displayXL.copyWith(color: scheme.onSurface),
          ),
          Text(
            _plan.numberLabel,
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: DialColors.of(context).muted),
          ),
        ],
      ),
    );
  }

  Widget _tableView(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final DialColors colors = DialColors.of(context);
    final TextStyle? head = text.labelLarge;
    final TextStyle? body = text.bodyMedium;
    Widget cell(String s, TextStyle? style) => Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: DialSpace.xs,
        vertical: DialSpace.xxs,
      ),
      child: Text(
        s,
        style: style,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
    final String? note = _plan.tableNote;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (_plan.cells.isEmpty)
          Text('No rows', style: body?.copyWith(color: colors.muted))
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Table(
              defaultColumnWidth: const IntrinsicColumnWidth(),
              border: TableBorder(
                horizontalInside: BorderSide(color: colors.line),
              ),
              children: <TableRow>[
                TableRow(
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: colors.line)),
                  ),
                  children: <Widget>[
                    for (final String c in _plan.columns) cell(c, head),
                  ],
                ),
                for (final List<String> row in _plan.cells)
                  TableRow(
                    children: <Widget>[
                      for (final String v in row) cell(v, body),
                    ],
                  ),
              ],
            ),
          ),
        if (note != null) ...<Widget>[
          const SizedBox(height: DialSpace.xs),
          Text(note, style: text.bodySmall?.copyWith(color: colors.muted)),
        ],
      ],
    );
  }

  Color _colour(int s, DialColors colors, ColorScheme scheme) {
    final AskSeries series = _plan.series[s];
    final HabitMark? mark =
        widget.marksByName[series.key] ?? widget.marksByName[series.name];
    if (mark != null) return colors.habit(mark);
    // The habit hues mean habits, so other series are ink, told apart by
    // shade on bars and by dashes on lines.
    final List<Color> inks = <Color>[
      scheme.onSurface,
      colors.muted,
      scheme.outline,
      colors.spoke,
    ];
    return inks[_nonHabitRank(s) % inks.length];
  }

  int _nonHabitRank(int s) {
    int rank = 0;
    for (int i = 0; i < s; i++) {
      final AskSeries other = _plan.series[i];
      if (!widget.marksByName.containsKey(other.key) &&
          !widget.marksByName.containsKey(other.name)) {
        rank++;
      }
    }
    return rank;
  }

  List<int>? _dashes(int s) {
    final AskSeries series = _plan.series[s];
    if (widget.marksByName.containsKey(series.key) ||
        widget.marksByName.containsKey(series.name)) {
      return null;
    }
    const List<List<int>?> patterns = <List<int>?>[
      null,
      <int>[6, 3],
      <int>[2, 3],
      <int>[8, 3, 2, 3],
    ];
    return patterns[_nonHabitRank(s) % patterns.length];
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _moveTo(_cursor - 1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      _moveTo(_cursor + 1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _chart(BuildContext context) {
    final DialColors colors = DialColors.of(context);
    final DialType type = DialType.of(context);
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;
    final int n = _plan.points.length;
    final int shown = _cursor.clamp(0, n - 1);
    final AskPoint point = _plan.points[shown];
    final VoidCallback? earlier = shown > 0 ? () => _moveTo(shown - 1) : null;
    final VoidCallback? later = shown < n - 1 ? () => _moveTo(shown + 1) : null;
    final bool canOpen =
        widget.onOpenDay != null &&
        point.day != null &&
        (_plan.xKind == AskXKind.day ||
            _plan.xKind == AskXKind.week ||
            _plan.xKind == AskXKind.month);

    final Widget readout = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          point.full,
          style: text.labelLarge,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        Wrap(
          spacing: DialSpace.s,
          children: <Widget>[
            for (int s = 0; s < _plan.series.length; s++)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (_plan.series.length > 1) ...<Widget>[
                    _Swatch(colour: _colour(s, colors, scheme)),
                    const SizedBox(width: DialSpace.xxs),
                  ],
                  Text(
                    '${_plan.series[s].name} '
                    '${_valueText(_plan.series[s].values[shown])}',
                    style: type.monoM.copyWith(color: scheme.onSurface),
                  ),
                ],
              ),
          ],
        ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Semantics(
          container: true,
          label: askChartSummary(_plan),
          value: askReadout(_plan, shown),
          decreasedValue: earlier == null ? null : askReadout(_plan, shown - 1),
          increasedValue: later == null ? null : askReadout(_plan, shown + 1),
          onDecrease: earlier,
          onIncrease: later,
          excludeSemantics: true,
          child: Focus(
            focusNode: _focus,
            onKeyEvent: _onKey,
            child: Builder(
              builder: (BuildContext context) => DecoratedBox(
                position: DecorationPosition.foreground,
                decoration: ShapeDecoration(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(DialRadius.tile),
                    side: Focus.of(context).hasPrimaryFocus
                        ? BorderSide(
                            color: scheme.primary,
                            width: 2,
                            strokeAlign: BorderSide.strokeAlignOutside,
                          )
                        : BorderSide.none,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    readout,
                    const SizedBox(height: DialSpace.xs),
                    _plot(context, shown, colors, type, scheme),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (canOpen)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              onPressed: () => widget.onOpenDay!(point.day!),
              child: Text('Open ${point.openLabel} in Today'),
            ),
          ),
      ],
    );
  }

  Widget _plot(
    BuildContext context,
    int shown,
    DialColors colors,
    DialType type,
    ColorScheme scheme,
  ) {
    final int n = _plan.points.length;
    final TextStyle axisStyle = type.monoS.copyWith(color: colors.muted);
    final ({double low, double high, double step}) scale = _scale(_plan);
    final double leftWidth =
        <String>[
              formatAskNumber(scale.high),
              formatAskNumber(scale.low),
              formatAskNumber(scale.low + scale.step),
            ]
            .map((String s) => chartLabelSize(context, s, axisStyle).width)
            .reduce(max) +
        _labelGap;
    final double bottomHeight = max(
      24,
      chartLabelSize(context, '0', axisStyle).height + _labelGap,
    );
    final double widest = _plan.points
        .map(
          (AskPoint p) =>
              chartLabelSize(context, p.axisWithYear, axisStyle).width,
        )
        .reduce(max);
    final Duration duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : DialMotion.pendingFill;
    final bool line = _plan.kind == AskChartKind.line;

    return SizedBox(
      height: AskChart.plotHeight,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final double plotWidth = max(1, constraints.maxWidth - leftWidth);
          final List<String?> labels = askAxisLabels(
            _plan,
            min(8, (plotWidth + 8) ~/ (widest + 12)),
          );

          int indexAt(double dx) {
            final double t = ((dx - leftWidth) / plotWidth).clamp(0, 1);
            return line ? (t * (n - 1)).round() : min(n - 1, (t * n).floor());
          }

          void touch(Offset at) {
            _focus.requestFocus();
            _moveTo(indexAt(at.dx));
          }

          Widget bottomTitle(double value, TitleMeta meta) {
            final int i = value.round();
            if (value != i.toDouble() || i < 0 || i >= n || labels[i] == null) {
              return const SizedBox.shrink();
            }
            return SideTitleWidget(
              meta: meta,
              fitInside: SideTitleFitInsideData.fromTitleMeta(
                meta,
                distanceFromEdge: 0,
              ),
              child: Text(
                labels[i]!,
                style: axisStyle,
                maxLines: 1,
                softWrap: false,
              ),
            );
          }

          final FlTitlesData titles = FlTitlesData(
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: leftWidth,
                interval: scale.step,
                getTitlesWidget: (double value, TitleMeta meta) => Padding(
                  padding: const EdgeInsets.only(right: _labelGap),
                  child: Text(
                    formatAskNumber(value),
                    style: axisStyle,
                    textAlign: TextAlign.end,
                  ),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: bottomHeight,
                interval: 1,
                getTitlesWidget: bottomTitle,
              ),
            ),
          );
          final FlGridData grid = FlGridData(
            drawVerticalLine: false,
            horizontalInterval: scale.step,
            getDrawingHorizontalLine: (double _) =>
                FlLine(color: colors.line, strokeWidth: 1),
          );

          final Widget chart = line
              ? LineChart(
                  duration: duration,
                  LineChartData(
                    minX: 0,
                    maxX: (n - 1).toDouble(),
                    minY: scale.low,
                    maxY: scale.high,
                    gridData: grid,
                    borderData: FlBorderData(show: false),
                    titlesData: titles,
                    lineTouchData: const LineTouchData(enabled: false),
                    extraLinesData: ExtraLinesData(
                      verticalLines: <VerticalLine>[
                        VerticalLine(
                          x: shown.toDouble(),
                          color: scheme.outline,
                          strokeWidth: 1,
                        ),
                      ],
                    ),
                    lineBarsData: <LineChartBarData>[
                      for (int s = 0; s < _plan.series.length; s++)
                        LineChartBarData(
                          spots: <FlSpot>[
                            for (int i = 0; i < n; i++)
                              if (_plan.series[s].values[i] case final double v)
                                FlSpot(i.toDouble(), v)
                              else
                                FlSpot.nullSpot,
                          ],
                          color: _colour(s, colors, scheme),
                          barWidth: s == 0 ? 2 : 1.5,
                          dashArray: _dashes(s),
                          dotData: FlDotData(
                            checkToShowDot: (FlSpot spot, LineChartBarData _) =>
                                n <= 31 || spot.x == shown,
                          ),
                        ),
                    ],
                  ),
                )
              : BarChart(
                  duration: duration,
                  BarChartData(
                    alignment: BarChartAlignment.spaceAround,
                    minY: scale.low,
                    maxY: scale.high,
                    gridData: grid,
                    borderData: FlBorderData(show: false),
                    titlesData: titles,
                    barTouchData: BarTouchData(enabled: false),
                    barGroups: <BarChartGroupData>[
                      for (int i = 0; i < n; i++)
                        BarChartGroupData(
                          x: i,
                          barsSpace: 2,
                          barRods: <BarChartRodData>[
                            for (int s = 0; s < _plan.series.length; s++)
                              BarChartRodData(
                                toY: _plan.series[s].values[i] ?? 0,
                                width:
                                    (plotWidth / n * 0.7 / _plan.series.length -
                                            2)
                                        .clamp(2, 24),
                                borderRadius: BorderRadius.zero,
                                color: _colour(
                                  s,
                                  colors,
                                  scheme,
                                ).withValues(alpha: i == shown ? 1 : 0.55),
                              ),
                          ],
                        ),
                    ],
                  ),
                );

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (TapDownDetails d) => touch(d.localPosition),
            onHorizontalDragStart: (DragStartDetails d) =>
                touch(d.localPosition),
            onHorizontalDragUpdate: (DragUpdateDetails d) =>
                _moveTo(indexAt(d.localPosition.dx)),
            child: chart,
          );
        },
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.colour});

  final Color colour;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 10,
    height: 10,
    child: DecoratedBox(
      decoration: BoxDecoration(color: colour, shape: BoxShape.circle),
    ),
  );
}
