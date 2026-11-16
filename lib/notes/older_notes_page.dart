import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/account/claude_access.dart';
import 'package:tracker/claude/claude_working.dart';
import 'package:tracker/data/trigger_tree.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/design/dial_icons.dart';
import 'package:tracker/design/tokens.dart';
import 'package:tracker/formats.dart';
import 'package:tracker/insights/insights_report.dart';
import 'package:tracker/notes/note_reader.dart';
import 'package:tracker/notes/note_reader_setting.dart';
import 'package:tracker/notes/older_notes.dart';
import 'package:tracker/providers/today_provider.dart';
import 'package:tracker/providers/vice_activity_day_provider.dart';
import 'package:tracker/providers/vice_list_provider.dart';
import 'package:tracker/widgets/info_box.dart';
import 'package:tracker/widgets/settings_card.dart';

/// The Settings row opening [OlderNotesPage], usable while notes are read
/// into tags.
class OlderNotesRow extends ConsumerWidget {
  const OlderNotesRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(claudeAllowedProvider)) {
      return const ClaudeNeedsEmailRow(label: OlderNotesPage.title);
    }
    final bool reader = ref.watch(noteReaderEnabledProvider);
    return CardRow(
      label: OlderNotesPage.title,
      subtitle: reader
          ? OlderNotesPage.rowSubtitle
          : OlderNotesPage.needsReader,
      enabled: reader,
      glyph: DialGlyph.right,
      onTap: reader
          ? () => Navigator.of(context).pushNamed(OlderNotesPage.route)
          : null,
    );
  }
}

/// Notes written before the note reader was on, read in batches the person
/// starts and reviewed note by note; nothing is saved until they keep a tag.
class OlderNotesPage extends ConsumerStatefulWidget {
  const OlderNotesPage({super.key});

  static const String route = '/settings/older-notes';
  static const String title = 'Tag older notes';
  static const String rowSubtitle =
      'Suggests tags for notes you wrote before, for you to review.';
  static const String needsReader =
      'Turn on Suggest tags from notes to use this.';
  static const String off =
      'Turn on Suggest tags from notes in Settings, with a verified email, '
      'to use this.';
  static const String noKey =
      'Your journal key has not loaded yet. Try again once it has.';
  static const String readFailed = 'Penchant couldn’t read your journal.';
  static const Object resultTag = ('older-notes', 'review');

  static String unread(int n) => n == 0
      ? 'Every note has been read.'
      : '${formatCount(n)} ${pluralWord(n, one: 'note', other: 'notes')} '
            'not yet read.';
  static const String sends =
      'Each note’s text is sent on its own to Penchant’s server and on to '
      'Anthropic’s Claude, as when you write a note. Nothing else goes with '
      'it: no amounts, times or habit names. Anthropic does not use it for '
      'training and deletes it within 30 days. Nothing changes until you '
      'keep a tag.';
  static String skipped({required int locked, required int full}) => <String>[
    if (locked > 0)
      '${formatCount(locked)} locked '
          '${pluralWord(locked, one: 'entry', other: 'entries')} left out',
    if (full > 0)
      '${formatCount(full)} '
          '${pluralWord(full, one: 'entry', other: 'entries')} already '
          'with 10 tags left out',
  ].join('; ');
  static String readNext(int n) =>
      'Read the next ${formatCount(n)} ${pluralWord(n, one: 'note', other: 'notes')}';
  static String perDay(int left) =>
      'Up to $olderNotesDailyCap a day on this device; '
      '${formatCount(left)} left today.';
  static const String enoughToday =
      'That’s enough for today. Come back tomorrow for the next ones.';
  static const String reviewFirst =
      'Review the notes below before reading more.';
  static const String failed =
      'Claude couldn’t be reached. The notes not read stay for next time.';
  static const String stop = 'Stop';
  static const String reading = 'Reading your notes';
  static const String review = 'To review';
  static const String keepAll = 'Keep every ticked tag shown';
  static String keepAllTitle(int tags, int notes) =>
      'Save ${formatCount(tags)} ${pluralWord(tags, one: 'tag', other: 'tags')} '
      'to ${formatCount(notes)} ${pluralWord(notes, one: 'entry', other: 'entries')}?';
  static const String keepAllBody =
      'Each ticked tag is added to its entry. Untick any you are not sure of '
      'first. You can change an entry’s tags later by opening it.';
  static const String save = 'Save';
  static const String cancel = 'Cancel';
  static const String keep = 'Keep ticked';
  static const String drop = 'Drop all';
  static const String gone = 'This entry is no longer in your journal.';
  static String saved(TagSaves s) {
    final int ok = s.saved + s.queued;
    return <String>[
      if (ok > 0)
        'Tags saved to ${formatCount(ok)} '
            '${pluralWord(ok, one: 'entry', other: 'entries')}'
            '${s.queued > 0 ? ', to sync when online' : ''}.',
      if (s.failed > 0)
        '${formatCount(s.failed)} not saved: open '
            '${pluralWord(s.failed, one: 'it', other: 'them')} to tag by hand.',
      if (ok == 0 && s.failed == 0) 'Nothing to save.',
    ].join(' ');
  }

