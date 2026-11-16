import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/claude/claude_working_painters.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/design/dial_theme.dart';
import 'package:tracker/design/habit_mark.dart';
import 'package:tracker/design/tokens.dart';
import 'package:tracker/providers/today_provider.dart';
import 'package:tracker/providers/vice_activity_day_provider.dart';
import 'package:tracker/providers/vice_list_provider.dart';

/// How a Claude call in flight is drawn. Every look shares the same
/// behaviour, text and timing; only the picture differs.
enum ClaudeWorkingLook {
  /// The Day Dial's 24-hour face holding the last four weeks as rings, a hand
  /// sweeping it, each entry ringing as the hand passes.
  dial,

  /// The person's words at the centre, fine ink lines tracing out from them
  /// across their entries, drawing together into the answer's outline.
  ink,

  /// The last four weeks as a field of hours, a loupe moving over it and
  /// drawing what it passes into focus.
  lens,
}

/// The look every call site uses.
final claudeWorkingLookProvider = Provider<ClaudeWorkingLook>(
  (Ref ref) => ClaudeWorkingLook.dial,
);

enum ClaudeWorkEnd { answered, failed, stopped }

/// One Claude call as the person is shown it: what is happening now, in
/// words that name only what is known, and how it ended. The call site keeps
/// it current; the screen and card only read it.
class ClaudeWork extends ChangeNotifier {
  ClaudeWork({
    required String status,
    String? detail,
    this.subject,
    this.steps,
    this.showElapsed = false,
    DateTime? started,
  }) : _status = status,
       _detail = detail,
       started = started ?? DateTime.now();

  /// The person's own words that were sent, if any.
  final String? subject;

  /// The most steps the call can take, for a staged call.
  final int? steps;
  final bool showElapsed;
  final DateTime started;

  String _status;
  String? _detail;
  int _stepsDone = 0;
  ClaudeWorkEnd? _end;

  String get status => _status;
  String? get detail => _detail;
  int get stepsDone => _stepsDone;
  ClaudeWorkEnd? get end => _end;
  bool get over => _end != null;

  void say(String status, {String? detail, int? stepsDone}) {
    if (over) return;
    _status = status;
    _detail = detail;
    if (stepsDone != null) _stepsDone = stepsDone;
    notifyListeners();
  }

  void finish(ClaudeWorkEnd end) {
    if (over) return;
    _end = end;
    notifyListeners();
  }
}

abstract final class ClaudeWorking {
  /// A call answered within this never leaves the page.
  static const Duration delay = Duration(milliseconds: 600);

  /// Once shown, the screen stays at least this long, so it never flashes.
  static const Duration minShown = Duration(milliseconds: 1400);
  static const Duration resolve = Duration(milliseconds: 700);
  static const Duration grow = DialMotion.beadTravel;

  static const String label = 'Claude';
  static const String stop = 'Stop';

  static String elapsed(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  static String stepOf(int step, int of) => 'Step $step of at most $of';
}

/// One entry of the last [claudeWorkingDays] days, as the looks draw it:
/// which day back, the minute of its day, its habit's colour slot, and its
/// size against the habit's median.
@immutable
class JournalMark {
  const JournalMark({
    required this.daysAgo,
    required this.minute,
    required this.slot,
    this.weight = 1,
  });

