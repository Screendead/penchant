import 'dart:convert';

import 'package:tracker/ask/ask_answer.dart';
import 'package:tracker/ask/ask_journal.dart';
import 'package:tracker/ask/journal_db.dart';
import 'package:tracker/data/trigger_tree.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/letter/letter_checks.dart';

/// Limits shared with functions/analyst.js (functions/analyst_fixture.json
/// holds both sides' copy, which a test on each side compares).
abstract final class AnalystLimits {
  /// Calls to the model per investigation, the last of which must conclude.
  static const int steps = 6;
  static const int queries = 3;
  static const int rows = 50;

  /// A result's JSON, in UTF-16 units, as sent; the server refuses past 8192.
  static const int resultChars = 8000;
  static const int columns = 20;
  static const int cell = 200;
  static const int headline = 200;
  static const int body = 1500;
}

/// Words that claim one thing produces another. Whether it does is for
/// Insights, which tests it; the analyst only describes counts.
const List<String> analystCausalTerms = <String>[
  'because', 'cause', 'causes', 'caused', 'causing', 'due to', 'leads to', //
  'lead to', 'led to', 'leading to', 'results in', 'resulted in',
  'result of', 'as a result', 'drives', 'drove', 'driven', 'triggers',
  'triggered', 'sets off', 'set off', 'makes you', 'made you', 'effect',
  'effects', 'affect', 'affects', 'affected', 'influence', 'influenced',
  'responsible for', 'explains', 'explained by', 'therefore', 'thanks to',
];

String _escape(String s) =>
    s.replaceAllMapped(RegExp(r'[.*+?^${}()|[\]\\]'), (Match m) => '\\${m[0]}');

final RegExp _causal = RegExp(
  "(^|[^a-z'])(${analystCausalTerms.map(_escape).join('|')})(?=\$|[^a-z'])",
  caseSensitive: false,
);

/// A cell as sent and as the numeral check reads it: an integer in digits, a
/// real rounded to 2 places with trailing zeros dropped, text cut to
/// [AnalystLimits.cell]; null for null and anything not finite.
String? cellText(Object? value) {
  switch (value) {
    case int v:
      return '$v';
    case double v when v.isFinite:
      String s = v.toStringAsFixed(2);
      if (s.contains('.')) {
        s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
      }
      return s == '-0' ? '0' : s;
    case String v:
      return v.length > AnalystLimits.cell
          ? v.substring(0, AnalystLimits.cell)
          : v;
    default:
      return null;
  }
}

/// What one statement's run sends: its rows as text, or why it did not run.
sealed class SentResult {
  const SentResult();

  Map<String, Object?> toJson();
}

class SentRows extends SentResult {
  const SentRows(this.columns, this.rows, {required this.truncated});

  final List<String> columns;
  final List<List<String?>> rows;
  final bool truncated;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'columns': columns,
    'rows': rows,
    'truncated': truncated,
  };
}

class SentRefusal extends SentResult {
  const SentRefusal(this.refusal);

  final AskRefusal refusal;

  @override
  Map<String, Object?> toJson() => <String, Object?>{'refused': refusal.name};
}

/// [run] cut to what may leave: at most [AnalystLimits.columns] columns and
/// [AnalystLimits.rows] rows, then rows dropped from the end until its JSON
/// is within [AnalystLimits.resultChars].
SentResult cutResult(AskRun run) {
  switch (run) {
    case AskRefused(:final AskRefusal refusal):
      return SentRefusal(refusal);
    case AskRan(:final AskRows rows, :final bool truncated):
      final int width = rows.columns.length.clamp(0, AnalystLimits.columns);
      final List<String> columns = <String>[
        for (final String c in rows.columns.take(width))
          c.length > 64 ? c.substring(0, 64) : c,
      ];
      final List<List<String?>> kept = <List<String?>>[
        for (final List<Object?> row in rows.rows.take(AnalystLimits.rows))
          <String?>[for (final Object? v in row.take(width)) cellText(v)],
      ];
      bool cut = truncated || rows.rows.length > AnalystLimits.rows;
      SentRows sent() => SentRows(columns, kept, truncated: cut);
      while (kept.isNotEmpty &&
          jsonEncode(sent().toJson()).length > AnalystLimits.resultChars) {
        kept.removeLast();
        cut = true;
      }
      if (jsonEncode(sent().toJson()).length > AnalystLimits.resultChars) {
        return const SentRefusal(AskRefusal.tooBig);
      }
      return sent();
  }
}