  @override
  ConsumerState<OlderNotesPage> createState() => _OlderNotesPageState();
}

class _OlderNotesPageState extends ConsumerState<OlderNotesPage> {
  /// Per entry, the tag paths unticked; every shown tag starts ticked.
  final Map<String, Set<String>> _unticked = <String, Set<String>>{};

  List<String> _kept(String id, List<ReadTag> tags) => <String>[
    for (final ReadTag t in tags)
      if (!(_unticked[id]?.contains(t.path) ?? false)) t.path,
  ];

  String _what(ViceActivity entry, Map<String, Vice> vices) =>
      'Tags not saved: ${vices[entry.viceID]?.name ?? 'an entry'}, '
      '${formatShortDay(entry.createdAt.toDate())}';

  Future<void> _decide(
    Map<String, List<String>> keep,
    Map<String, ViceActivity> entries,
    Map<String, Vice> vices,
  ) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final TagSaves result = await ref
        .read(olderNotesProvider.notifier)
        .decide(keep, entries, what: (ViceActivity e) => _what(e, vices));
    for (final String id in keep.keys) {
      _unticked.remove(id);
    }
    if (keep.values.any((List<String> k) => k.isNotEmpty) && mounted) {
      messenger.showSnackBar(
        SnackBar(content: Text(OlderNotesPage.saved(result))),
      );
    }
  }

  Future<void> _keepAll(
    List<(ViceActivity, List<ReadTag>)> shown,
    Map<String, ViceActivity> entries,
    Map<String, Vice> vices,
  ) async {
    final Map<String, List<String>> keep = <String, List<String>>{
      for (final (ViceActivity e, List<ReadTag> tags) in shown)
        e.id: _kept(e.id, tags),
    };
    final int tags = keep.values.fold(
      0,
      (int n, List<String> k) => n + k.length,
    );
    final int notes = keep.values
        .where((List<String> k) => k.isNotEmpty)
        .length;
    final bool? sure = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(OlderNotesPage.keepAllTitle(tags, notes)),
        content: const Text(OlderNotesPage.keepAllBody),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(OlderNotesPage.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(OlderNotesPage.save),
          ),
        ],
      ),
    );
    if (sure ?? false) await _decide(keep, entries, vices);
  }

  void _read(BuildContext from, List<ViceActivity> batch) {
    final OlderNotesRunner runner = ref.read(olderNotesProvider.notifier);
    final ClaudeWork work = ClaudeWork(
      status: OlderNotesPage.reading,
      steps: batch.length,
    );
    unawaited(
      showClaudeWorking(
        from,
        work,
        resultTag: OlderNotesPage.resultTag,
        onStop: runner.stop,
      ),
    );
    unawaited(runner.read(batch, work: work));
  }

  @override
  Widget build(BuildContext context) {
    final NoteReader? reader = ref.watch(olderNoteReaderProvider);
    final OlderNotesState state = ref.watch(olderNotesProvider);
    if (reader == null && !state.reading) {
      return const CardPage(
        title: OlderNotesPage.title,
        children: <Widget>[CardFoot(OlderNotesPage.off)],
      );
    }
    if (ref.watch(olderNotesFileProvider) == null) {
      return const CardPage(
        title: OlderNotesPage.title,
        children: <Widget>[CardFoot(OlderNotesPage.noKey)],
      );
    }
    final DateTime today = ref.watch(todayProvider);
    final AsyncValue<List<ViceActivity>> journal = ref.watch(
      viceActivityRangeProvider(insightsRange(today)),
    );
    final List<Vice>? vices = ref.watch(viceListProvider).value;
    final OlderNotesProgress? progress = state.progress;
    if (journal.hasError && !journal.hasValue) {
      return const CardPage(
        title: OlderNotesPage.title,
        children: <Widget>[
          InfoBox(message: OlderNotesPage.readFailed, isError: true),
        ],
      );
    }
    final List<ViceActivity>? entries = journal.value;
    if (entries == null || vices == null || progress == null) {
      return const CardPage(
        title: OlderNotesPage.title,
        children: <Widget>[
          Padding(
            padding: EdgeInsets.all(DialSpace.xl),
            child: Center(child: CircularProgressIndicator.adaptive()),
          ),
        ],
      );
    }
    final Map<String, Vice> byID = <String, Vice>{
      for (final Vice v in vices) v.id: v,
    };
    final Map<String, ViceActivity> byEntry = <String, ViceActivity>{
      for (final ViceActivity e in entries) e.id: e,
    };
    final List<(ViceActivity, List<ReadTag>)> shown =
        <(ViceActivity, List<ReadTag>)>[
          for (final MapEntry<String, List<ReadTag>> p
              in progress.proposals.entries)
            if (byEntry[p.key] case final ViceActivity e)
              if (!e.locked) (e, shownTags(e, p.value)),
        ].take(olderNotesBatch).toList();
    final OlderNotes notes = olderNotes(entries, progress);
    return CardPage(
      title: OlderNotesPage.title,
      children: <Widget>[
        if (state.reading)
          _Reading(onStop: ref.read(olderNotesProvider.notifier).stop)
        else
          _Start(
            notes: notes,
            left: progress.leftToday(DateTime.now()),
            problem: state.problem,
            reviewing: shown.isNotEmpty,
            onRead: _read,
          ),
        if (shown.isNotEmpty)
          ClaudeWorkingResult(
            tag: OlderNotesPage.resultTag,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                CardSectionLabel(
                  '${OlderNotesPage.review} (${formatCount(shown.length)})',
                ),
                for (final (ViceActivity e, List<ReadTag> tags) in shown)
                  _NoteReview(
                    key: ValueKey<String>(e.id),
                    entry: e,
                    habit: byID[e.viceID]?.name,
                    tags: tags,
                    unticked: _unticked[e.id] ?? const <String>{},
                    onTick: (String path, bool on) => setState(() {
                      final Set<String> off = _unticked[e.id] ??= <String>{};
                      on ? off.remove(path) : off.add(path);
                    }),
                    onKeep: () => _decide(
                      <String, List<String>>{e.id: _kept(e.id, tags)},
                      byEntry,
                      byID,
                    ),
                    onDrop: () => _decide(
                      <String, List<String>>{e.id: const <String>[]},
                      byEntry,
                      byID,
                    ),
                  ),
                if (shown.length > 1)
                  DialCard(
                    children: <Widget>[
                      CardRow(
                        label: OlderNotesPage.keepAll,
                        onTap: () => _keepAll(shown, byEntry, byID),
                      ),
                    ],
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Reading extends StatelessWidget {
  const _Reading({required this.onStop});

  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: DialSpace.l),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const ClaudeWorkingCard(
          status: OlderNotesPage.reading,
          detail:
              'One note at a time. You can leave this page; '
              'what is read is kept.',
        ),
        DialCard(
          children: <Widget>[
            CardRow(label: OlderNotesPage.stop, danger: true, onTap: onStop),
          ],
        ),
      ],
    ),
  );
}

class _Start extends StatelessWidget {
  const _Start({
    required this.notes,
    required this.left,
    required this.problem,
    required this.reviewing,
    required this.onRead,
  });

  final OlderNotes notes;
  final int left;
  final OlderNotesProblem? problem;
  final bool reviewing;
  final void Function(BuildContext from, List<ViceActivity> batch) onRead;

  @override
  Widget build(BuildContext context) {
    final int next = <int>[
      olderNotesBatch,
      notes.unread.length,
      left,
    ].reduce((int a, int b) => a < b ? a : b);
    final String skipped = OlderNotesPage.skipped(
      locked: notes.locked,
      full: notes.full,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (problem case final OlderNotesProblem p)
          Padding(
            padding: const EdgeInsets.only(top: DialSpace.l),
            child: InfoBox(
              message: switch (p) {
                OlderNotesProblem.enoughToday => OlderNotesPage.enoughToday,
                OlderNotesProblem.failed => OlderNotesPage.failed,
                OlderNotesProblem.noKey => OlderNotesPage.noKey,
              },
              isError: p == OlderNotesProblem.failed,
            ),
          ),
        CardFoot(OlderNotesPage.unread(notes.unread.length)),
        if (notes.unread.isNotEmpty) ...<Widget>[
          const CardFoot(OlderNotesPage.sends),
          if (reviewing)
            const CardFoot(OlderNotesPage.reviewFirst)
          else if (next > 0)
            DialCard(
              children: <Widget>[
                Builder(
                  builder: (BuildContext from) => CardRow(
                    label: OlderNotesPage.readNext(next),
                    glyph: DialGlyph.right,
                    onTap: () => onRead(from, notes.unread.take(next).toList()),
                  ),
                ),
              ],
            ),
          CardFoot(OlderNotesPage.perDay(left)),
        ],
        if (skipped.isNotEmpty) CardFoot('$skipped.'),
      ],
    );
  }
}

