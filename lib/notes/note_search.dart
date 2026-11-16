import 'dart:math';
import 'dart:typed_data';

import 'package:tracker/data/day_note.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/notes/day_note_route.dart';
import 'package:tracker/notes/follow_up.dart';

// Search over the person's own words: entry notes, day notes and the answers
// to their follow-up questions. Pure: the page supplies the opened journal
// and, where the device has one, each note's sentence embedding.
// tools/note-search-trial.swift scores the same rules; keep them in step.

enum NoteSource { entry, entryAnswer, dayNote, dayAnswer }

class SearchableNote {
  const SearchableNote({
    required this.key,
    required this.source,
    required this.text,
    required this.at,
    required this.day,
    required this.route,
    this.viceID,
    this.question,
  });

  /// Unique among the notes: the document id and which of its texts.
  final String key;
  final NoteSource source;
  final String text;

  /// When it was written about: the entry's time, or the day's midnight.
  final DateTime at;
  final DateTime day;
  final String route;
  final String? viceID;

  /// The follow-up question an answer replies to.
  final String? question;
}

/// What can be searched, and how many items would not open here.
typedef NoteCorpus = ({List<SearchableNote> notes, int locked});

NoteCorpus noteCorpus(List<ViceActivity> entries, List<DayNote> dayNotes) {
  final List<SearchableNote> notes = <SearchableNote>[];
  int locked = 0;
  for (final ViceActivity entry in entries) {
    if (entry.locked) {
      locked++;
      continue;
    }
    final DateTime at = entry.createdAt.toDate();
    final DateTime day = DateTime(at.year, at.month, at.day);
    final String route = '/vices/${entry.viceID}/activities/${entry.id}';
    final String? note = entry.note?.trim();
    if (note != null && note.isNotEmpty) {
      notes.add(
        SearchableNote(
          key: 'a/${entry.id}/note',
          source: NoteSource.entry,
          text: note,
          at: at,
          day: day,
          route: route,
          viceID: entry.viceID,
        ),
      );
    }
    final FollowUp? followUp = entry.followUp;
    if (followUp != null) {
      notes.add(
        SearchableNote(
          key: 'a/${entry.id}/answer',
          source: NoteSource.entryAnswer,
          text: followUp.answer.trim(),
          at: at,
          day: day,
          route: route,
          viceID: entry.viceID,
          question: followUp.question,
        ),
      );
    }
  }
  for (final DayNote dayNote in dayNotes) {
    if (dayNote.locked) {
      locked++;
      continue;
    }
    final DateTime? day = parseDayKey(dayNote.day);
    if (day == null) continue;
    final String route = dayNoteRoute(day);
    final String text = dayNote.text.trim();
    if (text.isNotEmpty) {
      notes.add(
        SearchableNote(
          key: 'd/${dayNote.id}/note',
          source: NoteSource.dayNote,
          text: text,
          at: day,
          day: day,
          route: route,
        ),
      );
    }
    final FollowUp? followUp = dayNote.followUp;
    if (followUp != null) {
      notes.add(
        SearchableNote(
          key: 'd/${dayNote.id}/answer',
          source: NoteSource.dayAnswer,
          text: followUp.answer.trim(),
          at: day,
          day: day,
          route: route,
          question: followUp.question,
        ),
      );
    }
  }
  return (notes: notes, locked: locked);
}

// Folding --------------------------------------------------------------------

const Map<String, String> _bases = <String, String>{
  'a': 'àáâãäåāăąǎ',
  'c': 'çćĉċč',
  'd': 'ďđ',
  'e': 'èéêëēĕėęě',
  'g': 'ĝğġģ',
  'h': 'ĥħ',
  'i': 'ìíîïĩīĭįıǐ',
  'j': 'ĵ',
  'k': 'ķ',
  'l': 'ĺļľŀł',
  'n': 'ñńņňŉ',
  'o': 'òóôõöøōŏőǒ',
  'r': 'ŕŗř',
  's': 'śŝşšș',
  't': 'ţťŧț',
  'u': 'ùúûüũūŭůűųǔ',
  'w': 'ŵ',
  'y': 'ýÿŷ',
  'z': 'źżž',
  'ss': 'ß',
  'ae': 'æ',
  'oe': 'œ',
  'th': 'þ',
  "'": '‘’ʼ',
};

