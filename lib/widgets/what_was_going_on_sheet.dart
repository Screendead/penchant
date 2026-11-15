import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/data/activity_content.dart';
import 'package:tracker/data/limits.dart';
import 'package:tracker/data/trigger_tree.dart';
import 'package:tracker/data/trigger_usage.dart';
import 'package:tracker/design/dial_theme.dart';
import 'package:tracker/design/tokens.dart';
import 'package:tracker/notes/note_reader.dart';
import 'package:tracker/widgets/trigger_picker.dart';
import 'package:tracker/widgets/urge_note_fields.dart';

/// What the panels close with on Done.
typedef WhatWasGoingOnPick = ({List<String> triggers, int? urge, String? note});

/// Opens the panels after a log of [viceID]: a note, the tags (read from the
/// note when a [NoteReader] is there, else picked by hand) and the urge.
/// Returns null when dismissed without Done. With [onUndoLog] every panel
/// offers Undo log, which closes it with null and calls that. With [at], the
/// entry's time, the tags panel offers what the calendar suggests.
Future<WhatWasGoingOnPick?> showWhatWasGoingOn(
  BuildContext context, {
  required String viceID,
  required String viceName,
  List<String> initial = const <String>[],
  DateTime? at,
  VoidCallback? onUndoLog,
}) => showModalBottomSheet<WhatWasGoingOnPick>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (BuildContext context) => TriggerSources(
    viceID: viceID,
    at: at,
    builder: (BuildContext context, TriggerOffers offers) =>
        WhatWasGoingOnSheet(
          viceName: viceName,
          offers: offers,
          initial: initial,
          onDone: (WhatWasGoingOnPick pick) => Navigator.of(context).pop(pick),
          onUndoLog: onUndoLog == null
              ? null
              : () {
                  Navigator.of(context).pop();
                  onUndoLog();
                },
        ),
  ),
);

/// Three panels moved only by Back and Next, each with Done.
class WhatWasGoingOnSheet extends ConsumerStatefulWidget {
  const WhatWasGoingOnSheet({
    super.key,
    required this.viceName,
    required this.onDone,
    this.offers = (
      usual: const <String>[],
      promoted: const <String>[],
      suggested: const <String>[],
    ),
    this.initial = const <String>[],
    this.onUndoLog,
  });

  final String viceName;
  final TriggerOffers offers;
  final List<String> initial;
  final ValueChanged<WhatWasGoingOnPick> onDone;
  final VoidCallback? onUndoLog;

  static const int panels = 3;
  static const Key nextKey = ValueKey<String>('panels-next');
  static const Key backKey = ValueKey<String>('panels-back');
  static const Key doneKey = ValueKey<String>('panels-done');
  static const String noteTitle = 'In your own words';
  static const String readsHint = 'Next reads it into tags.';
  static const String tagsTitle = 'Does this look right?';
  static const String handTitle = 'Optional. Tap any that fit.';
  static const String readingLine = 'Reading…';
  static const String readLine =
      'Tap a tag to drop it. Nothing is saved until Done.';
  static const String noneReadLine = 'Nothing recognised. Pick tags by hand.';
  static const String failedLine =
      'Could not read the note. Pick tags by hand.';
  static const Duration readTimeout = Duration(seconds: 10);

  @override
  ConsumerState<WhatWasGoingOnSheet> createState() =>
      _WhatWasGoingOnSheetState();
}

// One tag's arrival: its quote lit, then the phrase flying to its chip, then
// a beat before the next.
const Duration _lit = Duration(milliseconds: 260);
const Duration _flight = DialMotion.containerTransform;
const Duration _settle = Duration(milliseconds: 140);

// One height for every panel, so Next and Back never move the buttons.
const double _maxHeight = 600;

