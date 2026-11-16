import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/analyst/analyst_setting.dart';
import 'package:tracker/analyst/investigation.dart';
import 'package:tracker/analyst/investigation_view.dart';
import 'package:tracker/ask/ask_answer.dart';
import 'package:tracker/ask/ask_chart.dart';
import 'package:tracker/ask/ask_journal.dart';
import 'package:tracker/ask/journal_db.dart';
import 'package:tracker/claude/claude_working.dart';
import 'package:tracker/data/day_note.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/design/dial_theme.dart';
import 'package:tracker/design/habit_mark.dart';
import 'package:tracker/design/tokens.dart';
import 'package:tracker/insights/insights_report.dart';
import 'package:tracker/providers/day_note_provider.dart';
import 'package:tracker/providers/show_day_provider.dart';
import 'package:tracker/providers/today_provider.dart';
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/providers/vice_activity_day_provider.dart';
import 'package:tracker/providers/vice_list_provider.dart';
import 'package:tracker/widgets/dial_page.dart';

/// A question asked this session, with the server's answer once it comes.
class AskedQuestion {
  const AskedQuestion({
    required this.id,
    required this.question,
    this.answer,
    this.failed = false,
  });

  final int id;
  final String question;
  final AskAnswer? answer;
  final bool failed;

  bool get pending => answer == null && !failed;
}

/// This session's questions, oldest first, in memory only: forgotten on "New
/// question", and when the signed-in user changes.
final askSessionProvider = NotifierProvider<AskSession, List<AskedQuestion>>(
  AskSession.new,
);

/// The turns a follow-up sends: the answered ones of [asked], oldest first.
List<AskTurn> askHistory(List<AskedQuestion> asked) => <AskTurn>[
  for (final AskedQuestion q in asked)
    if (q.answer != null) AskTurn(q.question, q.answer!),
];

class AskSession extends Notifier<List<AskedQuestion>> {
  int _next = 0;

  @override
  List<AskedQuestion> build() {
    ref.watch(userProvider.select((AsyncValue<User?> user) => user.value?.uid));
    return const <AskedQuestion>[];
  }

  int start(String question) {
    final int id = _next++;
    state = <AskedQuestion>[
      ...state,
      AskedQuestion(id: id, question: question),
    ];
    return id;
  }

  void settle(int id, AskAnswer? answer) {
    state = <AskedQuestion>[
      for (final AskedQuestion q in state)
        q.id == id
            ? AskedQuestion(
                id: q.id,
                question: q.question,
                answer: answer,
                failed: answer == null,
              )
            : q,
    ];
  }

  /// Forgets question [id], whose answer is no longer wanted.
  void drop(int id) => state = <AskedQuestion>[
    for (final AskedQuestion q in state)
      if (q.id != id) q,
  ];

  void clear() => state = const <AskedQuestion>[];
}

class AskPage extends ConsumerStatefulWidget {
  const AskPage({super.key});

  static const String route = '/ask';
  static const String title = 'Ask your journal';
  static const String hint = 'When was my last week without wine?';
  static const String followUpHint = 'Ask a follow-up';
  static const String off =
      'Asking is off. Turn on “Ask your journal” in Settings to ask a '
      'question about your habits.';
  static const String ask = 'Ask';
  static const String newQuestion = 'New question';
  static const String working = 'Reading the question…';
  static const String counting = 'Counting…';
  static const String failed =
      'Couldn’t read the question just now. Nothing was counted.';
  static const String readFailed = 'Couldn’t read your journal on this device.';
  static const String couldNotRun = 'Penchant couldn’t run that.';
  static const String showQuery = 'Show query';
  static const String hideQuery = 'Hide query';
  static const String firstRows = 'Showing the first 500 rows.';
  static const String onDevice = 'Counted on this device';
  static const String insights =
      'That is a “why”, which Insights answers by comparison, and only when '
      'the numbers hold up.';
  static const String openInsights = 'Open it in Insights';
  static const String cannot = 'Penchant can’t answer that yet.';
  static const String investigate = 'Investigate with Claude';
  static const String investigateTyped = 'Investigate this question';
  static const String writingQuery = 'Claude is writing a query';
  static const String writingQueries = 'Claude is writing queries';
  static const String readingResults = 'Claude is reading the results';
  static const String sentQuestion =
      'Sent your question and your habits’ names';

