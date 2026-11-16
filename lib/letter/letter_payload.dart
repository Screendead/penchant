import 'dart:convert';

import 'package:tracker/data/day.dart';
import 'package:tracker/data/day_note.dart';
import 'package:tracker/data/limits.dart';
import 'package:tracker/data/trigger_usage.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/formats.dart';
import 'package:tracker/notes/follow_up.dart';

// What the letter sends, built on this device and shown before it is sent:
// for the period only, each entry's local date and time, amount and unit,
// habit name, tag labels, urge, note and follow-up; each day note's date,
// text, tag labels and follow-up; and figures worked out here. Never Health,
// places, calendar, findings, the uid, document ids or anything outside the
// period. functions/letter.js validInput takes exactly these keys.

/// The periods offered, in months back from today.
const List<int> letterMonths = <int>[1, 3, 6];
const int defaultLetterMonths = 3;

/// The server refuses a request over 200,000 characters
/// (functions/letter.js MAX_CHARS); the device stays under it with room.
const int letterBudget = 190000;

const int _maxEntries = 5000;
const int _maxDayNotes = 200;
const int _maxUnit = 20;
const int _maxTag = 200;
const int _maxTopTags = 10;

/// An entry's urge as words, 1 to 5; the server accepts only these.
const List<String> urgeWords = <String>[
  'barely',
  'a little',
  'some',
  'a lot',
  'couldn\'t not',
];

