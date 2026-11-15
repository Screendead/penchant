import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/ask/ask_journal.dart';
import 'package:tracker/ask/ask_query.dart';
import 'package:tracker/ask/ask_runner.dart';
import 'package:tracker/ask/describe_query.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/design/dial_theme.dart';
import 'package:tracker/design/habit_mark.dart';
import 'package:tracker/design/tokens.dart';
import 'package:tracker/insights/insights_report.dart';
import 'package:tracker/providers/today_provider.dart';
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/providers/vice_activity_day_provider.dart';
import 'package:tracker/providers/vice_list_provider.dart';
import 'package:tracker/widgets/dial_page.dart';

/// A question asked this session, with what the server made of it. [habits]
/// and [today] are those sent, so the query's habit indexes resolve against
/// the same list.
class AskedQuestion {
  const AskedQuestion({
    required this.id,
    required this.question,
    required this.habits,
    required this.today,
    this.parsed,
    this.failed = false,
  });

  final int id;
  final String question;
  final List<Vice> habits;
  final DateTime today;
  final AskParsed? parsed;
  final bool failed;

  bool get pending => parsed == null && !failed;
}

/// The last few questions, newest first, in memory for this session only and
/// forgotten when the signed-in user changes.
final askHistoryProvider = NotifierProvider<AskHistory, List<AskedQuestion>>(
  AskHistory.new,
);

class AskHistory extends Notifier<List<AskedQuestion>> {
  static const int kept = 5;

  int _next = 0;

  @override
  List<AskedQuestion> build() {
    ref.watch(
      userProvider.select((AsyncValue<User?> user) => user.value?.uid),
    );
    return const <AskedQuestion>[];
  }

  int start(String question, List<Vice> habits, DateTime today) {
    final int id = _next++;
    state = <AskedQuestion>[
      AskedQuestion(id: id, question: question, habits: habits, today: today),
      ...state,
    ].take(kept).toList();
    return id;
  }

  void settle(int id, {AskParsed? parsed}) {
    state = <AskedQuestion>[
      for (final AskedQuestion q in state)
        q.id == id
            ? AskedQuestion(
                id: q.id,
                question: q.question,
                habits: q.habits,
                today: q.today,
                parsed: parsed,
                failed: parsed == null,
              )
            : q,
    ];
  }
}

class AskPage extends ConsumerStatefulWidget {
  const AskPage({super.key});

  static const String route = '/ask';
  static const String title = 'Ask your journal';
  static const String hint = 'When was my last week without wine?';
  static const String off =
      'Asking is off. Turn on “Ask your journal” in Settings to ask a '
      'question about your habits.';
  static const String ask = 'Ask';
  static const String working = 'Reading the question…';
  static const String counting = 'Counting…';
  static const String failed =
      'Couldn’t read the question just now. Nothing was counted.';
  static const String readFailed = 'Couldn’t read your journal on this device.';
  static const String onDevice = 'Counted on this device';
  static const String insights =
      'That is a “why”, which Insights answers by comparison, and only when '
      'the numbers hold up.';
  static const String openInsights = 'Open it in Insights';
  static const String cannot = 'Penchant can’t answer that yet.';

  static String cannotDetail(AskReason? reason) => switch (reason) {
    AskReason.notAboutJournal => 'It answers questions about your habits.',
    AskReason.unknownHabit => 'That doesn’t match one of your habits.',
    AskReason.notSupported => 'That is outside what it can count so far.',
    AskReason.unclear || null => 'Try asking another way.',
  };

  @override
  ConsumerState<AskPage> createState() => _AskPageState();
}

class _AskPageState extends ConsumerState<AskPage> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _ask() async {
    final AskJournal? service = ref.read(askJournalProvider);
    final List<Vice>? vices = ref.read(viceListProvider).value;
    final String question = _controller.text.trim();
    if (service == null || vices == null || question.isEmpty) return;
    final List<Vice> habits = askHabits(vices);
    final DateTime today = ref.read(todayProvider);
    final AskHistory history = ref.read(askHistoryProvider.notifier);
    final int id = history.start(question, habits, today);
    _controller.clear();
    AskParsed? parsed;
    try {
      parsed = await service.ask(question, habits: habits, today: today);
    } catch (_) {
      // Not reported: a report would carry the question.
      parsed = null;
    }
    history.settle(id, parsed: parsed);
  }

  @override
  Widget build(BuildContext context) {
    final bool on = ref.watch(askJournalProvider) != null;
    final bool habitsLoaded = ref.watch(viceListProvider).value != null;
    final List<AskedQuestion> asked = ref.watch(askHistoryProvider);
    final bool running = asked.any(
      (AskedQuestion q) => q.parsed is AskRun,
    );
    final DateTime today = ref.watch(todayProvider);
    // Read only once a query needs entries; the same one-time read as
    // Insights, so the same query shape and index.
    final AsyncValue<List<ViceActivity>>? entries = running
        ? ref.watch(viceActivityRangeProvider(insightsRange(today)))
        : null;
    final Map<String, HabitMark> marks = habitMarks(
      ref.watch(viceListProvider).value ?? const <Vice>[],
    );

    return DialPage(
      title: AskPage.title,
      children: <Widget>[
        const SizedBox(height: DialSpace.l),
        if (!on)
          _Note(AskPage.off)
        else
          _QuestionField(
            controller: _controller,
            enabled: habitsLoaded,
            onAsk: _ask,
          ),
        for (final AskedQuestion q in asked) ...<Widget>[
          const SizedBox(height: DialSpace.l),
          _QuestionPill(q.question),
          const SizedBox(height: 8),
          _AnswerCard(asked: q, entries: entries, marks: marks),
        ],
      ],
    );
  }
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
    required this.controller,
    required this.enabled,
    required this.onAsk,
  });

  final TextEditingController controller;
  final bool enabled;
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
              hintText: AskPage.hint,
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
          child: Text(question, style: DialTypeScale.body.copyWith(fontSize: 14)),
        ),
      ),
    );
  }
}

