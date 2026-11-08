import 'dart:async';
import 'dart:math';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart' show ValueListenable, listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/data/dial_layout.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/design/dial_theme.dart';
import 'package:tracker/design/habit_mark.dart';
import 'package:tracker/design/tokens.dart';
import 'package:tracker/formats.dart';
import 'package:tracker/widgets/bead_arrivals.dart';
import 'package:tracker/widgets/bead_painter.dart';

// One entry as the dial draws it.
class DialEntry {
  const DialEntry({
    required this.id,
    required this.vice,
    required this.mark,
    required this.quantity,
    required this.at,
    this.pending = false,
  });

  final String id;
  final Vice vice;
  final HabitMark mark;
  final num quantity;
  final DateTime at;
  final bool pending;
}

// The copy of a day with no entries, in the hub.
abstract final class ClearDay {
  static const String headline = 'A clear day';
  static String subline({required bool isToday}) =>
      isToday ? 'so far' : 'nothing logged';

  // Offline, an empty day may only be one this device never fetched.
  static const String offlineHeadline = 'Nothing on this device';
  static const String offlineBody =
      'Entries made elsewhere show once you are back online.';
}

class DayDial extends ConsumerStatefulWidget {
  const DayDial({
    super.key,
    required this.day,
    required this.today,
    required this.entries,
    required this.semanticsLabel,
    this.offline = false,
    this.storedTypicals = const <String, double>{},
    this.onBeadTap,
    this.onSwipe,
  });

  final DateTime day;
  final DateTime today;
  // Null while the day loads.
  final List<DialEntry>? entries;
  final String? semanticsLabel;
  final bool offline;
  // Each habit's typical entry from the monthly summary, by vice ID; a habit
  // missing from it is sized against the shown day's median.
  final Map<String, double> storedTypicals;
  final void Function(DialEntry entry)? onBeadTap;
  // -1 for the day before, 1 for the day after.
  final void Function(int days)? onSwipe;

  // The dial's one spoken label: the day, each habit's total, and when the
  // first and last entries were.
  static String summary(
    DateTime day,
    DateTime today,
    List<Vice> habits,
    List<num> totals,
    List<DateTime> times, {
    required bool alwaysUse24HourFormat,
  }) {
    final int daysAgo = daysBetween(day, today);
    final String date = daysAgo < 2
        ? '${dayWord(day, today)}, ${dayPillDate(day, today)}'
        : formatDay(day);
    final String parts = [
      for (int i = 0; i < habits.length; i++)
        '${habits[i].name} ${habits[i].unit.label(totals[i])}',
    ].join(', ');
    String time(DateTime t) =>
        formatTime(t, alwaysUse24HourFormat: alwaysUse24HourFormat);
    final List<DateTime> sorted = [...times]..sort();
    final String span = sorted.isEmpty
        ? 'Nothing recorded.'
        : sorted.length == 1
        ? 'One entry, at ${time(sorted.first)}.'
        : 'First entry ${time(sorted.first)}, last ${time(sorted.last)}.';
    return '$date. ${parts.isEmpty ? '' : '$parts. '}$span';
  }

  static String beadLabel(DialEntry entry, {required bool alwaysUse24Hour}) =>
      '${entry.vice.name}, ${entry.vice.unit.label(entry.quantity)} at '
      '${formatTime(entry.at, alwaysUse24HourFormat: alwaysUse24Hour)}'
      '${entry.pending ? ', not yet synced' : ''}';

  // The quantity each habit's beads are sized against.
  static Map<String, double> typicals(
    Iterable<DialEntry> entries, {
    Map<String, double> stored = const <String, double>{},
  }) {
    final Map<String, List<num>> byHabit = <String, List<num>>{};
    for (final DialEntry e in entries) {
      (byHabit[e.vice.id] ??= <num>[]).add(e.quantity);
    }
    return <String, double>{
      for (final MapEntry<String, List<num>>(:key, :value) in byHabit.entries)
        key: stored[key] ?? typicalQuantity(value),
    };
  }

  // Where each bead sits, by id; an entry merged into its hour's arc has none.
  static Map<String, BeadPlacement> layout(
    List<DialEntry> entries, {
    Map<String, double> stored = const <String, double>{},
  }) {
    final Map<String, double> typical = typicals(entries, stored: stored);
    final Set<int> dense = denseHours(<double>[
      for (final DialEntry e in entries) minuteOfDay(e.at),
    ]);
    return layoutBeads(
      <DialBeadInput>[
        for (final DialEntry e in entries)
          if (!dense.contains(e.at.hour))
            DialBeadInput(
              id: e.id,
              habit: e.vice.id,
              minute: minuteOfDay(e.at),
              radius: beadRadius(e.quantity, typical[e.vice.id]!),
            ),
      ],
      arcs: <HourArc>[for (final int hour in dense) HourArc(hour)],
    );
  }

  // The entries of each hour drawn as one arc, by hour, in time order.
  static Map<int, List<DialEntry>> denseHourEntries(List<DialEntry> entries) {
    final Set<int> dense = denseHours(<double>[
      for (final DialEntry e in entries) minuteOfDay(e.at),
    ]);
    final Map<int, List<DialEntry>> byHour = <int, List<DialEntry>>{};
    for (final DialEntry e in entries) {
      if (dense.contains(e.at.hour)) {
        (byHour[e.at.hour] ??= <DialEntry>[]).add(e);
      }
    }
    for (final List<DialEntry> hour in byHour.values) {
      hour.sort((DialEntry a, DialEntry b) => a.at.compareTo(b.at));
    }
    return byHour;
  }