  static String ranQueries(int n) => n == 1
      ? 'Ran 1 query on this phone and sent back what it found'
      : 'Ran $n queries on this phone and sent back what they found';

  static String cannotDetail(AskReason reason) => switch (reason) {
    AskReason.notAboutJournal => 'It answers questions about your habits.',
    AskReason.unknownHabit => 'That doesn’t match one of your habits.',
    AskReason.notSupported => 'That is outside what it can count so far.',
    AskReason.unclear || AskReason.none => 'Try asking another way.',
  };

  @override
  ConsumerState<AskPage> createState() => _AskPageState();
}

class _AskPageState extends ConsumerState<AskPage> {
  final TextEditingController _controller = TextEditingController();
  final GlobalKey _fieldKey = GlobalKey();

  JournalDb? _db;
  Object? _builtFrom;
  Object? _failedFrom;
  final Map<(int, int), AskRun> _runs = <(int, int), AskRun>{};

  /// Investigations this page is running; any other still pending was left
  /// behind by a closed page and has stopped.
  final Set<int> _investigating = <int>{};

  @override
  void initState() {
    super.initState();
    ref.listenManual<String?>(
      userProvider.select((AsyncValue<User?> user) => user.value?.uid),
      (String? before, String? after) {
        if (before != after) _drop();
      },
    );
  }

  @override
  void dispose() {
    _drop();
    _controller.dispose();
    super.dispose();
  }

  void _drop() {
    _db?.close();
    _db = null;
    _builtFrom = null;
    _failedFrom = null;
    _runs.clear();
  }

  /// The database for this exact read of the journal, built once per read.
  JournalDb? _database(
    List<Vice> vices,
    List<ViceActivity> entries,
    List<DayNote> notes,
    DateTime today,
  ) {
    final Object key = (vices, entries, notes, today);
    if (_db != null && _builtFrom == key) return _db;
    // A build that failed is not tried again for the same read.
    if (_failedFrom == key) return null;
    _drop();
    try {
      _db = JournalDb.build(
        vices: vices,
        entries: entries,
        notes: notes,
        today: today,
      );
    } catch (_) {
      // Not reported: nothing about the journal goes into a report.
      _failedFrom = key;
      return null;
    }
    _builtFrom = key;
    return _db;
  }

  Future<void> _ask() async {
    final AskJournal? service = ref.read(askJournalProvider);
    final List<Vice>? vices = ref.read(viceListProvider).value;
    final String question = _controller.text.trim();
    if (service == null || vices == null || question.isEmpty) return;
    final List<({int id, Vice vice})> sent = numberedHabits(
      vices,
    ).take(askHabits(vices).length).toList();
    final DateTime today = ref.read(todayProvider);
    final AskSession session = ref.read(askSessionProvider.notifier);
    final List<AskTurn> history = askHistory(ref.read(askSessionProvider));
    final int id = session.start(question);
    _controller.clear();
    final ClaudeWork work = ClaudeWork(
      subject: question,
      status: AskPage.writingQuery,
      detail: AskPage.sentQuestion,
    );
    bool stopped = false;
    final BuildContext? from = _fieldKey.currentContext;
    if (from != null) {
      unawaited(
        showClaudeWorking(
          from,
          work,
          resultTag: ('ask', id),
          onStop: () {
            stopped = true;
            session.drop(id);
            if (_controller.text.trim().isEmpty) _controller.text = question;
          },
        ),
      );
    }
    AskAnswer? answer;
    try {
      answer = await service.ask(
        question,
        habits: sent,
        today: today,
        history: history,
      );
    } catch (_) {
      // Not reported: a report would carry the question.
      answer = null;
    }
    if (stopped || !mounted) return;
    session.settle(id, answer);
    work.finish(answer == null ? ClaudeWorkEnd.failed : ClaudeWorkEnd.answered);
    if (answer == null && _controller.text.trim().isEmpty) {
      _controller.text = question;
    }
  }

  void _newQuestion() {
    ref.read(askSessionProvider.notifier).clear();
    ref.read(investigationSessionProvider.notifier).clear();
    _runs.clear();
  }

