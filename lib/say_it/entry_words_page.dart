import 'dart:async';

import 'package:clock/clock.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/claude/claude_working.dart';
import 'package:tracker/data/activity_content.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/data/trigger_tree.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/design/dial_icons.dart';
import 'package:tracker/design/dial_theme.dart';
import 'package:tracker/design/tokens.dart';
import 'package:tracker/errors/report_error.dart';
import 'package:tracker/formats.dart';
import 'package:tracker/providers/habit_summary_provider.dart';
import 'package:tracker/providers/tracker_writes_provider.dart';
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/providers/vice_list_provider.dart';
import 'package:tracker/say_it/entry_reader.dart';
import 'package:tracker/say_it/speech.dart';
import 'package:tracker/widgets/settings_card.dart';
import 'package:tracker/widgets/undo_bar.dart';
import 'package:tracker/writes/log_one.dart';
import 'package:tracker/writes/rejected_writes.dart';
import 'package:tracker/writes/settle_write.dart';
import 'package:tracker/writes/tracker_writes.dart';

/// Say it to log ([EntryMode.now]) and Catch up ([EntryMode.days]): the
/// person's words, read by Claude into draft entries, which the person
/// checks, edits or removes before anything is written.
class EntryWordsPage extends ConsumerStatefulWidget {
  const EntryWordsPage({super.key, required this.mode, this.initialDays});

  final EntryMode mode;

  /// Catch up's picked days, for tests and renders; else yesterday.
  final List<DateTime>? initialDays;

  static const String sayRoute = '/say-it';
  static const Key micKey = ValueKey<String>('say-it-mic');
  static const String catchUpRoute = '/catch-up';

  static const String sayTitle = 'Say it to log';
  static const String catchUpTitle = 'Catch up';
  static const String sayHint =
      'Two pints at the pub with Sam, about an hour ago';
  static const String catchUpHint =
      'Fri about 4 pints from 7. Sat a bottle of wine over dinner, two '
      'coffees. Sun nothing.';
  static const String sayIntro =
      'Say or type what you had. Claude suggests entries; you check them '
      'before anything is saved.';
  static const String catchUpIntro =
      'Pick the days you missed, then describe each one. Claude suggests '
      'entries, marked as caught up; you check them before anything is '
      'saved.';
  static const String fieldLabel = 'What you had';
  static const String daysLabel = 'Days you missed';
  static const String listen = 'Speak';
  static const String stopListening = 'Stop listening';
  static const String listening = 'Listening on this device…';
  static const String speechDenied =
      'Penchant can’t hear you: allow speech recognition and the microphone '
      'in Settings, or type instead.';
  static const String speechFailed = 'Didn’t catch that. Try again or type.';
  static const String read = 'Read it';
  static const String readingStatus = 'Reading your words';
  static const String sentWords = 'Sent your words and your habits’ names';
  static const String couldNotRead =
      'Claude couldn’t read that just now. Your words are still here.';
  static const String enough = 'That’s enough reading for today.';
  static const String noHabits = 'Add a habit first.';
  static const String noneFound =
      'No entries found in that. Name a habit and an amount.';
  static const String startAgain = 'Start again';
  static const String save = 'Save';
  static const String saveAll = 'Save all';
  static const String remove = 'Remove';
  static const String aboveUsual = 'Far above your usual: check the amount';
  static const String off =
      'Turn this on in Settings > Claude to use it. It needs a verified email.';

  static String leftOut(int n) => n == 1
      ? 'One suggestion was left out: it didn’t pass Penchant’s checks.'
      : '$n suggestions were left out: they didn’t pass Penchant’s checks.';

  static String logged(int n) =>
      n == 1 ? 'Logged 1 entry' : 'Logged $n entries';

  @override
  ConsumerState<EntryWordsPage> createState() => _EntryWordsPageState();
}

class _EntryWordsPageState extends ConsumerState<EntryWordsPage> {
  final TextEditingController _text = TextEditingController();
  final GlobalKey _readKey = GlobalKey();
  late final Set<DateTime> _days = <DateTime>{
    for (final DateTime d
        in widget.initialDays ??
            <DateTime>[addDays(startOfDay(clock.now()), -1)])
      startOfDay(d),
  };

  StreamSubscription<String>? _listening;
  SpeechSource? _speech;
  String? _speechNote;
  int _readId = 0;
  bool _reading = false;
  String? _error;
  List<DraftEntry>? _drafts;
  int _dropped = 0;
  bool _saving = false;

  EntryMode get _mode => widget.mode;

