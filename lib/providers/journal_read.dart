import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tracker/data/updated_at.dart';
import 'package:tracker/data/vice_activity.dart';

// Reading every entry of the journal from the server costs a read per entry
// (about 4,900 for a long journal) on every Insights or Ask open. Instead a
// device that has done one full read keeps a cursor, the newest `updatedAt`
// the server showed it, and on the next open asks the server only for entries
// stamped since, checks one count() against what its cache then holds, and
// reads the rest from the cache. Any doubt falls back to the full read.

// How long a device trusts its cache before reading the whole journal again.
// It bounds what neither the cursor nor the count can see: an edit by an
// older build, which does not stamp `updatedAt`, and a delete elsewhere
// cancelled out by an unstamped create.
const Duration fullReadEvery = Duration(days: 7);

// Taken off every stored cursor, so the next delta overlaps the last read:
// nothing promises that a write's `request.time` orders it against a read
// running at the same moment.
const Duration cursorMargin = Duration(minutes: 5);

typedef JournalCursor = ({DateTime since, DateTime fullReadAt});

// Per uid, so one user's cursor is never another's; timestamps only.
abstract interface class JournalCursorStore {
  Future<JournalCursor?> read(String uid);
  Future<void> write(String uid, JournalCursor cursor);
}

// A read's entries, whether the SDK answered from its cache, and the newest
// server `updatedAt` among them (null when none has one).
typedef JournalPage = ({
  List<ViceActivity> entries,
  bool fromCache,
  DateTime? newest,
});

// One user's whole-journal query, as the reads the decision needs.
abstract interface class JournalSource {
  // False where Firestore keeps no disk cache (emulator builds): the cache
  // then holds only what a listener holds, so every read is a full one.
  bool get persistentCache;

  // Queued writes sit in the cache but not in the server's count.
  Future<void> settlePending();

  // The query from the server, or from the cache when the server cannot be
  // reached, as a default-source get() answers.
  Future<JournalPage> full();

  // From the server: entries in the query's range stamped at or after [since].
  Future<JournalPage> changedSince(DateTime since);

  // The server's count() of the query.
  Future<int> serverCount();

  // The query from the cache alone.
  Future<JournalPage> cached();
}

enum JournalReadKind { full, fullFromCache, delta }

typedef JournalRead = ({List<ViceActivity> entries, JournalReadKind kind});

DateTime _laterOf(DateTime a, DateTime b) => a.isAfter(b) ? a : b;

int _newestFirst(ViceActivity a, ViceActivity b) {
  final int byTime = b.createdAt.compareTo(a.createdAt);
  return byTime != 0 ? byTime : b.id.compareTo(a.id);
}

Future<JournalRead> readJournal({
  required String uid,
  required JournalSource source,
  required JournalCursorStore cursors,
  required DateTime now,
}) async {
  Future<JournalRead> fullRead() async {
    final JournalPage page = await source.full();
    if (page.fromCache) {
      return (entries: page.entries, kind: JournalReadKind.fullFromCache);
    }
    if (source.persistentCache) {
      // With no stamped entry yet, every stamped one is new to this device.
      final DateTime since = page.newest == null
          ? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true)
          : page.newest!.subtract(cursorMargin);
      await cursors.write(uid, (since: since, fullReadAt: now));
    }
    return (entries: page.entries, kind: JournalReadKind.full);
  }

  if (!source.persistentCache) {
    return fullRead();
  }
  final JournalCursor? cursor = await cursors.read(uid);
  final Duration? age = cursor == null
      ? null
      : now.difference(cursor.fullReadAt);
  // A clock set back makes the age negative; trust it no more than an old one.
  if (cursor == null || age! > fullReadEvery || age.isNegative) {
    return fullRead();
  }

  final JournalPage changed;
  final int serverCount;
  final JournalPage cached;
  try {
    await source.settlePending();
    changed = await source.changedSince(cursor.since);
    serverCount = await source.serverCount();
    cached = await source.cached();
  } on Exception {
    // Offline, the full read answers from the cache; online (an index still
    // building, say) it reads from the server and starts a new cursor.
    return fullRead();
  }

  // The SDK writes server results through to its cache, but the merge does
  // not rest on it; a cached copy with a queued write is the newer one.
  final Map<String, ViceActivity> byID = <String, ViceActivity>{
    for (final ViceActivity entry in cached.entries) entry.id: entry,
  };
  for (final ViceActivity entry in changed.entries) {
    if (byID[entry.id]?.pending != true) {
      byID[entry.id] = entry;
    }
  }
  // A delete elsewhere, an entry the cache evicted, or one an older build
  // created unstamped elsewhere.
  if (byID.length != serverCount) {
    return fullRead();
  }
  final DateTime? newest = changed.newest;
  if (newest != null) {
    await cursors.write(uid, (
      since: _laterOf(cursor.since, newest.subtract(cursorMargin)),
      fullReadAt: cursor.fullReadAt,
    ));
  }
  return (
    entries: byID.values.toList()..sort(_newestFirst),
    kind: JournalReadKind.delta,
  );
}

const String _cursorPrefix = 'journalRead.';

class PrefsJournalCursorStore implements JournalCursorStore {
  const PrefsJournalCursorStore();

  static String _since(String uid) => '$_cursorPrefix$uid.since';
  static String _fullReadAt(String uid) => '$_cursorPrefix$uid.fullReadAt';

  @override
  Future<JournalCursor?> read(String uid) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final int? since = prefs.getInt(_since(uid));
    final int? fullReadAt = prefs.getInt(_fullReadAt(uid));
    if (since == null || fullReadAt == null) {
      return null;
    }
    return (
      since: DateTime.fromMillisecondsSinceEpoch(since, isUtc: true),
      fullReadAt: DateTime.fromMillisecondsSinceEpoch(fullReadAt, isUtc: true),
    );
  }

  @override
  Future<void> write(String uid, JournalCursor cursor) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_since(uid), cursor.since.millisecondsSinceEpoch);
    await prefs.setInt(
      _fullReadAt(uid),
      cursor.fullReadAt.millisecondsSinceEpoch,
    );
  }

  // Every user's, with the cache they describe: sign-out and deletion.
  static Future<void> clearAll() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    for (final String key in prefs.getKeys().where(
      (String key) => key.startsWith(_cursorPrefix),
    )) {
      await prefs.remove(key);
    }
  }
}

// The newest resolved server `updatedAt` in [snapshot]; a queued write's is
// still unresolved and says nothing about the server.
DateTime? newestStamp(QuerySnapshot<Map<String, dynamic>> snapshot) {
  DateTime? newest;
  for (final QueryDocumentSnapshot<Map<String, dynamic>> doc in snapshot.docs) {
    if (doc.metadata.hasPendingWrites) continue;
    final Object? stamp = doc.data()[updatedAtField];
    if (stamp is Timestamp) {
      final DateTime at = stamp.toDate().toUtc();
      if (newest == null || at.isAfter(newest)) newest = at;
    }
  }
  return newest;
}
