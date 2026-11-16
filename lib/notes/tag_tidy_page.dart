import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/account/claude_access.dart';
import 'package:tracker/claude/claude_working.dart';
import 'package:tracker/data/day_note.dart';
import 'package:tracker/data/free_text_triggers.dart';
import 'package:tracker/data/trigger_tree.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/design/dial_icons.dart';
import 'package:tracker/design/tokens.dart';
import 'package:tracker/errors/report_error.dart';
import 'package:tracker/formats.dart';
import 'package:tracker/insights/insights_report.dart';
import 'package:tracker/notes/older_notes.dart';
import 'package:tracker/notes/tag_tidy.dart';
import 'package:tracker/providers/day_note_provider.dart';
import 'package:tracker/providers/today_provider.dart';
import 'package:tracker/providers/tracker_writes_provider.dart';
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/providers/vice_activity_day_provider.dart';
import 'package:tracker/widgets/info_box.dart';
import 'package:tracker/widgets/settings_card.dart';
import 'package:tracker/writes/rejected_writes.dart';
import 'package:tracker/writes/tracker_writes.dart';

/// The Settings row opening [TagTidyPage].
class TagTidyRow extends ConsumerWidget {
  const TagTidyRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(claudeAllowedProvider)) {
      return const ClaudeNeedsEmailRow(label: TagTidyPage.title);
    }
    return CardRow(
      label: TagTidyPage.title,
      subtitle: TagTidyPage.rowSubtitle,
      glyph: DialGlyph.right,
      onTap: () => Navigator.of(context).pushNamed(TagTidyPage.route),
    );
  }
}

/// Own-words tags shown first, sent alone only when the person says so, and
/// each proposed merge applied only once approved.
class TagTidyPage extends ConsumerStatefulWidget {
  const TagTidyPage({super.key});

  static const String route = '/settings/tidy-tags';
  static const String title = 'Tidy my tags';
  static const String rowSubtitle =
      'Suggests merges for tags you typed in your own words.';
  static const String off =
      'This needs a verified email, and isn’t available in this build.';
  static const String readFailed = 'Penchant couldn’t read your journal.';
  static const String tooFew =
      'Nothing to tidy yet: you have fewer than two tags in your own words.';
  static const Object resultTag = ('tidy-tags', 'suggestions');

  static String found(int labels) =>
      'You have ${formatCount(labels)} '
      '${pluralWord(labels, one: 'tag', other: 'tags')} in your own words.';
  static String onlyMost(int sent) =>
      'The ${formatCount(sent)} most used are sent; the rest stay as they are.';
  static const String sends =
      'Only the labels below are sent to Penchant’s server and on to '
      'Anthropic’s Claude, which suggests merges for you to approve. No '
      'entries, dates, amounts or notes go with them, but a label can say a '
      'lot on its own: check the list first. Anthropic does not use them for '
      'training and deletes them within 30 days.';
  static String send(int n) =>
      'Send ${formatCount(n)} ${pluralWord(n, one: 'label', other: 'labels')} to Claude';
  static const String sending = 'Sent your tags';
  static const String failed =
      'Claude couldn’t suggest anything this time. Try again later.';
  static const String enoughToday =
      'That’s enough tidying for today. Try again tomorrow.';
  static const String noSuggestions =
      'Claude found nothing to merge. Your tags stay as they are.';
  static const String suggestions = 'Suggestions';
  static const String accept = 'Accept';
  static const String skip = 'Skip';
  static String uses(OwnWords? w) {
    if (w == null) return '';
    final int n = w.entries + w.dayNotes;
    return '${formatCount(n)} ${pluralWord(n, one: 'use', other: 'uses')}';
  }

  static String apply(int n) =>
      'Apply ${formatCount(n)} accepted '
      '${pluralWord(n, one: 'change', other: 'changes')}';
  static String applyTitle(int entries, int notes) {
    final String places = <String>[
      if (entries > 0)
        '${formatCount(entries)} ${pluralWord(entries, one: 'entry', other: 'entries')}',
      if (notes > 0)
        '${formatCount(notes)} ${pluralWord(notes, one: 'day note', other: 'day notes')}',
    ].join(' and ');
    return 'Change the tags on $places?';
  }

