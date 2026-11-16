import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/design/dial_icons.dart';
import 'package:tracker/design/dial_theme.dart';
import 'package:tracker/design/tokens.dart';
import 'package:tracker/errors/report_error.dart';
import 'package:tracker/formats.dart';
import 'package:tracker/insights_page.dart';
import 'package:tracker/letter/letter_checks.dart';
import 'package:tracker/letter/letter_journal.dart';
import 'package:tracker/letter/letter_payload.dart';
import 'package:tracker/letter/letter_store.dart';
import 'package:tracker/letter/letter_writer.dart';
import 'package:tracker/providers/today_provider.dart';
import 'package:tracker/providers/vice_list_provider.dart';
import 'package:tracker/widgets/info_box.dart';
import 'package:tracker/widgets/settings_card.dart';

/// The letter: saved letters newest first, and writing a new one through a
/// period, a preview of exactly what is sent, and the wait.
class LetterPage extends ConsumerStatefulWidget {
  const LetterPage({super.key});

  static const String route = '/letter';
  static const String title = 'Letter';
  static const String write = 'Write a letter';
  static const String saved = 'Saved letters';
  static const String none = 'No letters yet.';
  static const String off =
      'The letter is off. Turn it on in Settings, under Claude.';
  static const String intro =
      'Claude reads a period of your journal and writes a few hundred words: '
      'what you wrote about most, what shifted, and a few things worth '
      'testing. Nothing is sent until you have seen it and pressed Send.';
  static const String choose = 'Which period?';
  static const String next = 'See what will be sent';
  static const String reading = 'Reading your journal…';
  static const String readFailed = 'Your journal couldn’t be read.';
  static const String nothing =
      'Nothing to send: no entries or day notes in this period.';
  static const String tooMuch =
      'Even one day of this journal is too much for one letter.';
  static const String previewTitle = 'What will be sent';
  static const String disclosure =
      'This goes to Penchant’s server and on to Anthropic’s Claude Opus, which '
      'writes the letter. It is not used for training and is deleted by '
      'Anthropic within 30 days. Health, places and calendar data are never '
      'sent.';
  static const String send = 'Send';
  static const String cancel = 'Cancel';
  static const String notesHeading = 'Every note sent';
  static const String noNotes = 'No notes in this period.';
  static const String writing = 'Writing your letter…';
  static const String writingBody =
      'This can take one to two minutes. You can leave this page: the letter '
      'is saved here when it arrives, as long as Penchant stays open. If '
      'Penchant is closed first, the letter is lost.';
  static const String failed = 'No letter this time';
  static const String ok = 'OK';
  static const String worthTesting = 'Worth testing';
  static const String testInInsights = 'Open Insights';
  static const String delete = 'Delete this letter';
  static const String deleteTitle = 'Delete this letter?';
  static const String deleteBody =
      'It is kept only on this device, so it cannot be brought back.';
  static const String keep = 'Keep';
  static const String back = 'All letters';

  static String months(int n) => n == 1 ? 'Last month' : 'Last $n months';

  static String count(int n, String one, String other) =>
      '${formatCount(n)} ${pluralWord(n, one: one, other: other)}';

  static String counts(LetterCounts c) =>
      '${count(c.entries, 'entry', 'entries')}, '
      '${count(c.entryNotes, 'note', 'notes')}, '
      '${count(c.dayNotes, 'day note', 'day notes')}';

  static String size(int chars) =>
      'About ${formatCount((chars / 1000).ceil())} thousand characters '
      '(${formatCount((chars / 6).round())} words or so)';

  static String shortened(DateTime from) =>
      'The whole period is too much for one letter, so it starts on '
      '${formatDate(from)}.';

  static String leftOut(int n) =>
      '${count(n, 'entry or note', 'entries or notes')} that would not open '
      'on this device, or whose habit is gone, are left out.';