/// One step's statements, what each found on this device, and what of that
/// was sent.
class InvestigationRound {
  const InvestigationRound(this.queries, this.runs, this.sent);

  final List<AskCard> queries;
  final List<AskRun> runs;
  final List<SentResult> sent;
}

/// The model's answer to one step.
sealed class InvestigationStep {
  const InvestigationStep();
}

class MoreQueries extends InvestigationStep {
  const MoreQueries(this.queries);

  final List<AskCard> queries;
}

class Finding extends InvestigationStep {
  const Finding(this.headline, this.body, this.restsOn);

  final String headline;
  final String body;

  /// Statement numbers, from 1 across the whole investigation in order.
  final List<int> restsOn;
}

bool _keysExactly(Map<Object?, Object?> map, Set<String> keys) =>
    map.length == keys.length && map.keys.every(keys.contains);

String? _text(Object? v, int max) =>
    v is String && v.trim().isNotEmpty && v.length <= max ? v.trim() : null;

/// The server's `step`, or null unless it fits exactly: `queries` with 1 to 3
/// cards and an empty finding, or `finding` with no cards, a headline, a body
/// and 1 or more statement numbers.
InvestigationStep? parseStep(Object? value) {
  if (value is! Map ||
      !_keysExactly(value, <String>{'kind', 'queries', 'finding'})) {
    return null;
  }
  final Object? rawQueries = value['queries'];
  final Object? finding = value['finding'];
  if (rawQueries is! List ||
      finding is! Map ||
      !_keysExactly(finding, <String>{'headline', 'body', 'rests_on'})) {
    return null;
  }
  final List<AskCard> queries = <AskCard>[];
  for (final Object? raw in rawQueries) {
    final AskCard? card = parseAskCard(raw);
    if (card == null) return null;
    queries.add(card);
  }
  final Object? restsOn = finding['rests_on'];
  if (restsOn is! List || restsOn.any((Object? n) => n is! int)) return null;
  switch (value['kind']) {
    case 'queries':
      final bool empty =
          finding['headline'] == '' && finding['body'] == '' && restsOn.isEmpty;
      return empty &&
              queries.isNotEmpty &&
              queries.length <= AnalystLimits.queries
          ? MoreQueries(queries)
          : null;
    case 'finding':
      final String? headline = _text(
        finding['headline'],
        AnalystLimits.headline,
      );
      final String? body = _text(finding['body'], AnalystLimits.body);
      if (queries.isNotEmpty ||
          headline == null ||
          body == null ||
          restsOn.isEmpty) {
        return null;
      }
      return Finding(headline, body, restsOn.cast<int>());
    default:
      return null;
  }
}

/// The labels a cell may hold that no query can make up: every starter-tree
/// label, "Own words", and own-words stand-ins.
bool _knownLabel(String cell) =>
    _treeLabels.contains(cell) || _ownWords.hasMatch(cell);

final Set<String> _treeLabels = <String>{
  'Own words',
  for (final String path in triggerPaths()) ...triggerLabels(path)!,
};
final RegExp _ownWords = RegExp(r'^own words \d+$');
final RegExp _wholeHour = RegExp(r'^\d{1,2}$');