  static const String applyBody =
      'This can’t be undone in one step. To change one back, open the entry '
      'or day note and edit its tags.';
  static const String change = 'Change';
  static const String cancel = 'Cancel';
  static String applied(TagSaves s) {
    final int ok = s.saved + s.queued;
    return <String>[
      'Changed the tags on ${formatCount(ok)} '
          '${pluralWord(ok, one: 'place', other: 'places')}'
          '${s.queued > 0 ? ', some to sync when online' : ''}.',
      if (s.failed > 0)
        '${formatCount(s.failed)} not changed: '
            'open ${pluralWord(s.failed, one: 'it', other: 'them')} to edit by hand.',
    ].join(' ');
  }

  static String targetLabel(TidySuggestion s) => s.path != null
      ? triggerLabels(s.path!)?.join(' › ') ?? s.path!
      : '“${s.label}”';

  @override
  ConsumerState<TagTidyPage> createState() => _TagTidyPageState();
}

class _TagTidyPageState extends ConsumerState<TagTidyPage> {
  int _generation = 0;
  bool _sending = false;
  bool _applying = false;
  String? _problem;
  String? _done;
  List<TidySuggestion>? _suggestions;
  final Set<int> _accepted = <int>{};

  Future<void> _send(BuildContext from, List<String> labels) async {
    final TagTidier? tidier = ref.read(tagTidierProvider);
    if (tidier == null || _sending) return;
    final int generation = ++_generation;
    final ClaudeWork work = ClaudeWork(status: TagTidyPage.sending);
    unawaited(
      showClaudeWorking(
        from,
        work,
        resultTag: TagTidyPage.resultTag,
        onStop: () {
          _generation++;
          if (mounted) setState(() => _sending = false);
        },
      ),
    );
    setState(() {
      _sending = true;
      _problem = null;
      _done = null;
    });
    List<TidySuggestion>? got;
    String? problem;
    try {
      got = await tidier.tidy(labels);
    } on FirebaseFunctionsException catch (e) {
      problem = e.code == 'resource-exhausted'
          ? TagTidyPage.enoughToday
          : TagTidyPage.failed;
    } catch (_) {
      problem = TagTidyPage.failed;
    }
    // Stopped, or the page has gone: the answer is dropped unseen.
    if (generation != _generation || !mounted) {
      work.finish(ClaudeWorkEnd.stopped);
      return;
    }
    setState(() {
      _sending = false;
      _problem = problem;
      _suggestions = got;
      _accepted.clear();
    });
    work.finish(got == null ? ClaudeWorkEnd.failed : ClaudeWorkEnd.answered);
  }

