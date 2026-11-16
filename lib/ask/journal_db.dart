import 'dart:convert';
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:tracker/ask/ask_answer.dart';
import 'package:tracker/ask/ask_journal.dart';
import 'package:tracker/ask/sqlite_ffi.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/data/day_note.dart';
import 'package:tracker/data/trigger_tree.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/data/vice_activity.dart';

/// The tables and columns the model is told about, and the only ones its SQL
/// may read (the authorizer's allow-list).
const Map<String, List<String>> askTables = <String, List<String>>{
  'habits': <String>[
    'id',
    'name',
    'unit',
    'unit_one',
    'archived',
    'first_day',
    'price',
    'currency',
  ],
  'entries': <String>[
    'id',
    'habit_id',
    'at',
    'day',
    'hour',
    'weekday',
    'week',
    'month',
    'year',
    'amount',
    'urge',
    'note',
    'logged_via',
  ],
  'entry_tags': <String>['entry_id', 'tag', 'area', 'label', 'area_label'],
  'day_notes': <String>['day', 'text'],
  'day_note_tags': <String>['day', 'tag', 'area', 'label', 'area_label'],
  'days': <String>['day', 'weekday', 'week', 'month', 'year'],
};

const Map<String, String> _types = <String, String>{
  'id': 'INTEGER',
  'habit_id': 'INTEGER',
  'entry_id': 'INTEGER',
  'archived': 'INTEGER',
  'price': 'REAL',
  'hour': 'INTEGER',
  'weekday': 'INTEGER',
  'year': 'INTEGER',
  'amount': 'REAL',
  'urge': 'INTEGER',
};

const List<String> _indexes = <String>[
  'CREATE INDEX entries_habit_day ON entries(habit_id, day)',
  'CREATE INDEX entries_day ON entries(day)',
  'CREATE INDEX entries_week ON entries(week)',
  'CREATE INDEX entries_month ON entries(month)',
  'CREATE INDEX entries_hour ON entries(hour)',
  'CREATE INDEX entry_tags_entry ON entry_tags(entry_id)',
  'CREATE INDEX entry_tags_tag ON entry_tags(tag)',
  'CREATE INDEX entry_tags_area ON entry_tags(area)',
  'CREATE UNIQUE INDEX days_day ON days(day)',
  'CREATE INDEX days_week ON days(week)',
  'CREATE INDEX days_month ON days(month)',
  'CREATE INDEX day_notes_day ON day_notes(day)',
  'CREATE INDEX day_note_tags_day ON day_note_tags(day)',
];

/// Built-in functions a query may call; any other is refused at prepare.
/// No randomblob or zeroblob (bulk out of nothing), no load_extension, no
/// json table functions (virtual tables are refused anyway), no sqlite_*.
const Set<String> askFunctions = <String>{
  // aggregates
  'count', 'sum', 'total', 'avg', 'min', 'max', 'group_concat', 'string_agg',
  'median', 'percentile', 'percentile_cont', 'percentile_disc',
  // window
  'row_number', 'rank', 'dense_rank', 'percent_rank', 'cume_dist', 'ntile',
  'lag', 'lead', 'first_value', 'last_value', 'nth_value',
  // date and time
  'date', 'time', 'datetime', 'julianday', 'unixepoch', 'strftime',
  'timediff',
  // strings
  'length', 'lower', 'upper', 'trim', 'ltrim', 'rtrim', 'substr', 'substring',
  'replace', 'instr', 'like', 'glob', 'printf', 'format', 'concat',
  'concat_ws', 'char', 'unicode', 'octet_length',
  // values and maths
  'abs', 'round', 'coalesce', 'ifnull', 'nullif', 'iif', 'if', 'typeof',
  'sign', 'ceil', 'ceiling', 'floor', 'trunc', 'sqrt', 'pow', 'power', 'ln',
  'log', 'log10', 'log2', 'exp', 'mod',
};

/// Why a query did not run. Codes only: the SQL itself is never logged.
enum AskRefusal {
  tooLong,
  notOneStatement,
  notSelect,
  forbidden,
  tooSlow,
  tooBig,
  failed,
}

sealed class AskRun {
  const AskRun();
}

class AskRan extends AskRun {
  const AskRan(this.rows, {this.truncated = false});

  final AskRows rows;

  /// More rows than [JournalDb.maxRows] came back; only those are kept.
  final bool truncated;
}

class AskRefused extends AskRun {
  const AskRefused(this.refusal);

  final AskRefusal refusal;
}

