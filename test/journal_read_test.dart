import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/providers/journal_read.dart';

final DateTime _t0 = DateTime.utc(2026, 11, 1, 12);

ViceActivity _entry(String id, {int quantity = 1, bool pending = false}) =>
    ViceActivity(
      id: id,
      viceID: 'v',
      quantity: quantity,
      ownerID: 'alice',
      createdAt: Timestamp.fromDate(
        _t0.subtract(Duration(hours: id.hashCode % 100)),
      ),
      triggers: const <String>[],
      pending: pending,
    );

class _MemoryCursors implements JournalCursorStore {
  final Map<String, JournalCursor> byUid = <String, JournalCursor>{};

  @override
  Future<JournalCursor?> read(String uid) async => byUid[uid];

  @override
  Future<void> write(String uid, JournalCursor cursor) async =>
      byUid[uid] = cursor;
}

// One user's documents on the server, each with its stamp (null for one an
// older build wrote), and this device's cache of them.
class _Journal implements JournalSource {
  final Map<String, (ViceActivity, DateTime?)> server =
      <String, (ViceActivity, DateTime?)>{};
  final Map<String, ViceActivity> cache = <String, ViceActivity>{};
  bool offline = false;
  bool indexBuilding = false;
  bool writeThrough = true;
  @override
  bool persistentCache = true;
  final List<String> calls = <String>[];

  void put(String id, DateTime? stamp, {int quantity = 1}) =>
      server[id] = (_entry(id, quantity: quantity), stamp);

  DateTime? _newest(Iterable<DateTime?> stamps) {
    DateTime? newest;
    for (final DateTime? s in stamps) {
      if (s != null && (newest == null || s.isAfter(newest))) newest = s;
    }
    return newest;
  }

  void _unavailable() {
    if (offline) {
      throw FirebaseException(plugin: 'cloud_firestore', code: 'unavailable');
    }
  }

  @override
  Future<void> settlePending() async {}

  @override
  Future<JournalPage> full() async {
    calls.add('full');
    if (offline) {
      return (entries: cache.values.toList(), fromCache: true, newest: null);
    }
    cache
      ..clear()
      ..addAll(<String, ViceActivity>{
        for (final MapEntry<String, (ViceActivity, DateTime?)> e
            in server.entries)
          e.key: e.value.$1,
      });
    return (
      entries: <ViceActivity>[for (final e in server.values) e.$1],
      fromCache: false,
      newest: _newest(server.values.map((e) => e.$2)),
    );
  }

  @override
  Future<JournalPage> changedSince(DateTime since) async {
    calls.add('delta');
    _unavailable();
    if (indexBuilding) {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'failed-precondition',
      );
    }
    final List<(ViceActivity, DateTime?)> changed = <(ViceActivity, DateTime?)>[
      for (final (ViceActivity, DateTime?) e in server.values)
        if (e.$2 != null && !e.$2!.isBefore(since)) e,
    ];
    // Latency compensation: a queued local write stays on top of the
    // server's copy in the cache.
    for (final (ViceActivity, DateTime?) e in changed) {
      if (writeThrough && cache[e.$1.id]?.pending != true) {
        cache[e.$1.id] = e.$1;
      }
    }
    return (
      entries: <ViceActivity>[for (final e in changed) e.$1],
      fromCache: false,
      newest: _newest(changed.map((e) => e.$2)),
    );
  }

  @override
  Future<int> serverCount() async {
    calls.add('count');
    _unavailable();
    return server.length;
  }

  @override
  Future<JournalPage> cached() async {
    calls.add('cache');
    return (entries: cache.values.toList(), fromCache: true, newest: null);
  }
}