  // An arc's habits in the face's habit order, each with its entry count and
  // total.
  static List<({Vice vice, HabitMark mark, int count, num total})> arcShares(
    List<DialEntry> hour,
  ) {
    final Map<String, ({Vice vice, HabitMark mark, int count, num total})>
    byHabit = <String, ({Vice vice, HabitMark mark, int count, num total})>{};
    for (final DialEntry e in hour) {
      final ({Vice vice, HabitMark mark, int count, num total})? seen =
          byHabit[e.vice.id];
      byHabit[e.vice.id] = (
        vice: e.vice,
        mark: e.mark,
        count: (seen?.count ?? 0) + 1,
        total: (seen?.total ?? 0) + e.quantity,
      );
    }
    return byHabit.values.toList()
      ..sort((a, b) => a.mark.creationIndex.compareTo(b.mark.creationIndex));
  }

  static const String arcHint = 'Opens the latest entry';

  // One action label per entry of an arc. Actions with one label are one
  // action, so entries that read alike are numbered.
  static List<(String, DialEntry)> arcActions(
    List<DialEntry> entries, {
    required bool alwaysUse24Hour,
  }) {
    final Map<String, int> seen = <String, int>{};
    final List<(String, DialEntry)> actions = <(String, DialEntry)>[];
    for (final DialEntry e in entries) {
      final String label = beadLabel(e, alwaysUse24Hour: alwaysUse24Hour);
      final int k = seen[label] = (seen[label] ?? 0) + 1;
      actions.add((k == 1 ? label : '$label ($k)', e));
    }
    return actions;
  }

  static String arcLabel(
    int hour,
    List<DialEntry> entries, {
    required bool alwaysUse24Hour,
  }) {
    final DateTime at = entries.first.at;
    String time(int h) => formatTime(
      DateTime(at.year, at.month, at.day, h),
      alwaysUse24HourFormat: alwaysUse24Hour,
    );
    final String habits = <String>[
      for (final s in arcShares(entries))
        '${s.vice.name} ${s.vice.unit.label(s.total)}',
    ].join(', ');
    final int pending = entries.where((DialEntry e) => e.pending).length;
    return '${formatCount(entries.length)} entries from ${time(hour)} to '
        '${time(hour + 1)}: $habits'
        '${pending > 0 ? ', ${formatCount(pending)} not yet synced' : ''}';
  }

  @override
  ConsumerState<DayDial> createState() => _DayDialState();
}