/// A habit's number in the tables and in what is sent: those [askHabits]
/// sends first, from 1 in that order, then the rest (locked or blank names).
List<({int id, Vice vice})> numberedHabits(Iterable<Vice> vices) {
  final List<Vice> sent = askHabits(vices);
  final Set<String> sentIDs = <String>{for (final Vice v in sent) v.id};
  final List<Vice> rest =
      vices.where((Vice v) => !sentIDs.contains(v.id)).toList()
        ..sort((Vice a, Vice b) {
          final int byTime = a.createdAt.compareTo(b.createdAt);
          return byTime != 0 ? byTime : a.id.compareTo(b.id);
        });
  return <({int id, Vice vice})>[
    for (final (int i, Vice v) in <Vice>[...sent, ...rest].indexed)
      (id: i + 1, vice: v),
  ];
}

String _two(int n) => n.toString().padLeft(2, '0');

String _dayText(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${_two(d.month)}-${_two(d.day)}';

String _monthText(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${_two(d.month)}';

DateTime _monday(DateTime day) => addDays(startOfDay(day), 1 - day.weekday);

// The callbacks below are plain top-level functions, called synchronously on
// the isolate that runs the statement; Dart callbacks need no closure here.
int _authorize(
  Pointer<Void> _,
  int action,
  Pointer<Utf8> a1,
  Pointer<Utf8> a2,
  Pointer<Utf8> a3,
  Pointer<Utf8> a4,
) {
  String? text(Pointer<Utf8> p) => p.address == 0 ? null : p.toDartString();
  switch (action) {
    case Sq.actionSelect:
    case Sq.actionRecursive:
      return Sq.ok;
    case Sq.actionRead:
      final String table = text(a1) ?? '';
      final String column = text(a2) ?? '';
      // A table or CTE in FROM with none of its columns read comes with no
      // column and no database: it reveals a row count at most, so it may be
      // anything but SQLite's own tables.
      if (column.isEmpty) {
        return table.toLowerCase().startsWith('sqlite_') ? Sq.authDeny : Sq.ok;
      }
      final List<String>? columns = askTables[table];
      return text(a3) == 'main' && columns != null && columns.contains(column)
          ? Sq.ok
          : Sq.authDeny;
    case Sq.actionFunction:
      final String? name = text(a2)?.toLowerCase();
      return name != null && askFunctions.contains(name) ? Sq.ok : Sq.authDeny;
    default:
      return Sq.authDeny;
  }
}

Stopwatch? _running;
int _budgetMs = 0;

int _progress(Pointer<Void> _) {
  final Stopwatch? clock = _running;
  return clock != null && clock.elapsedMilliseconds > _budgetMs ? 1 : 0;
}

final Pointer<NativeFunction<AuthorizerNative>> _authorizer =
    Pointer.fromFunction<AuthorizerNative>(_authorize, Sq.authDeny);
final Pointer<NativeFunction<ProgressNative>> _progressHandler =
    Pointer.fromFunction<ProgressNative>(_progress, 1);

final RegExp _leadingNoise = RegExp(r'^(\s+|--[^\n]*(\n|$)|/\*[\s\S]*?\*/)*');
final RegExp _selectStart = RegExp(r'^(select|with)\b', caseSensitive: false);

/// The person's journal as a private SQLite database in memory: never a file,
/// temp tables in memory, closed with [close]. Model-written SQL runs only
/// through [run], inside these layers:
/// 1. one statement: SQLite's own parse must leave no tail, and must report
///    the statement read-only and not EXPLAIN; it must start SELECT or WITH;
/// 2. an authorizer allowing only SELECT, recursive CTEs, reads of
///    [askTables]' columns in `main` and [askFunctions], denying everything
///    else (ATTACH, PRAGMA, writes, schema, transactions, other functions);
///    virtual tables (pragma_*, json_each, dbstat ...) refused at prepare;
/// 3. limits: no attached databases, 1 MB values, short SQL, shallow
///    expressions and compounds, short LIKE patterns; defensive mode, no
///    trusted schema, triggers, views or extension loading; query_only;
/// 4. a progress handler stopping a query after [budget], [maxRows] rows and
///    [maxBytes] of results.
class JournalDb {
  JournalDb._(this._db);

  static const Duration budget = Duration(milliseconds: 250);
  static const int maxRows = 500;
  static const int maxBytes = 256 * 1024;
  static const int maxValueBytes = 1000000;

  final Pointer<Void> _db;
  bool _closed = false;

  Sqlite get _sq => Sqlite.instance;

  /// Builds the tables from one read of the journal: [vices] every habit
  /// (archived and locked included), [entries] every entry, [notes] every day
  /// note. A locked entry gives its plaintext columns only. Days are local,
  /// in this device's current zone, up to [today].
  static JournalDb build({
    required List<Vice> vices,
    required List<ViceActivity> entries,
    required List<DayNote> notes,
    required DateTime today,
    // Off only for the tests of the layers under it.
    @visibleForTesting bool authorize = true,
  }) {
    final Sqlite sq = Sqlite.instance;
    final Pointer<Void> handle = using((Arena arena) {
      final Pointer<Pointer<Void>> out = arena<Pointer<Void>>();
      final int rc = sq.openV2(
        ':memory:'.toNativeUtf8(allocator: arena),
        out,
        Sq.openReadWrite |
            Sq.openCreate |
            Sq.openMemory |
            Sq.openNoMutex |
            Sq.openPrivateCache |
            Sq.openNoFollow,
        nullptr,
      );
      if (rc != Sq.ok) {
        if (out.value.address != 0) sq.closeV2(out.value);
        throw StateError('sqlite open failed: $rc');
      }
      return out.value;
    });
    final JournalDb db = JournalDb._(handle);
    try {
      db._fill(vices, entries, notes, today);
      db._lockDown(authorize: authorize);
    } catch (_) {
      db.close();
      rethrow;
    }
    return db;
  }

  void _exec(String sql) {
    using((Arena arena) {
      final int rc = _sq.exec(
        _db,
        sql.toNativeUtf8(allocator: arena),
        nullptr,
        nullptr,
        nullptr,
      );
      if (rc != Sq.ok) {
        throw StateError('sqlite build failed');
      }
    });
  }

  void _config(int op, int value) {
    using((Arena arena) {
      final Pointer<Int> out = arena<Int>();
      if (_sq.dbConfig(_db, op, value, out) != Sq.ok || out.value != value) {
        throw StateError('sqlite config $op refused');
      }
    });
  }

  void _insert(String table, Iterable<List<Object?>> rows) {
    final List<String> columns = askTables[table]!;
    using((Arena arena) {
      final Pointer<Pointer<Void>> out = arena<Pointer<Void>>();
      final String sql =
          'INSERT INTO $table (${columns.join(', ')}) '
          'VALUES (${List<String>.filled(columns.length, '?').join(', ')})';
      if (_sq.prepareV3(
            _db,
            sql.toNativeUtf8(allocator: arena),
            -1,
            0,
            out,
            nullptr,
          ) !=
          Sq.ok) {
        throw StateError('sqlite build failed');
      }
      final Pointer<Void> stmt = out.value;
      try {
        for (final List<Object?> row in rows) {
          for (final (int i, Object? value) in row.indexed) {
            switch (value) {
              case null:
                _sq.bindNull(stmt, i + 1);
              case int v:
                _sq.bindInt64(stmt, i + 1, v);
              case double v:
                _sq.bindDouble(stmt, i + 1, v);
              case String v:
                using((Arena a) {
                  final Pointer<Utf8> p = v.toNativeUtf8(allocator: a);
                  _sq.bindText(stmt, i + 1, p, p.length, sqliteTransient);
                });
              default:
                throw ArgumentError.value(value);
            }
          }
          if (_sq.step(stmt) != Sq.done) {
            throw StateError('sqlite build failed');
          }
          _sq.reset(stmt);
        }
      } finally {
        _sq.finalize(stmt);
      }
    });
  }

  void _fill(
    List<Vice> vices,
    List<ViceActivity> entries,
    List<DayNote> notes,
    DateTime today,
  ) {
    _config(Sq.configDefensive, 1);
    _config(Sq.configTrustedSchema, 0);
    _config(Sq.configEnableTrigger, 0);
    _config(Sq.configEnableView, 0);
    _config(Sq.configWritableSchema, 0);
    // Apple's build omits extension loading; elsewhere it is switched off.
    using((Arena arena) {
      _sq.dbConfig(_db, Sq.configEnableLoadExtension, 0, arena<Int>());
    });
    _exec('PRAGMA temp_store = MEMORY');
    for (final MapEntry<String, List<String>> t in askTables.entries) {
      _exec(
        'CREATE TABLE ${t.key} (${t.value.map((String c) => '$c ${_types[c] ?? 'TEXT'}').join(', ')})',
      );
    }

    final List<({int id, Vice vice})> habits = numberedHabits(vices);
    final Map<String, int> habitID = <String, int>{
      for (final ({int id, Vice vice}) h in habits) h.vice.id: h.id,
    };
    final List<ViceActivity> kept =
        entries
            .where((ViceActivity a) => habitID.containsKey(a.viceID))
            .toList()
          ..sort((ViceActivity a, ViceActivity b) {
            final int byTime = a.createdAt.compareTo(b.createdAt);
            return byTime != 0 ? byTime : a.id.compareTo(b.id);
          });
    final Map<int, String> firstDay = <int, String>{};
    final List<List<Object?>> entryRows = <List<Object?>>[];
    final List<List<Object?>> tagRows = <List<Object?>>[];
    DateTime? first;
    for (final (int i, ViceActivity a) in kept.indexed) {
      final int id = i + 1;
      final DateTime at = a.createdAt.toDate();
      final DateTime day = startOfDay(at);
      first = first == null || day.isBefore(first) ? day : first;
      final int habit = habitID[a.viceID]!;
      firstDay.putIfAbsent(habit, () => _dayText(day));
      entryRows.add(<Object?>[
        id,
        habit,
        '${_dayText(at)} ${_two(at.hour)}:${_two(at.minute)}:${_two(at.second)}',
        _dayText(day),
        at.hour,
        at.weekday,
        _dayText(_monday(day)),
        _monthText(day),
        day.year,
        a.measure.toDouble(),
        if (a.locked) null else a.urge,
        if (a.locked) null else a.note,
        if (a.locked) null else a.loggedVia?.name,
      ]);
      if (!a.locked) {
        tagRows.addAll(<List<Object?>>[
          for (final String tag in a.triggers)
            <Object?>[id, ...tagColumns(tag)],
        ]);
      }
    }
    final List<List<Object?>> noteRows = <List<Object?>>[];
    final List<List<Object?>> noteTagRows = <List<Object?>>[];
    for (final DayNote n in notes) {
      if (n.locked || n.day.isEmpty) continue;
      if (n.text.trim().isNotEmpty) noteRows.add(<Object?>[n.day, n.text]);
      noteTagRows.addAll(<List<Object?>>[
        for (final String tag in n.triggers)
          <Object?>[n.day, ...tagColumns(tag)],
      ]);
    }

    final DateTime last = startOfDay(today);
    final List<List<Object?>> dayRows = <List<Object?>>[];
    for (
      DateTime d = first == null || first.isAfter(last) ? last : first;
      !d.isAfter(last);
      d = addDays(d, 1)
    ) {
      dayRows.add(<Object?>[
        _dayText(d),
        d.weekday,
        _dayText(_monday(d)),
        _monthText(d),
        d.year,
      ]);
    }

    _exec('BEGIN');
    _insert('habits', <List<Object?>>[
      for (final ({int id, Vice vice}) h in habits)
        <Object?>[
          h.id,
          h.vice.name,
          h.vice.units.plural,
          h.vice.units.singular,
          h.vice.archived ? 1 : 0,
          firstDay[h.id],
          h.vice.costPerUnit,
          h.vice.costPerUnit == null ? null : h.vice.currency,
        ],
    ]);
    _insert('entries', entryRows);
    _insert('entry_tags', tagRows);
    _insert('day_notes', noteRows);
    _insert('day_note_tags', noteTagRows);
    _insert('days', dayRows);
    _exec('COMMIT');
    _indexes.forEach(_exec);
    _exec('ANALYZE');
  }

  void _lockDown({required bool authorize}) {
    _exec('PRAGMA query_only = ON');
    void limit(int id, int value) => _sq.limit(_db, id, value);
    limit(Sq.limitAttached, 0);
    limit(Sq.limitLength, maxValueBytes);
    limit(Sq.limitSqlLength, AskLimits.sql * 4);
    limit(Sq.limitColumn, 100);
    limit(Sq.limitExprDepth, 100);
    limit(Sq.limitCompoundSelect, 20);
    limit(Sq.limitLikePatternLength, 200);
    limit(Sq.limitFunctionArg, 16);
    limit(Sq.limitVariableNumber, 0);
    limit(Sq.limitTriggerDepth, 0);
    if (authorize && _sq.setAuthorizer(_db, _authorizer, nullptr) != Sq.ok) {
      throw StateError('sqlite authorizer refused');
    }
    _sq.progressHandler(_db, 1000, _progressHandler, nullptr);
  }

  /// Runs one model-written query. Never throws for anything in [sql].
  AskRun run(String sql) => _run(sql, checked: true);

  /// [run] without the statement checks of the first layer, for the tests of
  /// the layers under it.
  @visibleForTesting
  AskRun runUnchecked(String sql) => _run(sql, checked: false);

  AskRun _run(String sql, {required bool checked}) {
    if (_closed) return const AskRefused(AskRefusal.failed);
    if (sql.length > AskLimits.sql) return const AskRefused(AskRefusal.tooLong);
    final String body = sql.replaceFirst(_leadingNoise, '');
    if (checked && !_selectStart.hasMatch(body)) {
      return const AskRefused(AskRefusal.notSelect);
    }
    return using((Arena arena) {
      final Pointer<Utf8> text = sql.toNativeUtf8(allocator: arena);
      final int textBytes = text.length;
      final Pointer<Pointer<Void>> out = arena<Pointer<Void>>();
      final Pointer<Pointer<Utf8>> tail = arena<Pointer<Utf8>>();
      final int rc = _sq.prepareV3(
        _db,
        text,
        textBytes + 1,
        Sq.prepareNoVtab,
        out,
        tail,
      );
      final Pointer<Void> stmt = out.value;
      if (rc != Sq.ok) {
        if (stmt.address != 0) _sq.finalize(stmt);
        return AskRefused(rc == Sq.auth ? AskRefusal.forbidden : _refusal(rc));
      }
      if (stmt.address == 0) {
        return const AskRefused(AskRefusal.notOneStatement);
      }
      try {
        final int used = tail.value.address - text.address;
        final String rest = used >= 0 && used <= textBytes
            ? utf8.decode(
                Pointer<Uint8>.fromAddress(
                  text.address + used,
                ).asTypedList(textBytes - used),
                allowMalformed: true,
              )
            : 'x';
        if (checked && rest.trim().isNotEmpty) {
          return const AskRefused(AskRefusal.notOneStatement);
        }
        if (checked &&
            (_sq.stmtReadonly(stmt) == 0 || _sq.stmtIsExplain(stmt) != 0)) {
          return const AskRefused(AskRefusal.notSelect);
        }
        return _rows(stmt);
      } finally {
        _sq.finalize(stmt);
      }
    });
  }

  AskRun _rows(Pointer<Void> stmt) {
    final int count = _sq.columnCount(stmt);
    final List<String> columns = <String>[
      for (int i = 0; i < count; i++) _sq.columnName(stmt, i).toDartString(),
    ];
    final List<List<Object?>> rows = <List<Object?>>[];
    int bytes = 0;
    _budgetMs = budget.inMilliseconds;
    _running = Stopwatch()..start();
    try {
      for (;;) {
        final int rc = _sq.step(stmt);
        if (rc == Sq.done) break;
        if (rc != Sq.row) return AskRefused(_refusal(rc));
        if (rows.length == maxRows) {
          return AskRan(AskRows(columns, rows), truncated: true);
        }
        final List<Object?> row = <Object?>[];
        for (int i = 0; i < count; i++) {
          switch (_sq.columnType(stmt, i)) {
            case Sq.integer:
              row.add(_sq.columnInt64(stmt, i));
              bytes += 8;
            case Sq.float:
              row.add(_sq.columnDouble(stmt, i));
              bytes += 8;
            case Sq.nullType:
              row.add(null);
            default:
              final Pointer<Uint8> p = _sq.columnText(stmt, i);
              final int n = _sq.columnBytes(stmt, i);
              bytes += n;
              if (bytes > maxBytes) return const AskRefused(AskRefusal.tooBig);
              row.add(
                p.address == 0
                    ? null
                    : utf8.decode(p.asTypedList(n), allowMalformed: true),
              );
          }
        }
        if (bytes > maxBytes) return const AskRefused(AskRefusal.tooBig);
        rows.add(row);
      }
      return AskRan(AskRows(columns, rows));
    } finally {
      _running = null;
    }
  }

  static AskRefusal _refusal(int rc) => switch (rc & 0xff) {
    Sq.interrupt => AskRefusal.tooSlow,
    Sq.tooBig => AskRefusal.tooBig,
    Sq.auth => AskRefusal.forbidden,
    _ => AskRefusal.failed,
  };

  /// Closes the database; everything in it is gone. Safe to call twice.
  void close() {
    if (_closed) return;
    _closed = true;
    _sq.closeV2(_db);
  }
}

/// A trigger as entry_tags and day_note_tags store it: tag, area, label,
/// area_label. Own words are area `own`.
List<String> tagColumns(String tag) {
  final List<String>? labels = triggerLabels(tag);
  if (labels == null) return <String>[tag, 'own', tag, 'Own words'];
  return <String>[
    tag,
    tag.split(triggerPathSeparator).first,
    labels.last,
    labels.first,
  ];
}
