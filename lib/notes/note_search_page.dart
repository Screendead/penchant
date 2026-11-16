import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/data/day_note.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/deleted_habit_page.dart';
import 'package:tracker/design/dial_icons.dart';
import 'package:tracker/design/dial_theme.dart';
import 'package:tracker/design/habit_mark.dart';
import 'package:tracker/design/tokens.dart';
import 'package:tracker/errors/report_error.dart';
import 'package:tracker/formats.dart';
import 'package:tracker/insights/insights_report.dart';
import 'package:tracker/notes/note_meaning.dart';
import 'package:tracker/notes/note_search.dart';
import 'package:tracker/providers/day_note_provider.dart';
import 'package:tracker/providers/today_provider.dart';
import 'package:tracker/providers/vice_activity_day_provider.dart';
import 'package:tracker/providers/vice_list_provider.dart';
import 'package:tracker/widgets/bead_painter.dart';
import 'package:tracker/widgets/dial_page.dart';
import 'package:tracker/widgets/settings_card.dart' show CardRow;

/// Search over entry notes, day notes and follow-up answers, on the device.
class NoteSearchPage extends ConsumerStatefulWidget {
  const NoteSearchPage({super.key});

  static const String route = '/search';
  static const String title = 'Search notes';
  static const String fieldLabel = 'Search your notes';
  static const String hint = 'the wedding, when work was awful';
  static const String onDevice =
      'Searched on this device. Nothing you type here is sent anywhere.';
  static const String emptyPrompt =
      'Type a word or two to find it in your entry notes, day notes and the '
      'answers to follow-up questions.';
  static const String noNotes =
      'No notes yet. Notes you add to entries and days are searched here.';
  static const String loading = 'Opening your notes';
  static const String failed = 'Your notes could not be read.';
  static const String retry = 'Try again';
  static const String someWords = 'Some of the words';
  static const String closeInMeaning = 'Close in meaning';
  static const String closeInMeaningNote =
      'Found by Apple’s on-device model. Often loose: check before relying '
      'on it.';
  static const String meaningLabel = 'Also search by meaning';
  static const String meaningSubtitle =
      'Adds notes worded differently, from Apple’s model on this device. '
      'Rough: in a trial it found few that words missed.';
  static const String dayNoteLabel = 'Day note';
  static const String deletedHabit = 'Deleted habit';
  static const int shownLimit = 100;

  static String noResults(String query) => 'No note has “${query.trim()}”.';

  static String lockedLine(int n) =>
      '${formatCount(n)} ${pluralWord(n, one: 'entry or day note is', other: 'entries and day notes are')} '
      'locked on this device and not searched.';

  static String countLine(int n) =>
      '${formatCount(n)} ${pluralWord(n, one: 'note', other: 'notes')}';

  @override
  ConsumerState<NoteSearchPage> createState() => _NoteSearchPageState();
}

class _NoteSearchPageState extends ConsumerState<NoteSearchPage> {
  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;

  // The index is made once per journal read, not on each keystroke.
  List<ViceActivity>? _indexedEntries;
  List<DayNote>? _indexedDayNotes;
  NoteCorpus? _corpus;
  List<IndexedNote> _index = const <IndexedNote>[];