  @override
  void dispose() {
    if (_listening != null) unawaited(_speech?.stop());
    unawaited(_listening?.cancel());
    _text.dispose();
    super.dispose();
  }

  Future<void> _toggleListening() async {
    final SpeechSource? speech = _speech ??= ref.read(speechSourceProvider);
    if (speech == null) return;
    if (_listening != null) {
      await speech.stop();
      return;
    }
    final bool allowed = await speech.requestAccess().catchError((_) => false);
    if (!mounted) return;
    if (!allowed) {
      setState(() => _speechNote = EntryWordsPage.speechDenied);
      return;
    }
    final String before = _text.text.trim();
    setState(() => _speechNote = null);
    _listening = speech.listen().listen(
      (String words) {
        _text.text = before.isEmpty ? words : '$before $words';
        _text.selection = TextSelection.collapsed(offset: _text.text.length);
      },
      onError: (Object e) {
        if (mounted) setState(() => _speechNote = EntryWordsPage.speechFailed);
      },
      onDone: () {
        if (mounted) setState(() => _listening = null);
      },
    );
    setState(() {});
  }

  Future<void> _read() async {
    final EntryReader? reader = ref.read(entryReaderProvider(_mode));
    final List<Vice>? vices = ref.read(viceListProvider).value;
    final String text = _text.text.trim();
    if (reader == null || vices == null || text.isEmpty || _reading) return;
    if (text.length > EntryLimits.maxText(_mode)) return;
    if (_listening != null) await _speech?.stop();
    final DateTime now = clock.now();
    final List<DateTime> days = entryDays(_mode, now, days: _days.toList());
    if (days.isEmpty) return;
    final List<({int id, Vice vice})> habits = entryHabits(vices);
    if (habits.isEmpty) {
      setState(() => _error = EntryWordsPage.noHabits);
      return;
    }
    final int id = ++_readId;
    final ClaudeWork work = ClaudeWork(
      subject: text,
      status: EntryWordsPage.readingStatus,
      detail: EntryWordsPage.sentWords,
    );
    bool stopped = false;
    setState(() {
      _reading = true;
      _error = null;
      _drafts = null;
    });
    final BuildContext? from = _readKey.currentContext;
    if (from != null && from.mounted) {
      unawaited(
        showClaudeWorking(
          from,
          work,
          resultTag: ('entries', id),
          onStop: () {
            stopped = true;
            if (mounted && id == _readId) setState(() => _reading = false);
          },
        ),
      );
    }
    ReadEntries? got;
    String failure = EntryWordsPage.couldNotRead;
    try {
      got = await reader.read(
        _mode,
        text,
        now: now,
        days: days,
        habits: habits,
      );
    } on FirebaseFunctionsException catch (e) {
      // Not reported: nothing about the words goes into a report.
      if (e.code == 'resource-exhausted') failure = EntryWordsPage.enough;
    } catch (_) {
      // Not reported, as above.
    }
    // Stopped: whatever came back is dropped unseen.
    if (stopped || !mounted || id != _readId) return;
    work.finish(got == null ? ClaudeWorkEnd.failed : ClaudeWorkEnd.answered);
    setState(() {
      _reading = false;
      if (got == null) {
        _error = failure;
      } else {
        _drafts = List<DraftEntry>.of(got.entries)
          ..sort((DraftEntry a, DraftEntry b) => a.at.compareTo(b.at));
        _dropped = got.dropped;
        if (got.entries.isEmpty) _error = EntryWordsPage.noneFound;
      }
    });
  }

