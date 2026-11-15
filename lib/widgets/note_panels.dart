import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/data/limits.dart';
import 'package:tracker/data/trigger_tree.dart';
import 'package:tracker/data/trigger_usage.dart';
import 'package:tracker/design/dial_theme.dart';
import 'package:tracker/design/tokens.dart';
import 'package:tracker/notes/follow_up.dart';
import 'package:tracker/notes/note_reader.dart';
import 'package:tracker/widgets/trigger_picker.dart';
import 'package:tracker/widgets/urge_note_fields.dart';

/// The keys and copy shared by every sheet of note panels.
abstract final class NotePanels {
  static const Key nextKey = ValueKey<String>('panels-next');
  static const Key backKey = ValueKey<String>('panels-back');
  static const Key doneKey = ValueKey<String>('panels-done');
  static const Key flyingKey = ValueKey<String>('panels-flying-tag');
  static const Key answerKey = ValueKey<String>('panels-follow-up-answer');
  static const Key skipKey = ValueKey<String>('panels-follow-up-skip');
  static const String followUpTitle = 'One more, if you like';
  static const String answerHint = 'Optional';
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

  /// The panel whose arrival reads the note into tags.
  static const int tagsPanel = 1;

  /// The follow-up question's panel, there only once a question has come.
  static const int followUpPanel = tagsPanel + 1;
}

// One tag's arrival: its quote lit, then the phrase flying to its chip, then
// a beat before the next.
const Duration _lit = Duration(milliseconds: 260);
const Duration _flight = DialMotion.containerTransform;
const Duration _settle = Duration(milliseconds: 140);

// One height for every panel, so Next and Back never move the buttons.
const double _maxHeight = 600;