  static String withheld(int n) => n == 1
      ? 'One passage was left out.'
      : '${formatCount(n)} passages were left out.';

  static String writtenBy(SavedLetter l) =>
      'Written by Claude on ${formatDate(l.writtenAt)} · what was sent: '
      '${counts(l.counts)}';

  static String failedBody(String reason) => switch (reason) {
    'refusal' => 'Claude declined to write this one.',
    'offline' => 'The letter couldn’t be asked for. Check your connection.',
    'not_saved' => 'The letter arrived but couldn’t be kept on this device.',
    _ =>
      'What came back didn’t pass this app’s checks, so it isn’t shown. '
          'Nothing was saved.',
  };

  @override
  ConsumerState<LetterPage> createState() => _LetterPageState();
}

enum _Step { list, choose, preview }

class _LetterPageState extends ConsumerState<LetterPage> {
  _Step step = _Step.list;
  int months = defaultLetterMonths;
  SavedLetter? viewing;

  /// The preview's payload once read; null while reading.
  LetterPayload? payload;
  bool reading = false;
  String? problem;

  Future<void> _preview() async {
    final LetterJournal? journal = ref.read(letterJournalProvider);
    final List<Vice>? vices = ref.read(viceListProvider).value;
    if (journal == null || vices == null) return;
    final DateTime today = ref.read(todayProvider);
    setState(() {
      step = _Step.preview;
      reading = true;
      payload = null;
      problem = null;
    });
    try {
      final LetterJournalData data = await journal.read(
        letterStart(today, months),
        addDays(startOfDay(today), 1),
      );
      final LetterPayload? built = buildLetterPayload(
        vices: vices,
        activities: data.activities,
        dayNotes: data.dayNotes,
        today: today,
        months: months,
      );
      if (!mounted) return;
      setState(() {
        reading = false;
        payload = built;
        problem = built == null
            ? LetterPage.tooMuch
            : built.isEmpty
            ? LetterPage.nothing
            : null;
      });
    } catch (e, stack) {
      reportError(e, stack, context: 'while reading the journal for a letter');
      if (!mounted) return;
      setState(() {
        reading = false;
        problem = LetterPage.readFailed;
      });
    }
  }

  void _toList() => setState(() {
    step = _Step.list;
    payload = null;
    problem = null;
    viewing = null;
  });

  Future<void> _send(LetterPayload p) async {
    setState(() {
      step = _Step.list;
      payload = null;
    });
    await ref.read(letterRunProvider.notifier).send(p);
  }

  Future<void> _delete(SavedLetter letter) async {
    final bool? sure = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text(LetterPage.deleteTitle),
        content: const Text(LetterPage.deleteBody),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(LetterPage.keep),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(LetterPage.delete),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    await ref.read(lettersProvider.notifier).delete(letter.id);
    ref.read(letterRunProvider.notifier).clear();
    if (mounted) _toList();
  }

  @override
  Widget build(BuildContext context) {
    final LetterWriter? writer = ref.watch(letterWriterProvider);
    final LetterRun run = ref.watch(letterRunProvider);
    final SavedLetter? shown =
        viewing ?? (run is LetterWritten ? run.letter : null);
    if (shown != null) {
      return CardPage(
        title: LetterPage.title,
        children: <Widget>[
          _LetterView(letter: shown),
          DialCard(
            children: <Widget>[
              CardRow(
                label: LetterPage.back,
                glyph: DialGlyph.left,
                onTap: () {
                  ref.read(letterRunProvider.notifier).clear();
                  _toList();
                },
              ),
              CardRow(
                label: LetterPage.delete,
                danger: true,
                onTap: () => _delete(shown),
              ),
            ],
          ),
        ],
      );
    }
    if (writer == null && run is! LetterSending) {
      return const CardPage(
        title: LetterPage.title,
        children: <Widget>[
          DialCard(children: <Widget>[CardRow(label: LetterPage.off)]),
        ],
      );
    }
    return CardPage(
      title: LetterPage.title,
      children: switch (step) {
        _Step.list => _list(context, run),
        _Step.choose => _choose(),
        _Step.preview => _previewChildren(context),
      },
    );
  }