class _DayDialState extends ConsumerState<DayDial>
    with TickerProviderStateMixin {
  static const SpringDescription _spring = DialMotion.landing;
  static const Duration _springTail = Duration(milliseconds: 700);
  // The mock-up's ease back from a drag too short to change the day.
  static const Duration _snapBack = Duration(milliseconds: 220);

  late final Ticker _ticker;
  Duration _t = Duration.zero;

  // Beads of the day being left, drawn while they contract to the hub.
  List<DialEntry> _outgoing = const <DialEntry>[];
  Map<String, BeadPlacement> _outgoingLayout = const {};
  Duration? _contractStart;
  bool _awaitingSweep = false;
  Duration? _sweepStart;
  Duration? _fadeStart;
  final Map<String, Duration> _popAt = <String, Duration>{};
  final Map<String, Duration> _landAt = <String, Duration>{};
  final Map<String, Duration> _syncAt = <String, Duration>{};
  final Map<String, Duration> _fadeInAt = <String, Duration>{};
  final Set<String> _flying = <String>{};
  Set<String> _known = <String>{};
  Set<String> _pending = <String>{};
  final List<OverlayEntry> _flights = <OverlayEntry>[];

  bool _clear = false;
  Duration? _clearStart;
  double _clearFrom = 0;

  final ValueNotifier<DateTime> _clock = ValueNotifier<DateTime>(clock.now());
  Timer? _clockTimer;
  double _drag = 0;
  // Where a drag caught the dial while it was still easing back.
  double _dragFrom = 0;
  double _snapFrom = 0;
  Duration? _snapStart;
  final ValueNotifier<double> _spin = ValueNotifier<double>(0);
  bool _wasMoving = false;

  bool get _reduced => MediaQuery.disableAnimationsOf(context);
  bool get _isToday => widget.day == widget.today;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    _awaitingSweep = true;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _armClock();
    _absorb();
  }

  @override
  void didUpdateWidget(DayDial old) {
    super.didUpdateWidget(old);
    if (old.day != widget.day) {
      _outgoing = old.entries ?? const <DialEntry>[];
      _outgoingLayout = DayDial.layout(_outgoing, stored: old.storedTypicals);
      _known = <String>{};
      _popAt.clear();
      _landAt.clear();
      _fadeInAt.clear();
      _awaitingSweep = true;
      _sweepStart = null;
      // Under reduce motion the old day's beads fade where they are rather
      // than contract.
      if (_outgoing.isNotEmpty) {
        _contractStart = _start();
      } else {
        _outgoing = const <DialEntry>[];
      }
    }
    _armClock();
    _absorb();
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _clock.dispose();
    _spin.dispose();
    for (final OverlayEntry flight in _flights) {
      flight.remove();
      flight.dispose();
    }
    _flights.clear();
    _ticker.dispose();
    super.dispose();
  }

  void _armClock() {
    _clockTimer?.cancel();
    _clockTimer = null;
    if (!_isToday) {
      return;
    }
    _clock.value = clock.now();
    _clockTimer = Timer.periodic(
      _reduced ? const Duration(minutes: 1) : const Duration(seconds: 1),
      (_) => _clock.value = clock.now(),
    );
  }

  // The ticker's elapsed time restarts with it, so every start time is taken
  // from the run in progress.
  // Whatever was timed by an earlier run has finished, so it is dropped.
  Duration _start() {
    if (!_ticker.isActive) {
      _t = Duration.zero;
      _popAt.clear();
      _landAt.clear();
      _syncAt.clear();
      _fadeInAt.clear();
      _sweepStart = null;
      _fadeStart = null;
      _clearStart = null;
      _contractStart = null;
      _snapStart = null;
      _ticker.start();
    }
    return _t;
  }

  // A pending bead's turning rim only repaints the bead layer, so a day left
  // unsynced offline does not rebuild the dial every frame.
  void _onTick(Duration elapsed) {
    _t = elapsed;
    _spin.value = _reduced
        ? 0
        : elapsed.inMicroseconds /
              DialMotion.pendingRotation.inMicroseconds *
              2 *
              pi;
    final bool moving = _animating();
    if (!moving && !_spinning) {
      _ticker.stop();
    }
    // One more build after the motion ends draws its last frame.
    if (moving || _wasMoving) {
      setState(() {});
    }
    _wasMoving = moving;
  }

  bool get _spinning => _pending.isNotEmpty && !_reduced;

  bool _within(Duration? start, Duration length) =>
      start != null && _t - start < length;

  bool _animating() =>
      _within(_contractStart, _leaving) ||
      _within(_snapStart, _snapBack) ||
      _awaitingSweepAfterContract ||
      _within(_sweepStart, DialMotion.daySweep + _springTail) ||
      _within(_fadeStart, DialMotion.reducedFade) ||
      _popAt.values.any((Duration s) => _within(s, _springTail)) ||
      _landAt.values.any((Duration s) => _within(s, _springTail)) ||
      _syncAt.values.any((Duration s) => _within(s, DialMotion.pendingFill)) ||
      _fadeInAt.values.any(
        (Duration s) => _within(s, DialMotion.reducedFade),
      ) ||
      _within(_clearStart, DialMotion.cleanDayGlow);

  Duration get _leaving =>
      _reduced ? DialMotion.reducedFade : DialMotion.dayContract;

  bool get _awaitingSweepAfterContract =>
      _awaitingSweep && widget.entries != null && _contractStart != null;

  // Takes in what the latest entries change: the sweep once a new day has
  // loaded, beads arriving from a log, entries that synced or appeared.
  void _absorb() {
    final List<DialEntry>? entries = widget.entries;
    if (entries == null) {
      return;
    }

    final bool clear = entries.isEmpty;
    if (clear != _clear) {
      _clearFrom = _clearProgress();
      _clear = clear;
      _clearStart = _reduced ? null : _start();
    }

    final Set<String> ids = <String>{for (final DialEntry e in entries) e.id};
    final Set<String> pending = <String>{
      for (final DialEntry e in entries)
        if (e.pending) e.id,
    };
    for (final String id in _pending.difference(pending)) {
      if (ids.contains(id) && !_reduced) {
        _syncAt[id] = _start();
      }
    }
    _pending = pending;
    if (_spinning) {
      _start();
    }

    if (_awaitingSweep) {
      if (_contractStart != null && _t - _contractStart! < _leaving) {
        return;
      }
      _awaitingSweep = false;
      _contractStart = null;
      _outgoing = const <DialEntry>[];
      _known = ids;
      ref.read(beadArrivalsProvider).takeAll(ids);
      if (entries.isNotEmpty) {
        if (_reduced) {
          _fadeStart = _start();
        } else {
          _sweepStart = _start();
        }
      }
      return;
    }

    final Map<String, Offset> arrivals = ref
        .read(beadArrivalsProvider)
        .takeAll(ids.difference(_known));
    for (final String id in ids.difference(_known)) {
      final Offset? from = arrivals[id];
      if (_reduced) {
        _fadeInAt[id] = _start();
      } else if (from != null) {
        _flying.add(id);
        WidgetsBinding.instance.addPostFrameCallback((_) => _fly(id, from));
      } else {
        _popAt[id] = _start();
      }
    }
    _known = ids;
  }

  void _fly(String id, Offset from) {
    final DialEntry? entry = widget.entries
        ?.where((DialEntry e) => e.id == id)
        .firstOrNull;
    final RenderBox? box = context.findRenderObject() as RenderBox?;
    if (!mounted || entry == null || box == null || !box.hasSize) {
      _flying.remove(id);
      return;
    }
    final double scale = box.size.shortestSide / DialFace.side;
    final BeadPlacement place =
        DayDial.layout(widget.entries!, stored: widget.storedTypicals)[id] ??
        BeadPlacement(
          angle: HourArc(entry.at.hour).middle,
          track: HourArc.track,
          radius: HourArc.half,
        );
    final Offset to = box.localToGlobal(
      box.size.center(Offset.zero) + place.position * scale,
    );
    final DialColors colors = DialColors.of(context);
    late final OverlayEntry flight;
    flight = OverlayEntry(
      builder: (BuildContext context) => _BeadFlight(
        from: from,
        to: to,
        radius: place.radius * scale,
        mark: entry.mark,
        colors: colors,
        onLanded: () {
          // The dial removes what is still flying when it goes.
          if (!_flights.remove(flight)) {
            return;
          }
          flight.remove();
          flight.dispose();
          if (!mounted) {
            return;
          }
          HapticFeedback.lightImpact();
          setState(() {
            _flying.remove(id);
            _landAt[id] = _start();
          });
        },
      ),
    );
    _flights.add(flight);
    Overlay.of(context, rootOverlay: true).insert(flight);
  }

  double _clearProgress() {
    final double target = _clear ? 1 : 0;
    if (_clearStart == null) {
      return target;
    }
    final double k =
        ((_t - _clearStart!).inMicroseconds /
                DialMotion.cleanDayGlow.inMicroseconds)
            .clamp(0, 1);
    return _clearFrom + (target - _clearFrom) * DialMotion.travel.transform(k);
  }

  double _springAt(Duration since, {double from = 0}) {
    final double seconds = since.inMicroseconds / 1e6;
    if (seconds <= 0) {
      return from;
    }
    if (seconds >= _springTail.inMicroseconds / 1e6) {
      return 1;
    }
    return SpringSimulation(_spring, from, 1, 0).x(seconds);
  }

  // The dial follows a quarter of the drag, and eases back once let go.
  double _shift() {
    if (_snapStart case final Duration start) {
      final double k = (_t - start).inMicroseconds / _snapBack.inMicroseconds;
      return k >= 1 ? 0 : _snapFrom * (1 - Curves.easeOut.transform(k));
    }
    return _dragFrom + _drag * 0.25;
  }

  void _release() {
    setState(() {
      _snapFrom = _dragFrom + _drag * 0.25;
      _dragFrom = 0;
      _drag = 0;
      _snapStart = _snapFrom == 0 || _reduced ? null : _start();
    });
  }

  // The hand's share of a turn during the day sweep, or null outside one.
  double? _sweepTurn() {
    if (_sweepStart == null) {
      return null;
    }
    final Duration since = _t - _sweepStart!;
    if (since >= DialMotion.daySweep) {
      return null;
    }
    return DialMotion.travel.transform(
      since.inMicroseconds / DialMotion.daySweep.inMicroseconds,
    );
  }

  // The sweep's trace: its share of a turn and its opacity, held full once the
  // hand has gone round and fading out after, or null when there is none.
  // The mock-up fades it over 260 ms, which has no token; the ripple's 300 ms
  // is the nearest.
  ({double turn, double alpha})? _sweepTrace() {
    if (_sweepTurn() case final double turn) {
      return (turn: turn, alpha: 1);
    }
    if (_sweepStart == null) {
      return null;
    }
    final Duration after = _t - _sweepStart! - DialMotion.daySweep;
    if (after >= DialMotion.landingRipple) {
      return null;
    }
    return (
      turn: 1,
      alpha:
          1 -
          DialMotion.enter.transform(
            after.inMicroseconds / DialMotion.landingRipple.inMicroseconds,
          ),
    );
  }

  double _beadScale(String id, double angle) {
    if (_flying.contains(id)) {
      return 0;
    }
    if (_sweepStart != null) {
      final Duration since = _t - _sweepStart!;
      if (since < DialMotion.daySweep + _springTail) {
        final Duration? popped = _popAt[id];
        if (popped == null) {
          final double turn = ((angle + pi / 2) / (2 * pi)) % 1;
          final double? hand = _sweepTurn();
          if (hand == null || hand + 0.005 >= turn) {
            _popAt[id] = _t;
          }
          return 0;
        }
      }
    }
    final Duration? landed = _landAt[id];
    if (landed != null) {
      final double seconds = (_t - landed).inMicroseconds / 1e6;
      if (seconds < _springTail.inMicroseconds / 1e6) {
        return SpringSimulation(_spring, 1.25, 1, 0).x(seconds);
      }
    }
    final Duration? popped = _popAt[id];
    if (popped != null) {
      return _springAt(_t - popped);
    }
    return 1;
  }

  double _beadOpacity(String id) {
    final Duration? start = _fadeInAt[id] ?? _fadeStart;
    if (start == null) {
      return 1;
    }
    return ((_t - start).inMicroseconds / DialMotion.reducedFade.inMicroseconds)
        .clamp(0, 1);
  }

  void _onTapUp(TapUpDetails details, double scale, Size size) {
    final List<DialEntry>? entries = widget.entries;
    if (entries == null || widget.onBeadTap == null) {
      return;
    }
    final Map<String, BeadPlacement> layout = DayDial.layout(
      entries,
      stored: widget.storedTypicals,
    );
    final Offset local =
        (details.localPosition - size.center(Offset.zero)) / scale;
    DialEntry? nearest;
    double best = double.infinity;
    for (final DialEntry e in entries) {
      final BeadPlacement? p = layout[e.id];
      if (p == null) {
        continue;
      }
      final double d = (p.position - local).distance;
      if (d <= _hitRadius(p.radius, scale) / scale && d < best) {
        best = d;
        nearest = e;
      }
    }
    if (nearest == null &&
        (local.distance - HourArc.track).abs() <=
            HourArc.half + _hitRadius(0, scale) / scale) {
      // A tap on an arc opens the entry nearest the time tapped. The hour is
      // the tap's angle, so adjacent arcs never claim each other's taps.
      final double minute = HourArc.minuteAt(local);
      final List<DialEntry>? inHour = DayDial.denseHourEntries(
        entries,
      )[minute ~/ 60];
      nearest = inHour?.reduce(
        (DialEntry a, DialEntry b) =>
            (minuteOfDay(a.at) - minute).abs() <=
                (minuteOfDay(b.at) - minute).abs()
            ? a
            : b,
      );
    }
    if (nearest != null) {
      widget.onBeadTap!(nearest);
    }
  }

  // The design's slop, widened to the platform's minimum target.
  static double _hitRadius(double radius, double scale) =>
      max((radius + DialFace.beadHitSlop) * scale, DialSize.minTapTarget / 2);

  @override
  Widget build(BuildContext context) {
    if (_awaitingSweepAfterContract && _t - _contractStart! >= _leaving) {
      _absorb();
    }
    final DialColors colors = DialColors.of(context);
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final DialType type = DialType.of(context);
    final bool alwaysUse24Hour = MediaQuery.alwaysUse24HourFormatOf(context);
    final TextScaler textScaler = MediaQuery.textScalerOf(
      context,
    ).clamp(maxScaleFactor: 1.35);
    final List<DialEntry>? entries = widget.entries;
    final bool contracting =
        _contractStart != null && _t - _contractStart! < _leaving;
    final double left = contracting
        ? (_t - _contractStart!).inMicroseconds / _leaving.inMicroseconds
        : 1;
    final List<DialEntry> shown = contracting
        ? _outgoing
        : entries ?? const <DialEntry>[];
    final Map<String, BeadPlacement> layout = contracting
        ? _outgoingLayout
        : DayDial.layout(shown, stored: widget.storedTypicals);
    final double contract = contracting && !_reduced
        ? 1 - DialMotion.exit.transform(left)
        : 1;
    final double clear = entries == null ? 0 : _clearProgress();

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double side = constraints.biggest.shortestSide;
        final Size size = Size.square(side);
        final double scale = side / DialFace.side;
        final Offset centre = size.center(Offset.zero);

        final List<_PlacedBead> beads = <_PlacedBead>[
          for (final DialEntry e in shown)
            if (layout[e.id] case final BeadPlacement p)
              _PlacedBead(
                entry: e,
                centre: centre + p.position * scale * contract,
                radius: p.radius * scale,
                scale: contracting ? contract : _beadScale(e.id, p.angle),
                opacity: contracting
                    ? (_reduced ? 1 - left : 1)
                    : _beadOpacity(e.id),
                fill: _syncFill(e.id),
                label: shown.length <= DialFace.timedBeads && !contracting
                    ? (
                        text: formatClock(e.at),
                        at: beadLabelOffset(p.angle, p.radius),
                      )
                    : null,
              ),
        ];

        final List<_PlacedArc> arcs = <_PlacedArc>[
          for (final MapEntry<int, List<DialEntry>>(key: hour, value: inHour)
              in DayDial.denseHourEntries(shown).entries)
            _PlacedArc(
              arc: HourArc(hour),
              entries: inHour,
              contract: contract,
              scale: contracting ? 1 : _arcScale(hour, inHour),
              opacity: contracting ? 1 : _beadOpacity('hour-$hour'),
            ),
        ];

        final Widget face = RepaintBoundary(
          child: CustomPaint(
            size: size,
            painter: _FacePainter(
              colors: colors,
              surface: scheme.surfaceContainerLow,
              numeralStyle: type.dialNumeral,
              textScaler: textScaler,
              clear: clear,
              shadows: DialShadows.disc(Theme.of(context).brightness),
              // The mock-up's 60% is under 3:1 on the light wash.
              ringAlpha: Theme.of(context).brightness == Brightness.dark
                  ? 0.6
                  : 0.72,
            ),
          ),
        );

        final Widget hand = CustomPaint(
          size: size,
          painter: _HandPainter(
            clock: _clock,
            isToday: _isToday,
            accent: scheme.primary,
            text: scheme.onSurface,
            surface: scheme.surfaceContainerLow,
            sweep: _sweepTrace(),
          ),
        );

        final Widget beadLayer = RepaintBoundary(
          child: CustomPaint(
            size: size,
            painter: _BeadsPainter(
              beads: beads,
              arcs: arcs,
              colors: colors,
              surface: scheme.surfaceContainerLow,
              labelStyle: type.dialTime,
              textScaler: textScaler,
              spin: _spin,
              ripples:
                  <({Offset centre, double radius, HabitMark mark, double k})>[
                    for (final _PlacedBead b in beads)
                      if (_landAt[b.entry.id] case final Duration landed
                          when _t - landed < DialMotion.landingRipple)
                        (
                          centre: b.centre,
                          radius: b.radius,
                          mark: b.entry.mark,
                          k: DialMotion.enter.transform(
                            (_t - landed).inMicroseconds /
                                DialMotion.landingRipple.inMicroseconds,
                          ),
                        ),
                  ],
            ),
          ),
        );

        return Semantics(
          container: true,
          label: widget.semanticsLabel,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (TapUpDetails d) => _onTapUp(d, scale, size),
            onHorizontalDragStart: widget.onSwipe == null
                ? null
                : (DragStartDetails d) => setState(() {
                    _dragFrom = _shift();
                    _drag = 0;
                    _snapStart = null;
                  }),
            onHorizontalDragUpdate: widget.onSwipe == null
                ? null
                : (DragUpdateDetails d) => setState(() => _drag += d.delta.dx),
            onHorizontalDragEnd: widget.onSwipe == null
                ? null
                : (DragEndDetails d) {
                    final double dx = _drag;
                    _release();
                    if (dx > 50) {
                      widget.onSwipe!(-1);
                    } else if (dx < -50) {
                      widget.onSwipe!(1);
                    }
                  },
            onHorizontalDragCancel: _release,
            child: Transform.translate(
              offset: Offset(_shift(), 0),
              child: SizedBox.fromSize(
                size: size,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: <Widget>[
                    ExcludeSemantics(child: face),
                    ExcludeSemantics(child: hand),
                    ExcludeSemantics(child: beadLayer),
                    for (final _PlacedBead b in beads)
                      _beadTarget(b, scale, alwaysUse24Hour),
                    for (final _PlacedArc a in arcs)
                      _arcTarget(a, centre, scale, alwaysUse24Hour),
                    Positioned.fromRect(
                      rect: Rect.fromCircle(
                        center: centre,
                        radius: DialFace.hub * scale,
                      ),
                      child: ExcludeSemantics(
                        child: _hub(
                          context,
                          colors,
                          scheme,
                          type,
                          textScaler,
                          entries,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  double _syncFill(String id) {
    final Duration? synced = _syncAt[id];
    if (synced == null) {
      return 1;
    }
    final double k =
        (_t - synced).inMicroseconds / DialMotion.pendingFill.inMicroseconds;
    if (k >= 1) {
      return 1;
    }
    return DialMotion.enter.transform(k.clamp(0, 1));
  }

  // An arc pops in with the sweep as a bead does, and springs when one of
  // its entries lands.
  double _arcScale(int hour, List<DialEntry> inHour) {
    final double popped = _beadScale('hour-$hour', HourArc(hour).start);
    Duration? landed;
    for (final DialEntry e in inHour) {
      final Duration? at = _landAt[e.id];
      if (at != null && (landed == null || at > landed)) {
        landed = at;
      }
    }
    if (landed != null && _t - landed < _springTail) {
      return SpringSimulation(
        _spring,
        1.25,
        1,
        0,
      ).x((_t - landed).inMicroseconds / 1e6);
    }
    return popped;
  }

  // An arc is one button for a screen reader, naming the hour and what it
  // holds. A pointer opens the entry nearest the time tapped, which a screen
  // reader has no way to aim, so activating it opens the hour's latest entry
  // and each entry is one of its custom actions.
  Widget _arcTarget(
    _PlacedArc a,
    Offset centre,
    double scale,
    bool alwaysUse24Hour,
  ) {
    final void Function(DialEntry)? open = widget.onBeadTap;
    final Rect bounds = a.arc.outline().getBounds().inflate(
      DialFace.beadHitSlop,
    );
    return Positioned.fromRect(
      key: ValueKey<String>('arc-${a.arc.hour}'),
      rect: Rect.fromLTRB(
        centre.dx + bounds.left * scale,
        centre.dy + bounds.top * scale,
        centre.dx + bounds.right * scale,
        centre.dy + bounds.bottom * scale,
      ),
      child: Semantics(
        container: true,
        button: open != null,
        label: DayDial.arcLabel(
          a.arc.hour,
          a.entries,
          alwaysUse24Hour: alwaysUse24Hour,
        ),
        hint: open == null ? null : DayDial.arcHint,
        onTap: open == null ? null : () => open(a.entries.last),
        customSemanticsActions: open == null
            ? null
            : <CustomSemanticsAction, VoidCallback>{
                for (final (String label, DialEntry e) in DayDial.arcActions(
                  a.entries,
                  alwaysUse24Hour: alwaysUse24Hour,
                ))
                  CustomSemanticsAction(label: label): () => open(e),
              },
        child: const SizedBox.expand(),
      ),
    );
  }

  // Each bead is its own button for a screen reader; a pointer's tap goes to
  // the nearest bead through the dial's own detector.
  Widget _beadTarget(_PlacedBead b, double scale, bool alwaysUse24Hour) {
    final double hit = _hitRadius(b.radius / scale, scale);
    return Positioned.fromRect(
      key: ValueKey<String>('bead-${b.entry.id}'),
      rect: Rect.fromCircle(center: b.centre, radius: hit),
      child: Semantics(
        button: true,
        label: DayDial.beadLabel(b.entry, alwaysUse24Hour: alwaysUse24Hour),
        onTap: widget.onBeadTap == null
            ? null
            : () => widget.onBeadTap!(b.entry),
        child: const SizedBox.expand(),
      ),
    );
  }

  Widget _hub(
    BuildContext context,
    DialColors colors,
    ColorScheme scheme,
    DialType type,
    TextScaler textScaler,
    List<DialEntry>? entries,
  ) {
    final TextStyle second = DialTypeScale.bodyS.copyWith(
      color: colors.muted,
      fontSize: 12,
      height: 1.2,
    );
    final Widget content;
    if (entries == null) {
      content = SizedBox.square(
        dimension: 20,
        child: CircularProgressIndicator(strokeWidth: 2, color: colors.muted),
      );
    } else if (entries.isEmpty) {
      final TextStyle style = DialTypeScale.label.copyWith(
        color: colors.clearInk,
        fontSize: 12.5,
        height: 1.25,
      );
      content = Column(
        mainAxisSize: MainAxisSize.min,
        children: widget.offline
            ? <Widget>[
                Text(
                  ClearDay.offlineHeadline,
                  textAlign: TextAlign.center,
                  style: style,
                ),
              ]
            : <Widget>[
                Text(ClearDay.headline, style: style),
                Text(ClearDay.subline(isToday: _isToday), style: style),
              ],
      );
    } else {
      final String count =
          '${formatCount(entries.length)} '
          '${pluralWord(entries.length, one: 'entry', other: 'entries')}';
      content = Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (_isToday)
            ValueListenableBuilder<DateTime>(
              valueListenable: _clock,
              builder: (BuildContext context, DateTime now, _) => Text(
                formatClock(now),
                style: type.monoL.copyWith(fontSize: 21),
              ),
            )
          else
            Text(
              formatWeekdayShort(widget.day),
              style: type.monoL.copyWith(
                fontFamily: DialFonts.text,
                fontSize: 21,
              ),
            ),
          Text(count, style: second),
        ],
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(color: scheme.surface, shape: BoxShape.circle),
      child: MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: textScaler),
        child: Padding(
          padding: const EdgeInsets.all(6),
          // The text may run past the hub, as "nothing logged" does in the
          // mock-up, but stays inside the innermost bead track (radius 68).
          child: OverflowBox(
            maxWidth: 120,
            child: FittedBox(fit: BoxFit.scaleDown, child: content),
          ),
        ),
      ),
    );
  }
}

class _PlacedBead {
  const _PlacedBead({
    required this.entry,
    required this.centre,
    required this.radius,
    required this.scale,
    required this.opacity,
    required this.fill,
    required this.label,
  });

  final DialEntry entry;
  final Offset centre;
  final double radius;
  final double scale;
  final double opacity;
  final double fill;
  final ({String text, ({Offset offset, int align}) at})? label;
}

class _PlacedArc {
  const _PlacedArc({
    required this.arc,
    required this.entries,
    required this.contract,
    required this.scale,
    required this.opacity,
  });

  final HourArc arc;
  final List<DialEntry> entries;
  // The day-change contraction toward the hub, 1 at rest.
  final double contract;
  // The pop or landing spring of its width.
  final double scale;
  final double opacity;
}

class _FacePainter extends CustomPainter {
  _FacePainter({
    required this.colors,
    required this.surface,
    required this.numeralStyle,
    required this.textScaler,
    required this.clear,
    required this.shadows,
    required this.ringAlpha,
  });

  final List<BoxShadow> shadows;
  final double ringAlpha;
  final DialColors colors;
  final Color surface;
  final TextStyle numeralStyle;
  final TextScaler textScaler;
  // 0 with entries, 1 on a clear day; between while the ring draws on.
  final double clear;

  @override
  void paint(Canvas canvas, Size size) {
    final double scale = size.shortestSide / DialFace.side;
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(scale);

    for (final BoxShadow shadow in shadows) {
      canvas.drawCircle(
        shadow.offset,
        DialFace.disc + shadow.spreadRadius,
        shadow.toPaint(),
      );
    }
    canvas.drawCircle(Offset.zero, DialFace.disc, Paint()..color = surface);
    canvas.drawCircle(
      Offset.zero,
      DialFace.disc,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = colors.line,
    );

    if (clear > 0) {
      canvas.drawCircle(
        Offset.zero,
        DialFace.clearRing,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = DialFace.clearBand
          ..color = colors.clear.withValues(
            alpha: colors.clear.a * min(1, clear * 2),
          ),
      );
      canvas.drawArc(
        Rect.fromCircle(center: Offset.zero, radius: DialFace.clearRing),
        -pi / 2,
        2 * pi * clear,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round
          ..color = colors.clearInk.withValues(alpha: ringAlpha),
      );
    }

    for (int i = 0; i < 24; i++) {
      final bool major = i % 3 == 0;
      final double a = dialAngle(i * 60.0);
      final Paint paint = Paint()
        ..strokeCap = StrokeCap.round
        ..strokeWidth = major ? 1.4 : 1
        ..color = colors.spoke.withValues(
          alpha: colors.spoke.a * spokeOpacity(major: major, clear: clear),
        );
      canvas.drawLine(
        dialPoint(
          a,
          major ? DialFace.majorSpokeInner : DialFace.minorSpokeInner,
        ),
        dialPoint(
          a,
          major ? DialFace.majorSpokeOuter : DialFace.minorSpokeOuter,
        ),
        paint,
      );
    }

    for (final int hour in const <int>[0, 6, 12, 18]) {
      final TextPainter numeral = TextPainter(
        text: TextSpan(
          text: hour.toString().padLeft(2, '0'),
          style: numeralStyle.copyWith(color: colors.muted),
        ),
        textDirection: TextDirection.ltr,
        textScaler: textScaler,
      )..layout();
      final Offset at = dialPoint(dialAngle(hour * 60.0), DialFace.numerals);
      numeral.paint(canvas, at - Offset(numeral.width / 2, numeral.height / 2));
      numeral.dispose();
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(_FacePainter old) =>
      old.clear != clear ||
      old.ringAlpha != ringAlpha ||
      !listEquals(old.shadows, shadows) ||
      old.colors != colors ||
      old.surface != surface ||
      old.numeralStyle != numeralStyle ||
      old.textScaler != textScaler;
}

class _HandPainter extends CustomPainter {
  _HandPainter({
    required this.clock,
    required this.isToday,
    required this.accent,
    required this.text,
    required this.surface,
    required this.sweep,
  }) : super(repaint: clock);

  final ValueNotifier<DateTime> clock;
  final bool isToday;
  final Color accent;
  final Color text;
  final Color surface;
  // The sweeping hand's share of a turn on a day change, and its opacity.
  final ({double turn, double alpha})? sweep;

  @override
  void paint(Canvas canvas, Size size) {
    final double scale = size.shortestSide / DialFace.side;
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(scale);

    if (sweep case (turn: final double turn, alpha: final double alpha)) {
      final double a = -pi / 2 + 2 * pi * turn;
      canvas.drawArc(
        Rect.fromCircle(center: Offset.zero, radius: DialFace.disc),
        -pi / 2,
        2 * pi * turn,
        true,
        Paint()..color = text.withValues(alpha: 0.05 * alpha),
      );
      canvas.drawLine(
        Offset.zero,
        dialPoint(a, DialFace.majorSpokeOuter + 2),
        Paint()
          ..strokeWidth = 1.5
          ..strokeCap = StrokeCap.round
          ..color = text.withValues(alpha: 0.5 * alpha),
      );
    }

    if (isToday) {
      final double a = dialAngle(minuteOfDay(clock.value));
      canvas.drawArc(
        Rect.fromCircle(center: Offset.zero, radius: DialFace.disc),
        -pi / 2,
        a + pi / 2,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round
          ..color = accent.withValues(alpha: 0.22),
      );
      canvas.drawLine(
        Offset.zero,
        dialPoint(a, DialFace.hand),
        Paint()
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round
          ..color = accent,
      );
      canvas.drawCircle(Offset.zero, DialFace.handDot, Paint()..color = accent);
      final Offset tip = dialPoint(a, DialFace.disc);
      canvas.drawCircle(tip, DialFace.handTip, Paint()..color = surface);
      canvas.drawCircle(
        tip,
        DialFace.handTip,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = accent,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_HandPainter old) =>
      old.isToday != isToday ||
      old.sweep != sweep ||
      old.accent != accent ||
      old.text != text ||
      old.surface != surface;
}

class _BeadsPainter extends CustomPainter {
  _BeadsPainter({
    required this.beads,
    required this.arcs,
    required this.colors,
    required this.surface,
    required this.labelStyle,
    required this.textScaler,
    required this.spin,
    required this.ripples,
  }) : super(repaint: spin);

  final List<_PlacedBead> beads;
  final List<_PlacedArc> arcs;
  final DialColors colors;
  final Color surface;
  final TextStyle labelStyle;
  final TextScaler textScaler;
  // The pending rims' turn, in radians.
  final ValueListenable<double> spin;
  final List<({Offset centre, double radius, HabitMark mark, double k})>
  ripples;

  @override
  void paint(Canvas canvas, Size size) {
    final double scale = size.shortestSide / DialFace.side;
    for (final ({Offset centre, double radius, HabitMark mark, double k}) r
        in ripples) {
      canvas.drawCircle(
        r.centre,
        r.radius + 16 * scale * r.k,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2 * scale
          ..color = colors.habitInk(r.mark).withValues(alpha: 0.4 * (1 - r.k)),
      );
    }
    for (final _PlacedBead b in beads) {
      if (b.scale <= 0 || b.opacity <= 0) {
        continue;
      }
      final bool faded = b.opacity < 1;
      if (faded) {
        canvas.saveLayer(
          Rect.fromCircle(center: b.centre, radius: b.radius * 2 + 8),
          Paint()..color = surface.withValues(alpha: b.opacity),
        );
      }
      paintHabitMark(
        canvas,
        b.centre,
        b.radius * b.scale,
        b.entry.mark,
        colors,
        pending: b.entry.pending,
        fill: b.fill,
        rotation: spin.value,
      );
      if (faded) {
        canvas.restore();
      }
    }
    final Offset centre = size.center(Offset.zero);
    for (final _PlacedArc a in arcs) {
      if (a.scale <= 0 || a.opacity <= 0) {
        continue;
      }
      canvas
        ..save()
        ..translate(centre.dx, centre.dy)
        ..scale(scale);
      if (a.opacity < 1) {
        canvas.saveLayer(
          a.arc.outline().getBounds().inflate(8),
          Paint()..color = surface.withValues(alpha: a.opacity),
        );
      }
      final List<({Vice vice, HabitMark mark, int count, num total})> shares =
          DayDial.arcShares(a.entries);
      final List<Path> pieces = a.arc.shares(
        <int>[
          for (final ({Vice vice, HabitMark mark, int count, num total}) s
              in shares)
            s.count,
        ],
        radius: HourArc.track * a.contract,
        width: HourArc.half * a.scale * a.contract,
      );
      for (int i = 0; i < shares.length; i++) {
        paintHabitBand(canvas, pieces[i], shares[i].mark, colors);
      }
      if (a.opacity < 1) {
        canvas.restore();
      }
      canvas.restore();
    }
    for (final _PlacedBead b in beads) {
      if (b.label case final label? when b.scale > 0.5) {
        _paintLabel(canvas, b.centre, label.text, label.at, scale);
      }
    }
    for (final _PlacedArc a in arcs) {
      if (a.scale > 0.5 && a.contract == 1) {
        final double angle = a.arc.middle;
        _paintLabel(
          canvas,
          centre + dialPoint(angle, HourArc.track) * scale,
          formatCount(a.entries.length),
          beadLabelOffset(angle, HourArc.half),
          scale,
        );
      }
    }
  }

  void _paintLabel(
    Canvas canvas,
    Offset centre,
    String text,
    ({Offset offset, int align}) at,
    double scale,
  ) {
    TextPainter layOut(Paint? stroke) => TextPainter(
      text: TextSpan(
        text: text,
        style: stroke == null
            ? labelStyle.copyWith(color: colors.muted)
            : labelStyle.copyWith(foreground: stroke),
      ),
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
    )..layout();
    final TextPainter halo = layOut(
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeJoin = StrokeJoin.round
        ..color = surface,
    );
    final TextPainter label = layOut(null);
    final Offset anchor = centre + at.offset * scale;
    final double dx = switch (at.align) {
      0 => -label.width / 2,
      1 => 0,
      _ => -label.width,
    };
    final Offset origin = anchor + Offset(dx, -label.height / 2);
    halo.paint(canvas, origin);
    label.paint(canvas, origin);
    halo.dispose();
    label.dispose();
  }

  @override
  bool shouldRepaint(_BeadsPainter old) => true;
}

// A bead travelling from where it was logged to its place on the dial, along
// a quadratic arc, growing from the size it left at to its own.
class _BeadFlight extends StatefulWidget {
  const _BeadFlight({
    required this.from,
    required this.to,
    required this.radius,
    required this.mark,
    required this.colors,
    required this.onLanded,
  });

  final Offset from;
  final Offset to;
  final double radius;
  final HabitMark mark;
  final DialColors colors;
  final VoidCallback onLanded;

  @override
  State<_BeadFlight> createState() => _BeadFlightState();
}

class _BeadFlightState extends State<_BeadFlight>
    with SingleTickerProviderStateMixin {
  late final AnimationController _travel = AnimationController(
    vsync: this,
    animationBehavior: AnimationBehavior.preserve,
    duration: DialMotion.beadTravel,
  )..forward().then((_) => widget.onLanded());

  @override
  void dispose() {
    _travel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: AnimatedBuilder(
      animation: _travel,
      builder: (BuildContext context, _) => CustomPaint(
        size: Size.infinite,
        painter: _FlightPainter(
          t: DialMotion.travel.transform(_travel.value),
          from: widget.from,
          to: widget.to,
          radius: widget.radius,
          mark: widget.mark,
          colors: widget.colors,
        ),
      ),
    ),
  );
}

class _FlightPainter extends CustomPainter {
  _FlightPainter({
    required this.t,
    required this.from,
    required this.to,
    required this.radius,
    required this.mark,
    required this.colors,
  });

  final double t;
  final Offset from;
  final Offset to;
  final double radius;
  final HabitMark mark;
  final DialColors colors;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset d = to - from;
    final double length = max(d.distance, 1);
    final double side = to.dx < from.dx ? 1 : -1;
    final Offset control =
        (from + to) / 2 + Offset(-d.dy, d.dx) / length * length * 0.32 * side;
    final double u = 1 - t;
    final Offset at = from * (u * u) + control * (2 * u * t) + to * (t * t);
    paintHabitMark(canvas, at, 11 + (radius - 11) * t, mark, colors);
  }

  @override
  bool shouldRepaint(_FlightPainter old) => old.t != t;
}
