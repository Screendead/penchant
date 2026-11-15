import 'dart:async';
import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/data/trigger_usage.dart';
import 'package:tracker/firebase_init.dart';
import 'package:tracker/insights/weekly_review.dart';
import 'package:tracker/insights/weekly_words_setting.dart';
import 'package:tracker/providers/user_provider.dart';

/// The most habits sent, one placeholder letter each.
const int maxWordedHabits = 26;

/// The most busiest hours and tags sent, as the review page lists them.
const int maxWordedHours = 3;
const int maxWordedTags = 5;

/// The words a number may not be written as (functions/weekly_words.js has
/// the same list): the model is told to write numerals only, and a reply
/// using one of these outside a sent label or unit is dropped, since its value
/// cannot be checked against the figures.
const List<String> numberWords = <String>[
  'zero', 'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight',
  'nine', 'ten', 'eleven', 'twelve', 'thirteen', 'fourteen', 'fifteen',
  'sixteen', 'seventeen', 'eighteen', 'nineteen', 'twenty', 'thirty',
  'forty', 'fifty', 'sixty', 'seventy', 'eighty', 'ninety', 'hundred',
  'thousand', 'million', 'dozen', 'half', 'halves', 'quarter', 'third',
  'once', 'twice', 'thrice', 'double', 'triple', 'couple',
];

final RegExp _numeral = RegExp(r'\d+(?:[.:]\d+)*');
final RegExp _nonAsciiNumeral = RegExp(r'[^\P{N}0-9]', unicode: true);
final RegExp _placeholder = RegExp(r'\bHabit [A-Z]\b');
final RegExp _numberWord = RegExp(
  '\\b(?:${numberWords.join('|')})\\b',
  caseSensitive: false,
);

String placeholderFor(int index) =>
    'Habit ${String.fromCharCode(0x41 + index)}';

/// [n] in ASCII digits with a point, to 2 decimal places, no grouping: the
/// form the server and the check compare.
String numeral(num n) {
  final double r = (n * 100).round() / 100;
  return r == r.roundToDouble() ? r.toInt().toString() : r.toString();
}

String _clock(int hour) => '${hour.toString().padLeft(2, '0')}:00';

/// What is sent for one week ([data]: computed figures only, each habit under
/// a placeholder) and the habit names that go back in by placeholder
/// ([names], which never leave the device).
@immutable
class WeeklyFigures {
  WeeklyFigures(this.data, this.names) : key = jsonEncode(data);

  final Map<String, Object?> data;
  final Map<String, String> names;

  /// [data] encoded, which is what equality compares.
  final String key;

  /// The figures of [review], or null for a week with nothing logged, which
  /// is never sent. Free-text triggers go as a count only.
  static WeeklyFigures? of(WeeklyReview review) {
    if (review.entries == 0 || review.habits.isEmpty) return null;
    final Map<String, String> names = <String, String>{};
    final List<Map<String, Object?>> habits = <Map<String, Object?>>[];
    for (final (int i, HabitWeek h) in review.habits
        .take(maxWordedHabits)
        .indexed) {
      final String placeholder = placeholderFor(i);
      names[placeholder] = h.vice.name;
      final double? usual = h.usual;
      habits.add(<String, Object?>{
        'habit': placeholder,
        'unitOne': h.vice.units.singular,
        'unitOther': h.vice.units.plural,
        'total': numeral(h.total),
        'entries': numeral(h.entries),
        'days': numeral(review.days[h.vice.id] ?? 0),
        'usual': usual == null ? null : numeral((usual * 10).round() / 10),
      });
    }
    return WeeklyFigures(<String, Object?>{
      'entries': numeral(review.entries),
      'habits': habits,
      'hours': <Map<String, Object?>>[
        for (final HourCount h in review.busiest(maxWordedHours))
          <String, Object?>{
            'from': _clock(h.hour),
            'to': _clock((h.hour + 1) % 24),
            'entries': numeral(h.entries),
          },
      ],
      'tags': <Map<String, Object?>>[
        for (final TagCount t in review.tags.take(maxWordedTags))
          <String, Object?>{
            'path': t.path,
            'label': triggerDisplay(t.path),
            'entries': numeral(t.entries),
          },
      ],
      'ownWords': numeral(review.ownWords),
    }, names);
  }

  @override
  bool operator ==(Object other) =>
      other is WeeklyFigures &&
      other.key == key &&
      mapEquals(other.names, names);

  @override
  int get hashCode => Object.hash(key, Object.hashAllUnordered(names.values));
}

List<Map<String, Object?>> _list(Object? value) => <Map<String, Object?>>[
  if (value is List)
    for (final Object? item in value)
      if (item is Map<String, Object?>) item,
];

