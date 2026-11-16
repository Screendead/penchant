import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:tracker/claude/claude_working.dart';
import 'package:tracker/design/dial_theme.dart';
import 'package:tracker/design/tokens.dart';
import 'package:tracker/widgets/settings_card.dart';

enum GalleryRun { short, long, staged }

/// Emulator builds only: each look at each length of call, over fake calls
/// and a made-up journal. Nothing here sends anything.
class ClaudeWorkingGallery extends StatefulWidget {
  const ClaudeWorkingGallery({super.key});

  static const String route = '/claude-working';
  static const String title = 'Claude working';

  static Key button(ClaudeWorkingLook look, GalleryRun run) =>
      ValueKey<String>('gallery-${look.name}-${run.name}');

  static String runLabel(GalleryRun run) => switch (run) {
    GalleryRun.short => '3 s',
    GalleryRun.long => '20 s',
    GalleryRun.staged => 'Staged',
  };

  @override
  State<ClaudeWorkingGallery> createState() => _ClaudeWorkingGalleryState();
}

/// A plausible four weeks of three habits, the same on every run.
List<JournalMark> galleryMarks() {
  final math.Random random = math.Random(7);
  return <JournalMark>[
    for (int day = 0; day < claudeWorkingDays; day++) ...<JournalMark>[
      for (int i = 0; i < 1 + random.nextInt(3); i++)
        JournalMark(
          daysAgo: day,
          minute: 7 * 60 + random.nextInt(180),
          slot: 1,
          weight: 0.7 + random.nextDouble() * 0.6,
        ),
      if (random.nextDouble() < 0.7)
        for (int i = 0; i < 1 + random.nextInt(3); i++)
          JournalMark(
            daysAgo: day,
            minute: 18 * 60 + random.nextInt(300),
            slot: 0,
            weight: 0.6 + random.nextDouble(),
          ),
      if (random.nextDouble() < 0.35)
        JournalMark(
          daysAgo: day,
          minute: 12 * 60 + random.nextInt(300),
          slot: 2,
          weight: 1,
        ),
    ],
  ];
}

class _ClaudeWorkingGalleryState extends State<ClaudeWorkingGallery> {
  final List<JournalMark> _marks = galleryMarks();
  final Map<ClaudeWorkingLook, (int, String)> _results =
      <ClaudeWorkingLook, (int, String)>{};
  final List<Timer> _timers = <Timer>[];
  int _next = 0;

  @override
  void dispose() {
    for (final Timer t in _timers) {
      t.cancel();
    }
    super.dispose();
  }

  void _at(int ms, VoidCallback f) =>
      _timers.add(Timer(Duration(milliseconds: ms), f));

  void _play(BuildContext from, ClaudeWorkingLook look, GalleryRun run) {
    final int id = _next++;
    final List<Timer> mine = <Timer>[];
    void at(int ms, VoidCallback f) {
      _at(ms, f);
      mine.add(_timers.last);
    }

    final ClaudeWork work = switch (run) {
      GalleryRun.short => ClaudeWork(
        subject: 'When was my last week without wine?',
        status: 'Claude is writing a query',
        detail: 'Sent your question and your habits’ names',
      ),
      GalleryRun.long => ClaudeWork(
        status: 'Claude is writing your letter',
        detail: 'Sent 212 entries, 31 notes, 6 day notes',
        showElapsed: true,
      ),
      GalleryRun.staged => ClaudeWork(
        subject: 'Are my Fridays heavier than other days?',
        status: 'Claude is writing queries',
        detail: 'Sent your question and your habits’ names',
        steps: 6,
        showElapsed: true,
      ),
    };
    void answer(String text) {
      if (!mounted || work.over) return;
      setState(() => _results[look] = (id, text));
      work.finish(ClaudeWorkEnd.answered);
    }

    switch (run) {
      case GalleryRun.short:
        at(3000, () => answer('A sample answer: 9 to 15 March.'));
      case GalleryRun.long:
        at(20000, () => answer('A sample letter arrived.'));
      case GalleryRun.staged:
        at(
          5000,
          () => work.say(
            'Claude is reading the results',
            detail: 'Ran 3 queries on this phone and sent back what they found',
            stepsDone: 1,
          ),
        );
        at(
          11000,
          () => work.say(
            'Claude is reading the results',
            detail: 'Ran 2 queries on this phone and sent back what they found',
            stepsDone: 2,
          ),
        );
        at(17000, () => answer('A sample finding, from 5 queries.'));
    }
    showClaudeWorking(
      from,
      work,
      resultTag: ('gallery', id),
      look: look,
      marks: _marks,
      onStop: () {
        for (final Timer t in mine) {
          t.cancel();
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return CardPage(
      title: ClaudeWorkingGallery.title,
      children: <Widget>[
        const CardFoot(
          'Fake calls over a made-up journal, to compare the looks. '
          'Nothing is sent.',
        ),
        for (final ClaudeWorkingLook look
            in ClaudeWorkingLook.values) ...<Widget>[
          CardSectionLabel(look.name),
          Row(
            children: <Widget>[
              for (final GalleryRun run in GalleryRun.values)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Builder(
                      builder: (BuildContext from) => OutlinedButton(
                        key: ClaudeWorkingGallery.button(look, run),
                        onPressed: () => _play(from, look, run),
                        child: Text(ClaudeWorkingGallery.runLabel(run)),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: DialSpace.s),
          if (_results[look] case (final int id, final String text))
            ClaudeWorkingResult(
              tag: ('gallery', id),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLow,
                  border: Border.all(color: DialColors.of(context).line),
                  borderRadius: BorderRadius.circular(DialRadius.tile),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(DialSpace.m),
                  child: Text(
                    text,
                    style: DialTypeScale.bodyL.copyWith(
                      color: scheme.onSurface,
                    ),
                  ),
                ),
              ),
            )
          else
            ClaudeWorkingCard(
              look: look,
              marks: _marks,
              status: 'Claude is writing',
              detail: 'The inline card, for calls nobody tapped',
            ),
        ],
      ],
    );
  }
}
