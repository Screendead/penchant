// The checks a letter passes on this device before it is shown, the same as
// functions/letter.js checkPassage and checkLetter (test/letter_checks_test.dart
// runs both over functions/letter_fixture.json). The server has checked it
// already; nothing it sends is shown unchecked.

/// The follow-up question's deny-list (functions/note_reader.js) less its
/// words about amounts and counts and `suggest`, `change`, `instead`, `why`,
/// plus the letter's own: the exact list functions/letter.js builds.
const List<String> letterDeniedTerms = <String>[
  'should', 'shouldn\'t', 'need to', 'needs to', 'have to', 'must', 'try', //
  'consider', 'maybe you', 'might want', 'recommend', 'advice', 'help',
  'support', 'encourage', 'good', 'bad', 'better', 'worse', 'wrong', 'okay',
  'ok', 'alright', 'fine', 'normal', 'proud', 'well done', 'great',
  'congratulations', 'guilt', 'guilty', 'shame', 'ashamed', 'regret',
  'mistake', 'excuse', 'problem', 'problems', 'issue', 'addict', 'addicted',
  'addiction', 'addictive', 'dependence', 'dependent', 'dependency',
  'alcoholic', 'alcoholism', 'abuse', 'habit-forming', 'disorder', 'relapse',
  'relapsed', 'recovery', 'sober', 'sobriety', 'clean', 'craving', 'cravings',
  'healthy', 'unhealthy', 'health', 'risk', 'risky', 'harm', 'harmful',
  'damage', 'danger', 'dangerous', 'worry', 'worried', 'worrying', 'concern',
  'concerned', 'concerning', 'too much', 'too many', 'excessive', 'binge',
  'therapy', 'therapist', 'doctor', 'treatment', 'will you', 'would you',
  'going to', 'next time', 'tomorrow', 'future', 'from now on', 'plan to',
  'stop', 'stopping', 'quit', 'quitting', 'cut down', 'cut back', 'cutting',
  'reduce', 'avoid', 'goal', 'goals', 'ai', 'claude', 'assistant', 'chatbot',
  'language model', 'as a model', 'anthropic', 'progress', 'success',
  'successful', 'failure', 'fail', 'failed', 'failing', 'struggle',
  'struggling', 'journey', 'willpower', 'discipline', 'weak', 'weakness',
  'improve', 'improved', 'improvement', 'improving', 'reducing', 'moderation',
  'diagnosis', 'depression', 'depressed', 'too little', 'ought', 'you can do',
];

/// Counts in words: the model counting for itself. "one" and "once" stay.
const List<String> letterNumberWords = <String>[
  'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine', 'ten', //
  'eleven', 'twelve', 'thirteen', 'fourteen', 'fifteen', 'sixteen',
  'seventeen', 'eighteen', 'nineteen', 'twenty', 'thirty', 'forty', 'fifty',
  'sixty', 'seventy', 'eighty', 'ninety', 'hundred', 'hundreds', 'thousand',
  'thousands', 'dozen', 'dozens', 'twice', 'thrice', 'couple',
];

const int minLetterSections = 3;
const int maxLetterSections = 5;
const int maxLetterToTest = 3;
const int minShownSections = 2;
const int _maxHeading = 80;
const int _maxBody = 1500;
const int _maxTitle = 120;
const int _maxWhy = 600;

String _escape(String s) =>
    s.replaceAllMapped(RegExp(r'[.*+?^${}()|[\]\\]'), (Match m) => '\\${m[0]}');

RegExp _terms(List<String> terms) => RegExp(
  "(^|[^a-z'])(${terms.map(_escape).join('|')})(?=\$|[^a-z'])",
  caseSensitive: false,
);

final RegExp _denied = _terms(letterDeniedTerms);
final RegExp _numberWord = _terms(letterNumberWords);
final RegExp _numeral = RegExp(r'\d+(?:[.:]\d+)*');
final RegExp _clockHour = RegExp(r'^(\d{1,2}):00$');

/// What a count word allowed by [LetterContext.counts] stands for, from 2.
const List<String> _countWords = <String>[
  'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine', 'ten', //
  'eleven', 'twelve',
];

/// The runs of digits [checkPassage] compares, with any '.' or ':' between.
Iterable<String> numeralsIn(String s) =>
    _numeral.allMatches(s).map((Match m) => m[0]!);

final RegExp _nonAsciiNumeral = RegExp(r'(?![0-9])\p{N}', unicode: true);
final RegExp _quoteSpan = RegExp(r'“([^“”]*)”|"([^"]*)"');
final RegExp _quoteMark = RegExp(r'[“”"]');