  String _query = '';
  String? _meaningQuery;
  Map<String, double>? _similarities;
  bool _meaningBusy = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_changed);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _changed() {
    final String query = _controller.text;
    if (query == _query) return;
    setState(() => _query = query);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), _searchMeaning);
  }

  bool get _meaningOn =>
      ref.read(meaningSearchProvider) &&
      (ref.read(meaningAvailableProvider).value ?? false);

  Future<void> _searchMeaning() async {
    final String query = _query.trim();
    final NoteCorpus? corpus = _corpus;
    if (!_meaningOn || corpus == null || queryWords(query).isEmpty) return;
    if (query == _meaningQuery && _similarities != null) return;
    setState(() => _meaningBusy = true);
    try {
      final Map<String, double> found = await ref
          .read(meaningIndexProvider)
          .similarities(query, corpus.notes);
      if (!mounted || _query.trim() != query) return;
      setState(() {
        _meaningQuery = query;
        _similarities = found;
      });
    } catch (e, stack) {
      // The context only: nothing the person wrote goes into a report.
      reportError(e, stack, context: 'while searching notes by meaning');
    } finally {
      if (mounted) setState(() => _meaningBusy = false);
    }
  }

  void _retry() {
    ref.invalidate(viceActivityRangeForUserProvider);
    ref.invalidate(allDayNotesForUserProvider);
  }

  void _reindex(List<ViceActivity> entries, List<DayNote> dayNotes) {
    if (identical(entries, _indexedEntries) &&
        identical(dayNotes, _indexedDayNotes)) {
      return;
    }
    _indexedEntries = entries;
    _indexedDayNotes = dayNotes;
    final NoteCorpus corpus = noteCorpus(entries, dayNotes);
    _corpus = corpus;
    _index = <IndexedNote>[
      for (final SearchableNote n in corpus.notes) IndexedNote(n),
    ];
    _meaningQuery = null;
    _similarities = null;
  }

  @override
  Widget build(BuildContext context) {
    final DateTime today = ref.watch(todayProvider);
    final AsyncValue<List<ViceActivity>> entries = ref.watch(
      viceActivityRangeProvider(insightsRange(today)),
    );
    final AsyncValue<List<DayNote>> dayNotes = ref.watch(allDayNotesProvider);
    final List<Vice> vices =
        ref.watch(viceListProvider).value ?? const <Vice>[];
    final bool meaningAvailable =
        ref.watch(meaningAvailableProvider).value ?? false;
    final bool meaningOn = meaningAvailable && ref.watch(meaningSearchProvider);
    ref.listen(meaningSearchProvider, (_, bool on) {
      if (on) _searchMeaning();
    });

    final DialColors colors = DialColors.of(context);
    final List<ViceActivity>? entryList = entries.value;
    final List<DayNote>? dayNoteList = dayNotes.value;
    if (entryList != null && dayNoteList != null) {
      _reindex(entryList, dayNoteList);
    }
    final bool failed =
        (entries.hasError && entryList == null) ||
        (dayNotes.hasError && dayNoteList == null);

    final List<Widget> body;
    if (failed) {
      body = <Widget>[
        _Message(text: NoteSearchPage.failed),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton(
            onPressed: _retry,
            child: const Text(NoteSearchPage.retry),
          ),
        ),
      ];
    } else if (_corpus == null) {
      body = const <Widget>[_Loading()];
    } else {
      body = _results(context, vices, meaningOn: meaningOn);
    }

    return DialPage(
      title: NoteSearchPage.title,
      children: <Widget>[
        const SizedBox(height: DialSpace.m),
        TextField(
          controller: _controller,
          autofocus: true,
          textInputAction: TextInputAction.search,
          style: DialTypeScale.body,
          decoration: InputDecoration(
            labelText: NoteSearchPage.fieldLabel,
            floatingLabelBehavior: FloatingLabelBehavior.never,
            hintText: NoteSearchPage.hint,
            filled: true,
            fillColor: colors.surface2,
            prefixIcon: Padding(
              padding: const EdgeInsetsDirectional.only(start: 14, end: 8),
              child: StrokeIcon(
                DialGlyph.search,
                size: 18,
                color: colors.muted,
              ),
            ),
            prefixIconConstraints: const BoxConstraints(minWidth: 40),
            suffixIcon: _query.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear',
                    onPressed: _controller.clear,
                    icon: StrokeIcon(
                      DialGlyph.close,
                      size: 16,
                      color: colors.muted,
                    ),
                  ),
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
        Padding(
          padding: const EdgeInsets.fromLTRB(4, DialSpace.xs, 4, 0),
          child: Text(
            NoteSearchPage.onDevice,
            style: DialTypeScale.bodyS.copyWith(color: colors.muted),
          ),
        ),
        ...body,
        if (meaningAvailable)
          Padding(
            padding: const EdgeInsets.only(top: DialSpace.xl),
            child: _MeaningSwitch(on: meaningOn),
          ),
      ],
    );
  }

  List<Widget> _results(
    BuildContext context,
    List<Vice> vices, {
    required bool meaningOn,
  }) {
    final NoteCorpus corpus = _corpus!;
    final List<Widget> locked = <Widget>[
      if (corpus.locked > 0)
        _Message(text: NoteSearchPage.lockedLine(corpus.locked), small: true),
    ];
    if (corpus.notes.isEmpty) {
      return <Widget>[_Message(text: NoteSearchPage.noNotes), ...locked];
    }
    if (queryWords(_query).isEmpty) {
      return <Widget>[
        _Message(text: NoteSearchPage.emptyPrompt),
        _Message(
          text: '${NoteSearchPage.countLine(corpus.notes.length)} to search.',
          small: true,
        ),
        ...locked,
      ];
    }
    final List<NoteMatch> matches = searchNotes(
      _index,
      _query,
      similarities: meaningOn && _meaningQuery == _query.trim()
          ? _similarities
          : null,
    );
    final bool busy = meaningOn && _meaningBusy;
    if (matches.isEmpty) {
      return <Widget>[
        if (busy)
          const _Loading()
        else
          _Message(text: NoteSearchPage.noResults(_query)),
        ...locked,
      ];
    }
    final Map<String, HabitMark> marks = habitMarks(vices);
    final Map<String, Vice> byID = <String, Vice>{
      for (final Vice v in vices) v.id: v,
    };
    final List<NoteMatch> shown = matches
        .take(NoteSearchPage.shownLimit)
        .toList();
    final List<Widget> rows = <Widget>[];
    String? section;
    DateTime? day;
    for (final NoteMatch m in shown) {
      final String? heading = switch (m.tier) {
        MatchTier.phrase || MatchTier.allWords => null,
        MatchTier.someWords => NoteSearchPage.someWords,
        MatchTier.meaning => NoteSearchPage.closeInMeaning,
      };
      if (heading != null && heading != section) {
        section = heading;
        day = null;
        rows.add(
          _SectionHeading(
            text: heading,
            note: m.tier == MatchTier.meaning
                ? NoteSearchPage.closeInMeaningNote
                : null,
          ),
        );
      }
      if (m.note.day != day) {
        day = m.note.day;
        rows.add(_DayHeading(day: m.note.day));
      }
      final Vice? vice = m.note.viceID == null ? null : byID[m.note.viceID];
      rows.add(
        _ResultRow(
          match: m,
          vice: vice,
          mark: vice == null ? null : marks[vice.id],
        ),
      );
    }
    return <Widget>[
      _Message(
        text: matches.length > shown.length
            ? 'The first ${formatCount(shown.length)} of '
                  '${NoteSearchPage.countLine(matches.length)}'
            : NoteSearchPage.countLine(matches.length),
        small: true,
        liveRegion: true,
      ),
      ...rows,
      if (busy) const _Loading(),
      ...locked,
    ];
  }
}