final Map<int, String> _foldTable = <int, String>{
  for (final MapEntry<String, String> e in _bases.entries)
    for (final int c in e.value.runes) c: e.key,
};

bool _isCombiningMark(int c) =>
    (c >= 0x0300 && c <= 0x036f) ||
    (c >= 0x1ab0 && c <= 0x1aff) ||
    (c >= 0x1dc0 && c <= 0x1dff) ||
    (c >= 0x20d0 && c <= 0x20ff) ||
    (c >= 0xfe20 && c <= 0xfe2f);

/// [text] lower-cased with its diacritics removed, and for each of its code
/// units the span of the original it came from, so a match found in the
/// folded text is highlighted in the original.
class FoldedText {
  FoldedText._(this.text, this._from, this._to);

  factory FoldedText(String original) {
    final StringBuffer out = StringBuffer();
    final List<int> from = <int>[];
    final List<int> to = <int>[];
    int i = 0;
    for (final int rune in original.runes) {
      final int width = rune > 0xffff ? 2 : 1;
      if (_isCombiningMark(rune)) {
        // Joins the previous character's span, so a highlight keeps it.
        if (to.isNotEmpty) to[to.length - 1] = i + width;
        i += width;
        continue;
      }
      final String lower = String.fromCharCode(rune).toLowerCase();
      final String folded = lower.runes.length == 1
          ? _foldTable[lower.runes.first] ?? lower
          : lower;
      for (int k = 0; k < folded.length; k++) {
        from.add(i);
        to.add(i + width);
      }
      out.write(folded);
      i += width;
    }
    return FoldedText._(out.toString(), from, to);
  }

  final String text;
  final List<int> _from;
  final List<int> _to;

  /// The original's span for the folded span [start, end).
  (int, int) original(int start, int end) => (_from[start], _to[end - 1]);
}

String foldText(String s) => FoldedText(s).text;

final RegExp _wordPattern = RegExp(
  r"[\p{L}\p{N}]+(?:'[\p{L}\p{N}]+)*",
  unicode: true,
);

typedef _Token = ({String word, int start, int end});

List<_Token> _tokens(String folded) => <_Token>[
  for (final RegExpMatch m in _wordPattern.allMatches(folded))
    (word: m[0]!, start: m.start, end: m.end),
];

// English words too common to search by. A query of nothing else is
// searched as written.
const Set<String> stopWords = <String>{
  'a', 'an', 'and', 'the', 'of', 'to', 'in', 'on', 'at', 'for', 'with', 'by', //
  'from', 'about', 'as', 'is', 'was', 'were', 'be', 'been', 'am', 'are', 'it',
  'its', 'i', 'me', 'my', 'we', 'our', 'you', 'your', 'he', 'she', 'they',
  'them', 'this', 'that', 'these', 'those', 'when', 'what', 'where', 'who',
  'how', 'why', 'then', 'than', 'so', 'or', 'but', 'if', 'not', 'no', 'do',
  'did', 'had', 'has', 'have', 'just', 'very',
};

List<String> queryWords(String query) {
  final List<String> all = <String>[
    for (final _Token t in _tokens(foldText(query))) t.word,
  ];
  final List<String> kept = <String>[
    for (final String w in all)
      if (!stopWords.contains(w)) w,
  ];
  return (kept.isEmpty ? all : kept).toSet().toList();
}

// A word of three letters or more also finds longer words it begins:
// "wed" finds "wedding".
bool _wordMatches(String query, String word) =>
    query.length >= 3 ? word.startsWith(query) : word == query;

// Search ----------------------------------------------------------------------

/// How a note matched, best first.
enum MatchTier { phrase, allWords, someWords, meaning }

class NoteMatch {
  const NoteMatch({
    required this.note,
    required this.tier,
    required this.highlights,
    this.share = 1,
    this.similarity,
  });

  final SearchableNote note;
  final MatchTier tier;

  /// Spans of [SearchableNote.text] to highlight, in order, not overlapping.
  final List<(int, int)> highlights;

  /// The share of the query's words found.
  final double share;

  /// Cosine similarity with the query, where meaning was compared.
  final double? similarity;
}