  /// One investigation of [question], only after the person says yes to
  /// what it sends, over its own figures-only database, closed at the end.
  Future<void> _investigate(String question) async {
    final String q = question.trim();
    if (q.isEmpty || ref.read(investigatorProvider) == null) return;
    if (!await confirmInvestigation(context) || !mounted) return;
    final Investigator? investigator = ref.read(investigatorProvider);
    final List<Vice>? vices = ref.read(viceListProvider).value;
    final DateTime today = ref.read(todayProvider);
    final List<ViceActivity>? entries = ref
        .read(viceActivityRangeProvider(insightsRange(today)))
        .value;
    final List<DayNote>? notes = ref.read(allDayNotesProvider).value;
    if (investigator == null ||
        vices == null ||
        entries == null ||
        notes == null) {
      return;
    }
    final String? uid = ref.read(userProvider).value?.uid;
    final InvestigationSession session = ref.read(
      investigationSessionProvider.notifier,
    );
    if (_controller.text.trim() == q) _controller.clear();
    final int id = session.start(q);
    _investigating.add(id);
    final ClaudeWork work = ClaudeWork(
      subject: q,
      steps: AnalystLimits.steps,
      showElapsed: true,
      status: AskPage.writingQueries,
      detail: AskPage.sentQuestion,
    );
    List<InvestigationRound> ran = const <InvestigationRound>[];
    bool stopped = false;
    final BuildContext? from = _fieldKey.currentContext;
    if (from != null && from.mounted) {
      unawaited(
        showClaudeWorking(
          from,
          work,
          resultTag: ('investigate', id),
          onStop: () {
            stopped = true;
            _investigating.remove(id);
            session.settle(id, InvestigationFailed('stopped', ran));
          },
        ),
      );
    }
    final JournalDb db;
    try {
      db = JournalDb.build(
        vices: vices,
        entries: entries,
        notes: notes,
        today: today,
        figuresOnly: true,
      );
    } catch (_) {
      // Not reported: nothing about the journal goes into a report.
      session.settle(
        id,
        const InvestigationFailed('read', <InvestigationRound>[]),
      );
      work.finish(ClaudeWorkEnd.failed);
      return;
    }
    try {
      final InvestigationOutcome outcome = await runInvestigation(
        investigator: investigator,
        db: db,
        question: q,
        habits: numberedHabits(vices).take(askHabits(vices).length).toList(),
        today: today,
        stillWanted: () =>
            !stopped && mounted && ref.read(userProvider).value?.uid == uid,
        onRound: (List<InvestigationRound> rounds) {
          ran = rounds;
          if (stopped || !mounted) return;
          session.progress(id, rounds);
          work.say(
            AskPage.readingResults,
            detail: AskPage.ranQueries(rounds.last.queries.length),
            stepsDone: rounds.length,
          );
        },
      );
      if (!stopped && mounted && ref.read(userProvider).value?.uid == uid) {
        session.settle(id, outcome);
      }
      work.finish(
        outcome is InvestigationShown
            ? ClaudeWorkEnd.answered
            : ClaudeWorkEnd.failed,
      );
    } finally {
      db.close();
      _investigating.remove(id);
    }
  }

  void _openDay(DateTime day) =>
      ref.read(pendingShowDayProvider.notifier).request(day);