  Future<void> _save() async {
    final List<DraftEntry>? drafts = _drafts;
    if (drafts == null || drafts.isEmpty || _saving) return;
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final bool h24 = MediaQuery.alwaysUse24HourFormatOf(context);
    final User? user = ref.read(userProvider).value;
    final TrackerWrites writes = ref.read(trackerWritesProvider);
    if (user == null) return;
    if (!writes.canCreate) {
      showUndoBar(
        messenger,
        const TextSpan(text: 'Not saved. $noJournalKeyMessage'),
      );
      return;
    }
    final RejectedWrites rejected = ref.read(rejectedWritesProvider.notifier);
    final DateTime now = clock.now();
    setState(() => _saving = true);
    final List<({String id, String entry})> saved =
        <({String id, String entry})>[];
    for (final DraftEntry d in drafts) {
      // An edit cannot move an entry past now; the clock may have.
      final DateTime at = d.at.isAfter(now) ? now : d.at;
      final StoredMeasure m = storedMeasure(d.amount);
      final String id = writes.newActivityID();
      final String entry = describeActivity(
        d.vice.name,
        d.vice.unit,
        d.amount,
        at,
        alwaysUse24HourFormat: h24,
      );
      final SentWrite write = writes.recordActivity(
        id,
        ownerID: user.uid,
        viceID: d.vice.id,
        quantity: m.quantity,
        amount: m.amount,
        createdAt: at,
        triggers: d.triggers,
        note: d.note,
        loggedVia: _mode == EntryMode.now
            ? LoggedVia.spoken
            : LoggedVia.caughtUp,
      );
      saved.add((id: id, entry: entry));
      unawaited(
        rejected
            .settle(write, 'Not saved: $entry')
            .then<void>(
              (_) {},
              onError: (Object e, StackTrace stack) {
                reportError(e, stack, context: 'while saving read entries');
              },
            ),
      );
    }
    showUndoBar(
      messenger,
      TextSpan(text: EntryWordsPage.logged(saved.length)),
      onUndo: () {
        for (final ({String id, String entry}) s in saved) {
          unawaited(undoLog(messenger, writes, rejected, s.id, s.entry));
        }
      },
    );
    if (mounted) Navigator.of(context).maybePop();
  }

  void _startAgain() => setState(() {
    _readId++;
    _drafts = null;
    _dropped = 0;
    _error = null;
  });

  @override
  Widget build(BuildContext context) {
    final EntryReader? reader = ref.watch(entryReaderProvider(_mode));
    // Kept listened, so Save reads the signed-in user at once.
    ref.watch(userProvider);
    final String title = _mode == EntryMode.now
        ? EntryWordsPage.sayTitle
        : EntryWordsPage.catchUpTitle;
    if (reader == null) {
      return CardPage(
        title: title,
        children: const <Widget>[CardFoot(EntryWordsPage.off)],
      );
    }
    final List<DraftEntry>? drafts = _drafts;
    return CardPage(
      title: title,
      children: drafts == null || drafts.isEmpty
          ? _compose(context)
          : _review(context, drafts),
    );
  }

  List<Widget> _compose(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final DialColors colors = DialColors.of(context);
    final bool mic =
        _mode == EntryMode.now &&
        (ref.watch(speechAvailableProvider).value ?? false);
    final DateTime today = startOfDay(clock.now());
    return <Widget>[
      CardFoot(
        _mode == EntryMode.now
            ? EntryWordsPage.sayIntro
            : EntryWordsPage.catchUpIntro,
      ),
      if (_mode == EntryMode.days) ...<Widget>[
        const CardSectionLabel(EntryWordsPage.daysLabel),
        Wrap(
          spacing: DialSpace.xs,
          runSpacing: DialSpace.xs,
          children: <Widget>[
            for (int back = EntryLimits.catchUpReach; back >= 1; back--)
              _dayChip(addDays(today, -back), today),
          ],
        ),
        const SizedBox(height: DialSpace.m),
      ],
      const SizedBox(height: DialSpace.m),
      TextField(
        key: const ValueKey<String>('entry-words-field'),
        controller: _text,
        minLines: _mode == EntryMode.now ? 3 : 5,
        maxLines: 8,
        maxLength: EntryLimits.maxText(_mode),
        enabled: !_reading,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(
          labelText: EntryWordsPage.fieldLabel,
          hintText: _mode == EntryMode.now
              ? EntryWordsPage.sayHint
              : EntryWordsPage.catchUpHint,
          hintMaxLines: 3,
          alignLabelWithHint: true,
          border: const OutlineInputBorder(),
        ),
        onChanged: (_) => setState(() {}),
      ),
      if (mic) ...<Widget>[
        const SizedBox(height: DialSpace.s),
        Row(
          children: <Widget>[
            _MicButton(
              on: _listening != null,
              onPressed: _reading ? null : _toggleListening,
            ),
            const SizedBox(width: DialSpace.s),
            Expanded(
              child: Text(
                _listening != null
                    ? EntryWordsPage.listening
                    : _speechNote ?? '',
                style: DialTypeScale.bodyS.copyWith(color: colors.muted),
              ),
            ),
          ],
        ),
      ],
      if (_error != null) ...<Widget>[
        const SizedBox(height: DialSpace.s),
        Text(_error!, style: DialTypeScale.body.copyWith(color: scheme.error)),
      ],
      const SizedBox(height: DialSpace.m),
      Align(
        alignment: Alignment.centerRight,
        child: FilledButton(
          key: _readKey,
          style: FilledButton.styleFrom(
            minimumSize: const Size(120, DialSize.minTapTarget),
          ),
          onPressed:
              _reading ||
                  _text.text.trim().isEmpty ||
                  (_mode == EntryMode.days && _days.isEmpty)
              ? null
              : _read,
          child: const Text(EntryWordsPage.read),
        ),
      ),
    ];
  }