/// What a passage may use besides its own words, from the request sent.
class LetterContext {
  LetterContext._(this.numerals, this.notes, this.phrases)
    : hours = const <int>{},
      counts = const <int>{},
      cells = const <String>{};

  /// The analyst's: numerals from the results it saw, no notes to quote,
  /// [phrases] longest first, and the [hours], [counts] and [cells] it was
  /// shown.
  LetterContext.figures(
    this.numerals,
    Iterable<String> phrases, {
    this.hours = const <int>{},
    this.counts = const <int>{},
    this.cells = const <String>{},
  }) : notes = const <String>[],
       phrases =
           phrases.where((String p) => p.trim().isNotEmpty).toSet().toList()
             ..sort((String a, String b) => b.length.compareTo(a.length));

  /// From a payload's JSON (`LetterPayload.json`), as functions/letter.js
  /// contextOf reads its validated input.
  factory LetterContext.of(Map<String, Object?> json) {
    final Map<String, Object?> period = _map(json['period']);
    final Map<String, Object?> figures = _map(json['figures']);
    final List<String> numberSources = <String>[
      ?_str(period['from']),
      ?_str(period['to']),
    ];
    final List<String> labels = <String>[];
    for (final Map<String, Object?> h in _maps(figures['habits'])) {
      numberSources.addAll(<String>[
        ?_str(h['total']),
        ?_str(h['entries']),
        ?_str(h['days']),
      ]);
      labels.addAll(<String>[?_str(h['habit']), ?_str(h['unit'])]);
    }
    for (final Map<String, Object?> m in _maps(figures['months'])) {
      numberSources.addAll(<String>[?_str(m['month'])]);
      for (final Map<String, Object?> h in _maps(m['habits'])) {
        numberSources.addAll(<String>[
          ?_str(h['total']),
          ?_str(h['entries']),
          ?_str(h['days']),
        ]);
      }
    }
    final Map<String, Object?> noteCounts = _map(figures['notes']);
    numberSources.addAll(<String>[
      ?_str(noteCounts['entryNotes']),
      ?_str(noteCounts['dayNotes']),
      ?_str(noteCounts['followUps']),
    ]);
    for (final Map<String, Object?> t in _maps(figures['tags'])) {
      numberSources.addAll(<String>[?_str(t['count'])]);
      labels.addAll(<String>[?_str(t['tag'])]);
    }
    final List<String> notes = <String>[];
    for (final Map<String, Object?> e in _maps(json['entries'])) {
      labels.addAll(<String>[?_str(e['habit']), ?_str(e['unit'])]);
      labels.addAll(_strs(e['tags']));
      notes.addAll(<String>[?_str(e['note'])]);
      notes.addAll(<String>[?_str(_map(e['followUp'])['answer'])]);
    }
    for (final Map<String, Object?> n in _maps(json['dayNotes'])) {
      labels.addAll(_strs(n['tags']));
      notes.addAll(<String>[?_str(n['text'])]);
      notes.addAll(<String>[?_str(_map(n['followUp'])['answer'])]);
    }
    final List<String> phrases =
        <String>{
            for (final String l in labels) ...<String>[l, ...l.split(' › ')],
          }.where((String p) => p.trim().isNotEmpty).toList()
          ..sort((String a, String b) => b.length.compareTo(a.length));
    numberSources.addAll(phrases);
    return LetterContext._(
      <String>{
        for (final String s in numberSources)
          for (final Match m in _numeral.allMatches(s)) m[0]!,
      },
      notes,
      phrases,
    );
  }

  final Set<String> numerals;
  final List<String> notes;
  final List<String> phrases;

  /// Hours a clock time H:00 or HH:00 may name though not itself a numeral.
  final Set<int> hours;

  /// Values a count word two to twelve may name.
  final Set<int> counts;

  /// Texts a passage may quote whole; their words are still checked.
  final Set<String> cells;

  bool quotes(String text) => notes.any((String n) => n.contains(text));
}

Map<String, Object?> _map(Object? v) =>
    v is Map ? v.cast<String, Object?>() : const <String, Object?>{};

Iterable<Map<String, Object?>> _maps(Object? v) =>
    v is List ? v.whereType<Map>().map(_map) : const <Map<String, Object?>>[];

String? _str(Object? v) => v is String ? v : null;

Iterable<String> _strs(Object? v) =>
    v is List ? v.whereType<String>() : const <String>[];