class _WhatWasGoingOnSheetState extends ConsumerState<WhatWasGoingOnSheet>
    with SingleTickerProviderStateMixin {
  final PageController pages = PageController();
  int page = 0;
  final GlobalKey<FormState> noteForm = GlobalKey<FormState>();
  final TextEditingController note = TextEditingController();
  late List<String> selected = <String>[...widget.initial];
  int? urge;
  String? error;

  // The note as last read, and what reading it found, in order.
  String? readNote;
  final List<ReadTag> read = <ReadTag>[];
  final Set<String> shown = <String>{};
  final Queue<ReadTag> arriving = Queue<ReadTag>();
  StreamSubscription<ReadTag>? reading;
  Timer? waited;
  bool readFailed = false;
  ReadTag? lit;
  ({Rect from, Rect to})? flight;

  late final AnimationController arrival = AnimationController(
    vsync: this,
    duration: _lit + _flight + _settle,
  );
  final GlobalKey stackKey = GlobalKey();
  final GlobalKey echoKey = GlobalKey();
  final Map<String, GlobalKey> chipKeys = <String, GlobalKey>{};

  bool get still => MediaQuery.disableAnimationsOf(context);

  bool get last => page == WhatWasGoingOnSheet.panels - 1;

  @override
  void dispose() {
    waited?.cancel();
    reading?.cancel();
    arrival.dispose();
    pages.dispose();
    note.dispose();
    super.dispose();
  }

  Future<void> go(int to) async {
    FocusManager.instance.primaryFocus?.unfocus();
    if (page == 1 && to != 1) stopReading();
    setState(() {
      page = to;
      error = null;
    });
    if (still) {
      pages.jumpToPage(to);
    } else {
      await pages.animateToPage(
        to,
        duration: DialMotion.fadeThrough,
        curve: DialMotion.enter,
      );
    }
    if (mounted && page == 1) startReading();
  }

  void next() {
    if (page == 0 && !(noteForm.currentState?.validate() ?? true)) return;
    go(page + 1);
  }

  void done() {
    final String? text = storedNote(note.text);
    final String? tooLong =
        noteError(text) ??
        answersTooLong(triggers: selected, urge: urge, note: text);
    if (tooLong != null) {
      setState(() => error = tooLong);
      return;
    }
    stopReading();
    widget.onDone((
      triggers: List<String>.of(selected),
      urge: urge,
      note: text,
    ));
  }

  void startReading() {
    final String? text = storedNote(note.text);
    if (text == readNote) return;
    stopReading();
    setState(() {
      selected.removeWhere(
        (String p) =>
            read.any((ReadTag t) => t.path == p) && !widget.initial.contains(p),
      );
      read.clear();
      shown.clear();
      readFailed = false;
      readNote = text;
    });
    final NoteReader? reader = ref.read(noteReaderProvider);
    if (reader == null || text == null) return;
    void failed() {
      if (!mounted) return;
      stopReading(again: false);
      setState(() => readFailed = true);
    }

    reading = reader
        .read(text)
        .listen(
          (ReadTag tag) {
            waited?.cancel();
            waited = Timer(WhatWasGoingOnSheet.readTimeout, failed);
            arrive(text, tag);
          },
          onError: (Object _) => failed(),
          onDone: () {
            waited?.cancel();
            if (mounted) setState(() => reading = null);
          },
          cancelOnError: true,
        );
    waited = Timer(WhatWasGoingOnSheet.readTimeout, failed);
    setState(() {});
  }

  // Ends a read; one cut short is read [again] on the next visit.
  void stopReading({bool again = true}) {
    if (again && reading != null) readNote = null;
    waited?.cancel();
    reading?.cancel();
    reading = null;
    arrival.stop();
    if (lit case final ReadTag t) shown.add(t.path);
    for (final ReadTag t in arriving) {
      shown.add(t.path);
    }
    arriving.clear();
    lit = null;
    flight = null;
  }

  void arrive(String text, ReadTag tag) {
    if (!mounted ||
        tag.quote.isEmpty ||
        !text.contains(tag.quote) ||
        triggerLabels(tag.path) == null ||
        read.any((ReadTag t) => t.path == tag.path) ||
        (!selected.contains(tag.path) && selected.length >= maxTriggers)) {
      return;
    }
    setState(() {
      read.add(tag);
      if (!selected.contains(tag.path)) selected.add(tag.path);
    });
    arriving.add(tag);
    if (lit == null) land();
  }

  void land() {
    if (!mounted || arriving.isEmpty) return;
    final ReadTag tag = arriving.removeFirst();
    if (still) {
      setState(() => shown.add(tag.path));
      land();
      return;
    }
    setState(() => lit = tag);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || lit != tag) return;
      flight = flightOf(tag);
      arrival.forward(from: 0).whenCompleteOrCancel(() {
        if (!mounted || lit != tag) return;
        setState(() {
          shown.add(tag.path);
          lit = null;
          flight = null;
        });
        land();
      });
    });
  }

  // From the quote in the note to its chip, in the panel's own coordinates.
  ({Rect from, Rect to})? flightOf(ReadTag tag) {
    final RenderObject? stack = stackKey.currentContext?.findRenderObject();
    final RenderObject? echo = echoKey.currentContext?.findRenderObject();
    final RenderObject? chip = chipKeys[tag.path]?.currentContext
        ?.findRenderObject();
    if (stack is! RenderBox ||
        echo is! RenderParagraph ||
        chip is! RenderBox ||
        readNote == null) {
      return null;
    }
    final int start = readNote!.indexOf(tag.quote);
    final List<TextBox> boxes = echo.getBoxesForSelection(
      TextSelection(baseOffset: start, extentOffset: start + tag.quote.length),
    );
    if (boxes.isEmpty) return null;
    final Rect quote = boxes
        .map((TextBox b) => b.toRect())
        .reduce((Rect a, Rect b) => a.expandToInclude(b));
    Rect inStack(RenderBox box, Rect r) => Rect.fromPoints(
      stack.globalToLocal(box.localToGlobal(r.topLeft)),
      stack.globalToLocal(box.localToGlobal(r.bottomRight)),
    );
    return (
      from: inStack(echo, quote),
      to: inStack(chip, Offset.zero & chip.size),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final double height = MediaQuery.sizeOf(context).height;
    final double keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final bool cramped = crampedByKeyboard(context);

    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: SizedBox(
        height: keyboard > 0
            ? height - keyboard
            : math.min(_maxHeight, height * 0.85),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (!cramped)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  DialSpace.xl,
                  DialSpace.xl,
                  DialSpace.xl,
                  DialSpace.xs,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        'What was going on?',
                        style: theme.textTheme.headlineSmall,
                      ),
                    ),
                    Text(
                      '${page + 1} of ${WhatWasGoingOnSheet.panels}',
                      semanticsLabel:
                          'Step ${page + 1} of ${WhatWasGoingOnSheet.panels}',
                      style: DialTypeScale.monoS.copyWith(
                        color: DialColors.of(context).muted,
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: PageView(
                controller: pages,
                physics: const NeverScrollableScrollPhysics(),
                children: <Widget>[
                  for (int i = 0; i < WhatWasGoingOnSheet.panels; i++)
                    ExcludeFocus(
                      excluding: i != page,
                      child: ExcludeSemantics(
                        excluding: i != page,
                        child: IgnorePointer(
                          ignoring: i != page,
                          child: switch (i) {
                            0 => _notePanel(context),
                            1 => _tagsPanel(context),
                            _ => _urgePanel(),
                          },
                        ),
                      ),
                    ),
                ],
              ),
            ),
            _footer(context, cramped),
          ],
        ),
      ),
    );
  }

  Widget _notePanel(BuildContext context) => ListView(
    padding: const EdgeInsets.all(DialSpace.m),
    children: <Widget>[
      Form(
        key: noteForm,
        child: NoteField(
          controller: note,
          label: WhatWasGoingOnSheet.noteTitle,
        ),
      ),
      if (ref.read(noteReaderProvider) != null)
        Padding(
          padding: const EdgeInsets.only(top: DialSpace.xs),
          child: Text(
            WhatWasGoingOnSheet.readsHint,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: DialColors.of(context).muted,
            ),
          ),
        ),
    ],
  );

  Widget _urgePanel() => ListView(
    padding: const EdgeInsets.all(DialSpace.m),
    children: <Widget>[
      UrgeField(
        value: urge,
        onChanged: (int? value) => setState(() => urge = value),
      ),
    ],
  );

  void _setSelected(List<String> next) => setState(() => selected = next);

  Widget _tagsPanel(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DialColors colors = DialColors.of(context);
    final bool echoing =
        readNote != null && (reading != null || read.isNotEmpty);
    final String? line = switch (()) {
      _ when reading != null => WhatWasGoingOnSheet.readingLine,
      _ when readFailed => WhatWasGoingOnSheet.failedLine,
      _ when readNote == null || ref.read(noteReaderProvider) == null => null,
      _ when read.isEmpty => WhatWasGoingOnSheet.noneReadLine,
      _ => WhatWasGoingOnSheet.readLine,
    };
    final List<String> byHand = selected
        .where((String p) => !read.any((ReadTag t) => t.path == p))
        .toList();

    return Stack(
      key: stackKey,
      children: <Widget>[
        ListView(
          padding: const EdgeInsets.all(DialSpace.m),
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: DialSpace.xs),
              child: Text(
                echoing
                    ? WhatWasGoingOnSheet.tagsTitle
                    : WhatWasGoingOnSheet.handTitle,
                style: echoing
                    ? theme.textTheme.titleMedium
                    : theme.textTheme.bodyMedium?.copyWith(color: colors.muted),
              ),
            ),
            const SizedBox(height: DialSpace.s),
            if (echoing) ...<Widget>[
              DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.surface2,
                  borderRadius: BorderRadius.circular(DialRadius.tile),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: DialSpace.s,
                    vertical: DialSpace.xs,
                  ),
                  child: RichText(
                    key: echoKey,
                    text: _echo(context, readNote!),
                  ),
                ),
              ),
              const SizedBox(height: DialSpace.s),
              Wrap(
                spacing: DialSpace.xs,
                runSpacing: DialSpace.xs,
                children: <Widget>[
                  for (final ReadTag tag in read)
                    Visibility(
                      key: chipKeys.putIfAbsent(tag.path, GlobalKey.new),
                      visible: shown.contains(tag.path),
                      maintainSize: true,
                      maintainAnimation: true,
                      maintainState: true,
                      child: FilterChip(
                        label: Text(triggerDisplay(tag.path)),
                        selected: selected.contains(tag.path),
                        onSelected: (_) => _setSelected(
                          selected.contains(tag.path)
                              ? (selected.toList()..remove(tag.path))
                              : selected.length < maxTriggers
                              ? <String>[...selected, tag.path]
                              : selected,
                        ),
                      ),
                    ),
                ],
              ),
            ],
            if (line != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  DialSpace.xs,
                  DialSpace.xs,
                  DialSpace.xs,
                  0,
                ),
                child: Text(
                  line,
                  style: DialTypeScale.monoS.copyWith(color: colors.muted),
                ),
              ),
            if (byHand.isNotEmpty) ...<Widget>[
              const SizedBox(height: DialSpace.s),
              SelectedTriggers(
                selected: byHand,
                onChanged: (List<String> kept) => _setSelected(
                  selected
                      .where(
                        (String p) => !byHand.contains(p) || kept.contains(p),
                      )
                      .toList(),
                ),
              ),
            ],
            const SizedBox(height: DialSpace.m),
            TriggerChoices(
              // Keeps the open area and free text as the rows above come and
              // go.
              key: const ValueKey<String>('hand-picker'),
              viceName: widget.viceName,
              usual: widget.offers.usual,
              promoted: widget.offers.promoted,
              suggested: widget.offers.suggested,
              selected: selected,
              onChanged: _setSelected,
            ),
          ],
        ),
        if (flight case final ({Rect from, Rect to}) f)
          IgnorePointer(
            child: AnimatedBuilder(
              animation: arrival,
              builder: (BuildContext context, Widget? child) {
                final double total = arrival.duration!.inMilliseconds
                    .toDouble();
                final double begin = _lit.inMilliseconds / total;
                final double end = (_lit + _flight).inMilliseconds / total;
                if (arrival.value < begin) return const SizedBox.shrink();
                final double t = Interval(
                  begin,
                  end,
                  curve: DialMotion.enter,
                ).transform(arrival.value);
                return Stack(
                  children: <Widget>[
                    Positioned.fromRect(
                      rect: Rect.lerp(f.from, f.to, t)!,
                      child: child!,
                    ),
                  ],
                );
              },
              child: _FlyingTag(triggerDisplay(lit!.path)),
            ),
          ),
      ],
    );
  }

  TextSpan _echo(BuildContext context, String text) {
    final ThemeData theme = Theme.of(context);
    final TextStyle? base = theme.textTheme.bodyMedium?.copyWith(
      color: DialColors.of(context).muted,
    );
    final ReadTag? on = lit;
    final int at = on == null ? -1 : text.indexOf(on.quote);
    if (on == null || at < 0) return TextSpan(text: text, style: base);
    return TextSpan(
      style: base,
      children: <InlineSpan>[
        TextSpan(text: text.substring(0, at)),
        TextSpan(
          text: on.quote,
          style: TextStyle(
            color: theme.colorScheme.onPrimary,
            background: Paint()..color = theme.colorScheme.primary,
          ),
        ),
        TextSpan(text: text.substring(at + on.quote.length)),
      ],
    );
  }

  Widget _footer(BuildContext context, bool cramped) {
    const Size target = Size(44, 44);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: DialColors.of(context).line)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: DialSpace.m,
          vertical: DialSpace.s,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (error case final String e)
              Padding(
                padding: const EdgeInsets.only(bottom: DialSpace.xs),
                child: Text(
                  e,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (!cramped && (widget.onUndoLog != null || !last))
              Padding(
                padding: const EdgeInsets.only(bottom: DialSpace.xs),
                child: Row(
                  children: <Widget>[
                    if (widget.onUndoLog case final VoidCallback undo)
                      UndoLogButton(onPressed: undo),
                    const Spacer(),
                    if (!last)
                      TextButton(
                        key: WhatWasGoingOnSheet.doneKey,
                        style: TextButton.styleFrom(minimumSize: target),
                        onPressed: done,
                        child: const Text('Done'),
                      ),
                  ],
                ),
              ),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton(
                    key: WhatWasGoingOnSheet.backKey,
                    style: OutlinedButton.styleFrom(minimumSize: target),
                    onPressed: page == 0 ? null : () => go(page - 1),
                    child: const Text('Back'),
                  ),
                ),
                const SizedBox(width: DialSpace.xs),
                Expanded(
                  flex: 2,
                  child: last
                      ? FilledButton(
                          key: WhatWasGoingOnSheet.doneKey,
                          style: FilledButton.styleFrom(minimumSize: target),
                          onPressed: done,
                          child: const Text('Done'),
                        )
                      : FilledButton(
                          key: WhatWasGoingOnSheet.nextKey,
                          style: FilledButton.styleFrom(minimumSize: target),
                          onPressed: next,
                          child: const Text('Next'),
                        ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FlyingTag extends StatelessWidget {
  const _FlyingTag(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: scheme.primary,
        shape: const StadiumBorder(),
      ),
      child: FittedBox(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: DialSpace.s,
            vertical: DialSpace.xs,
          ),
          child: Text(
            label,
            maxLines: 1,
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(color: scheme.onPrimary),
          ),
        ),
      ),
    );
  }
}