/// A note with its folded text, made once per journal read.
class IndexedNote {
  IndexedNote(this.note) : folded = FoldedText(note.text) {
    _words = _tokens(folded.text);
  }

  final SearchableNote note;
  final FoldedText folded;
  late final List<_Token> _words;
}

/// A meaning-only result needs at least this cosine similarity. Chosen on
/// the trial's made-up notes, where Apple's sentence embedding put wrong
/// notes as close as right ones; see tools/note-search-trial.swift.
const double meaningFloor = 0.40;

/// At most this many meaning-only results, below every word match.
const int meaningShown = 10;

/// Notes matching [query] in wording, best first: the query as written, then
/// every word, then some (more of them first); recent first within each.
/// With [similarities] (each note's cosine similarity with the query, by
/// key), notes matching no word follow, closest first, from [meaningFloor].
/// A word match is never placed below a meaning-only one.
List<NoteMatch> searchNotes(
  List<IndexedNote> index,
  String query, {
  Map<String, double>? similarities,
}) {
  final List<String> words = queryWords(query);
  if (words.isEmpty) return const <NoteMatch>[];
  final String phrase = foldText(query).trim().replaceAll(RegExp(r'\s+'), ' ');
  final List<NoteMatch> byWords = <NoteMatch>[];
  final List<NoteMatch> byMeaning = <NoteMatch>[];
  for (final IndexedNote item in index) {
    final Set<String> found = <String>{};
    final List<(int, int)> spans = <(int, int)>[];
    for (final _Token token in item._words) {
      for (final String w in words) {
        if (_wordMatches(w, token.word)) {
          found.add(w);
          spans.add((token.start, token.end));
          break;
        }
      }
    }
    final double? similarity = similarities?[item.note.key];
    if (found.isEmpty) {
      if (similarity != null && similarity >= meaningFloor) {
        byMeaning.add(
          NoteMatch(
            note: item.note,
            tier: MatchTier.meaning,
            highlights: const <(int, int)>[],
            share: 0,
            similarity: similarity,
          ),
        );
      }
      continue;
    }
    final int at = phrase.isEmpty ? -1 : item.folded.text.indexOf(phrase);
    if (at >= 0) spans.add((at, at + phrase.length));
    byWords.add(
      NoteMatch(
        note: item.note,
        tier: at >= 0
            ? MatchTier.phrase
            : found.length == words.length
            ? MatchTier.allWords
            : MatchTier.someWords,
        highlights: _originalSpans(item.folded, spans),
        share: found.length / words.length,
        similarity: similarity,
      ),
    );
  }
  byWords.sort((NoteMatch a, NoteMatch b) {
    final int tier = a.tier.index.compareTo(b.tier.index);
    if (tier != 0) return tier;
    final int share = b.share.compareTo(a.share);
    if (share != 0) return share;
    return b.note.at.compareTo(a.note.at);
  });
  byMeaning.sort((NoteMatch a, NoteMatch b) {
    final int closer = b.similarity!.compareTo(a.similarity!);
    return closer != 0 ? closer : b.note.at.compareTo(a.note.at);
  });
  return <NoteMatch>[...byWords, ...byMeaning.take(meaningShown)];
}

List<(int, int)> _originalSpans(FoldedText folded, List<(int, int)> spans) {
  final List<(int, int)> mapped = <(int, int)>[
    for (final (int s, int e) in spans) folded.original(s, e),
  ]..sort(((int, int) a, (int, int) b) => a.$1.compareTo(b.$1));
  final List<(int, int)> merged = <(int, int)>[];
  for (final (int s, int e) in mapped) {
    if (merged.isNotEmpty && s <= merged.last.$2) {
      merged.last = (merged.last.$1, max(merged.last.$2, e));
    } else {
      merged.add((s, e));
    }
  }
  return merged;
}

double cosineSimilarity(Float32List a, Float32List b) {
  if (a.length != b.length) return 0;
  double dot = 0, na = 0, nb = 0;
  for (int i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
    na += a[i] * a[i];
    nb += b[i] * b[i];
  }
  return na == 0 || nb == 0 ? 0 : dot / (sqrt(na) * sqrt(nb));
}