class _AnswerCard extends StatelessWidget {
  const _AnswerCard({
    required this.asked,
    required this.entries,
    required this.marks,
  });

  final AskedQuestion asked;
  final AsyncValue<List<ViceActivity>>? entries;
  final Map<String, HabitMark> marks;

  @override
  Widget build(BuildContext context) {
    final DialColors colors = DialColors.of(context);
    final TextStyle body = DialTypeScale.body.copyWith(
      color: Theme.of(context).colorScheme.onSurface,
    );
    final TextStyle headline = DialTypeScale.displayM.copyWith(
      fontWeight: FontWeight.w800,
      color: Theme.of(context).colorScheme.onSurface,
    );
    final List<Widget> children = switch (asked.parsed) {
      _ when asked.pending => <Widget>[Text(AskPage.working, style: body)],
      _ when asked.failed => <Widget>[Text(AskPage.failed, style: body)],
      AskNeedsInsights() => <Widget>[
        Text(AskPage.insights, style: body),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton(
            onPressed: () => Navigator.of(context).pushNamed('/insights'),
            child: const Text(AskPage.openInsights),
          ),
        ),
      ],
      AskCannotAnswer(:final AskReason? reason) => <Widget>[
        Text(AskPage.cannot, style: headline),
        const SizedBox(height: 4),
        Text(AskPage.cannotDetail(reason), style: body),
      ],
      AskRun(:final AskQuery query) => _answer(context, query, body, headline),
      null => const <Widget>[],
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        border: Border.all(color: colors.line),
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

  List<Widget> _answer(
    BuildContext context,
    AskQuery query,
    TextStyle body,
    TextStyle headline,
  ) {
    final DialColors colors = DialColors.of(context);
    final List<ViceActivity>? all = entries?.value;
    final Widget words = Text(
      describeQuery(query, asked.habits),
      style: DialTypeScale.bodyS.copyWith(color: colors.muted),
    );
    if (all == null) {
      return <Widget>[
        Text(
          entries?.hasError ?? false ? AskPage.readFailed : AskPage.counting,
          style: body,
        ),
        const SizedBox(height: 8),
        words,
      ];
    }
    final AskAnswer answer = runAskQuery(
      query,
      habits: asked.habits,
      activities: all,
      today: asked.today,
    );
    return <Widget>[
      Semantics(
        liveRegion: true,
        child: Text(answer.headline, style: headline),
      ),
      if (answer.detail != null) ...<Widget>[
        const SizedBox(height: 4),
        Text(answer.detail!, style: body),
      ],
      if (answer.bars != null && answer.bars!.isNotEmpty) ...<Widget>[
        const SizedBox(height: 12),
        AskBars(bars: answer.bars!, marks: marks),
      ],
      const SizedBox(height: 10),
      words,
      const SizedBox(height: 8),
      Text(
        AskPage.onDevice.toUpperCase(),
        style: DialTypeScale.label.copyWith(
          fontSize: 11,
          letterSpacing: 0.9,
          color: colors.muted,
        ),
      ),
    ];
  }
}

/// The answer's small chart: a bar per bucket in the habit's colour (ink for
/// all habits together), an empty one as a hairline stub, the marked one
/// ringed, and the first and last bars named underneath.
class AskBars extends StatelessWidget {
  const AskBars({super.key, required this.bars, required this.marks});

  static const double height = 44;

  final List<AskBar> bars;
  final Map<String, HabitMark> marks;

  @override
  Widget build(BuildContext context) {
    final DialColors colors = DialColors.of(context);
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final double top = bars.map((AskBar b) => b.value).fold(0, max);
    final TextStyle axis = DialTypeScale.monoL.copyWith(
      fontSize: 11,
      fontWeight: FontWeight.w500,
      color: colors.muted,
    );
    Color colour(AskBar bar) {
      final HabitMark? mark = bar.viceID == null ? null : marks[bar.viceID];
      return mark == null ? scheme.onSurface : colors.habit(mark);
    }

    return Semantics(
      label: bars
          .map((AskBar b) => '${b.label}: ${_number(b.value)}')
          .join('; '),
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SizedBox(
            height: height,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                for (int i = 0; i < bars.length; i++) ...<Widget>[
                  if (i > 0) const SizedBox(width: 4),
                  Expanded(
                    child: bars[i].value <= 0 || top <= 0
                        ? Container(
                            height: 6,
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: bars[i].marked
                                    ? scheme.onSurface
                                    : colors.line,
                                width: bars[i].marked ? 1.5 : 1,
                              ),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          )
                        : Container(
                            height: max(3, height * bars[i].value / top),
                            decoration: BoxDecoration(
                              color: colour(bars[i]),
                              border: bars[i].marked
                                  ? Border.all(color: scheme.onSurface, width: 1.5)
                                  : null,
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(3),
                              ),
                            ),
                          ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: <Widget>[
              Expanded(child: Text(bars.first.label, style: axis)),
              if (bars.length > 1)
                Text(bars.last.label, style: axis, textAlign: TextAlign.end),
            ],
          ),
        ],
      ),
    );
  }

  static String _number(double v) {
    final double r = (v * 100).round() / 100;
    return r == r.roundToDouble() ? r.toInt().toString() : r.toString();
  }
}
