import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/analyst/investigation.dart';
import 'package:tracker/ask/ask_answer.dart';
import 'package:tracker/ask/ask_page.dart';
import 'package:tracker/ask/journal_db.dart';
import 'package:tracker/claude/claude_working.dart';
import 'package:tracker/design/dial_theme.dart';
import 'package:tracker/design/habit_mark.dart';
import 'package:tracker/design/tokens.dart';
import 'package:tracker/providers/user_provider.dart';

/// One investigation this session: its question, the steps run so far and,
/// once over, how it ended.
class Investigation {
  const Investigation({
    required this.id,
    required this.question,
    this.rounds = const <InvestigationRound>[],
    this.outcome,
  });

  final int id;
  final String question;
  final List<InvestigationRound> rounds;
  final InvestigationOutcome? outcome;
}

/// This session's investigations, oldest first, in memory only: forgotten on
/// "New question", and when the signed-in user changes.
final investigationSessionProvider =
    NotifierProvider<InvestigationSession, List<Investigation>>(
      InvestigationSession.new,
    );

class InvestigationSession extends Notifier<List<Investigation>> {
  int _next = 0;

  @override
  List<Investigation> build() {
    ref.watch(userProvider.select((AsyncValue<User?> user) => user.value?.uid));
    return const <Investigation>[];
  }

  int start(String question) {
    final int id = _next++;
    state = <Investigation>[
      ...state,
      Investigation(id: id, question: question),
    ];
    return id;
  }

  void _replace(int id, Investigation Function(Investigation) change) =>
      state = <Investigation>[
        for (final Investigation i in state) i.id == id ? change(i) : i,
      ];

  void progress(int id, List<InvestigationRound> rounds) => _replace(
    id,
    (Investigation i) =>
        Investigation(id: i.id, question: i.question, rounds: rounds),
  );

  void settle(int id, InvestigationOutcome outcome) => _replace(
    id,
    (Investigation i) => Investigation(
      id: i.id,
      question: i.question,
      rounds: outcome.rounds,
      outcome: outcome,
    ),
  );

  void clear() => state = const <Investigation>[];
}

/// An investigation on the Ask page: its progress, then the checked finding
/// with the queries it rests on (each as Ask draws it, from this device's own
/// run), or a plain message when it was withheld or failed.
class InvestigationView extends StatefulWidget {
  const InvestigationView({
    super.key,
    required this.investigation,
    required this.marksByName,
    required this.onOpenDay,
  });

  final Investigation investigation;
  final Map<String, HabitMark> marksByName;
  final ValueChanged<DateTime> onOpenDay;

  static const String label = 'Investigation';
  static const String reading =
      'Claude’s reading of figures counted on this device, not a finding';
  static const String insights =
      'Whether one thing sets off another is a question for Insights, which '
      'tests it.';
  static const String openInsights = 'Test it in Insights';
  static const String withheld =
      'Claude’s account didn’t pass Penchant’s checks, so it isn’t shown.';
  static const String showAll = 'Show every query';
  static const String hideAll = 'Hide the other queries';

  static String working(int step, int queries) =>
      'Investigating… step $step of at most ${AnalystLimits.steps}.'
      '${queries == 0 ? '' : ' Queries run on this device so far: $queries.'}';

  static String failed(String reason) => switch (reason) {
    'daily_cap' => 'That’s enough investigations for today.',
    'no_finding' =>
      'Claude didn’t reach an account within ${AnalystLimits.steps} steps.',
    'stopped' => 'The investigation stopped.',
    _ => 'Couldn’t investigate just now.',
  };

  @override
  State<InvestigationView> createState() => _InvestigationViewState();
}

class _InvestigationViewState extends State<InvestigationView> {
  bool _showAll = false;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final DialColors colors = DialColors.of(context);
    final TextStyle body = DialTypeScale.body.copyWith(color: scheme.onSurface);
    final TextStyle small = DialTypeScale.label.copyWith(
      fontSize: 11,
      letterSpacing: 0.9,
      color: colors.muted,
    );
    final Investigation inv = widget.investigation;
    final List<(AskCard, AskRun)> all = <(AskCard, AskRun)>[
      for (final InvestigationRound r in inv.rounds)
        for (int i = 0; i < r.queries.length; i++) (r.queries[i], r.runs[i]),
    ];
    final InvestigationOutcome? outcome = inv.outcome;
    final List<int> restsOn = outcome is InvestigationShown
        ? outcome.finding.restsOn
        : const <int>[];

    Widget cardOf(int n) => Padding(
      padding: const EdgeInsets.only(top: 8),
      child: AskCardView(
        card: all[n - 1].$1,
        run: all[n - 1].$2,
        readFailed: false,
        marksByName: widget.marksByName,
        onOpenDay: widget.onOpenDay,
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        ClaudeWorkingResult(
          tag: ('investigate', inv.id),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              border: Border.all(color: colors.line),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(InvestigationView.label.toUpperCase(), style: small),
                  const SizedBox(height: 4),
                  Text(
                    inv.question,
                    style: DialTypeScale.body.copyWith(
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 10),
                  ...switch (outcome) {
                    null => <Widget>[
                      ClaudeWorkingCard(
                        status: InvestigationView.working(
                          inv.rounds.length + 1,
                          all.length,
                        ),
                      ),
                    ],
                    InvestigationShown(:final Finding finding) => <Widget>[
                      Text(
                        finding.headline,
                        style: DialTypeScale.body.copyWith(
                          fontWeight: FontWeight.w700,
                          color: scheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(finding.body, style: body),
                      const SizedBox(height: 10),
                      Text(
                        InvestigationView.reading.toUpperCase(),
                        style: small,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        InvestigationView.insights,
                        style: DialTypeScale.bodyS.copyWith(
                          color: colors.muted,
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          onPressed: () =>
                              Navigator.of(context).pushNamed('/insights'),
                          child: const Text(InvestigationView.openInsights),
                        ),
                      ),
                    ],
                    InvestigationWithheld() => <Widget>[
                      Text(InvestigationView.withheld, style: body),
                    ],
                    InvestigationFailed(:final String reason) => <Widget>[
                      Text(InvestigationView.failed(reason), style: body),
                    ],
                  },
                ],
              ),
            ),
          ),
        ),
        for (final int n in restsOn) cardOf(n),
        // Only a finding that passed shows its queries: their titles and
        // explanations passed the same checks with it.
        if (outcome is InvestigationShown &&
            all.length > restsOn.length) ...<Widget>[
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => setState(() => _showAll = !_showAll),
              child: Text(
                _showAll
                    ? InvestigationView.hideAll
                    : InvestigationView.showAll,
              ),
            ),
          ),
          if (_showAll)
            for (int n = 1; n <= all.length; n++)
              if (!restsOn.contains(n)) cardOf(n),
        ],
      ],
    );
  }
}