/// One read note: its habit and day, the note with each ticked tag's quote
/// marked, and a row per proposed tag with the words behind it.
class _NoteReview extends StatelessWidget {
  const _NoteReview({
    super.key,
    required this.entry,
    required this.habit,
    required this.tags,
    required this.unticked,
    required this.onTick,
    required this.onKeep,
    required this.onDrop,
  });

  final ViceActivity entry;
  final String? habit;
  final List<ReadTag> tags;
  final Set<String> unticked;
  final void Function(String path, bool on) onTick;
  final VoidCallback onKeep;
  final VoidCallback onDrop;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String note = entry.note ?? '';
    final List<String> quotes = <String>[
      for (final ReadTag t in tags)
        if (!unticked.contains(t.path)) t.quote,
    ];
    return DialCard(
      top: DialSpace.s,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(
            DialSpace.l,
            DialSpace.m,
            DialSpace.l,
            DialSpace.xs,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '${habit ?? 'Entry'} · ${formatShortDay(entry.createdAt.toDate())}',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: DialSpace.xs),
              Text.rich(
                markQuotes(note, quotes, theme),
                style: theme.textTheme.bodyLarge,
              ),
            ],
          ),
        ),
        for (final ReadTag t in tags)
          CheckboxListTile(
            value: !unticked.contains(t.path),
            onChanged: (bool? on) => onTick(t.path, on ?? false),
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(triggerLabels(t.path)?.join(' › ') ?? t.path),
            subtitle: Text('“${t.quote}”'),
          ),
        if (tags.isEmpty)
          const Padding(
            padding: EdgeInsets.all(DialSpace.l),
            child: Text('Its tags are already on the entry.'),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            DialSpace.s,
            0,
            DialSpace.s,
            DialSpace.xs,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: <Widget>[
              TextButton(
                onPressed: onDrop,
                child: const Text(OlderNotesPage.drop),
              ),
              TextButton(
                onPressed: onKeep,
                child: const Text(OlderNotesPage.keep),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// [note] with each of [quotes] (its first place) underlined in ink.
TextSpan markQuotes(String note, List<String> quotes, ThemeData theme) {
  final List<(int, int)> ranges = <(int, int)>[];
  for (final String q in quotes) {
    final int at = note.indexOf(q);
    if (at >= 0 && q.isNotEmpty) ranges.add((at, at + q.length));
  }
  ranges.sort(((int, int) a, (int, int) b) => a.$1.compareTo(b.$1));
  final TextStyle marked = TextStyle(
    fontWeight: FontWeight.w600,
    decoration: TextDecoration.underline,
    decorationColor: theme.colorScheme.primary,
  );
  final List<TextSpan> spans = <TextSpan>[];
  int from = 0;
  for (final (int start, int end) in ranges) {
    if (end <= from) continue;
    final int s = start < from ? from : start;
    if (s > from) spans.add(TextSpan(text: note.substring(from, s)));
    spans.add(TextSpan(text: note.substring(s, end), style: marked));
    from = end;
  }
  if (from < note.length) spans.add(TextSpan(text: note.substring(from)));
  return TextSpan(children: spans);
}