/// What a finding may use besides its own words: the numerals of every cell
/// sent, and as phrases the habit names, unit words and the cells that are
/// tag labels. Other text cells are not phrases: a query's own literal could
/// otherwise carry any prose past the checks. Hours, each cell that is wholly
/// an integer 0 to 23, which a clock time H:00 may name; counts, each cell
/// that is wholly an integer 2 to 12 and each untruncated result's number of
/// rows and of distinct values in each column, which a count word two to
/// twelve may name; cells, every text cell, which a passage may quote whole
/// (its words still checked). The same as contextOf in functions/analyst.js.
LetterContext findingContext(
  List<InvestigationRound> rounds,
  List<({int id, Vice vice})> habits,
) {
  final Set<String> numerals = <String>{};
  final List<String> phrases = <String>[
    for (final ({int id, Vice vice}) h in habits) ...<String>[
      h.vice.name,
      h.vice.units.plural,
      h.vice.units.singular,
    ],
  ];
  final Set<int> hours = <int>{};
  final Set<int> counts = <int>{};
  final Set<String> cells = <String>{};
  for (final InvestigationRound r in rounds) {
    for (final SentResult s in r.sent) {
      if (s is! SentRows) continue;
      for (final List<String?> row in s.rows) {
        for (final String? cell in row) {
          if (cell == null) continue;
          numerals.addAll(numeralsIn(cell));
          if (_knownLabel(cell)) phrases.add(cell);
          cells.add(cell);
          if (_wholeHour.hasMatch(cell)) {
            final int value = int.parse(cell);
            if (value <= 23) hours.add(value);
            if (value >= 2 && value <= 12) counts.add(value);
          }
        }
      }
      if (s.truncated) continue;
      counts.add(s.rows.length);
      for (int i = 0; i < s.columns.length; i++) {
        counts.add(
          <String>{for (final List<String?> row in s.rows) ?row[i]}.length,
        );
      }
    }
  }
  return LetterContext.figures(
    numerals,
    phrases,
    hours: hours,
    counts: counts,
    cells: cells,
  );
}

/// Why [passage] cannot be shown, or `ok`: the letter's rules
/// ([checkPassage]: quotes, numerals, number words, its deny-list), then no
/// [analystCausalTerms] outside the phrases.
String checkAnalystPassage(String passage, LetterContext context) {
  final String letter = checkPassage(passage, context);
  if (letter != 'ok') return letter;
  String rest = passage;
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
  final Match? term = _causal.firstMatch(rest.replaceAll('’', "'"));
  return term == null ? 'ok' : 'cause:${term[2]!.toLowerCase()}';
}

/// Why [finding] cannot be shown beside [rounds], or `ok`: each statement it
/// rests on exists and ran, and its headline, body and every statement's
/// title and explanation (all are shown with it) pass [checkAnalystPassage] against what this
/// device itself sent.
String checkFinding(
  Finding finding,
  List<InvestigationRound> rounds,
  List<({int id, Vice vice})> habits,
) {
  final List<(AskCard, SentResult)> all = <(AskCard, SentResult)>[
    for (final InvestigationRound r in rounds)
      for (int i = 0; i < r.queries.length; i++) (r.queries[i], r.sent[i]),
  ];
  if (finding.restsOn.toSet().length != finding.restsOn.length) {
    return 'rests_on';
  }
  for (final int n in finding.restsOn) {
    if (n < 1 || n > all.length || all[n - 1].$2 is! SentRows) {
      return 'rests_on';
    }
  }
  final LetterContext context = findingContext(rounds, habits);
  for (final String text in <String>[
    finding.headline,
    finding.body,
    for (final (AskCard card, _) in all) ...<String>[card.title, card.explain],
  ]) {
    final String why = checkAnalystPassage(text, context);
    if (why != 'ok') return why;
  }
  return 'ok';
}