  @override
  Widget build(BuildContext context) {
    final bool on = ref.watch(askJournalProvider) != null;
    final List<Vice>? vices = ref.watch(viceListProvider).value;
    final List<AskedQuestion> asked = ref.watch(askSessionProvider);
    final bool canInvestigate = on && ref.watch(investigatorProvider) != null;
    final List<Investigation> investigations = ref.watch(
      investigationSessionProvider,
    );
    final DateTime today = ref.watch(todayProvider);
    // One read of the journal while the page is open and asking is on: the
    // same one-time read and index as Insights.
    final AsyncValue<List<ViceActivity>>? entries = on
        ? ref.watch(viceActivityRangeProvider(insightsRange(today)))
        : null;
    final AsyncValue<List<DayNote>>? notes = on
        ? ref.watch(allDayNotesProvider)
        : null;
    JournalDb? db;
    bool buildFailed = false;
    if (vices != null && entries?.value != null && notes?.value != null) {
      db = _database(vices, entries!.value!, notes!.value!, today);
      buildFailed = db == null;
    }
    final bool readFailed =
        buildFailed ||
        (entries?.hasError ?? false) ||
        (notes?.hasError ?? false);
    final Map<String, HabitMark> marks = habitMarks(vices ?? const <Vice>[]);
    final Map<String, HabitMark> marksByName = <String, HabitMark>{
      for (final Vice v in vices ?? const <Vice>[])
        if (!v.locked && marks[v.id] != null) v.name: marks[v.id]!,
    };

    return DialPage(
      title: AskPage.title,
      children: <Widget>[
        const SizedBox(height: DialSpace.l),
        if (!on)
          const _Note(AskPage.off)
        else ...<Widget>[
          _QuestionField(
            key: _fieldKey,
            controller: _controller,
            enabled: vices != null,
            hint: asked.isEmpty ? AskPage.hint : AskPage.followUpHint,
            onAsk: _ask,
          ),
          if (asked.isNotEmpty || investigations.isNotEmpty || canInvestigate)
            Wrap(
              children: <Widget>[
                if (asked.isNotEmpty || investigations.isNotEmpty)
                  TextButton(
                    onPressed: _newQuestion,
                    child: const Text(AskPage.newQuestion),
                  ),
                if (canInvestigate)
                  TextButton(
                    onPressed: vices == null
                        ? null
                        : () => _investigate(_controller.text),
                    child: const Text(AskPage.investigateTyped),
                  ),
              ],
            ),
        ],
        for (final Investigation inv in investigations.reversed) ...<Widget>[
          const SizedBox(height: DialSpace.l),
          InvestigationView(
            investigation:
                inv.outcome == null && !_investigating.contains(inv.id)
                ? Investigation(
                    id: inv.id,
                    question: inv.question,
                    rounds: inv.rounds,
                    outcome: InvestigationFailed('stopped', inv.rounds),
                  )
                : inv,
            marksByName: marksByName,
            onOpenDay: _openDay,
          ),
        ],
        for (final AskedQuestion q in asked.reversed) ...<Widget>[
          const SizedBox(height: DialSpace.l),
          _QuestionPill(q.question),
          const SizedBox(height: 8),
          if (_answer(context, q, db, readFailed, marksByName, canInvestigate)
              case [
                final Widget first,
                ...final List<Widget> rest,
              ]) ...<Widget>[
            q.pending
                ? first
                : ClaudeWorkingResult(tag: ('ask', q.id), child: first),
            ...rest,
          ],
        ],
      ],
    );
  }

  List<Widget> _answer(
    BuildContext context,
    AskedQuestion q,
    JournalDb? db,
    bool readFailed,
    Map<String, HabitMark> marksByName,
    bool canInvestigate,
  ) {
    final Widget? investigate = canInvestigate
        ? Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(
              onPressed: () => _investigate(q.question),
              child: const Text(AskPage.investigate),
            ),
          )
        : null;
    final TextStyle body = DialTypeScale.body.copyWith(
      color: Theme.of(context).colorScheme.onSurface,
    );
    final TextStyle headline = DialTypeScale.displayM.copyWith(
      fontWeight: FontWeight.w800,
      color: Theme.of(context).colorScheme.onSurface,
    );
    final AskAnswer? answer = q.answer;
    if (q.pending) {
      return const <Widget>[ClaudeWorkingCard(status: AskPage.working)];
    }
    if (answer == null) {
      return <Widget>[
        _Card(children: <Widget>[Text(AskPage.failed, style: body)]),
      ];
    }
    switch (answer.kind) {
      case AskKind.needsInsights:
        return <Widget>[
          _Card(
            children: <Widget>[
              Text(AskPage.insights, style: body),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pushNamed('/insights'),
                  child: const Text(AskPage.openInsights),
                ),
              ),
              if (investigate != null) ...<Widget>[
                const SizedBox(height: 6),
                investigate,
              ],
            ],
          ),
        ];
      case AskKind.cannotAnswer:
        return <Widget>[
          _Card(
            children: <Widget>[
              Text(AskPage.cannot, style: headline),
              const SizedBox(height: 4),
              Text(AskPage.cannotDetail(answer.reason), style: body),
              if (investigate != null) ...<Widget>[
                const SizedBox(height: 10),
                investigate,
              ],
            ],
          ),
        ];
      case AskKind.answer:
        return <Widget>[
          for (final (int i, AskCard card) in answer.cards.indexed) ...<Widget>[
            if (i > 0) const SizedBox(height: 8),
            AskCardView(
              card: card,
              run: db == null
                  ? null
                  : _runs.putIfAbsent((q.id, i), () => db.run(card.sql)),
              readFailed: readFailed,
              marksByName: marksByName,
              onOpenDay: _openDay,
            ),
          ],
        ];
    }
  }
}