  Future<void> _apply(
    List<ViceActivity> entries,
    List<DayNote> dayNotes,
  ) async {
    final List<TidySuggestion> all = _suggestions ?? const <TidySuggestion>[];
    final Map<String, String> map = tidyMap(<TidySuggestion>[
      for (final int i in _accepted.toList()..sort()) all[i],
    ]);
    if (map.isEmpty) return;
    final List<ViceActivity> hitEntries = <ViceActivity>[
      for (final ViceActivity e in entries)
        if (!e.locked && touches(e.triggers, map)) e,
    ];
    final List<DayNote> hitNotes = <DayNote>[
      for (final DayNote n in dayNotes)
        if (!n.locked && touches(n.triggers, map)) n,
    ];
    final bool? sure = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(TagTidyPage.applyTitle(hitEntries.length, hitNotes.length)),
        content: const Text(TagTidyPage.applyBody),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(TagTidyPage.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(TagTidyPage.change),
          ),
        ],
      ),
    );
    if (!(sure ?? false) || !mounted) return;
    setState(() => _applying = true);
    final TrackerWrites writes = ref.read(trackerWritesProvider);
    final RejectedWrites rejected = ref.read(rejectedWritesProvider.notifier);
    final List<TagSave> saves = await Future.wait(<Future<TagSave>>[
      for (final ViceActivity e in hitEntries)
        setTriggers(
          writes,
          rejected,
          e,
          (List<String> t) => tidied(t, map),
          'Tags not tidied: an entry of ${formatShortDay(e.createdAt.toDate())}',
        ),
      for (final DayNote n in hitNotes) _tidyDayNote(writes, rejected, n, map),
    ]);
    final String? uid = ref.read(userProvider).value?.uid;
    if (uid != null) {
      try {
        await const FreeTextTriggers().rename(uid, map, isOwnWords: isOwnWords);
      } catch (e, stack) {
        reportError(e, stack, context: 'while renaming own-words tag counts');
      }
    }
    if (!mounted) return;
    setState(() {
      _applying = false;
      _done = TagTidyPage.applied(countSaves(saves));
      _suggestions = null;
      _accepted.clear();
    });
  }

  Future<TagSave> _tidyDayNote(
    TrackerWrites writes,
    RejectedWrites rejected,
    DayNote note,
    Map<String, String> map,
  ) async {
    if (!writes.canCreate) return TagSave.failed;
    try {
      return await rejected.settle(
            writes.setDayNote(
              ownerID: note.ownerID,
              day: note.day,
              text: note.text,
              triggers: tidied(note.triggers, map),
              followUp: note.followUp,
              replacing: note,
            ),
            'Tags not tidied: the note of ${note.day}',
          )
          ? TagSave.saved
          : TagSave.queued;
    } on FirebaseException catch (e, stack) {
      reportError(e, stack, context: 'while tidying a day note’s tags');
      return TagSave.failed;
    }
  }

  @override
  Widget build(BuildContext context) {
    final TagTidier? tidier = ref.watch(tagTidierProvider);
    if (tidier == null) {
      return const CardPage(
        title: TagTidyPage.title,
        children: <Widget>[CardFoot(TagTidyPage.off)],
      );
    }
    final DateTime today = ref.watch(todayProvider);
    final AsyncValue<List<ViceActivity>> journal = ref.watch(
      viceActivityRangeProvider(insightsRange(today)),
    );
    final AsyncValue<List<DayNote>> notes = ref.watch(allDayNotesProvider);
    if ((journal.hasError && !journal.hasValue) ||
        (notes.hasError && !notes.hasValue)) {
      return const CardPage(
        title: TagTidyPage.title,
        children: <Widget>[
          InfoBox(message: TagTidyPage.readFailed, isError: true),
        ],
      );
    }
    final List<ViceActivity>? entries = journal.value;
    final List<DayNote>? dayNotes = notes.value;
    if (entries == null || dayNotes == null) {
      return const CardPage(
        title: TagTidyPage.title,
        children: <Widget>[
          Padding(
            padding: EdgeInsets.all(DialSpace.xl),
            child: Center(child: CircularProgressIndicator.adaptive()),
          ),
        ],
      );
    }
    final List<OwnWords> words = ownWords(entries, dayNotes);
    final Map<String, OwnWords> byLabel = <String, OwnWords>{
      for (final OwnWords w in words) w.label: w,
    };
    final List<String> labels = <String>[
      for (final OwnWords w in words.take(tidyMaxLabels)) w.label,
    ];
    final List<TidySuggestion>? suggestions = _suggestions;
    return CardPage(
      title: TagTidyPage.title,
      children: <Widget>[
        if (_done case final String done)
          Padding(
            padding: const EdgeInsets.only(top: DialSpace.l),
            child: InfoBox(message: done),
          ),
        if (_problem case final String problem)
          Padding(
            padding: const EdgeInsets.only(top: DialSpace.l),
            child: InfoBox(message: problem, isError: true),
          ),
        if (suggestions != null)
          ClaudeWorkingResult(
            tag: TagTidyPage.resultTag,
            child: _Suggestions(
              suggestions: suggestions,
              accepted: _accepted,
              byLabel: byLabel,
              applying: _applying,
              onToggle: (int i, bool on) =>
                  setState(() => on ? _accepted.add(i) : _accepted.remove(i)),
              onApply: () => _apply(entries, dayNotes),
            ),
          )
        else if (_sending)
          const Padding(
            padding: EdgeInsets.only(top: DialSpace.l),
            child: ClaudeWorkingCard(status: TagTidyPage.sending),
          )
        else if (labels.length < 2)
          const CardFoot(TagTidyPage.tooFew)
        else ...<Widget>[
          CardFoot(TagTidyPage.found(words.length)),
          if (words.length > tidyMaxLabels)
            CardFoot(TagTidyPage.onlyMost(tidyMaxLabels)),
          const CardFoot(TagTidyPage.sends),
          DialCard(
            children: <Widget>[
              Builder(
                builder: (BuildContext from) => CardRow(
                  label: TagTidyPage.send(labels.length),
                  glyph: DialGlyph.right,
                  onTap: () => _send(from, labels),
                ),
              ),
            ],
          ),
          _LabelList(words: words.take(tidyMaxLabels).toList()),
        ],
      ],
    );
  }
}