  List<Widget> _list(BuildContext context, LetterRun run) {
    final List<SavedLetter> letters =
        ref.watch(lettersProvider).value ?? const <SavedLetter>[];
    final DialColors colors = DialColors.of(context);
    return <Widget>[
      const CardFoot(LetterPage.intro),
      switch (run) {
        LetterSending() => DialCard(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      if (!MediaQuery.disableAnimationsOf(context)) ...<Widget>[
                        const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: DialSpace.s),
                      ],
                      Text(LetterPage.writing, style: DialTypeScale.bodyL),
                    ],
                  ),
                  const SizedBox(height: DialSpace.xs),
                  Text(
                    LetterPage.writingBody,
                    style: DialTypeScale.label.copyWith(color: colors.muted),
                  ),
                ],
              ),
            ),
          ],
        ),
        LetterNotWritten(:final String reason) => Padding(
          padding: const EdgeInsets.only(top: DialSpace.l),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              InfoBox(
                message:
                    '${LetterPage.failed}. ${LetterPage.failedBody(reason)}',
                isError: true,
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => ref.read(letterRunProvider.notifier).clear(),
                  child: const Text(LetterPage.ok),
                ),
              ),
            ],
          ),
        ),
        _ => DialCard(
          children: <Widget>[
            CardRow(
              label: LetterPage.write,
              glyph: DialGlyph.right,
              onTap: () => setState(() => step = _Step.choose),
            ),
          ],
        ),
      },
      const CardSectionLabel(LetterPage.saved),
      DialCard(
        children: <Widget>[
          if (letters.isEmpty) const CardRow(label: LetterPage.none),
          for (final SavedLetter l in letters)
            CardRow(
              label: letterPeriodLabel(l.from, l.to),
              subtitle: 'Written ${formatDate(l.writtenAt)}',
              glyph: DialGlyph.right,
              onTap: () => setState(() => viewing = l),
            ),
        ],
      ),
    ];
  }

  List<Widget> _choose() => <Widget>[
    const CardSectionLabel(LetterPage.choose),
    DialCard(
      children: <Widget>[
        for (final int m in letterMonths)
          Semantics(
            selected: m == months,
            child: CardRow(
              label: LetterPage.months(m),
              glyph: m == months ? DialGlyph.check : null,
              onTap: () => setState(() => months = m),
            ),
          ),
      ],
    ),
    const SizedBox(height: DialSpace.l),
    _Buttons(primary: LetterPage.next, onPrimary: _preview, onCancel: _toList),
  ];

  List<Widget> _previewChildren(BuildContext context) {
    final LetterPayload? p = payload;
    if (reading) {
      return const <Widget>[
        DialCard(children: <Widget>[CardRow(label: LetterPage.reading)]),
      ];
    }
    if (p == null || problem != null) {
      return <Widget>[
        const SizedBox(height: DialSpace.l),
        InfoBox(
          message: problem ?? LetterPage.readFailed,
          isError: problem == LetterPage.readFailed,
          onRetry: problem == LetterPage.readFailed ? _preview : null,
        ),
        const SizedBox(height: DialSpace.l),
        _Buttons(onCancel: _toList),
      ];
    }
    final bool busy = ref.watch(letterRunProvider) is LetterSending;
    return <Widget>[
      const CardSectionLabel(LetterPage.previewTitle),
      DialCard(
        children: <Widget>[
          CardRow(label: letterPeriodLabel(p.from, p.to)),
          CardRow(label: LetterPage.counts(p.counts)),
          CardRow(label: LetterPage.size(p.chars)),
        ],
      ),
      if (p.shortened) CardFoot(LetterPage.shortened(p.from)),
      if (p.counts.leftOut > 0) CardFoot(LetterPage.leftOut(p.counts.leftOut)),
      const CardFoot(LetterPage.disclosure),
      const SizedBox(height: DialSpace.l),
      _Buttons(
        primary: LetterPage.send,
        onPrimary: busy ? null : () => _send(p),
        onCancel: _toList,
      ),
      const CardSectionLabel(LetterPage.notesHeading),
      DialCard(
        children: <Widget>[
          if (p.notes.isEmpty) const CardRow(label: LetterPage.noNotes),
          for (final LetterNote n in p.notes) _NoteRow(note: n),
        ],
      ),
    ];
  }
}