  final int daysAgo;
  final int minute;
  final int slot;
  final double weight;
}

const int claudeWorkingDays = 28;

List<JournalMark> journalMarks(
  List<Vice> vices,
  List<ViceActivity> entries,
  DateTime today,
) {
  final Map<String, HabitMark> marks = habitMarks(vices);
  final Map<String, List<double>> byHabit = <String, List<double>>{};
  for (final ViceActivity e in entries) {
    (byHabit[e.viceID] ??= <double>[]).add(e.measure.toDouble());
  }
  final Map<String, double> median = <String, double>{
    for (final MapEntry<String, List<double>> h in byHabit.entries)
      h.key: (h.value..sort())[h.value.length ~/ 2],
  };
  return <JournalMark>[
    for (final ViceActivity e in entries)
      if (marks[e.viceID] case final HabitMark mark)
        if (daysBetween(e.createdAt.toDate(), today) case final int ago
            when ago >= 0 && ago < claudeWorkingDays)
          JournalMark(
            daysAgo: ago,
            minute:
                e.createdAt.toDate().hour * 60 + e.createdAt.toDate().minute,
            slot: mark.slot,
            weight: median[e.viceID]! > 0
                ? math
                      .sqrt(e.measure / median[e.viceID]!)
                      .clamp(0.6, 1.8)
                      .toDouble()
                : 1,
          ),
  ];
}

/// The last [claudeWorkingDays] days' entries on this device, for the looks;
/// empty until they load. Nothing here is sent anywhere.
final claudeWorkingMarksProvider = Provider.autoDispose<List<JournalMark>>((
  Ref ref,
) {
  final DateTime today = startOfDay(ref.watch(todayProvider));
  final List<Vice>? vices = ref.watch(viceListProvider).value;
  final List<ViceActivity>? entries = ref
      .watch(
        viceActivityRangeProvider((
          start: addDays(today, -(claudeWorkingDays - 1)),
          end: addDays(today, 1),
        )),
      )
      .value;
  if (vices == null || entries == null) return const <JournalMark>[];
  return journalMarks(vices, entries, today);
});

/// Shows [work] fullscreen once it has run for [ClaudeWorking.delay], grown
/// out of [from] (the tapped widget). When the work is answered, the screen
/// draws together and flies into the widget wrapped in
/// [ClaudeWorkingResult] with [resultTag], if there is one on the page below;
/// otherwise, and on failure or Stop, it shrinks back into [from]. Back hides
/// the screen and leaves the call running. [onStop] adds Stop, which must
/// really abandon the call's result; the screen then calls
/// `work.finish(ClaudeWorkEnd.stopped)` itself. Completes once the screen is
/// gone, or at once when the work ended before the delay.
Future<void> showClaudeWorking(
  BuildContext from,
  ClaudeWork work, {
  Object? resultTag,
  VoidCallback? onStop,
  ClaudeWorkingLook? look,
  List<JournalMark>? marks,
}) async {
  if (work.over) return;
  final NavigatorState navigator = Navigator.of(from);
  final RenderObject? box = from.findRenderObject();
  final Rect origin = box is RenderBox && box.hasSize
      ? box.localToGlobal(Offset.zero) & box.size
      : Rect.zero;
  final Completer<bool> shown = Completer<bool>();
  final Timer timer = Timer(ClaudeWorking.delay, () {
    if (!shown.isCompleted) shown.complete(true);
  });
  void ended() {
    if (work.over && !shown.isCompleted) {
      timer.cancel();
      shown.complete(false);
    }
  }

  work.addListener(ended);
  final bool show = await shown.future;
  work.removeListener(ended);
  if (!show || !navigator.mounted) return;
  await navigator.push(
    ClaudeWorkingRoute(
      work: work,
      origin: origin,
      resultTag: resultTag,
      onStop: onStop,
      look: look,
      marks: marks,
    ),
  );
}

/// Wraps where a call's result appears, so the working screen resolves into
/// it. [tag] must be unique on the page and the same one given to
/// [showClaudeWorking].
class ClaudeWorkingResult extends StatelessWidget {
  const ClaudeWorkingResult({
    super.key,
    required this.tag,
    required this.child,
  });

  final Object tag;
  final Widget child;