const List<String> _monthNames = <String>[
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// [value] as the figures carry it: ASCII digits, a point and at most two
/// decimals, never grouped, so the device's check and the server's read the
/// same text.
String letterFigure(num value) {
  final num rounded = (value * 100).round() / 100;
  if (rounded == rounded.roundToDouble()) return rounded.round().toString();
  String s = rounded.toStringAsFixed(2);
  while (s.endsWith('0')) {
    s = s.substring(0, s.length - 1);
  }
  return s;
}

String _two(int n) => n.toString().padLeft(2, '0');

String _cut(String s, int max) => s.length > max ? s.substring(0, max) : s;

final RegExp _lineControl = RegExp(r'[\x00-\x09\x0b-\x1f\x7f-\x9f]');
final RegExp _control = RegExp(r'[\x00-\x1f\x7f-\x9f]');

String _oneLine(String s) => s.replaceAll(_control, ' ').trim();

String _lines(String s) =>
    s.replaceAll('\r\n', '\n').replaceAll(_lineControl, ' ').trim();

/// One note, day note or answer as the preview lists it.
class LetterNote {
  const LetterNote({
    required this.day,
    required this.text,
    this.habit,
    this.followUp,
  });

  final DateTime day;

  /// The habit of an entry's note; null for a day note.
  final String? habit;
  final String text;
  final ({String question, String answer})? followUp;
}

/// How much is sent, and what was left out, for the preview and the saved
/// letter.
class LetterCounts {
  const LetterCounts({
    required this.entries,
    required this.entryNotes,
    required this.dayNotes,
    required this.followUps,
    required this.leftOut,
  });

  final int entries;
  final int entryNotes;
  final int dayNotes;
  final int followUps;

  /// Entries and day notes that would not open here, or whose habit would
  /// not or is gone: never sent.
  final int leftOut;

  Map<String, Object?> toJson() => <String, Object?>{
    'entries': entries,
    'entryNotes': entryNotes,
    'dayNotes': dayNotes,
    'followUps': followUps,
    'leftOut': leftOut,
  };

  static LetterCounts? fromJson(Object? json) {
    if (json is! Map) return null;
    int? n(String key) => switch (json[key]) {
      final int v when v >= 0 => v,
      _ => null,
    };
    final List<int?> values = <int?>[
      n('entries'),
      n('entryNotes'),
      n('dayNotes'),
      n('followUps'),
      n('leftOut'),
    ];
    if (values.contains(null)) return null;
    return LetterCounts(
      entries: values[0]!,
      entryNotes: values[1]!,
      dayNotes: values[2]!,
      followUps: values[3]!,
      leftOut: values[4]!,
    );
  }
}

/// The request for one letter, exactly as it will be sent.
class LetterPayload {
  const LetterPayload({
    required this.json,
    required this.from,
    required this.to,
    required this.months,
    required this.shortened,
    required this.counts,
    required this.notes,
  });

  final Map<String, Object?> json;

  /// The first and last local days sent.
  final DateTime from;
  final DateTime to;
  final int months;

  /// The chosen period was over [letterBudget] and starts later.
  final bool shortened;
  final LetterCounts counts;
  final List<LetterNote> notes;

  int get chars => jsonEncode(json).length;

  bool get isEmpty => counts.entries == 0 && counts.dayNotes == 0;
}

/// The first day of the last [months] months ending with [today].
DateTime letterStart(DateTime today, int months) {
  final DateTime day = startOfDay(today);
  return DateTime(day.year, day.month - months, day.day + 1);
}

/// The payload for the last [months] months to [today], from the [vices],
/// [activities] and [dayNotes] read for it (anything outside the period is
/// dropped here). Over [budget] characters, the period starts as late as it
/// must to fit and [LetterPayload.shortened] says so. Null when not even
/// [today] alone fits.
LetterPayload? buildLetterPayload({
  required List<Vice> vices,
  required List<ViceActivity> activities,
  required List<DayNote> dayNotes,
  required DateTime today,
  required int months,
  int budget = letterBudget,
}) {
  final DateTime last = startOfDay(today);
  final DateTime first = letterStart(today, months);
  LetterPayload build(DateTime from, bool shortened) => _build(
    vices: vices,
    activities: activities,
    dayNotes: dayNotes,
    from: from,
    to: last,
    months: months,
    shortened: shortened,
  );
  final LetterPayload whole = build(first, false);
  if (whole.chars <= budget) return whole;
  // The latest start that does not fit, and the earliest known to.
  int tooBig = 0;
  int fits = daysBetween(first, last);
  LetterPayload? best = build(last, true);
  if (best.chars > budget) return null;
  while (fits - tooBig > 1) {
    final int mid = (tooBig + fits) ~/ 2;
    final LetterPayload trial = build(addDays(first, mid), true);
    if (trial.chars <= budget) {
      fits = mid;
      best = trial;
    } else {
      tooBig = mid;
    }
  }
  return best;
}

({String question, String answer})? _followUp(FollowUp? f) {
  if (f == null) return null;
  final String question = _oneLine(_cut(f.question, maxFollowUpQuestionLength));
  final String answer = _lines(_cut(f.answer, maxFollowUpAnswerLength));
  if (question.isEmpty || answer.isEmpty) return null;
  return (question: question, answer: answer);
}

List<String> _tags(List<String> triggers) => <String>[
  for (final String t in triggers.take(maxTriggers))
    if (_oneLine(_cut(triggerDisplay(t), _maxTag)) case final String label
        when label.isNotEmpty)
      label,
];

class _Tally {
  num total = 0;
  int entries = 0;
  final Set<String> days = <String>{};

  void add(num measure, String day) {
    total += measure;
    entries++;
    days.add(day);
  }

  Map<String, Object?> row(String habit, {String? unit}) => <String, Object?>{
    'habit': habit,
    'unit': ?unit,
    'total': letterFigure(total),
    'entries': '$entries',
    'days': '${days.length}',
  };
}

LetterPayload _build({
  required List<Vice> vices,
  required List<ViceActivity> activities,
  required List<DayNote> dayNotes,
  required DateTime from,
  required DateTime to,
  required int months,
  required bool shortened,
}) {
  final DateTime end = addDays(to, 1);
  final Map<String, Vice> byId = <String, Vice>{
    for (final Vice v in vices) v.id: v,
  };
  int leftOut = 0;

  final List<ViceActivity> inPeriod =
      activities.where((ViceActivity a) {
        final DateTime at = a.createdAt.toDate();
        return !at.isBefore(from) && at.isBefore(end);
      }).toList()..sort(
        (ViceActivity a, ViceActivity b) => a.createdAt.compareTo(b.createdAt),
      );

  final List<Map<String, Object?>> entries = <Map<String, Object?>>[];
  final List<LetterNote> notes = <LetterNote>[];
  final Map<String, _Tally> habits = <String, _Tally>{};
  final Map<String, String> habitUnits = <String, String>{};
  final Map<String, Map<String, _Tally>> monthly =
      <String, Map<String, _Tally>>{};
  final List<String> monthOrder = <String>[];
  final Map<String, int> tagCounts = <String, int>{};
  int entryNotes = 0;
  int followUps = 0;

  for (final ViceActivity a in inPeriod) {
    final Vice? vice = byId[a.viceID];
    final String name = vice == null
        ? ''
        : _oneLine(_cut(vice.name, maxViceNameLength));
    if (a.locked || vice == null || vice.locked || name.isEmpty) {
      leftOut++;
      continue;
    }
    if (entries.length == _maxEntries) {
      leftOut++;
      continue;
    }
    final DateTime at = a.createdAt.toDate();
    final String day = dayKey(at);
    final num measure = a.measure;
    final List<String> tags = _tags(a.triggers);
    final String? note = switch (a.note) {
      final String n when _oneLine(_cut(n, maxNoteLength)).isNotEmpty =>
        _oneLine(_cut(n, maxNoteLength)),
      _ => null,
    };
    final ({String question, String answer})? follow = _followUp(a.followUp);
    final int? urge = a.urge;
    entries.add(<String, Object?>{
      'date': day,
      'time': '${_two(at.hour)}:${_two(at.minute)}',
      'habit': name,
      'amount': letterFigure(measure),
      'unit': _oneLine(_cut(vice.units.nameFor(measure), _maxUnit)),
      'tags': tags,
      if (urge != null && urge >= 1 && urge <= urgeWords.length)
        'urge': urgeWords[urge - 1],
      'note': ?note,
      if (follow != null)
        'followUp': <String, Object?>{
          'question': follow.question,
          'answer': follow.answer,
        },
    });
    if (note != null) entryNotes++;
    if (follow != null) followUps++;
    if (note != null || follow != null) {
      notes.add(
        LetterNote(
          day: startOfDay(at),
          habit: name,
          text: note ?? '',
          followUp: follow,
        ),
      );
    }
    for (final String t in tags) {
      tagCounts[t] = (tagCounts[t] ?? 0) + 1;
    }
    habits.putIfAbsent(name, _Tally.new).add(measure, day);
    habitUnits.putIfAbsent(
      name,
      () => _oneLine(_cut(vice.units.plural, _maxUnit)),
    );
    final String month = '${_monthNames[at.month - 1]} ${at.year}';
    if (!monthly.containsKey(month)) monthOrder.add(month);
    monthly
        .putIfAbsent(month, () => <String, _Tally>{})
        .putIfAbsent(name, _Tally.new)
        .add(measure, day);
  }

  final List<({DateTime day, DayNote note})> dated =
      <({DateTime day, DayNote note})>[
        for (final DayNote n in dayNotes)
          if (parseDayKey(n.day) case final DateTime day
              when !day.isBefore(from) && day.isBefore(end))
            (day: day, note: n),
      ]..sort((a, b) => a.day.compareTo(b.day));
  final List<Map<String, Object?>> sentDayNotes = <Map<String, Object?>>[];
  for (final (:DateTime day, :DayNote note) in dated) {
    final String text = _lines(_cut(note.text, maxDayNoteLength));
    if (note.locked || text.isEmpty || sentDayNotes.length == _maxDayNotes) {
      if (note.locked || text.isNotEmpty) leftOut++;
      continue;
    }
    final List<String> tags = _tags(note.triggers);
    final ({String question, String answer})? follow = _followUp(
      note.followUp,
    );
    sentDayNotes.add(<String, Object?>{
      'date': dayKey(day),
      'text': text,
      'tags': tags,
      if (follow != null)
        'followUp': <String, Object?>{
          'question': follow.question,
          'answer': follow.answer,
        },
    });
    if (follow != null) followUps++;
    notes.add(LetterNote(day: day, text: text, followUp: follow));
    for (final String t in tags) {
      tagCounts[t] = (tagCounts[t] ?? 0) + 1;
    }
  }
  notes.sort((LetterNote a, LetterNote b) => a.day.compareTo(b.day));

  final List<MapEntry<String, int>> topTags = tagCounts.entries.toList()
    ..sort((MapEntry<String, int> a, MapEntry<String, int> b) {
      final int byCount = b.value.compareTo(a.value);
      return byCount != 0 ? byCount : a.key.compareTo(b.key);
    });

  final Map<String, Object?> json = <String, Object?>{
    'period': <String, Object?>{
      'from': dayKey(from),
      'to': dayKey(to),
      'months': months,
      'shortened': shortened,
    },
    'entries': entries,
    'dayNotes': sentDayNotes,
    'figures': <String, Object?>{
      'habits': <Object?>[
        for (final MapEntry<String, _Tally> h in habits.entries)
          h.value.row(h.key, unit: habitUnits[h.key]),
      ],
      'months': <Object?>[
        for (final String month in monthOrder)
          <String, Object?>{
            'month': month,
            'habits': <Object?>[
              for (final MapEntry<String, _Tally> h
                  in monthly[month]!.entries)
                h.value.row(h.key),
            ],
          },
      ],
      'notes': <String, Object?>{
        'entryNotes': '$entryNotes',
        'dayNotes': '${sentDayNotes.length}',
        'followUps': '$followUps',
      },
      'tags': <Object?>[
        for (final MapEntry<String, int> t in topTags.take(_maxTopTags))
          <String, Object?>{'tag': t.key, 'count': '${t.value}'},
      ],
    },
  };
  return LetterPayload(
    json: json,
    from: from,
    to: to,
    months: months,
    shortened: shortened,
    counts: LetterCounts(
      entries: entries.length,
      entryNotes: entryNotes,
      dayNotes: sentDayNotes.length,
      followUps: followUps,
      leftOut: leftOut,
    ),
    notes: notes,
  );
}

/// The period as the page names it: "16 August to 16 November 2026".
String letterPeriodLabel(DateTime from, DateTime to) =>
    '${formatDate(from)} to ${formatDate(to)}';