/// Everything one step sends. The only way anything of an investigation
/// leaves: Ask's request (question, today, weekday, habit numbers, names,
/// unit words, archived flags) and, per earlier step, its statements and
/// their [SentResult]s. Nothing here reads note text, which the figures-only
/// database does not hold.
Map<String, Object?> investigateRequest(
  String question, {
  required List<({int id, Vice vice})> habits,
  required DateTime today,
  required List<InvestigationRound> rounds,
}) => <String, Object?>{
  ...CallableAskJournal.request(question, habits: habits, today: today)
    ..remove('history'),
  'rounds': <Object?>[
    for (final InvestigationRound r in rounds)
      <String, Object?>{
        'queries': <Object?>[for (final AskCard c in r.queries) c.toJson()],
        'results': <Object?>[for (final SentResult s in r.sent) s.toJson()],
      },
  ],
};

/// Sends one step's request and reads the server's step.
abstract class Investigator {
  /// Throws [InvestigateFailed] when the server answered nothing usable, or
  /// the call's own error.
  Future<InvestigationStep> step(Map<String, Object?> request);
}

/// No step to take, for [reason]: the server's (`refusal`, `max_tokens`,
/// `unparsable`, `api_error`, `no_finding`, `checks`) or this device's
/// (`invalid`).
class InvestigateFailed implements Exception {
  const InvestigateFailed(this.reason);

  final String reason;

  @override
  String toString() => 'InvestigateFailed($reason)';
}

sealed class InvestigationOutcome {
  const InvestigationOutcome(this.rounds);

  final List<InvestigationRound> rounds;
}

class InvestigationShown extends InvestigationOutcome {
  const InvestigationShown(this.finding, super.rounds);

  final Finding finding;
}

/// The model concluded, but its finding broke a rule here: never shown.
class InvestigationWithheld extends InvestigationOutcome {
  const InvestigationWithheld(this.reason, super.rounds);

  final String reason;
}

class InvestigationFailed extends InvestigationOutcome {
  const InvestigationFailed(this.reason, super.rounds);

  final String reason;
}

/// Runs one investigation of [question] over [db], which must be figures
/// only: up to [AnalystLimits.steps] calls, each step's statements run here
/// and cut by [cutResult] before the next. [stillWanted] is asked before each
/// call (false when the page closed or the user changed); [onRound] after
/// each step's statements ran.
Future<InvestigationOutcome> runInvestigation({
  required Investigator investigator,
  required JournalDb db,
  required String question,
  required List<({int id, Vice vice})> habits,
  required DateTime today,
  bool Function()? stillWanted,
  void Function(List<InvestigationRound> rounds)? onRound,
}) async {
  if (!db.figuresOnly) throw ArgumentError.value(db, 'db', 'not figures only');
  final List<InvestigationRound> rounds = <InvestigationRound>[];
  for (int step = 1; step <= AnalystLimits.steps; step++) {
    if (!(stillWanted?.call() ?? true)) {
      return InvestigationFailed('stopped', rounds);
    }
    final InvestigationStep answer;
    try {
      answer = await investigator.step(
        investigateRequest(
          question,
          habits: habits,
          today: today,
          rounds: rounds,
        ),
      );
    } on InvestigateFailed catch (e) {
      // The server's own check of the finding refused it.
      return e.reason == 'checks'
          ? InvestigationWithheld(e.reason, rounds)
          : InvestigationFailed(e.reason, rounds);
    } catch (_) {
      return InvestigationFailed('call', rounds);
    }
    switch (answer) {
      case Finding():
        final String why = checkFinding(answer, rounds, habits);
        return why == 'ok'
            ? InvestigationShown(answer, rounds)
            : InvestigationWithheld(why, rounds);
      case MoreQueries(:final List<AskCard> queries):
        if (step == AnalystLimits.steps) {
          return InvestigationFailed('no_finding', rounds);
        }
        final List<AskRun> runs = <AskRun>[
          for (final AskCard c in queries) db.run(c.sql),
        ];
        rounds.add(
          InvestigationRound(queries, runs, runs.map(cutResult).toList()),
        );
        onRound?.call(List<InvestigationRound>.unmodifiable(rounds));
    }
  }
  return InvestigationFailed('no_finding', rounds);
}