/// Panels moved only by Back and Next, each with Done: the note first, then
/// at [NotePanels.tagsPanel] the tags read from it (or picked by hand), then,
/// once the reader has asked one, the follow-up question, then whatever else
/// a sheet asks. The step count counts the question's panel only from its
/// arrival, so it never promises a panel that does not come.
abstract class NotePanelsState<T extends ConsumerStatefulWidget>
    extends ConsumerState<T>
    with SingleTickerProviderStateMixin {
  final PageController pages = PageController();
  int page = 0;
  final GlobalKey<FormState> noteForm = GlobalKey<FormState>();
  final TextEditingController note = TextEditingController();
  late List<String> selected = <String>[...initial];
  String? error;

  // The note as last read, and what reading it found, in order.
  String? readNote;
  bool readAgain = false;
  final List<ReadTag> read = <ReadTag>[];
  final Set<String> shown = <String>{};
  final Queue<ReadTag> arriving = Queue<ReadTag>();
  StreamSubscription<ReadTag>? reading;
  Timer? waited;
  bool readFailed = false;
  ReadTag? lit;
  ({Rect from, Rect to})? flight;

  // The follow-up question about [readNote], and the answer typed to it.
  NoteQuestion? question;
  final TextEditingController answer = TextEditingController();
  int _asking = 0;

  late final AnimationController arrival = AnimationController(
    vsync: this,
    duration: _lit + _flight + _settle,
  );
  final GlobalKey stackKey = GlobalKey();
  final GlobalKey echoKey = GlobalKey();
  final Map<String, GlobalKey> chipKeys = <String, GlobalKey>{};

  String get title;

  /// The sheet's own panels, without the follow-up question's.
  int get basePanelCount;

  int get panelCount => basePanelCount + (question == null ? 0 : 1);

  /// Tags that stay picked when the note is read again.
  List<String> get initial;
  String get viceName => '';
  TriggerOffers get offers => (
    usual: const <String>[],
    promoted: const <String>[],
    suggested: const <String>[],
  );

  /// The sheet's own panel [index], counted without the follow-up's.
  Widget sheetPanel(BuildContext context, int index);

  Widget panel(BuildContext context, int index) => switch (question) {
    null => sheetPanel(context, index),
    final NoteQuestion q when index == NotePanels.followUpPanel =>
      followUpPanel(context, q),
    _ => sheetPanel(
      context,
      index > NotePanels.followUpPanel ? index - 1 : index,
    ),
  };

  /// The follow-up answered, to save with the note; null when skipped, left
  /// blank, or asked about other words than the note now holds.
  FollowUp? get followUp => storedNote(note.text) == readNote
      ? FollowUp.answered(question, answer.text)
      : null;

  /// Beside Done in the footer's upper row.
  Widget? footerLeading(BuildContext context) => null;

  void done();

  bool get still => MediaQuery.disableAnimationsOf(context);

  bool get last => page == panelCount - 1;

  @override
  void dispose() {
    waited?.cancel();
    reading?.cancel();
    arrival.dispose();
    pages.dispose();
    note.dispose();
    answer.dispose();
    super.dispose();
  }

  Future<void> go(int to) async {
    FocusManager.instance.primaryFocus?.unfocus();
    if (page == NotePanels.tagsPanel && to != NotePanels.tagsPanel) {
      stopReading();
    }
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
    if (mounted && page == NotePanels.tagsPanel) startReading();
  }

  void next() {
    if (page == 0 && !(noteForm.currentState?.validate() ?? true)) return;
    go(page + 1);
  }

  void startReading() {
    final String? text = storedNote(note.text);
    if (text == readNote && !readAgain) return;
    stopReading();
    setState(() {
      selected.removeWhere(
        (String p) =>
            read.any((ReadTag t) => t.path == p) && !initial.contains(p),
      );
      read.clear();
      shown.clear();
      readFailed = false;
      readAgain = false;
      readNote = text;
      question = null;
      answer.clear();
    });
    final NoteReader? reader = ref.read(noteReaderProvider);
    if (reader == null || text == null) return;
    void failed() {
      if (!mounted) return;
      stopReading(again: false);
      setState(() {
        readFailed = true;
        question = null;
      });
    }

    reading = reader
        .read(text)
        .listen(
          (ReadTag tag) {
            arrive(text, tag);
          },
          onError: (Object _) => failed(),
          onDone: () {
            waited?.cancel();
            if (mounted) setState(() => reading = null);
          },
          cancelOnError: true,
        );
    waited = Timer(NotePanels.readTimeout, failed);
    if (reader is QuestioningNoteReader) {
      final int asking = ++_asking;
      reader.question(text).then((NoteQuestion? q) {
        if (!mounted ||
            q == null ||
            asking != _asking ||
            readFailed ||
            readNote != text ||
            !text.contains(q.quote)) {
          return;
        }
        setState(() => question = q);
      }, onError: (Object _) {});
    }
    setState(() {});
  }

  // Ends a read; one cut short is read [again] on the next visit. Tags not yet
  // shown are dropped, so nothing unseen is saved.
  void stopReading({bool again = true}) {
    // A question still on its way when the read is cut short is dropped
    // with the unseen tags.
    if (reading != null) _asking++;
    if (again && reading != null) readAgain = true;
    waited?.cancel();
    reading?.cancel();
    reading = null;
    arrival.stop();
    if (lit case final ReadTag t) shown.add(t.path);
    for (final ReadTag t in arriving) {
      read.remove(t);
      if (!initial.contains(t.path)) selected.remove(t.path);
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
      setState(() => flight = flightOf(tag));
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

  /// The sheet's fixed height above the keyboard, holding [child].
  Widget sheetShell(BuildContext context, Widget child) {
    final double height = MediaQuery.sizeOf(context).height;
    final double keyboard = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: SizedBox(
        height: keyboard > 0
            ? height - keyboard
            : math.min(_maxHeight, height * 0.85),
        child: child,
      ),
    );
  }

  /// The title row, with the step count when [steps].
  Widget header(BuildContext context, {bool steps = true}) => Padding(
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
          child: Text(title, style: Theme.of(context).textTheme.headlineSmall),
        ),
        if (steps)
          Text(
            '${page + 1} of $panelCount',
            semanticsLabel: 'Step ${page + 1} of $panelCount',
            style: DialTypeScale.monoS.copyWith(
              color: DialColors.of(context).muted,
            ),
          ),
      ],
    ),
  );

  Widget buildPanels(BuildContext context) {
    final bool cramped = crampedByKeyboard(context);
    return sheetShell(
      context,
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (!cramped) header(context),
          Expanded(
            child: PageView(
              controller: pages,
              physics: const NeverScrollableScrollPhysics(),
              children: <Widget>[
                for (int i = 0; i < panelCount; i++)
                  ExcludeFocus(
                    excluding: i != page,
                    child: ExcludeSemantics(
                      excluding: i != page,
                      child: IgnorePointer(
                        ignoring: i != page,
                        child: panel(context, i),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          footer(context, cramped),
        ],
      ),
    );
  }

  /// The first panel: [field] in [noteForm], saying Next reads it when a
  /// reader is there.
  Widget notePanel(BuildContext context, Widget field) => ListView(
    padding: const EdgeInsets.all(DialSpace.m),
    children: <Widget>[
      Form(key: noteForm, child: field),
      if (ref.read(noteReaderProvider) != null)
        Padding(
          padding: const EdgeInsets.only(top: DialSpace.xs),
          child: Text(
            NotePanels.readsHint,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: DialColors.of(context).muted,
            ),
          ),
        ),
    ],
  );

  void _setSelected(List<String> next) => setState(() => selected = next);

  Widget tagsPanel(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DialColors colors = DialColors.of(context);
    final bool echoing =
        readNote != null && (reading != null || read.isNotEmpty);
    final String? line = switch (()) {
      _ when reading != null => NotePanels.readingLine,
      _ when readFailed => NotePanels.failedLine,
      _ when readNote == null || ref.read(noteReaderProvider) == null => null,
      _ when read.isEmpty => NotePanels.noneReadLine,
      _ => NotePanels.readLine,
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
                echoing ? NotePanels.tagsTitle : NotePanels.handTitle,
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
              viceName: viceName,
              usual: offers.usual,
              promoted: offers.promoted,
              suggested: offers.suggested,
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
              child: _FlyingTag(
                key: NotePanels.flyingKey,
                triggerDisplay(lit!.path),
              ),
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

  /// The follow-up question: the note with the quoted words marked, the
  /// question, an optional answer and Skip, which clears the answer and moves
  /// on (or finishes, on the last panel).
  Widget followUpPanel(BuildContext context, NoteQuestion q) {
    final ThemeData theme = Theme.of(context);
    final DialColors colors = DialColors.of(context);
    final String text = readNote ?? '';
    final int at = text.indexOf(q.quote);
    final TextStyle? base = theme.textTheme.bodyMedium?.copyWith(
      color: colors.muted,
    );
    return ListView(
      padding: const EdgeInsets.all(DialSpace.m),
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: DialSpace.xs),
          child: Text(
            NotePanels.followUpTitle,
            style: theme.textTheme.titleMedium,
          ),
        ),
        const SizedBox(height: DialSpace.s),
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
            child: Text.rich(
              at < 0
                  ? TextSpan(text: text, style: base)
                  : TextSpan(
                      style: base,
                      children: <InlineSpan>[
                        TextSpan(text: text.substring(0, at)),
                        TextSpan(
                          text: q.quote,
                          style: TextStyle(
                            color: theme.colorScheme.onPrimary,
                            background: Paint()
                              ..color = theme.colorScheme.primary,
                          ),
                        ),
                        TextSpan(text: text.substring(at + q.quote.length)),
                      ],
                    ),
            ),
          ),
        ),
        const SizedBox(height: DialSpace.s),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: DialSpace.xs),
          child: Text(
            askedLine(q.question, q.quote),
            style: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: DialSpace.s),
        TextField(
          key: NotePanels.answerKey,
          controller: answer,
          minLines: 2,
          maxLines: 5,
          maxLength: maxFollowUpAnswerLength,
          keyboardType: TextInputType.multiline,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: NotePanels.answerHint),
        ),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: TextButton(
            key: NotePanels.skipKey,
            style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
            onPressed: skip,
            child: const Text('Skip'),
          ),
        ),
      ],
    );
  }

  void skip() {
    answer.clear();
    if (last) {
      done();
    } else {
      go(page + 1);
    }
  }

  /// [error] above [rows], with the footer's rule and padding.
  Widget footerFrame(BuildContext context, List<Widget> rows) => DecoratedBox(
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
          ...rows,
        ],
      ),
    ),
  );

  Widget footer(BuildContext context, bool cramped) {
    const Size target = Size(44, 44);
    final Widget? leading = footerLeading(context);
    return footerFrame(context, <Widget>[
      if (!cramped && (leading != null || !last))
        Padding(
          padding: const EdgeInsets.only(bottom: DialSpace.xs),
          child: Row(
            children: <Widget>[
              ?leading,
              const Spacer(),
              if (!last)
                TextButton(
                  key: NotePanels.doneKey,
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
              key: NotePanels.backKey,
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
                    key: NotePanels.doneKey,
                    style: FilledButton.styleFrom(minimumSize: target),
                    onPressed: done,
                    child: const Text('Done'),
                  )
                : FilledButton(
                    key: NotePanels.nextKey,
                    style: FilledButton.styleFrom(minimumSize: target),
                    onPressed: next,
                    child: const Text('Next'),
                  ),
          ),
        ],
      ),
    ]);
  }
}

class _FlyingTag extends StatelessWidget {
  const _FlyingTag(this.label, {super.key});

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