  @override
  Widget build(BuildContext context) => Hero(
    tag: tag,
    flightShuttleBuilder:
        (
          BuildContext flight,
          Animation<double> animation,
          HeroFlightDirection direction,
          BuildContext fromHero,
          BuildContext toHero,
        ) {
          final Size? size = (toHero.findRenderObject() as RenderBox?)?.size;
          final Widget result = (toHero.widget as Hero).child;
          return AnimatedBuilder(
            animation: animation,
            builder: (BuildContext context, Widget? _) {
              final double t = direction == HeroFlightDirection.pop
                  ? 1 - animation.value
                  : animation.value;
              return Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  Opacity(
                    opacity: (1 - t * 1.6).clamp(0.0, 1.0),
                    child: (fromHero.widget as Hero).child,
                  ),
                  Opacity(
                    opacity: ((t - 0.25) / 0.75).clamp(0.0, 1.0),
                    child: ClipRect(
                      child: FittedBox(
                        fit: BoxFit.fill,
                        alignment: Alignment.topCenter,
                        child: SizedBox.fromSize(size: size, child: result),
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
    child: child,
  );
}

class ClaudeWorkingRoute extends PageRoute<void> {
  ClaudeWorkingRoute({
    required this.work,
    required this.origin,
    this.resultTag,
    this.onStop,
    this.look,
    this.marks,
  });

  final ClaudeWork work;
  final Rect origin;
  final Object? resultTag;
  final VoidCallback? onStop;
  final ClaudeWorkingLook? look;
  final List<JournalMark>? marks;

  // Set just before an answered pop, when the result's hero carries the
  // eye: the screen behind it fades rather than shrinking to the origin.
  bool _intoResult = false;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  bool get maintainState => true;

  @override
  Duration get transitionDuration => ClaudeWorking.grow;

  @override
  Duration get reverseTransitionDuration => DialMotion.containerTransform;

  // The Reduce motion setting decides through MediaQuery, as DialPageRoute.
  @override
  AnimationController createAnimationController() => AnimationController(
    duration: transitionDuration,
    reverseDuration: reverseTransitionDuration,
    debugLabel: debugLabel,
    animationBehavior: AnimationBehavior.preserve,
    vsync: navigator!,
  );

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => _ClaudeWorkingScreen(route: this);

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return FadeTransition(
        opacity: CurvedAnimation(
          parent: animation,
          curve: Interval(
            0,
            DialMotion.reducedFade.inMicroseconds /
                ClaudeWorking.grow.inMicroseconds,
          ),
        ),
        child: child,
      );
    }
    if (_intoResult) {
      return FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeIn),
        child: child,
      );
    }
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (BuildContext context, Widget? child) {
        final double t = DialMotion.travel.transform(animation.value);
        final Rect full = Offset.zero & MediaQuery.sizeOf(context);
        final Rect from = origin.isEmpty
            ? Rect.fromCenter(center: full.center, width: 120, height: 120)
            : origin;
        return ClipRRect(
          clipper: _GrowClipper(
            Rect.lerp(from, full, t)!,
            _lerp(DialRadius.tile, 0, t),
          ),
          child: Opacity(opacity: (t * 2.5).clamp(0.0, 1.0), child: child),
        );
      },
    );
  }
}

double _lerp(double a, double b, double t) => a + (b - a) * t;

class _GrowClipper extends CustomClipper<RRect> {
  const _GrowClipper(this.rect, this.radius);

  final Rect rect;
  final double radius;

  @override
  RRect getClip(Size size) =>
      RRect.fromRectAndRadius(rect, Radius.circular(radius));

  @override
  bool shouldReclip(_GrowClipper old) =>
      old.rect != rect || old.radius != radius;
}

class _ClaudeWorkingScreen extends ConsumerStatefulWidget {
  const _ClaudeWorkingScreen({required this.route});

  final ClaudeWorkingRoute route;