class _MeaningSwitch extends ConsumerWidget {
  const _MeaningSwitch({required this.on});

  final bool on;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void set(bool value) =>
        ref.read(meaningSearchProvider.notifier).choose(value);
    return MergeSemantics(
      child: CardRow(
        label: NoteSearchPage.meaningLabel,
        subtitle: NoteSearchPage.meaningSubtitle,
        onTap: () => set(!on),
        trailing: Switch.adaptive(
          value: on,
          activeTrackColor: Theme.of(context).colorScheme.primary,
          onChanged: set,
        ),
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: DialSpace.xl),
    child: Semantics(
      label: NoteSearchPage.loading,
      child: const Center(child: CircularProgressIndicator()),
    ),
  );
}

class _Message extends StatelessWidget {
  const _Message({
    required this.text,
    this.small = false,
    this.liveRegion = false,
  });

  final String text;
  final bool small;
  final bool liveRegion;

  @override
  Widget build(BuildContext context) {
    final DialColors colors = DialColors.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(4, small ? DialSpace.s : DialSpace.xl, 4, 0),
      child: Semantics(
        liveRegion: liveRegion,
        child: Text(
          text,
          style: small
              ? DialTypeScale.bodyS.copyWith(color: colors.muted)
              : DialTypeScale.body.copyWith(
                  color: Theme.of(context).colorScheme.onSurface,
                ),
        ),
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.text, this.note});

