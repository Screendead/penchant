import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/ask/journal_db.dart';
import 'package:tracker/data/activity_content.dart';
import 'package:tracker/data/day_note.dart';
import 'package:tracker/data/unit.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/data/vice_activity.dart';

import 'fakes.dart';

final DateTime today = DateTime(2026, 11, 15);

Vice habit(String id, int created, {bool archived = false}) => Vice(
  id: id,
  name: id,
  unit: Unit.drink,
  ownerID: ownerID,
  createdAt: Timestamp.fromMillisecondsSinceEpoch(created),
  archived: archived,
);

ViceActivity entry(
  String viceID,
  DateTime at, {
  int quantity = 1,
  List<String> triggers = const <String>[],
  String? note,
  int? urge,
  bool locked = false,
}) => ViceActivity(
  id: '$viceID-${at.toIso8601String()}',
  viceID: viceID,
  quantity: quantity,
  ownerID: ownerID,
  createdAt: Timestamp.fromDate(at),
  triggers: triggers,
  note: note,
  urge: urge,
  loggedVia: LoggedVia.sheet,
  locked: locked,
);

JournalDb journal({bool authorize = true}) => JournalDb.build(
  authorize: authorize,
  vices: <Vice>[habit('Wine', 0), habit('Coffee', 1, archived: true)],
  entries: <ViceActivity>[
    entry('Wine', DateTime(2026, 11, 1, 20, 15), quantity: 2),
    entry('Wine', DateTime(2026, 11, 2, 20, 40), note: 'after a long meeting'),
    entry(
      'Wine',
      DateTime(2026, 11, 3, 21, 5),
      triggers: <String>['work/meeting', 'tired'],
    ),
    entry('Wine', DateTime(2026, 11, 10, 20, 0), quantity: 3, urge: 4),
    entry('Coffee', DateTime(2026, 11, 2, 8, 30)),
    entry(
      'Coffee',
      DateTime(2026, 11, 3, 8, 45),
      note: 'secret',
      urge: 2,
      locked: true,
    ),
    entry('Gone', DateTime(2026, 11, 4, 9)),
  ],
  notes: <DayNote>[
    DayNote(
      id: 'n1',
      ownerID: ownerID,
      day: '2026-11-02',
      createdAt: Timestamp.fromDate(DateTime(2026, 11, 2)),
      text: 'A heavy day',
      triggers: const <String>['work'],
    ),
  ],
  today: today,
);

List<List<Object?>> rowsOf(AskRun run) {
  expect(run, isA<AskRan>(), reason: run is AskRefused ? '${run.refusal}' : '');
  return (run as AskRan).rows.rows;
}

AskRefusal refusalOf(AskRun run) {
  expect(run, isA<AskRefused>());
  return (run as AskRefused).refusal;
}