  @override
  ConsumerState<_ClaudeWorkingScreen> createState() =>
      _ClaudeWorkingScreenState();
}

class _ClaudeWorkingScreenState extends ConsumerState<_ClaudeWorkingScreen>
    with TickerProviderStateMixin {
  late final WorkingClock _clock = WorkingClock(this);
  late final AnimationController _resolve = AnimationController(
    vsync: this,
    duration: ClaudeWorking.resolve,
  );
  final DateTime _shownAt = DateTime.now();
  Timer? _hold;
  bool _plate = false;
  bool _leaving = false;

  ClaudeWork get work => widget.route.work;

  @override
  void initState() {
    super.initState();
    work.addListener(_changed);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _clock.still = MediaQuery.disableAnimationsOf(context);
  }

  @override
  void dispose() {
    work.removeListener(_changed);
    _hold?.cancel();
    _clock.dispose();
    _resolve.dispose();
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    if (!work.over || _hold != null || _leaving) return;
    final Duration left =
        ClaudeWorking.minShown - DateTime.now().difference(_shownAt);
    _hold = Timer(left.isNegative ? Duration.zero : left, _leave);
  }

  Future<void> _leave() async {
    if (!mounted || _leaving) return;
    _leaving = true;
    final ClaudeWorkingRoute route = widget.route;
    final bool still = MediaQuery.disableAnimationsOf(context);
    if (work.end == ClaudeWorkEnd.answered && route.resultTag != null) {
      if (!still) {
        setState(() => _plate = true);
        await _resolve.forward();
        if (!mounted) return;
        route._intoResult = true;
      }
    }
    if (!route.isActive) return;
    if (route.isCurrent) {
      Navigator.of(context).pop();
    } else {
      Navigator.of(context).removeRoute(route);
    }
  }

  void _stop() {
    widget.route.onStop?.call();
    work.finish(ClaudeWorkEnd.stopped);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final DialColors colors = DialColors.of(context);
    final ClaudeWorkingLook look =
        widget.route.look ?? ref.watch(claudeWorkingLookProvider);
    final List<JournalMark> marks =
        widget.route.marks ?? ref.watch(claudeWorkingMarksProvider);
    final String? subject = work.subject;
    final double width = MediaQuery.sizeOf(context).width;
    final Size plate = Size(math.min(width - 2 * DialSpace.gutter, 520), 132);

    return Material(
      color: scheme.surface,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: DialSpace.gutter),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const SizedBox(height: DialSpace.m),
              Row(
                children: <Widget>[
                  Text(
                    ClaudeWorking.label.toUpperCase(),
                    style: DialTypeScale.label.copyWith(
                      fontSize: 11,
                      letterSpacing: 1.4,
                      color: colors.muted,
                    ),
                  ),
                  const Spacer(),
                  if (work.steps case final int steps)
                    _Steps(steps: steps, done: work.stepsDone),
                ],
              ),
              if (subject != null && look != ClaudeWorkingLook.ink) ...<Widget>[
                const SizedBox(height: DialSpace.s),
                Text(
                  subject,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: DialTypeScale.displayM.copyWith(
                    color: scheme.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    ExcludeSemantics(
                      child: RepaintBoundary(
                        child: CustomPaint(
                          painter: workingPainter(
                            look,
                            WorkingScene(
                              clock: _clock,
                              resolve: _resolve,
                              marks: marks,
                              colors: WorkingColors.of(context),
                              label: DialType.of(context).monoS,
                              today: ref.watch(todayProvider),
                              plate: plate,
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (subject != null && look == ClaudeWorkingLook.ink)
                      Center(
                        child: FadeTransition(
                          opacity: ReverseAnimation(_resolve),
                          child: ConstrainedBox(
                            constraints: BoxConstraints(maxWidth: width * 0.62),
                            child: Text(
                              subject,
                              maxLines: 4,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: DialTypeScale.displayM.copyWith(
                                color: scheme.onSurface,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (work.showElapsed && look == ClaudeWorkingLook.dial)
                      Center(
                        child: FadeTransition(
                          opacity: ReverseAnimation(_resolve),
                          child: _Elapsed(
                            since: work.started,
                            style: DialType.of(context).monoL,
                          ),
                        ),
                      ),
                    if (_plate)
                      Center(
                        child: ScaleTransition(
                          scale: CurvedAnimation(
                            parent: _resolve,
                            curve: const Interval(
                              0.45,
                              1,
                              curve: Curves.easeOutBack,
                            ),
                          ),
                          child: Hero(
                            tag: widget.route.resultTag!,
                            child: SizedBox.fromSize(
                              size: plate,
                              child: const WorkingPlate(),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Semantics(
                liveRegion: true,
                label: <String>[work.status, ?work.detail].join('. '),
                child: ExcludeSemantics(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        work.status,
                        style: DialTypeScale.bodyL.copyWith(
                          color: scheme.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (work.detail case final String detail) ...<Widget>[
                        const SizedBox(height: 2),
                        Text(
                          detail,
                          style: DialTypeScale.body.copyWith(
                            color: colors.muted,
                          ),
                        ),
                      ],
                      if (work.showElapsed &&
                          look != ClaudeWorkingLook.dial) ...<Widget>[
                        const SizedBox(height: DialSpace.xs),
                        _Elapsed(
                          since: work.started,
                          style: DialType.of(context).monoM,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: DialSpace.m),
              if (widget.route.onStop != null)
                OutlinedButton(
                  onPressed: work.over ? null : _stop,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(DialSize.pillHeight),
                    shape: const StadiumBorder(),
                  ),
                  child: const Text(ClaudeWorking.stop),
                ),
              const SizedBox(height: DialSpace.m),
            ],
          ),
        ),
      ),
    );
  }
}

/// The card-shaped surface the screen draws together into, which flies to
/// the result.
class WorkingPlate extends StatelessWidget {
  const WorkingPlate({super.key});

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      border: Border.all(color: DialColors.of(context).line),
      borderRadius: BorderRadius.circular(DialRadius.tile),
    ),
  );
}

class _Steps extends StatelessWidget {
  const _Steps({required this.steps, required this.done});

  final int steps;
  final int done;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final DialColors colors = DialColors.of(context);
    return Semantics(
      label: ClaudeWorking.stepOf(math.min(done + 1, steps), steps),
      child: ExcludeSemantics(
        child: Row(
          children: <Widget>[
            Text(
              ClaudeWorking.stepOf(math.min(done + 1, steps), steps),
              style: DialType.of(context).monoS,
            ),
            const SizedBox(width: DialSpace.xs),
            for (int i = 0; i < steps; i++)
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: AnimatedContainer(
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : DialMotion.tallyRoll,
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i < done ? scheme.onSurface : null,
                    border: Border.all(
                      color: i <= done ? scheme.onSurface : colors.line,
                      width: 1.2,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Elapsed extends StatefulWidget {
  const _Elapsed({required this.since, required this.style});

  final DateTime since;
  final TextStyle style;

  @override
  State<_Elapsed> createState() => _ElapsedState();
}

class _ElapsedState extends State<_Elapsed> {
  late final Timer _tick = Timer.periodic(
    const Duration(seconds: 1),
    (_) => setState(() {}),
  );

  @override
  void initState() {
    super.initState();
    _tick;
  }

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text(
    ClaudeWorking.elapsed(DateTime.now().difference(widget.since)),
    style: widget.style,
  );
}

/// Seconds since the looks began, ticking each frame; held at one still
/// moment under reduce motion, so nothing schedules frames.
class WorkingClock extends ValueNotifier<double> {
  WorkingClock(TickerProvider vsync) : super(_stillAt) {
    _ticker = vsync.createTicker(
      (Duration elapsed) => value = elapsed.inMicroseconds / 1e6,
    );
  }

  static const double _stillAt = 2.4;

  late final Ticker _ticker;

  set still(bool still) {
    if (still) {
      _ticker.stop();
      value = _stillAt;
    } else if (!_ticker.isActive) {
      _ticker.start();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }
}

/// A call in flight drawn in place, for a call nobody tapped or one too
/// short to leave the page: the look in a small square beside its words.
class ClaudeWorkingCard extends ConsumerStatefulWidget {
  const ClaudeWorkingCard({
    super.key,
    required this.status,
    this.detail,
    this.look,
    this.marks = const <JournalMark>[],
  });

  final String status;
  final String? detail;
  final ClaudeWorkingLook? look;
  final List<JournalMark> marks;

  @override
  ConsumerState<ClaudeWorkingCard> createState() => _ClaudeWorkingCardState();
}

class _ClaudeWorkingCardState extends ConsumerState<ClaudeWorkingCard>
    with SingleTickerProviderStateMixin {
  late final WorkingClock _clock = WorkingClock(this);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _clock.still = MediaQuery.disableAnimationsOf(context);
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final DialColors colors = DialColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border.all(color: colors.line),
        borderRadius: BorderRadius.circular(DialRadius.tile),
      ),
      child: Padding(
        padding: const EdgeInsets.all(DialSpace.s),
        child: Row(
          children: <Widget>[
            ExcludeSemantics(
              child: RepaintBoundary(
                child: SizedBox.square(
                  dimension: 64,
                  child: CustomPaint(
                    painter: workingPainter(
                      widget.look ?? ref.watch(claudeWorkingLookProvider),
                      WorkingScene(
                        clock: _clock,
                        resolve: kAlwaysDismissedAnimation,
                        marks: widget.marks,
                        colors: WorkingColors.of(context),
                        label: DialType.of(context).monoS,
                        today: DateTime.now(),
                        plate: Size.zero,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: DialSpace.s),
            Expanded(
              child: Semantics(
                liveRegion: true,
                label: <String>[widget.status, ?widget.detail].join('. '),
                child: ExcludeSemantics(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        widget.status,
                        style: DialTypeScale.body.copyWith(
                          color: scheme.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (widget.detail case final String detail)
                        Text(
                          detail,
                          style: DialTypeScale.bodyS.copyWith(
                            color: colors.muted,
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
    );
  }
}