/// One card of an answer: its title and sentence as plain text, what its SQL
/// found on this device (or that it could not run), and the SQL on request.
class AskCardView extends StatefulWidget {
  const AskCardView({
    super.key,
    required this.card,
    required this.run,
    required this.readFailed,
    required this.marksByName,
    required this.onOpenDay,
  });

  final AskCard card;

  /// Null while the journal is still being read.
  final AskRun? run;
  final bool readFailed;
  final Map<String, HabitMark> marksByName;
  final ValueChanged<DateTime> onOpenDay;

  @override
  State<AskCardView> createState() => _AskCardViewState();
}

class _AskCardViewState extends State<AskCardView> {
  bool _showQuery = false;

  @override
  Widget build(BuildContext context) {
    final DialColors colors = DialColors.of(context);
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextStyle body = DialTypeScale.body.copyWith(color: scheme.onSurface);
    final AskRun? run = widget.run;
    return _Card(
      children: <Widget>[
        Text(
          widget.card.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: DialTypeScale.body.copyWith(
            fontWeight: FontWeight.w700,
            color: scheme.onSurface,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          widget.card.explain,
          style: DialTypeScale.bodyS.copyWith(color: colors.muted),
        ),
        const SizedBox(height: 10),
        switch (run) {
          null => Text(
            widget.readFailed ? AskPage.readFailed : AskPage.counting,
            style: body,
          ),
          AskRefused() => Text(AskPage.couldNotRun, style: body),
          AskRan(:final AskRows rows, :final bool truncated) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              AskChart(
                spec: widget.card.chart,
                rows: rows,
                marksByName: widget.marksByName,
                onOpenDay: widget.onOpenDay,
              ),
              if (truncated) ...<Widget>[
                const SizedBox(height: 4),
                Text(
                  AskPage.firstRows,
                  style: DialTypeScale.bodyS.copyWith(color: colors.muted),
                ),
              ],
            ],
          ),
        },
        const SizedBox(height: 6),
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                AskPage.onDevice.toUpperCase(),
                style: DialTypeScale.label.copyWith(
                  fontSize: 11,
                  letterSpacing: 0.9,
                  color: colors.muted,
                ),
              ),
            ),
            TextButton(
              onPressed: () => setState(() => _showQuery = !_showQuery),
              child: Text(_showQuery ? AskPage.hideQuery : AskPage.showQuery),
            ),
          ],
        ),
        if (_showQuery)
          DecoratedBox(
            decoration: BoxDecoration(
              color: colors.surface2,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: SelectableText(
                widget.card.sql,
                style: DialTypeScale.monoL.copyWith(
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  color: scheme.onSurface,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      border: Border.all(color: DialColors.of(context).line),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    ),
  );
}

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4),
    child: Text(
      text,
      style: DialTypeScale.body.copyWith(color: DialColors.of(context).muted),
    ),
  );
}

class _QuestionField extends StatelessWidget {
  const _QuestionField({
    super.key,
    required this.controller,
    required this.enabled,
    required this.hint,
    required this.onAsk,
  });

  final TextEditingController controller;
  final bool enabled;
  final String hint;
  final VoidCallback onAsk;

  @override
  Widget build(BuildContext context) {
    final DialColors colors = DialColors.of(context);
    return Row(
      children: <Widget>[
        Expanded(
          child: TextField(
            controller: controller,
            enabled: enabled,
            maxLength: CallableAskJournal.maxQuestion,
            textInputAction: TextInputAction.search,
            textCapitalization: TextCapitalization.sentences,
            onSubmitted: (_) => onAsk(),
            style: DialTypeScale.body,
            decoration: InputDecoration(
              hintText: hint,
              counterText: '',
              filled: true,
              fillColor: colors.surface2,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(999),
                borderSide: BorderSide(color: colors.line),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(999),
                borderSide: BorderSide(color: colors.line),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: enabled ? onAsk : null,
          child: const Text(AskPage.ask),
        ),
      ],
    );
  }
}

class _QuestionPill extends StatelessWidget {
  const _QuestionPill(this.question);

  final String question;

  @override
  Widget build(BuildContext context) {
    final DialColors colors = DialColors.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surface2,
          border: Border.all(color: colors.line),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Text(
            question,
            style: DialTypeScale.body.copyWith(fontSize: 14),
          ),
        ),
      ),
    );
  }
}