/// Why [text] cannot be shown beside the figures [data], or `ok`. The same
/// rules as `checkParagraph` in functions/weekly_words.js:
/// 1. 1 to 1200 UTF-16 units after trimming.
/// 2. No numeral other than ASCII digits (no ½, ², full-width digits).
/// 3. Each run of digits, with any '.' or ':' between digits (9, 10.5, 20:00),
///    equals one found the same way in a sent string.
/// 4. Each "Habit X" (X one capital letter) is a sent placeholder.
/// 5. With every sent unit word, tag label and part of a label between ' › '
///    taken out (ignoring case, longest first), no word of [numberWords] is
///    left.
/// Run it on the reply as sent, before names go back in.
String checkParagraph(String text, Map<String, Object?> data) {
  final String trimmed = text.trim();
  if (trimmed.isEmpty) return 'empty';
  if (trimmed.length > 1200) return 'too_long';
  if (_nonAsciiNumeral.hasMatch(trimmed)) return 'number';
  final List<Map<String, Object?>> habits = _list(data['habits']);
  final List<Map<String, Object?>> tags = _list(data['tags']);
  final List<String> sent = <String>[
    for (final Object? v in <Object?>[
      data['entries'],
      data['ownWords'],
      for (final Map<String, Object?> h in habits) ...<Object?>[
        h['habit'],
        h['unitOne'],
        h['unitOther'],
        h['total'],
        h['entries'],
        h['days'],
        h['usual'],
      ],
      for (final Map<String, Object?> h in _list(data['hours'])) ...<Object?>[
        h['from'],
        h['to'],
        h['entries'],
      ],
      for (final Map<String, Object?> t in tags) ...<Object?>[
        t['label'],
        t['entries'],
      ],
    ])
      if (v is String) v,
  ];
  final Set<String> allowed = <String>{
    for (final String s in sent)
      for (final Match m in _numeral.allMatches(s)) m[0]!,
  };
  for (final Match m in _numeral.allMatches(trimmed)) {
    if (!allowed.contains(m[0])) return 'number';
  }
  final Set<String> placeholders = <String>{
    for (final Map<String, Object?> h in habits)
      if (h['habit'] case final String p) p,
  };
  for (final Match m in _placeholder.allMatches(trimmed)) {
    if (!placeholders.contains(m[0])) return 'placeholder';
  }
  final List<String> phrases = <String>[
    for (final Map<String, Object?> h in habits)
      for (final Object? w in <Object?>[h['unitOne'], h['unitOther']])
        if (w is String) w,
    for (final Map<String, Object?> t in tags)
      if (t['label'] case final String label) ...<String>[
        label,
        ...label.split(' › '),
      ],
  ]..sort((String a, String b) => b.length.compareTo(a.length));
  String rest = trimmed;
  for (final String phrase in phrases) {
    if (phrase.isEmpty) continue;
    rest = rest.replaceAll(
      RegExp(RegExp.escape(phrase), caseSensitive: false),
      ' ',
    );
  }
  if (_numberWord.hasMatch(rest)) return 'number_word';
  return 'ok';
}

/// [text] with each placeholder replaced by its habit's name, in one pass so
/// a name that looks like a placeholder is never replaced again.
String restoreNames(String text, Map<String, String> names) =>
    text.replaceAllMapped(_placeholder, (Match m) => names[m[0]] ?? m[0]!);

/// Words a week's finished figures as a short paragraph.
abstract class WeeklyWords {
  /// The paragraph with habit names back in, or null when it could not be
  /// written or failed the check. Never throws.
  Future<String?> write(WeeklyFigures figures);
}

/// Null while writing the week in words is switched off or cannot work here
/// (signed out, an emulator build): the review then shows its lists alone.
final Provider<WeeklyWords?> weeklyWordsProvider = Provider<WeeklyWords?>((
  Ref ref,
) {
  // The function exists only in production, which a flagged build must never
  // reach.
  if (useFirebaseEmulators) return null;
  if (!ref.watch(weeklyWordsEnabledProvider)) return null;
  if (ref.watch(userProvider).value == null) return null;
  return CallableWeeklyWords(_callWriteWeekly);
});

/// The paragraph for [WeeklyFigures], null when there is none to show.
final weeklyParagraphProvider = FutureProvider.autoDispose
    .family<String?, WeeklyFigures>((Ref ref, WeeklyFigures figures) async {
      final WeeklyWords? words = ref.watch(weeklyWordsProvider);
      if (words == null) return null;
      return words.write(figures);
    });

Future<Object?> _callWriteWeekly(Map<String, Object?> data) async {
  final HttpsCallable callable = FirebaseFunctions.instance.httpsCallable(
    'writeWeekly',
    options: HttpsCallableOptions(timeout: CallableWeeklyWords.timeout),
  );
  return (await callable.call<Object?>(data)).data;
}

/// The `writeWeekly` Cloud Function, through [call], which sends the figures
/// and answers `{text, reason}`. Each week's answer, a failure included, is
/// kept for as long as this object lives, so reopening the page never calls
/// again; a user change or the switch makes a new one.
class CallableWeeklyWords implements WeeklyWords {
  CallableWeeklyWords(this.call);

  final Future<Object?> Function(Map<String, Object?> data) call;

  static const Duration timeout = Duration(seconds: 15);

  final Map<String, Future<String?>> _written = <String, Future<String?>>{};

  @override
  Future<String?> write(WeeklyFigures figures) =>
      _written[figures.key] ??= _write(figures);

  // Nothing about the figures or the reply is reported: a failure is a
  // missing paragraph and nothing more.
  Future<String?> _write(WeeklyFigures figures) async {
    try {
      final Object? answer = await call(figures.data).timeout(timeout);
      if (answer is! Map || answer['reason'] != 'ok') return null;
      final Object? text = answer['text'];
      if (text is! String) return null;
      if (checkParagraph(text, figures.data) != 'ok') return null;
      return restoreNames(text.trim(), figures.names);
    } catch (_) {
      return null;
    }
  }
}