class _Buttons extends StatelessWidget {
  const _Buttons({this.primary, this.onPrimary, required this.onCancel});

  final String? primary;
  final VoidCallback? onPrimary;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final ButtonStyle shape = FilledButton.styleFrom(
      minimumSize: const Size.fromHeight(52),
      shape: const StadiumBorder(),
      textStyle: DialTypeScale.body.copyWith(fontWeight: FontWeight.w600),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (primary != null)
          FilledButton(
            onPressed: onPrimary,
            style: shape,
            child: Text(primary!),
          ),
        const SizedBox(height: DialSpace.xs),
        TextButton(
          onPressed: onCancel,
          style: TextButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          child: const Text(LetterPage.cancel),
        ),
      ],
    );
  }
}

class _NoteRow extends StatelessWidget {
  const _NoteRow({required this.note});

  final LetterNote note;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final DialColors colors = DialColors.of(context);
    final TextStyle muted = DialTypeScale.label.copyWith(color: colors.muted);
    final TextStyle body = DialTypeScale.body.copyWith(color: scheme.onSurface);
    final ({String question, String answer})? follow = note.followUp;
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '${formatDay(note.day)} · ${note.habit ?? 'Day note'}',
              style: muted,
            ),
            if (note.text.isNotEmpty) ...<Widget>[
              const SizedBox(height: 4),
              Text(note.text, style: body),
            ],
            if (follow != null) ...<Widget>[
              const SizedBox(height: 6),
              Text(follow.question, style: muted),
              Text(follow.answer, style: body),
            ],
          ],
        ),
      ),
    );
  }
}

class _LetterView extends StatelessWidget {
  const _LetterView({required this.letter});

  final SavedLetter letter;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final DialColors colors = DialColors.of(context);
    final TextStyle heading = DialTypeScale.bodyL.copyWith(
      color: scheme.onSurface,
      fontWeight: FontWeight.w600,
    );
    final TextStyle body = DialTypeScale.bodyL.copyWith(
      color: scheme.onSurface,
    );
    Widget block(String h, String b) => Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      child: MergeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Semantics(header: true, child: Text(h, style: heading)),
            const SizedBox(height: 6),
            Text(b, style: body),
          ],
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        CardFoot(letterPeriodLabel(letter.from, letter.to)),
        DialCard(
          children: <Widget>[
            for (final LetterSection s in letter.sections)
              block(s.heading, s.body),
          ],
        ),
        if (letter.toTest.isNotEmpty) ...<Widget>[
          const CardSectionLabel(LetterPage.worthTesting),
          DialCard(
            children: <Widget>[
              for (final LetterTest t in letter.toTest) block(t.title, t.why),
              CardRow(
                label: LetterPage.testInInsights,
                glyph: DialGlyph.right,
                onTap: () =>
                    Navigator.of(context).pushNamed(InsightsPage.route),
              ),
            ],
          ),
        ],
        if (letter.withheld > 0) CardFoot(LetterPage.withheld(letter.withheld)),
        if (letter.shortened) CardFoot(LetterPage.shortened(letter.from)),
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 10, 6, 0),
          child: Text(
            LetterPage.writtenBy(letter),
            style: DialTypeScale.label.copyWith(color: colors.muted),
          ),
        ),
      ],
    );
  }
}