  final String text;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final DialColors colors = DialColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, DialSpace.xxl, 4, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Semantics(
            header: true,
            child: Text(
              text,
              style: DialTypeScale.displayM.copyWith(
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
          if (note != null)
            Padding(
              padding: const EdgeInsets.only(top: DialSpace.xxs),
              child: Text(
                note!,
                style: DialTypeScale.bodyS.copyWith(color: colors.muted),
              ),
            ),
        ],
      ),
    );
  }
}

class _DayHeading extends StatelessWidget {
  const _DayHeading({required this.day});

  final DateTime day;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, DialSpace.l, 4, DialSpace.xxs),
    child: Semantics(
      header: true,
      child: Text(
        formatDay(day),
        style: DialTypeScale.label.copyWith(
          color: DialColors.of(context).muted,
        ),
      ),
    ),
  );
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({required this.match, this.vice, this.mark});

  final NoteMatch match;
  final Vice? vice;
  final HabitMark? mark;

  // Long notes start near their first match, so it is on screen.
  static const int lead = 60;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final DialColors colors = DialColors.of(context);
    final SearchableNote note = match.note;
    final bool isEntry =
        note.source == NoteSource.entry ||
        note.source == NoteSource.entryAnswer;
    final String who = isEntry
        ? (vice == null
              ? NoteSearchPage.deletedHabit
              : vice!.locked
              ? NoteSearchPage.deletedHabit
              : vice!.name)
        : NoteSearchPage.dayNoteLabel;
    final String when = isEntry
        ? formatTime(
            note.at,
            alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
          )
        : '';
    final String? question = note.question;

    int from = 0;
    if (match.highlights.isNotEmpty && match.highlights.first.$1 > lead + 20) {
      final int cut = note.text.lastIndexOf(
        ' ',
        match.highlights.first.$1 - lead,
      );
      from = cut < 0 ? 0 : cut + 1;
    }
    final TextStyle base = DialTypeScale.body.copyWith(color: scheme.onSurface);
    final TextStyle hit = base.copyWith(
      fontWeight: FontWeight.w700,
      backgroundColor: scheme.secondaryContainer,
      color: scheme.onSecondaryContainer,
    );
    final List<InlineSpan> spans = <InlineSpan>[
      if (from > 0) TextSpan(text: '…', style: base),
    ];
    int at = from;
    for (final (int s, int e) in match.highlights) {
      if (e <= at) continue;
      final int start = s < at ? at : s;
      if (start > at) {
        spans.add(TextSpan(text: note.text.substring(at, start), style: base));
      }
      spans.add(TextSpan(text: note.text.substring(start, e), style: hit));
      at = e;
    }
    if (at < note.text.length) {
      spans.add(TextSpan(text: note.text.substring(at), style: base));
    }

    final String semantic = <String>[
      who,
      if (when.isNotEmpty) when,
      if (question != null) 'answer to $question',
      note.text,
    ].join(', ');

    return Semantics(
      button: true,
      label: semantic,
      hint: isEntry ? 'Opens the entry' : 'Opens the day note',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(DialRadius.tile),
        onTap: () => Navigator.of(context).pushNamed(note.route),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, DialSpace.xs, 4, DialSpace.xs),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.only(top: 4, right: DialSpace.s),
                child: SizedBox.square(
                  dimension: 14,
                  child: !isEntry
                      ? StrokeIcon(
                          DialGlyph.pencil,
                          size: 14,
                          color: colors.muted,
                        )
                      : mark == null
                      ? const DeletedHabitPip(size: 14)
                      : HabitPip(mark: mark!, size: 14),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      when.isEmpty ? who : '$who · $when',
                      style: DialTypeScale.label.copyWith(color: colors.muted),
                    ),
                    if (question != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          question,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: DialTypeScale.bodyS.copyWith(
                            color: colors.muted,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    const SizedBox(height: 2),
                    Text.rich(
                      TextSpan(children: spans),
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