/// The labels exactly as they would be sent, with how often each is used
/// (which is not sent).
class _LabelList extends StatelessWidget {
  const _LabelList({required this.words});

  final List<OwnWords> words;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return DialCard(
      top: DialSpace.s,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.all(DialSpace.l),
          child: Wrap(
            spacing: DialSpace.xs,
            runSpacing: DialSpace.xs,
            children: <Widget>[
              for (final OwnWords w in words)
                Semantics(
                  label: '${w.label}, ${TagTidyPage.uses(w)}',
                  excludeSemantics: true,
                  child: Chip(
                    label: Text.rich(
                      TextSpan(
                        text: w.label,
                        children: <InlineSpan>[
                          TextSpan(
                            text: '  ${w.entries + w.dayNotes}',
                            style: TextStyle(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Suggestions extends StatelessWidget {
  const _Suggestions({
    required this.suggestions,
    required this.accepted,
    required this.byLabel,
    required this.applying,
    required this.onToggle,
    required this.onApply,
  });

  final List<TidySuggestion> suggestions;
  final Set<int> accepted;
  final Map<String, OwnWords> byLabel;
  final bool applying;
  final void Function(int index, bool on) onToggle;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    if (suggestions.isEmpty) {
      return const CardFoot(TagTidyPage.noSuggestions);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const CardSectionLabel(TagTidyPage.suggestions),
        for (int i = 0; i < suggestions.length; i++)
          DialCard(
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
                    for (final String from in suggestions[i].from)
                      Text(
                        '“$from”  ${TagTidyPage.uses(byLabel[from])}',
                        style: theme.textTheme.bodyLarge,
                      ),
                    const SizedBox(height: DialSpace.xxs),
                    Text(
                      '→ ${TagTidyPage.targetLabel(suggestions[i])}',
                      style: theme.textTheme.titleMedium,
                    ),
                  ],
                ),
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
                      onPressed: () => onToggle(i, false),
                      child: Text(
                        TagTidyPage.skip,
                        style: TextStyle(
                          fontWeight: accepted.contains(i)
                              ? FontWeight.w400
                              : FontWeight.w700,
                        ),
                      ),
                    ),
                    Semantics(
                      selected: accepted.contains(i),
                      child: accepted.contains(i)
                          ? FilledButton(
                              onPressed: () => onToggle(i, false),
                              child: const Text(TagTidyPage.accept),
                            )
                          : OutlinedButton(
                              onPressed: () => onToggle(i, true),
                              child: const Text(TagTidyPage.accept),
                            ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        DialCard(
          children: <Widget>[
            CardRow(
              label: TagTidyPage.apply(accepted.length),
              enabled: accepted.isNotEmpty && !applying,
              onTap: accepted.isNotEmpty && !applying ? onApply : null,
            ),
          ],
        ),
      ],
    );
  }
}