/// Why [passage] cannot be shown beside [context], or `ok`; the rules of
/// functions/letter.js checkPassage, in the same order.
String checkPassage(String passage, LetterContext context) {
  String? bad;
  String rest = passage.replaceAllMapped(_quoteSpan, (Match m) {
    final String quoted = m[1] ?? m[2]!;
    final bool known =
        quoted.trim().isNotEmpty &&
        (context.quotes(quoted) || context.phrases.contains(quoted));
    if (known) return ' ';
    // A whole cell may be quoted, but it is still read as the passage's own
    // words: a query's literal can fill a cell with anything.
    if (quoted.trim().isNotEmpty && context.cells.contains(quoted)) {
      return ' $quoted ';
    }
    bad ??= 'quote';
    return ' ';
  });
  if (bad != null) return bad!;
  if (_quoteMark.hasMatch(rest)) return 'quote';
  for (final String phrase in context.phrases) {
    rest = rest.replaceAll(
      RegExp(
        '(?<![\\p{L}\\p{N}])${_escape(phrase)}(?![\\p{L}\\p{N}])',
        caseSensitive: false,
        unicode: true,
      ),
      ' ',
    );
  }
  if (_nonAsciiNumeral.hasMatch(rest)) return 'number';
  for (final Match m in _numeral.allMatches(rest)) {
    final String n = m[0]!;
    if (context.numerals.contains(n)) continue;
    final Match? clock = _clockHour.firstMatch(n);
    if (clock != null && context.hours.contains(int.parse(clock[1]!))) continue;
    return 'number:$n';
  }
  final String normalised = rest.replaceAll('’', "'");
  for (final Match word in _numberWord.allMatches(normalised)) {
    final String w = word[2]!.toLowerCase();
    final int value = _countWords.indexOf(w) + 2;
    if (value >= 2 && context.counts.contains(value)) continue;
    return 'number_word:$w';
  }
  final Match? term = _denied.firstMatch(normalised);
  if (term != null) return 'term:${term[2]!.toLowerCase()}';
  return 'ok';
}

class LetterSection {
  const LetterSection(this.heading, this.body);

  final String heading;
  final String body;

  Map<String, Object?> toJson() => <String, Object?>{
    'heading': heading,
    'body': body,
  };
}

class LetterTest {
  const LetterTest(this.title, this.why);

  final String title;
  final String why;

  Map<String, Object?> toJson() => <String, Object?>{
    'title': title,
    'why': why,
  };
}

/// A letter that passed: its surviving sections and things worth testing,
/// and how many passages were withheld.
class CheckedLetter {
  const CheckedLetter({
    required this.sections,
    required this.toTest,
    required this.withheld,
  });

  final List<LetterSection> sections;
  final List<LetterTest> toTest;
  final int withheld;
}

String? _passage(Object? v, int max) =>
    v is String && v.trim().isNotEmpty && v.length <= max ? v.trim() : null;

/// [answer] (the server's `letter`, or the model's reply) checked against
/// [json], the payload sent. A section or suggestion breaking a rule is
/// withheld and counted, with any the server withheld ([answer]'s
/// `withheld`). Null when the reply is malformed, has not 3 to 5 sections or
/// keeps fewer than 2.
CheckedLetter? checkLetter(Object? answer, Map<String, Object?> json) {
  if (answer is! Map) return null;
  final Object? sections = answer['sections'];
  final Object? toTest = answer['toTest'];
  final Object? before = answer['withheld'];
  if (sections is! List || toTest is! List) return null;
  final int earlier = before is int && before >= 0 ? before : 0;
  // The server sends only what survived its check, so fewer than 3 is fine
  // when it says it withheld the rest.
  if (sections.length + earlier < minLetterSections ||
      sections.length > maxLetterSections) {
    return null;
  }
  final LetterContext context = LetterContext.of(json);
  int withheld = earlier;
  bool passes(List<String?> parts) {
    final bool ok =
        !parts.contains(null) &&
        parts.every((String? p) => checkPassage(p!, context) == 'ok');
    if (!ok) withheld++;
    return ok;
  }

  final List<LetterSection> kept = <LetterSection>[];
  for (final Object? s in sections) {
    final Map<String, Object?> m = _map(s);
    final String? heading = _passage(m['heading'], _maxHeading);
    final String? body = _passage(m['body'], _maxBody);
    if (passes(<String?>[heading, body])) {
      kept.add(LetterSection(heading!, body!));
    }
  }
  final List<LetterTest> tests = <LetterTest>[];
  for (final Object? t in toTest.take(maxLetterToTest)) {
    final Map<String, Object?> m = _map(t);
    final String? title = _passage(m['title'], _maxTitle);
    final String? why = _passage(m['why'], _maxWhy);
    if (passes(<String?>[title, why])) tests.add(LetterTest(title!, why!));
  }
  if (kept.length < minShownSections) return null;
  return CheckedLetter(sections: kept, toTest: tests, withheld: withheld);
}