  Widget _dayChip(DateTime day, DateTime today) {
    final bool on = _days.contains(day);
    final bool full = !on && _days.length >= EntryLimits.maxDays;
    return FilterChip(
      label: Text(
        daysBetween(day, today) < 7 ? dayWord(day, today) : formatShortDay(day),
      ),
      selected: on,
      showCheckmark: false,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      onSelected: _reading || full
          ? null
          : (bool pick) => setState(() {
              if (pick) {
                _days.add(day);
              } else {
                _days.remove(day);
              }
            }),
    );
  }

  List<Widget> _review(BuildContext context, List<DraftEntry> drafts) {
    final DateTime today = startOfDay(clock.now());
    final Map<String, double> typicals = ref.watch(storedTypicalsProvider);
    final List<({int id, Vice vice})> habits = entryHabits(
      ref.watch(viceListProvider).value ?? const <Vice>[],
    );
    final List<Widget> groups = <Widget>[];
    DateTime? day;
    List<Widget> rows = <Widget>[];
    void close() {
      final DateTime? shown = day;
      if (shown == null) return;
      groups
        ..add(CardSectionLabel(formatDay(shown)))
        ..add(DialCard(top: 0, children: rows));
      rows = <Widget>[];
    }

    for (int i = 0; i < drafts.length; i++) {
      final DraftEntry d = drafts[i];
      final DateTime on = startOfDay(d.at);
      if (on != day) {
        close();
        day = on;
      }
      final double? typical = typicals[d.vice.id];
      rows.add(
        _DraftRow(
          key: ValueKey<String>('draft-$i'),
          draft: d,
          habits: habits.map((h) => h.vice).toList(),
          aboveUsual: typical != null && typical > 0 && d.amount > 3 * typical,
          today: today,
          onChanged: (DraftEntry next) => setState(() => drafts[i] = next),
          onRemove: () => setState(() {
            drafts.removeAt(i);
            if (drafts.isEmpty) _startAgain();
          }),
        ),
      );
    }
    close();
    return <Widget>[
      ClaudeWorkingResult(
        tag: ('entries', _readId),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            CardFoot(
              _mode == EntryMode.now
                  ? 'Check each entry. Nothing is saved until you tap Save.'
                  : 'Check each entry. They are marked as caught up, and '
                        'nothing is saved until you tap Save all.',
            ),
            if (_dropped > 0) CardFoot(EntryWordsPage.leftOut(_dropped)),
            ...groups,
          ],
        ),
      ),
      const SizedBox(height: DialSpace.l),
      Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: <Widget>[
          TextButton(
            style: TextButton.styleFrom(
              minimumSize: const Size(88, DialSize.minTapTarget),
            ),
            onPressed: _saving ? null : _startAgain,
            child: const Text(EntryWordsPage.startAgain),
          ),
          const SizedBox(width: DialSpace.xs),
          FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size(120, DialSize.minTapTarget),
            ),
            onPressed: _saving ? null : _save,
            child: Text(
              drafts.length == 1 ? EntryWordsPage.save : EntryWordsPage.saveAll,
            ),
          ),
        ],
      ),
    ];
  }
}

class _MicButton extends StatelessWidget {
  const _MicButton({required this.on, required this.onPressed});