void main() {
  late JournalDb db;
  setUp(() => db = journal());
  tearDown(() => db.close());

  group('the tables', () {
    test('habits are numbered as sent, with their first day', () {
      expect(
        rowsOf(
          db.run(
            'SELECT id, name, unit, archived, first_day FROM habits ORDER BY id',
          ),
        ),
        <List<Object?>>[
          <Object?>[1, 'Wine', 'drinks', 0, '2026-11-01'],
          <Object?>[2, 'Coffee', 'drinks', 1, '2026-11-02'],
        ],
      );
    });

    test('entries carry local text dates, and an unknown habit is left out', () {
      final AskRan ran =
          db.run(
                'SELECT at, day, hour, weekday, week, month, year, amount FROM entries ORDER BY id LIMIT 1',
              )
              as AskRan;
      expect(ran.rows.columns, <String>[
        'at',
        'day',
        'hour',
        'weekday',
        'week',
        'month',
        'year',
        'amount',
      ]);
      expect(ran.rows.rows.single, <Object?>[
        '2026-11-01 20:15:00',
        '2026-11-01',
        20,
        7,
        '2026-10-26',
        '2026-11',
        2026,
        2.0,
      ]);
      expect(rowsOf(db.run('SELECT count(*) FROM entries')), <List<Object?>>[
        <Object?>[6],
      ]);
    });

    test('a locked entry gives its plaintext columns only', () {
      expect(
        rowsOf(
          db.run(
            "SELECT note, urge, logged_via FROM entries WHERE habit_id = 2 AND day = '2026-11-03'",
          ),
        ),
        <List<Object?>>[
          <Object?>[null, null, null],
        ],
      );
    });

    test('tags carry their area and labels; own words are area own', () {
      expect(
        rowsOf(
          db.run(
            'SELECT tag, area, label, area_label FROM entry_tags ORDER BY tag',
          ),
        ),
        <List<Object?>>[
          <Object?>['tired', 'own', 'tired', 'Own words'],
          <Object?>['work/meeting', 'work', 'Meeting', 'Work or study'],
        ],
      );
      expect(rowsOf(db.run('SELECT day, text FROM day_notes')), <List<Object?>>[
        <Object?>['2026-11-02', 'A heavy day'],
      ]);
      expect(rowsOf(db.run('SELECT area FROM day_note_tags')), <List<Object?>>[
        <Object?>['work'],
      ]);
    });

    test('days runs from the first entry to today', () {
      expect(
        rowsOf(db.run('SELECT min(day), max(day), count(*) FROM days')),
        <List<Object?>>[
          <Object?>['2026-11-01', '2026-11-15', 15],
        ],
      );
    });
  });

  group('ordinary analytic SQL works', () {
    test('GROUP BY hour', () {
      expect(
        rowsOf(
          db.run(
            'SELECT hour, count(*) AS n FROM entries WHERE habit_id = 1 GROUP BY hour ORDER BY n DESC, hour LIMIT 1',
          ),
        ),
        <List<Object?>>[
          <Object?>[20, 3],
        ],
      );
    });

    test('a CTE with a window function over days, for the longest gap', () {
      const String sql = '''
        WITH marked AS (
          SELECT d.day, CASE WHEN e.id IS NULL THEN 0 ELSE 1 END AS used
          FROM days d LEFT JOIN entries e ON e.day = d.day AND e.habit_id = 1
          GROUP BY d.day
        ), runs AS (
          SELECT day, used,
                 row_number() OVER (ORDER BY day) - row_number() OVER (PARTITION BY used ORDER BY day) AS grp
          FROM marked
        )
        SELECT min(day) AS start, max(day) AS finish, count(*) AS days_without
        FROM runs WHERE used = 0 GROUP BY grp ORDER BY days_without DESC LIMIT 1''';
      expect(rowsOf(db.run(sql)), <List<Object?>>[
        <Object?>['2026-11-04', '2026-11-09', 6],
      ]);
    });

    test('strftime on the text columns, joins and LIKE over notes', () {
      expect(
        rowsOf(
          db.run(
            "SELECT strftime('%m', e.day) AS m, h.name FROM entries e JOIN habits h ON h.id = e.habit_id WHERE e.note LIKE '%meeting%'",
          ),
        ),
        <List<Object?>>[
          <Object?>['11', 'Wine'],
        ],
      );
    });

    test('a trailing semicolon and comments are fine', () {
      expect(
        rowsOf(
          db.run(
            '-- the total\nSELECT sum(amount) FROM entries WHERE habit_id = 1;  ',
          ),
        ),
        <List<Object?>>[
          <Object?>[7.0],
        ],
      );
    });
  });

  group('the sandbox refuses', () {
    test('a second statement after a semicolon', () {
      expect(
        refusalOf(db.run('SELECT 1; SELECT 2')),
        AskRefusal.notOneStatement,
      );
      expect(
        refusalOf(db.run('SELECT 1; DROP TABLE entries')),
        AskRefusal.notOneStatement,
      );
      expect(rowsOf(db.run('SELECT count(*) FROM entries')), <List<Object?>>[
        <Object?>[6],
      ]);
    });

    test('writes and schema changes', () {
      for (final String sql in <String>[
        "INSERT INTO habits (id, name) VALUES (9, 'x')",
        "UPDATE habits SET name = 'x'",
        'DELETE FROM entries',
        'DROP TABLE entries',
        'CREATE TABLE t (a)',
        'CREATE TEMP TABLE t (a)',
        'ALTER TABLE habits ADD COLUMN x',
        'BEGIN',
        'VACUUM',
        'REINDEX',
        'ANALYZE',
      ]) {
        expect(db.run(sql), isA<AskRefused>(), reason: sql);
      }
    });

    test('a write hidden in a CTE, or behind SELECT-looking text', () {
      for (final String sql in <String>[
        "WITH x AS (SELECT 1) INSERT INTO habits (id, name) SELECT 9, 'x' FROM x",
        'WITH x AS (SELECT 1) DELETE FROM entries',
        'WITH x AS (SELECT 1) UPDATE habits SET archived = 1',
        'WITH x AS (SELECT 1) DELETE FROM entries RETURNING id',
      ]) {
        expect(db.run(sql), isA<AskRefused>(), reason: sql);
      }
      expect(rowsOf(db.run('SELECT count(*) FROM entries')), <List<Object?>>[
        <Object?>[6],
      ]);
    });

    test('ATTACH to a path and to :memory:, and DETACH', () {
      for (final String sql in <String>[
        "ATTACH DATABASE '/tmp/penchant-leak.db' AS leak",
        "ATTACH DATABASE ':memory:' AS leak",
        "ATTACH 'file:leak?mode=memory' AS leak",
        'DETACH DATABASE main',
        "SELECT * FROM pragma_database_list",
      ]) {
        expect(db.run(sql), isA<AskRefused>(), reason: sql);
      }
    });

    test('PRAGMA of any kind, plain or as a table function', () {
      for (final String sql in <String>[
        'PRAGMA query_only = OFF',
        'PRAGMA table_info(habits)',
        'PRAGMA writable_schema = ON',
        'SELECT * FROM pragma_table_info(\'habits\')',
        'SELECT count(*) FROM pragma_table_list',
      ]) {
        expect(db.run(sql), isA<AskRefused>(), reason: sql);
      }
    });

    test('load_extension, unknown and unlisted functions', () {
      for (final String sql in <String>[
        "SELECT load_extension('/usr/lib/libz.dylib')",
        'SELECT no_such_function(1)',
        'SELECT randomblob(10)',
        'SELECT zeroblob(10)',
        "SELECT sqlite_version()",
        "SELECT json_extract('{}', '\$.a')",
        "SELECT * FROM json_each('[1,2]')",
      ]) {
        expect(
          refusalOf(db.run(sql)),
          anyOf(AskRefusal.forbidden, AskRefusal.failed),
          reason: sql,
        );
      }
    });

    test('reading sqlite_master, sqlite_schema or a column not listed', () {
      for (final String sql in <String>[
        'SELECT * FROM sqlite_master',
        'SELECT sql FROM sqlite_schema',
        'SELECT count(*) FROM sqlite_master',
        'SELECT * FROM sqlite_temp_master',
        'SELECT * FROM sqlite_stat1',
        'SELECT rowid FROM entries',
        'SELECT * FROM main.sqlite_master',
      ]) {
        expect(db.run(sql), isA<AskRefused>(), reason: sql);
      }
    });

    test('EXPLAIN', () {
      expect(refusalOf(db.run('EXPLAIN SELECT 1')), AskRefusal.notSelect);
      expect(
        refusalOf(db.run('EXPLAIN QUERY PLAN SELECT * FROM entries')),
        AskRefusal.notSelect,
      );
    });

    test('an endless recursive CTE is stopped', () {
      final Stopwatch clock = Stopwatch()..start();
      expect(
        refusalOf(
          db.run(
            'WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM n) SELECT count(*) FROM n',
          ),
        ),
        AskRefusal.tooSlow,
      );
      expect(clock.elapsed, lessThan(const Duration(seconds: 2)));
    });

    test('a cartesian blow-up is stopped', () {
      final Stopwatch clock = Stopwatch()..start();
      final AskRun run = db.run(
        'WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM n WHERE i < 5000) '
        'SELECT count(*) FROM n a, n b, n c',
      );
      expect(refusalOf(run), AskRefusal.tooSlow);
      expect(clock.elapsed, lessThan(const Duration(seconds: 2)));
    });

    test('a 2 MB string', () {
      for (final String sql in <String>[
        "SELECT printf('%.*c', 2000000, 'x')",
        "SELECT replace(printf('%.*c', 900000, 'x'), 'x', 'xx')",
        "SELECT zeroblob(2000000)",
        "SELECT randomblob(2000000)",
        "SELECT hex(zeroblob(1000000))",
      ]) {
        expect(db.run(sql), isA<AskRefused>(), reason: sql);
      }
    });

    test('too much in total, and more than 500 rows', () {
      expect(
        refusalOf(
          db.run(
            "WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM n WHERE i < 400) "
            "SELECT printf('%.*c', 900, 'x') FROM n",
          ),
        ),
        AskRefusal.tooBig,
      );
      final AskRun many = db.run(
        'WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM n WHERE i < 2000) SELECT i FROM n',
      );
      expect(many, isA<AskRan>());
      expect((many as AskRan).truncated, isTrue);
      expect(many.rows.rows, hasLength(JournalDb.maxRows));
    });

    test('an over-long statement', () {
      expect(
        refusalOf(
          db.run('SELECT ${List<String>.filled(1500, '1').join(' + ')}'),
        ),
        AskRefusal.tooLong,
      );
    });

    test('anything not starting SELECT or WITH, and an empty statement', () {
      expect(refusalOf(db.run('VALUES (1)')), AskRefusal.notSelect);
      expect(refusalOf(db.run('-- nothing')), AskRefusal.notSelect);
      expect(refusalOf(db.run('')), AskRefusal.notSelect);
    });

    test('nothing once closed', () {
      db.close();
      expect(refusalOf(db.run('SELECT 1')), AskRefusal.failed);
    });
  });

  group('under the authorizer, with the statement checks off', () {
    late JournalDb bare;
    setUp(() => bare = journal(authorize: false));
    tearDown(() => bare.close());

    test('query_only refuses writes and schema changes', () {
      for (final String sql in <String>[
        "INSERT INTO habits (id, name) VALUES (9, 'x')",
        'DELETE FROM entries',
        'DROP TABLE entries',
        'CREATE TABLE t (a)',
      ]) {
        expect(bare.runUnchecked(sql), isA<AskRefused>(), reason: sql);
      }
      expect(rowsOf(bare.run('SELECT count(*) FROM entries')), <List<Object?>>[
        <Object?>[6],
      ]);
    });

    test('the attached limit refuses ATTACH', () {
      expect(
        bare.runUnchecked("ATTACH DATABASE ':memory:' AS leak"),
        isA<AskRefused>(),
      );
    });

    test('the length limit refuses a 2 MB value', () {
      expect(
        refusalOf(bare.runUnchecked("SELECT printf('%.*c', 2000000, 'x')")),
        AskRefusal.tooBig,
      );
    });

    test('the progress handler stops an endless CTE', () {
      expect(
        refusalOf(
          bare.runUnchecked(
            'WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM n) '
            'SELECT count(*) FROM n',
          ),
        ),
        AskRefusal.tooSlow,
      );
    });

    test('extension loading is not there', () {
      expect(
        bare.runUnchecked("SELECT load_extension('/usr/lib/libz.dylib')"),
        isA<AskRefused>(),
      );
    });
  });
}
