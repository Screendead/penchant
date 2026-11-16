import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/account/claude_access.dart';
import 'package:tracker/data/activity_content.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/data/limits.dart';
import 'package:tracker/data/trigger_tree.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/firebase_init.dart';
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/say_it/say_it_setting.dart';

/// Which feature is reading: a sentence about now (Say it to log) or the
/// person's account of days they missed (Catch up).
enum EntryMode { now, days }

/// One entry Claude proposed, checked here; nothing is written until the
/// person saves it.
class DraftEntry {
  const DraftEntry({
    required this.vice,
    required this.amount,
    required this.at,
    this.note,
    this.triggers = const <String>[],
  });

  final Vice vice;
  final num amount;
  final DateTime at;
  final String? note;
  final List<String> triggers;

  DraftEntry copyWith({Vice? vice, num? amount, DateTime? at}) => DraftEntry(
    vice: vice ?? this.vice,
    amount: amount ?? this.amount,
    at: at ?? this.at,
    note: note,
    triggers: triggers,
  );
}

/// What came back: the entries that passed every check here, and how many
/// the server or this device dropped.
typedef ReadEntries = ({List<DraftEntry> entries, int dropped});

/// The limits shared with functions/entry_reader.js; a test runs both over
/// functions/entry_reader_fixture.json.
abstract final class EntryLimits {
  static const int maxHabits = 50;
  static const int maxName = 60;
  static const int maxUnit = 40;
  static const num maxAmount = 1000;
  static const int maxTags = 4;
  static int maxText(EntryMode mode) => mode == EntryMode.now ? 500 : 2000;
  static int maxEntries(EntryMode mode) => mode == EntryMode.now ? 10 : 40;
  static const int maxDays = 7;

  /// How far back Catch up offers days.
  static const int catchUpReach = 14;
}