  final bool on;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      toggled: on,
      label: on ? EntryWordsPage.stopListening : EntryWordsPage.listen,
      excludeSemantics: true,
      onTap: onPressed,
      child: Material(
        color: on ? scheme.primary : scheme.surfaceContainerHighest,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: EntryWordsPage.micKey,
          onTap: onPressed,
          child: SizedBox.square(
            dimension: 56,
            child: Center(
              child: StrokeIcon(
                on ? DialGlyph.close : DialGlyph.mic,
                size: 26,
                color: on ? scheme.onPrimary : scheme.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One draft: its habit (tap to change), amount (− and +), time (tap to
/// change, never past now), the words it came from and its tags, and Remove.
class _DraftRow extends StatelessWidget {
  const _DraftRow({
    super.key,
    required this.draft,
    required this.habits,
    required this.aboveUsual,
    required this.today,
    required this.onChanged,
    required this.onRemove,
  });

  final DraftEntry draft;
  final List<Vice> habits;
  final bool aboveUsual;
  final DateTime today;
  final ValueChanged<DraftEntry> onChanged;
  final VoidCallback onRemove;

  Future<void> _pickTime(BuildContext context) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(draft.at),
    );
    if (picked == null) return;
    final DateTime day = startOfDay(draft.at);
    DateTime at = DateTime(
      day.year,
      day.month,
      day.day,
      picked.hour,
      picked.minute,
    );
    final DateTime now = clock.now();
    if (at.isAfter(now)) at = now;
    onChanged(draft.copyWith(at: at));
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final DialColors colors = DialColors.of(context);
    final bool h24 = MediaQuery.alwaysUse24HourFormatOf(context);
    final num amount = draft.amount;
    final String amountText = draft.vice.units.label(amount);
    final String time = formatTime(draft.at, alwaysUse24HourFormat: h24);
    final List<String> tags = <String>[
      for (final String path in draft.triggers)
        triggerLabels(path)?.last ?? path,
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        18,
        DialSpace.xs,
        DialSpace.xs,
        DialSpace.xs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: PopupMenuButton<Vice>(
                  tooltip: 'Change habit',
                  onSelected: (Vice v) => onChanged(draft.copyWith(vice: v)),
                  itemBuilder: (BuildContext context) => <PopupMenuEntry<Vice>>[
                    for (final Vice v in habits)
                      PopupMenuItem<Vice>(value: v, child: Text(v.name)),
                  ],
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      minHeight: DialSize.minTapTarget,
                    ),
                    child: Row(
                      children: <Widget>[
                        Flexible(
                          child: Text(
                            draft.vice.name,
                            style: DialTypeScale.bodyL.copyWith(
                              fontWeight: FontWeight.w600,
                              color: scheme.onSurface,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        StrokeIcon(
                          DialGlyph.down,
                          size: 18,
                          color: colors.muted,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Semantics(
                button: true,
                label: 'Time $time. Change',
                excludeSemantics: true,
                onTap: () => _pickTime(context),
                child: TextButton(
                  style: TextButton.styleFrom(
                    minimumSize: const Size(
                      DialSize.minTapTarget,
                      DialSize.minTapTarget,
                    ),
                  ),
                  onPressed: () => _pickTime(context),
                  child: Text(time, style: DialTypeScale.monoM),
                ),
              ),
              IconButton(
                tooltip: EntryWordsPage.remove,
                constraints: const BoxConstraints(
                  minWidth: DialSize.minTapTarget,
                  minHeight: DialSize.minTapTarget,
                ),
                onPressed: onRemove,
                icon: StrokeIcon(
                  DialGlyph.close,
                  size: 20,
                  color: colors.muted,
                ),
              ),
            ],
          ),
          Row(
            children: <Widget>[
              IconButton(
                tooltip: 'Less',
                constraints: const BoxConstraints(
                  minWidth: DialSize.minTapTarget,
                  minHeight: DialSize.minTapTarget,
                ),
                onPressed: amount > 1
                    ? () => onChanged(
                        draft.copyWith(
                          amount: amount is int
                              ? amount - 1
                              : amount.ceil() - 1,
                        ),
                      )
                    : null,
                icon: const StrokeIcon(DialGlyph.minus, size: 20),
              ),
              Semantics(
                liveRegion: true,
                child: Text(
                  amountText,
                  style: DialTypeScale.monoM.copyWith(
                    color: aboveUsual ? scheme.error : scheme.onSurface,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'More',
                constraints: const BoxConstraints(
                  minWidth: DialSize.minTapTarget,
                  minHeight: DialSize.minTapTarget,
                ),
                onPressed: amount < EntryLimits.maxAmount
                    ? () => onChanged(
                        draft.copyWith(
                          amount: amount is int
                              ? amount + 1
                              : amount.floor() + 1,
                        ),
                      )
                    : null,
                icon: const StrokeIcon(DialGlyph.plus, size: 20),
              ),
            ],
          ),
          if (aboveUsual)
            Text(
              EntryWordsPage.aboveUsual,
              style: DialTypeScale.bodyS.copyWith(color: scheme.error),
            ),
          if (draft.note != null)
            Padding(
              padding: const EdgeInsets.only(top: DialSpace.xxs),
              child: Text(
                '“${draft.note}”',
                style: DialTypeScale.bodyS.copyWith(color: colors.muted),
              ),
            ),
          if (tags.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: DialSpace.xxs),
              child: Text(
                'Tags: ${tags.join(', ')}',
                style: DialTypeScale.bodyS.copyWith(color: colors.muted),
              ),
            ),
        ],
      ),
    );
  }
}