void main() {
  late _Journal journal;
  late _MemoryCursors cursors;

  Future<JournalRead> read({DateTime? now, String uid = 'alice'}) =>
      readJournal(uid: uid, source: journal, cursors: cursors, now: now ?? _t0);

  Map<String, int> quantities(JournalRead read) => <String, int>{
    for (final ViceActivity e in read.entries) e.id: e.quantity,
  };

  setUp(() {
    journal = _Journal()
      ..put('a', _t0.subtract(const Duration(days: 2)))
      ..put('b', null)
      ..put('c', _t0.subtract(const Duration(days: 1)));
    cursors = _MemoryCursors();
  });

  test('the first run reads in full and keeps a cursor short of the newest '
      'stamp', () async {
    final JournalRead first = await read();
    expect(first.kind, JournalReadKind.full);
    expect(first.entries, hasLength(3));
    expect(cursors.byUid['alice'], (
      since: _t0.subtract(const Duration(days: 1)).subtract(cursorMargin),
      fullReadAt: _t0,
    ));
  });

  test('with no stamped entry the cursor starts at the epoch', () async {
    journal.server.clear();
    journal.put('b', null);
    await read();
    expect(
      cursors.byUid['alice']!.since,
      DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  });

  test('an open with nothing changed reads the delta, one count and the '
      'cache', () async {
    await read();
    journal.calls.clear();
    final JournalRead next = await read(now: _t0.add(const Duration(days: 1)));
    expect(next.kind, JournalReadKind.delta);
    expect(journal.calls, <String>['delta', 'count', 'cache']);
    expect(next.entries, hasLength(3));
  });

  test(
    'an edit elsewhere arrives through the delta and moves the cursor',
    () async {
      await read();
      final DateTime editedAt = _t0.add(const Duration(hours: 3));
      journal.put('a', editedAt, quantity: 7);
      final JournalRead next = await read(
        now: _t0.add(const Duration(hours: 4)),
      );
      expect(next.kind, JournalReadKind.delta);
      expect(quantities(next)['a'], 7);
      expect(cursors.byUid['alice']!.since, editedAt.subtract(cursorMargin));
      expect(cursors.byUid['alice']!.fullReadAt, _t0);
    },
  );

  test('the delta wins over the cache even when the SDK did not write it '
      'through, unless the cached copy has a queued write', () async {
    await read();
    journal.writeThrough = false;
    journal.cache['a'] = _entry('a', quantity: 9, pending: true);
    journal.cache.remove('c');
    journal.put('c', _t0.add(const Duration(hours: 1)), quantity: 4);
    journal.put('a', _t0.add(const Duration(hours: 1)), quantity: 5);
    final JournalRead next = await read(now: _t0.add(const Duration(hours: 2)));
    expect(next.kind, JournalReadKind.delta);
    expect(quantities(next), <String, int>{'a': 9, 'b': 1, 'c': 4});
  });

  test('a new entry elsewhere arrives through the delta', () async {
    await read();
    journal.put('d', _t0.add(const Duration(hours: 1)));
    final JournalRead next = await read(now: _t0.add(const Duration(hours: 2)));
    expect(next.kind, JournalReadKind.delta);
    expect(next.entries.map((ViceActivity e) => e.id), contains('d'));
  });

  test('a delete elsewhere is caught by the count and read in full', () async {
    await read();
    journal.server.remove('a');
    journal.calls.clear();
    final JournalRead next = await read(now: _t0.add(const Duration(hours: 2)));
    expect(journal.calls, <String>['delta', 'count', 'cache', 'full']);
    expect(next.kind, JournalReadKind.full);
    expect(next.entries.map((ViceActivity e) => e.id), isNot(contains('a')));
  });

  test('an unstamped create elsewhere, or an evicted entry, is caught by the '
      'count', () async {
    await read();
    journal.put('e', null);
    expect((await read()).kind, JournalReadKind.full);
    journal.cache.remove('b');
    expect((await read()).kind, JournalReadKind.full);
    expect(journal.cache, contains('b'));
  });

  test(
    'the cursor is trusted for seven days, then read in full again',
    () async {
      await read();
      expect(
        (await read(now: _t0.add(fullReadEvery))).kind,
        JournalReadKind.delta,
      );
      final DateTime later = _t0.add(
        fullReadEvery + const Duration(minutes: 1),
      );
      expect((await read(now: later)).kind, JournalReadKind.full);
      expect(cursors.byUid['alice']!.fullReadAt, later);
    },
  );

  test('a clock set back before the last full read reads in full', () async {
    await read();
    expect(
      (await read(now: _t0.subtract(const Duration(hours: 1)))).kind,
      JournalReadKind.full,
    );
  });

  test('an index still building falls back to a full read', () async {
    await read();
    journal.indexBuilding = true;
    journal.calls.clear();
    final JournalRead next = await read(now: _t0.add(const Duration(hours: 1)));
    expect(journal.calls, <String>['delta', 'full']);
    expect(next.kind, JournalReadKind.full);
  });

  test('offline it answers from the cache and keeps the cursor', () async {
    await read();
    final JournalCursor before = cursors.byUid['alice']!;
    journal.offline = true;
    final JournalRead next = await read(now: _t0.add(const Duration(days: 1)));
    expect(next.kind, JournalReadKind.fullFromCache);
    expect(next.entries, hasLength(3));
    expect(cursors.byUid['alice'], before);
  });

  test('offline on a first run stores no cursor', () async {
    journal.offline = true;
    expect((await read()).kind, JournalReadKind.fullFromCache);
    expect(cursors.byUid, isEmpty);
  });

  test('without a disk cache every read is full and stores nothing', () async {
    journal.persistentCache = false;
    expect((await read()).kind, JournalReadKind.full);
    expect((await read()).kind, JournalReadKind.full);
    expect(cursors.byUid, isEmpty);
  });

  test("another user's cursor is never used", () async {
    await read();
    final JournalRead bob = await read(uid: 'bob');
    expect(bob.kind, JournalReadKind.full);
    expect(cursors.byUid.keys, containsAll(<String>['alice', 'bob']));
  });

  test('entries come newest first, as the full query orders them', () async {
    await read();
    final JournalRead next = await read();
    final List<Timestamp> times = <Timestamp>[
      for (final ViceActivity e in next.entries) e.createdAt,
    ];
    expect(times, List<Timestamp>.of(times)..sort((a, b) => b.compareTo(a)));
  });

  group('PrefsJournalCursorStore', () {
    setUp(
      () => SharedPreferences.setMockInitialValues(<String, Object>{
        'appearance': 'dark',
      }),
    );

    test('keeps a cursor per uid, and clearAll removes every one and nothing '
        'else', () async {
      const PrefsJournalCursorStore store = PrefsJournalCursorStore();
      final JournalCursor cursor = (since: _t0, fullReadAt: _t0);
      await store.write('alice', cursor);
      await store.write('bob', (since: _t0, fullReadAt: _t0));
      expect(await store.read('alice'), cursor);
      expect(await store.read('carol'), isNull);
      await PrefsJournalCursorStore.clearAll();
      expect(await store.read('alice'), isNull);
      expect(await store.read('bob'), isNull);
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('appearance'), 'dark');
    });
  });
}