const List<String> _weekdays = <String>[
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

String isoDate(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-'
    '${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';

String _clock(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// The habits that may be named, numbered from 1 in creation order:
/// unarchived, opened, with a name; at most [EntryLimits.maxHabits].
List<({int id, Vice vice})> entryHabits(Iterable<Vice> vices) {
  final List<Vice> open =
      vices
          .where((Vice v) => !v.archived && !v.locked && v.name.trim() != '')
          .toList()
        ..sort((Vice a, Vice b) {
          final int byTime = a.createdAt.compareTo(b.createdAt);
          return byTime != 0 ? byTime : a.id.compareTo(b.id);
        });
  return <({int id, Vice vice})>[
    for (int i = 0; i < open.length && i < EntryLimits.maxHabits; i++)
      (id: i + 1, vice: open[i]),
  ];
}

/// The days a reading may place entries on: yesterday and today for [now]
/// mode (so "last night" works), else the picked [days], oldest first.
List<DateTime> entryDays(
  EntryMode mode,
  DateTime now, {
  List<DateTime> days = const <DateTime>[],
}) {
  final DateTime today = startOfDay(now);
  if (mode == EntryMode.now) return <DateTime>[addDays(today, -1), today];
  final List<DateTime> picked =
      days
          .map(startOfDay)
          .where((DateTime d) => !d.isAfter(today))
          .toSet()
          .toList()
        ..sort();
  return picked;
}

/// Everything sent: the mode, the words, the local time now, the allowed
/// dates with their weekdays, and each habit's number, name and unit words.
/// No parameter can carry an entry, a note, Health or the uid.
Map<String, Object?> entryRequest(
  EntryMode mode,
  String text, {
  required DateTime now,
  required List<DateTime> days,
  required List<({int id, Vice vice})> habits,
}) {
  String cut(String s, int max) => s.length > max ? s.substring(0, max) : s;
  return <String, Object?>{
    'mode': mode.name,
    'text': text,
    'now': '${isoDate(now)}T${_clock(now)}',
    'dates': <Object?>[
      for (final DateTime d in days)
        <String, Object?>{
          'date': isoDate(d),
          'weekday': _weekdays[d.weekday - 1],
        },
    ],
    'habits': <Object?>[
      for (final ({int id, Vice vice}) h in habits)
        <String, Object?>{
          'id': h.id,
          'name': cut(h.vice.name, EntryLimits.maxName),
          'unit': cut(h.vice.units.plural, EntryLimits.maxUnit),
          'unit_one': cut(h.vice.units.singular, EntryLimits.maxUnit),
        },
    ],
  };
}

final RegExp _time = RegExp(r'^([01]\d|2[0-3]):([0-5]\d)$');
final RegExp _date = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');
final Set<String> _leafPaths = triggerPaths()
    .where((String p) => p.contains('/'))
    .toSet();

/// The server's `{entries, dropped}` checked again: each entry's habit is
/// one sent, its amount above 0 and at most [EntryLimits.maxAmount], its
/// date one sent and its time valid and not after [now], its note empty or
/// one line of [text] copied exactly, its tags tree leaves quoted from
/// [text]; at most [EntryLimits.maxEntries]. Anything else is dropped and
/// counted beside the server's count. Never throws.
ReadEntries checkEntries(
  Object? answer, {
  required EntryMode mode,
  required String text,
  required DateTime now,
  required List<DateTime> days,
  required List<({int id, Vice vice})> habits,
}) {
  final Object? listed = answer is Map ? answer['entries'] : null;
  final Object? serverDropped = answer is Map ? answer['dropped'] : null;
  int dropped = serverDropped is int && serverDropped > 0 ? serverDropped : 0;
  if (listed is! List) return (entries: const <DraftEntry>[], dropped: dropped);
  final Map<int, Vice> byId = <int, Vice>{
    for (final ({int id, Vice vice}) h in habits) h.id: h.vice,
  };
  final Set<String> dates = days.map(isoDate).toSet();
  final List<DraftEntry> out = <DraftEntry>[];
  for (final Object? e in listed) {
    final DraftEntry? entry = e is Map
        ? _checked(e, text: text, now: now, dates: dates, byId: byId)
        : null;
    if (entry == null || out.length == EntryLimits.maxEntries(mode)) {
      dropped++;
    } else {
      out.add(entry);
    }
  }
  return (entries: out, dropped: dropped);
}

DraftEntry? _checked(
  Map<Object?, Object?> e, {
  required String text,
  required DateTime now,
  required Set<String> dates,
  required Map<int, Vice> byId,
}) {
  final Object? habit = e['habit'];
  final Object? amount = e['amount'];
  final Object? date = e['date'];
  final Object? time = e['time'];
  final Object? note = e['note'];
  if (habit is! int || !byId.containsKey(habit)) return null;
  if (amount is! num || !amount.isFinite) return null;
  if (amount <= 0 || amount > EntryLimits.maxAmount) return null;
  if (date is! String || !dates.contains(date)) return null;
  if (time is! String) return null;
  final RegExpMatch? t = _time.firstMatch(time);
  final RegExpMatch? d = _date.firstMatch(date);
  if (t == null || d == null) return null;
  final DateTime at = DateTime(
    int.parse(d[1]!),
    int.parse(d[2]!),
    int.parse(d[3]!),
    int.parse(t[1]!),
    int.parse(t[2]!),
  );
  // The model is told minutes; a time in the current minute is now.
  final DateTime lastMinute = DateTime(
    now.year,
    now.month,
    now.day,
    now.hour,
    now.minute,
  );
  if (at.isAfter(lastMinute)) return null;
  if (note is! String) return null;
  String? kept;
  if (note != '') {
    if (note.length > maxNoteLength || note.contains(RegExp(r'[\r\n]'))) {
      return null;
    }
    if (note.trim().isEmpty || !text.contains(note)) return null;
    kept = note;
  }
  final List<String> triggers = <String>[];
  final Object? tags = e['tags'];
  if (tags is! List) return null;
  for (final Object? tag in tags) {
    if (triggers.length == EntryLimits.maxTags) break;
    if (tag is! Map) continue;
    final Object? path = tag['path'];
    final Object? quote = tag['quote'];
    if (path is! String || quote is! String) continue;
    if (!_leafPaths.contains(path) || triggers.contains(path)) continue;
    if (quote.trim().isEmpty || !text.contains(quote)) continue;
    triggers.add(path);
  }
  if (answersTooLong(triggers: triggers, urge: null, note: kept) != null) {
    return null;
  }
  return DraftEntry(
    vice: byId[habit]!,
    amount: amount is double && amount == amount.roundToDouble()
        ? amount.toInt()
        : amount,
    at: at,
    note: kept,
    triggers: triggers,
  );
}

/// The server read the words but sent nothing usable, for [reason]
/// (`refusal`, `max_tokens`, `unparsable`, `api_error`).
class EntryReadFailed implements Exception {
  const EntryReadFailed(this.reason);

  final String reason;

  @override
  String toString() => 'EntryReadFailed($reason)';
}

abstract interface class EntryReader {
  /// Proposed entries for [text], checked here. Throws [EntryReadFailed] or
  /// the call's own error.
  Future<ReadEntries> read(
    EntryMode mode,
    String text, {
    required DateTime now,
    required List<DateTime> days,
    required List<({int id, Vice vice})> habits,
  });
}

/// The `readEntries` Cloud Function (functions/entry_reader.js).
class CallableEntryReader implements EntryReader {
  CallableEntryReader(this.call);

  final Future<Object?> Function(Map<String, Object?> data, Duration timeout)
  call;

  /// Above the function's 50 s, itself above its model requests (12 s for a
  /// sentence, 40 s for a catch-up).
  static const Duration timeout = Duration(seconds: 55);

  @override
  Future<ReadEntries> read(
    EntryMode mode,
    String text, {
    required DateTime now,
    required List<DateTime> days,
    required List<({int id, Vice vice})> habits,
  }) async {
    final Object? answer = await call(
      entryRequest(mode, text, now: now, days: days, habits: habits),
      timeout,
    );
    final Object? reason = answer is Map ? answer['reason'] : null;
    if (reason != 'ok') {
      throw EntryReadFailed(reason is String ? reason : 'unparsable');
    }
    return checkEntries(
      answer,
      mode: mode,
      text: text,
      now: now,
      days: days,
      habits: habits,
    );
  }
}

/// Null unless [mode]'s switch is on, a verified account is signed in and
/// this is not an emulator build (the function exists only in production).
final entryReaderProvider = Provider.family<EntryReader?, EntryMode>((
  Ref ref,
  EntryMode mode,
) {
  if (useFirebaseEmulators) return null;
  if (!ref.watch(entryReadingEnabledProvider(mode))) return null;
  if (ref.watch(userProvider).value == null) return null;
  if (!ref.watch(claudeAllowedProvider)) return null;
  return CallableEntryReader(
    (Map<String, Object?> data, Duration timeout) =>
        callClaude('readEntries', timeout, data),
  );
});
