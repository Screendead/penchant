import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/data/usage_series.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/design/dial_icons.dart';
import 'package:tracker/design/dial_theme.dart';
import 'package:tracker/design/habit_mark.dart';
import 'package:tracker/design/tokens.dart';
import 'package:tracker/errors/firestore_errors.dart';
import 'package:tracker/formats.dart';
import 'package:tracker/providers/today_provider.dart';
import 'package:tracker/providers/vice_activity_history_provider.dart';
import 'package:tracker/trends/hour_ring.dart';
import 'package:tracker/trends/trends_chart.dart';
import 'package:tracker/trends/trends_day.dart';
import 'package:tracker/widgets/bead_painter.dart';
import 'package:tracker/widgets/circle_button.dart';
import 'package:tracker/widgets/info_box.dart';
import 'package:tracker/widgets/pill_toggle.dart';

typedef TrendsSelection = ({
  String? viceID,
  int rangeDays,
  int stepDays,
  int pickedWindow,
});

// What the chart shows for one habit and range, once its entries are in.
typedef TrendsSeries = ({
  UsageRange range,
  List<ViceActivity> activities,
  List<double> totals,
  List<double> smoothed,
  int window,
  UsageStats stats,
  HourProfile hours,
});

// A sheet controller's moves, passed on outside a build. The sheet resets its
// extent while it builds when its peek size changes (a resized window, a new
// text size), and widgets beside or above it may not be marked dirty then.
class SheetPosition extends ChangeNotifier {
  SheetPosition(this.controller) {
    controller.addListener(_moved);
  }

  final DraggableScrollableController controller;
  bool _scheduled = false;
  bool _disposed = false;

  void _moved() {
    final SchedulerBinding binding = SchedulerBinding.instance;
    if (binding.schedulerPhase != SchedulerPhase.persistentCallbacks) {
      notifyListeners();
      return;
    }
    if (_scheduled) {
      return;
    }
    _scheduled = true;
    binding.addPostFrameCallback((_) {
      _scheduled = false;
      if (!_disposed) {
        notifyListeners();
      }
    });
  }

  @override
  void dispose() {
    _disposed = true;
    controller.removeListener(_moved);
    super.dispose();
  }
}

// Trends: a sheet over Today that peeks at the bottom with a sparkline of the
// chosen habit, and opens over the dial to one habit's totals over a range.
// Beside Today in the split view it is a pane, always open, and a day picked
// on its chart goes to Today's dial instead of opening in the pane. Both keep
// their selection in the same page storage, so a resize across the split
// keeps it.
class TrendsSheet extends ConsumerStatefulWidget {
  const TrendsSheet({
    super.key,
    required DraggableScrollableController this.controller,
    required this.minSize,
    required this.habits,
    required this.marks,
  }) : onOpenDay = null;

  const TrendsSheet.pane({
    super.key,
    required this.habits,
    required this.marks,
    required ValueChanged<DateTime> this.onOpenDay,
  }) : controller = null,
       minSize = 1;

  // Null for the pane.
  final DraggableScrollableController? controller;
  // The peek, as a share of the height the sheet can take.
  final double minSize;
  // Every habit in chip order: in use first, then archived, each oldest first.
  final List<Vice> habits;
  final Map<String, HabitMark> marks;
  // The pane's way to show a day.
  final ValueChanged<DateTime>? onOpenDay;

  static const String title = 'Trends';
  static const String openHint = 'Opens Trends';
  static const String closeLabel = 'Close Trends';
  static const String shorterAverage = 'Shorter average';
  static const String longerAverage = 'Longer average';
  static const List<int> ranges = <int>[7, 30, 90, 365];
  static const Duration _move = Duration(milliseconds: 320);

  // The mock-up's peek: 127 pt at the default text size, padded 16 above and
  // 22 at the sides, the sparkline 44 tall from 58 down, and 25 below it. The
  // home indicator overlaps those 25, as it does in the mock-up.
  static const double _peekTop = DialSpace.m;
  static const double _peekSide = 22;
  static const double _sparkGap = 1;
  static const double sparkHeight = 44;
  static const double _peekBottom = 25;
  // A wide pane centres its content at this width, so the chart's days stay
  // close enough to read across.
  static const double paneContentWidth = 720;

  // The peek's height: its two lines of text at the device's text size and
  // the sparkline under them.
  static double peekHeight(BuildContext context) {
    final TextScaler scaler = MediaQuery.textScalerOf(context);
    return _peekTop +
        // The taller column: the 17 pt number on a 25 pt line, 4, a 12 pt
        // caption.
        scaler.scale(25) +
        4 +
        scaler.scale(12) +
        _sparkGap +
        sparkHeight +
        _peekBottom;
  }

  // 0 at the peek, 1 fully open.
  static double openness(DraggableScrollableController c, double minSize) =>
      c.isAttached && minSize < 1
      ? ((c.size - minSize) / (1 - minSize)).clamp(0.0, 1.0)
      : 0;

  static Future<void> moveTo(
    BuildContext context,
    DraggableScrollableController c,
    double size,
  ) async {
    if (!c.isAttached) {
      return;
    }
    if (MediaQuery.disableAnimationsOf(context)) {
      c.jumpTo(size);
      await WidgetsBinding.instance.endOfFrame;
    } else {
      await c.animateTo(size, duration: _move, curve: DialMotion.enter);
    }
  }

  static String rangeLabel(int days) => days == 365 ? '1Y' : '${days}D';

  static String rangeSpoken(int days) =>
      days == 365 ? '1 year' : '${formatCount(days)} days';

  static String chipLabel(Vice vice) =>
      vice.archived ? '${vice.name}, archived' : vice.name;

  static String averageLabel(int window, int stepDays) => window > 1
      ? 'Average over ${formatCount(window)} '
            '${stepDays == 1 ? 'days' : 'weeks'}'
      : 'No average line';

  static String peekLabel(Vice vice, int rangeDays, double? perDay) =>
      '$title. ${vice.name}, last ${formatCount(rangeDays)} days'
      '${perDay == null ? '' : ': ${formatAverage(perDay)} ${vice.unit.plural} a day'}';

  // In the pane a tapped day moves Today's dial beside it.
  static String hint(int stepDays, {bool pane = false}) => stepDays != 1
      ? 'Drag across the chart to read a week.'
      : pane
      ? 'Drag across the chart to read a day. Tap a day to show it on the dial.'
      : 'Drag across the chart to read a day. Tap a day to open its dial.';

  // Said when the pane hands a day to Today's dial, which a screen reader's
  // focus on the chart does not reach.
  static String shownOnDial(DateTime day) => 'The dial shows ${formatDay(day)}';

  static String whenTitle(
    HourProfile p, {
    required bool alwaysUse24HourFormat,
  }) {
    String at(int hour) => formatTime(
      DateTime(2000, 1, 1, hour),
      alwaysUse24HourFormat: alwaysUse24HourFormat,
    );
    return 'Mostly ${at(p.busiestStart)}–${at((p.busiestStart + 3) % 24)}';
  }

  static String whenBody(Vice vice, UsageRange range, HourProfile p) {
    final int days = min(range.days, hourProfileMaxDays);
    return 'When ${vice.name} happens, over the last ${formatCount(days)} '
        'days. ${p.beforeNoonPercent}% of it before noon.';
  }

  static const String whenEmptyTitle = 'Nothing in this range';
  static const String whenEmptyBody = 'Entries show here by hour of day.';

  @override
  ConsumerState<TrendsSheet> createState() => _TrendsSheetState();
}

class _TrendsSheetState extends ConsumerState<TrendsSheet> {
  static const String _storageID = 'TrendsSheet.selection';

  String? viceID;
  int rangeDays = 30;
  int stepDays = 1;
  int pickedWindow = defaultWindow(1);
  // The bucket the readout describes; null is the newest.
  int? cursor;
  // A day opened from the chart.
  DateTime? openDay;

  List<ViceActivity>? _bucketed;
  UsageRange? _bucketedRange;
  List<double> _totals = const <double>[];

  @override
  void initState() {
    super.initState();
    if (PageStorage.maybeOf(context)?.readState(context, identifier: _storageID)
        case final TrendsSelection saved) {
      viceID = saved.viceID;
      rangeDays = saved.rangeDays;
      stepDays = saved.stepDays;
      pickedWindow = saved.pickedWindow;
    }
  }

  void _update(VoidCallback change) {
    setState(change);
    final TrendsSelection selection = (
      viceID: viceID,
      rangeDays: rangeDays,
      stepDays: stepDays,
      pickedWindow: pickedWindow,
    );
    PageStorage.maybeOf(
      context,
    )?.writeState(context, selection, identifier: _storageID);
  }

  // Keyboard focus follows the sheet: from the peek to Close as it opens, and
  // back to the peek if it closes with focus inside.
  final FocusNode _sheetFocus = FocusNode(
    debugLabel: 'Trends sheet',
    canRequestFocus: false,
    skipTraversal: true,
  );
  final FocusNode _peekFocus = FocusNode(debugLabel: 'Trends peek');
  final FocusNode _closeFocus = FocusNode(debugLabel: 'Close Trends');
  // And between the chart and a day it opens.
  final FocusNode _chartFocus = FocusNode(debugLabel: TrendsChart.focusLabel);
  final FocusNode _backFocus = FocusNode(debugLabel: TrendsDay.backLabel);

  @override
  void dispose() {
    _sheetFocus.dispose();
    _peekFocus.dispose();
    _closeFocus.dispose();
    _chartFocus.dispose();
    _backFocus.dispose();
    super.dispose();
  }

  // Moves focus from [from] to [to] once [change] has built [to], if a
  // keyboard had it on [from].
  void _handOver(FocusNode from, FocusNode to, VoidCallback change) {
    final bool fromKeys = from.hasFocus;
    setState(change);
    if (fromKeys) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          to.requestFocus();
        }
      });
    }
  }

  Future<void> _open() async {
    final bool fromKeys = _peekFocus.hasFocus;
    await TrendsSheet.moveTo(context, widget.controller!, 1);
    if (fromKeys && mounted) {
      _closeFocus.requestFocus();
    }
  }

  Future<void> _close() async {
    final bool fromKeys = _sheetFocus.hasFocus;
    await TrendsSheet.moveTo(context, widget.controller!, widget.minSize);
    if (fromKeys && mounted) {
      _peekFocus.requestFocus();
    }
  }

  Vice _selected() {
    final List<Vice> habits = widget.habits;
    return habits.firstWhere(
      (Vice v) => v.id == viceID,
      orElse: () => habits.firstWhere(
        (Vice v) => !v.archived,
        orElse: () => habits.first,
      ),
    );
  }

  TrendsSeries _series(UsageRange range, List<ViceActivity> activities) {
    if (!identical(activities, _bucketed) || range != _bucketedRange) {
      _bucketed = activities;
      _bucketedRange = range;
      _totals = bucketTotals(range, activities);
    }
    final int window = effectiveWindow(pickedWindow, range.bucketCount);
    return (
      range: range,
      activities: activities,
      totals: _totals,
      smoothed: movingAverage(_totals, window),
      window: window,
      stats: usageStats(range, _totals),
      hours: hourProfile(range, activities),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Vice vice = _selected();
    final HabitMark mark = widget.marks[vice.id] ?? const HabitMark(0);
    final DateTime today = ref.watch(todayProvider);
    final UsageRange range = usageRange(today, rangeDays, stepDays);
    final AsyncValue<List<ViceActivity>> value = ref.watch(
      viceActivityGraphProvider((
        viceID: vice.id,
        start: range.start,
        end: range.end,
      )),
    );
    final Object? error = value.error;
    final List<ViceActivity>? activities = error == null ? value.value : null;
    final TrendsSeries? series = activities == null
        ? null
        : _series(range, activities);

    final ColorScheme scheme = Theme.of(context).colorScheme;
    final DialColors colors = DialColors.of(context);
    final double peek = TrendsSheet.peekHeight(context);
    final double bottomInset = MediaQuery.paddingOf(context).bottom;
    final DraggableScrollableController? controller = widget.controller;
    final ValueChanged<DateTime>? showDay = widget.onOpenDay;
    final DateTime? day = controller == null ? null : openDay;

    final Widget content = day != null
        ? TrendsDay(
            key: ValueKey<DateTime>(day),
            day: day,
            today: today,
            vice: vice,
            habits: widget.habits,
            marks: widget.marks,
            backFocus: _backFocus,
            onBack: () =>
                _handOver(_backFocus, _chartFocus, () => openDay = null),
          )
        : _TrendsPanel(
            key: const ValueKey<String>('panel'),
            habits: widget.habits,
            marks: widget.marks,
            vice: vice,
            mark: mark,
            range: range,
            series: series,
            error: error,
            cursor: cursor,
            onClose: controller == null ? null : _close,
            closeFocus: _closeFocus,
            chartFocus: _chartFocus,
            onHabit: (Vice v) => _update(() {
              viceID = v.id;
              cursor = null;
            }),
            onRange: (int days) => _update(() {
              rangeDays = days;
              cursor = null;
            }),
            onStep: (int step) => _update(() {
              if (step != stepDays) {
                stepDays = step;
                pickedWindow = defaultWindow(step);
                cursor = null;
              }
            }),
            onWindow: (int window) => _update(() => pickedWindow = window),
            onCursor: (int index) => setState(() => cursor = index),
            onOpenDay: stepDays != 1
                ? null
                : showDay != null
                ? (int index) {
                    final DateTime picked = range.bucketStart(index);
                    showDay(picked);
                    unawaited(
                      SemanticsService.sendAnnouncement(
                        View.of(context),
                        TrendsSheet.shownOnDial(picked),
                        Directionality.of(context),
                      ),
                    );
                  }
                : (int index) => _handOver(
                    _chartFocus,
                    _backFocus,
                    () => openDay = range.bucketStart(index),
                  ),
            onRetry: () => ref.invalidate(
              viceActivityGraphForUserProvider,
              asReload: true,
            ),
          );

    if (controller == null) {
      return Material(
        color: scheme.surfaceContainerLow,
        shape: BorderDirectional(start: BorderSide(color: colors.line)),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            DialSpace.gutter,
            DialSpace.xl,
            DialSpace.gutter + MediaQuery.paddingOf(context).right,
            DialSpace.xl + bottomInset,
          ),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: TrendsSheet.paneContentWidth,
              ),
              child: content,
            ),
          ),
        ),
      );
    }

    return DraggableScrollableSheet(
      controller: controller,
      initialChildSize: widget.minSize,
      minChildSize: widget.minSize,
      maxChildSize: 1,
      snap: true,
      builder: (BuildContext context, ScrollController scroll) {
        // The sheet's edge is its 1 px rim, and in light shadow-sheet.
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(DialRadius.sheet),
            ),
            boxShadow: DialShadows.sheet(Theme.of(context).brightness),
          ),
          child: Material(
            color: scheme.surfaceContainerLow,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(DialRadius.sheet),
              ),
              side: BorderSide(color: colors.line),
            ),
            child: CallbackShortcuts(
              bindings: <ShortcutActivator, VoidCallback>{
                const SingleActivator(LogicalKeyboardKey.escape): _close,
              },
              child: Focus(
                focusNode: _sheetFocus,
                child: SingleChildScrollView(
                  controller: scroll,
                  child: Stack(
                    children: <Widget>[
                      ListenableBuilder(
                        listenable: controller,
                        builder: (BuildContext context, Widget? child) {
                          final double p = TrendsSheet.openness(
                            controller,
                            widget.minSize,
                          );
                          // Built only once the sheet moves off its peek.
                          if (p <= 0) {
                            return SizedBox(height: peek);
                          }
                          final bool open = p > 0.9;
                          return Opacity(
                            opacity: ((p - 0.25) / 0.6).clamp(0.0, 1.0),
                            child: IgnorePointer(
                              ignoring: !open,
                              child: ExcludeFocus(
                                excluding: !open,
                                child: ExcludeSemantics(
                                  excluding: !open,
                                  child: child,
                                ),
                              ),
                            ),
                          );
                        },
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(
                            DialSpace.gutter,
                            DialSpace.xl,
                            DialSpace.gutter,
                            DialSpace.xl + bottomInset,
                          ),
                          child: AnimatedSwitcher(
                            duration: MediaQuery.disableAnimationsOf(context)
                                ? DialMotion.reducedFade
                                : DialMotion.fadeThrough,
                            child: content,
                          ),
                        ),
                      ),
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        height: peek,
                        child: ListenableBuilder(
                          listenable: controller,
                          builder: (BuildContext context, Widget? child) {
                            final double p = TrendsSheet.openness(
                              controller,
                              widget.minSize,
                            );
                            return Opacity(
                              opacity: (1 - p * 3).clamp(0.0, 1.0),
                              child: IgnorePointer(
                                ignoring: p > 0.2,
                                child: ExcludeFocus(
                                  excluding: p > 0.2,
                                  child: ExcludeSemantics(
                                    excluding: p > 0.2,
                                    child: child,
                                  ),
                                ),
                              ),
                            );
                          },
                          child: _Peek(
                            vice: vice,
                            mark: mark,
                            rangeDays: rangeDays,
                            series: series,
                            focusNode: _peekFocus,
                            onOpen: _open,
                          ),
                        ),
                      ),
                      Positioned(
                        top: DialSpace.xs,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: Container(
                            width: 38,
                            height: 5,
                            decoration: ShapeDecoration(
                              color: scheme.outline,
                              shape: const StadiumBorder(),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Peek extends StatelessWidget {
  const _Peek({
    required this.vice,
    required this.mark,
    required this.rangeDays,
    required this.series,
    required this.focusNode,
    required this.onOpen,
  });

  final Vice vice;
  final HabitMark mark;
  final int rangeDays;
  final TrendsSeries? series;
  final FocusNode focusNode;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final DialColors colors = DialColors.of(context);
    final DialType type = DialType.of(context);
    final TrendsSeries? s = series;
    final double? perDay = s == null ? null : s.stats.total / s.range.days;
    final TextStyle small = DialTypeScale.bodyS.copyWith(
      color: colors.muted,
      fontSize: 12,
      height: 1,
    );

    return MergeSemantics(
      child: Semantics(
        label: TrendsSheet.peekLabel(vice, rangeDays, perDay),
        hint: TrendsSheet.openHint,
        child: TextButton(
          focusNode: focusNode,
          onPressed: onOpen,
          style: TextButton.styleFrom(
            padding: const EdgeInsets.fromLTRB(
              TrendsSheet._peekSide,
              TrendsSheet._peekTop,
              TrendsSheet._peekSide,
              TrendsSheet._peekBottom,
            ),
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(DialRadius.sheet),
              ),
            ),
            alignment: Alignment.topCenter,
          ),
          child: ExcludeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            TrendsSheet.title,
                            style: type.displayM.copyWith(
                              fontSize: 15,
                              height: 1,
                            ),
                            maxLines: 1,
                          ),
                          const SizedBox(height: 5),
                          Text(
                            '${vice.name} · last ${formatCount(rangeDays)} days',
                            style: small.copyWith(fontSize: 12.5),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    if (perDay != null) ...<Widget>[
                      const SizedBox(width: DialSpace.s),
                      Flexible(
                        flex: 2,
                        // Holds the number against the right edge.
                        child: Align(
                          alignment: AlignmentDirectional.topEnd,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: <Widget>[
                              Text(
                                formatAverage(perDay),
                                style: type.monoM.copyWith(
                                  fontSize: 17,
                                  height: 25 / 17,
                                  color: colors.habitInk(mark),
                                ),
                                maxLines: 1,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${vice.unit.plural} a day',
                                style: small,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: TrendsSheet._sparkGap),
                SizedBox(
                  height: TrendsSheet.sparkHeight,
                  child: s == null
                      ? null
                      : CustomPaint(
                          painter: _SparklinePainter(
                            totals: s.totals,
                            smoothed: movingAverage(
                              s.totals,
                              effectiveWindow(
                                defaultWindow(s.range.stepDays),
                                s.range.bucketCount,
                              ),
                            ),
                            ink: colors.habitInk(mark),
                            raw: sparkRaw(context, mark),
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// The sparkline's daily series: lighter than its average, as in the
// mock-up, but held to 3:1 on the sheet (contrast-pairs.json): the hue halfway
// to its ink in light, the hue at 70% in dark.
Color sparkRaw(BuildContext context, HabitMark mark) {
  final DialColors colors = DialColors.of(context);
  final Color hue = colors.habit(mark);
  return Theme.of(context).brightness == Brightness.dark
      ? hue.withValues(alpha: 0.7)
      : Color.lerp(hue, colors.habitInk(mark), 0.5)!;
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter({
    required this.totals,
    required this.smoothed,
    required this.ink,
    required this.raw,
  });

  final List<double> totals;
  final List<double> smoothed;
  final Color ink;
  final Color raw;

  @override
  void paint(Canvas canvas, Size size) {
    final int n = totals.length;
    if (n == 0) {
      return;
    }
    final double most = totals.fold<double>(1, max);
    Offset at(int i, double v) => Offset(
      n == 1 ? size.width / 2 : i / (n - 1) * size.width,
      size.height - 3 - v / most * (size.height - 8),
    );
    Path line(List<double> values) {
      final Path path = Path()
        ..moveTo(at(0, values[0]).dx, at(0, values[0]).dy);
      for (int i = 1; i < values.length; i++) {
        final Offset p = at(i, values[i]);
        path.lineTo(p.dx, p.dy);
      }
      return path;
    }

    canvas
      ..drawPath(
        line(totals),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..strokeJoin = StrokeJoin.round
          ..color = raw,
      )
      ..drawPath(
        line(smoothed),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = ink,
      );
  }

  @override
  bool shouldRepaint(_SparklinePainter old) =>
      old.totals != totals ||
      old.smoothed != smoothed ||
      old.ink != ink ||
      old.raw != raw;
}

class _TrendsPanel extends StatelessWidget {
  const _TrendsPanel({
    super.key,
    required this.habits,
    required this.marks,
    required this.vice,
    required this.mark,
    required this.range,
    required this.series,
    required this.error,
    required this.cursor,
    required this.onClose,
    required this.closeFocus,
    required this.chartFocus,
    required this.onHabit,
    required this.onRange,
    required this.onStep,
    required this.onWindow,
    required this.onCursor,
    required this.onOpenDay,
    required this.onRetry,
  });

  final List<Vice> habits;
  final Map<String, HabitMark> marks;
  final Vice vice;
  final HabitMark mark;
  final UsageRange range;
  final TrendsSeries? series;
  final Object? error;
  final int? cursor;
  // Null in the pane, which has no Close.
  final VoidCallback? onClose;
  final FocusNode closeFocus;
  final FocusNode chartFocus;
  final ValueChanged<Vice> onHabit;
  final ValueChanged<int> onRange;
  final ValueChanged<int> onStep;
  final ValueChanged<int> onWindow;
  final ValueChanged<int> onCursor;
  final ValueChanged<int>? onOpenDay;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final DialType type = DialType.of(context);
    final DialColors colors = DialColors.of(context);
    final ThemeData theme = Theme.of(context);
    final TrendsSeries? s = series;

    final List<Widget> body;
    if (error case final Object e) {
      body = <Widget>[
        const SizedBox(height: DialSpace.l),
        InfoBox(
          message: loadErrorMessage('${vice.name} for this range', e),
          isError: true,
          onRetry: onRetry,
        ),
      ];
    } else if (s == null) {
      body = const <Widget>[
        SizedBox(
          height: TrendsChart.plotHeight,
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    } else {
      final int limit = smoothingLimit(range.bucketCount);
      final bool empty = s.stats.total == 0;
      body = <Widget>[
        const SizedBox(height: DialSpace.s),
        _Stats(vice: vice, range: range, stats: s.stats, totals: s.totals),
        const SizedBox(height: DialSpace.s),
        if (empty)
          SizedBox(
            height: TrendsChart.plotHeight,
            child: Center(
              child: InfoBox(
                message: 'No entries for ${vice.name} in this range',
              ),
            ),
          )
        else
          TrendsChart(
            key: ValueKey<String>('chart-${vice.id}'),
            vice: vice,
            mark: mark,
            range: range,
            totals: s.totals,
            smoothed: s.smoothed,
            window: s.window,
            cursor: cursor ?? s.totals.length - 1,
            onCursor: onCursor,
            onOpenBucket: onOpenDay,
            focusNode: chartFocus,
          ),
        const SizedBox(height: DialSpace.s),
        _AverageStepper(
          window: s.window,
          limit: limit,
          stepDays: range.stepDays,
          onWindow: onWindow,
        ),
        const SizedBox(height: DialSpace.s),
        _WhenCard(vice: vice, mark: mark, range: range, profile: s.hours),
        const SizedBox(height: DialSpace.s),
        Text(
          TrendsSheet.hint(range.stepDays, pane: onClose == null),
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(color: colors.muted),
        ),
      ];
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Semantics(
                header: true,
                child: Text(TrendsSheet.title, style: type.displayL),
              ),
            ),
            if (onClose case final VoidCallback close)
              CircleButton(
                icon: DialGlyph.down,
                tooltip: TrendsSheet.closeLabel,
                focusNode: closeFocus,
                onPressed: close,
              ),
          ],
        ),
        const SizedBox(height: DialSpace.s),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          child: Row(
            children: <Widget>[
              for (final Vice v in habits) ...<Widget>[
                if (v != habits.first) const SizedBox(width: DialSpace.xs),
                _HabitChip(
                  vice: v,
                  mark: marks[v.id] ?? const HabitMark(0),
                  selected: v.id == vice.id,
                  onPressed: () => onHabit(v),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: DialSpace.s),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: DialSpace.s,
          runSpacing: DialSpace.xs,
          children: <Widget>[
            PillSegments<int>(
              segments: <({int value, String label, String spoken})>[
                for (final int days in TrendsSheet.ranges)
                  (
                    value: days,
                    label: TrendsSheet.rangeLabel(days),
                    spoken: TrendsSheet.rangeSpoken(days),
                  ),
              ],
              selected: range.days,
              onChanged: onRange,
            ),
            PillSegments<int>(
              segments: const <({int value, String label, String spoken})>[
                (value: 1, label: 'Day', spoken: 'By day'),
                (value: 7, label: 'Week', spoken: 'By week'),
              ],
              selected: range.stepDays,
              onChanged: onStep,
            ),
          ],
        ),
        ...body,
      ],
    );
  }
}

class _HabitChip extends StatelessWidget {
  const _HabitChip({
    required this.vice,
    required this.mark,
    required this.selected,
    required this.onPressed,
  });

  final Vice vice;
  final HabitMark mark;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final DialColors colors = DialColors.of(context);
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Color surface = scheme.surfaceContainerLow;

    return PillToggle(
      selected: selected,
      onPressed: onPressed,
      color: colors.surface2,
      selectedColor: Color.alphaBlend(
        colors.habit(mark).withValues(alpha: 0.18),
        surface,
      ),
      selectedSide: BorderSide(color: colors.habitInk(mark), width: 1.5),
      restForeground: scheme.onSurface,
      semanticsLabel: TrendsSheet.chipLabel(vice),
      padding: const EdgeInsetsDirectional.only(start: 11, end: 14),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          HabitPip(mark: mark),
          const SizedBox(width: 7),
          Text(vice.name),
          if (vice.archived)
            Text(
              ' · archived',
              style: TextStyle(
                color: colors.muted,
                fontWeight: FontWeight.w500,
              ),
            ),
        ],
      ),
    );
  }
}

class _Stats extends StatelessWidget {
  const _Stats({
    required this.vice,
    required this.range,
    required this.stats,
    required this.totals,
  });

  final Vice vice;
  final UsageRange range;
  final UsageStats stats;
  final List<double> totals;

  @override
  Widget build(BuildContext context) {
    final int total = stats.total.round();
    final int peak = totals[stats.peakIndex].round();
    final bool daily = range.stepDays == 1;
    final DateTime peakStart = range.bucketStart(stats.peakIndex);
    final List<Widget> tiles = <Widget>[
      _StatTile(
        label: 'Total',
        value: formatCount(total),
        unit: vice.unit.nameFor(total),
        detail: 'last ${formatCount(range.days)} days',
      ),
      _StatTile(
        label: 'Average',
        value: formatAverage(stats.average),
        detail: daily ? 'per day' : 'per week',
      ),
      _StatTile(
        label: 'Peak',
        value: formatCount(peak),
        detail: total == 0
            ? 'none yet'
            : daily
            ? TrendsChart.readoutLabel(
                range,
                stats.peakIndex,
                addDays(range.end, -1),
              )
            : 'week of ${formatShortDay(peakStart)}',
      ),
    ];
    // Three across stop fitting at large text sizes; stacked, each has the
    // width.
    if (MediaQuery.textScalerOf(context).scale(10) > 15) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (final Widget tile in tiles) ...<Widget>[
            if (tile != tiles.first) const SizedBox(height: DialSpace.xs),
            tile,
          ],
        ],
      );
    }
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (final Widget tile in tiles) ...<Widget>[
            if (tile != tiles.first) const SizedBox(width: DialSpace.xs),
            Expanded(child: tile),
          ],
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    required this.detail,
    this.unit,
  });

  final String label;
  final String value;
  final String? unit;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final DialColors colors = DialColors.of(context);
    final DialType type = DialType.of(context);
    final TextStyle small = DialTypeScale.bodyS.copyWith(
      color: colors.muted,
      fontSize: 11.5,
      height: 1.3,
    );

    return MergeSemantics(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surface2,
          borderRadius: BorderRadius.circular(DialRadius.tile),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(label, style: small),
              const SizedBox(height: 5),
              Text.rich(
                TextSpan(
                  children: <InlineSpan>[
                    TextSpan(
                      text: value,
                      style: type.monoL.copyWith(fontSize: 21),
                    ),
                    if (unit != null) TextSpan(text: ' $unit', style: small),
                  ],
                ),
              ),
              const SizedBox(height: 3),
              Text(detail, style: small),
            ],
          ),
        ),
      ),
    );
  }
}

class _AverageStepper extends StatelessWidget {
  const _AverageStepper({
    required this.window,
    required this.limit,
    required this.stepDays,
    required this.onWindow,
  });

  final int window;
  final int limit;
  final int stepDays;
  final ValueChanged<int> onWindow;

  @override
  Widget build(BuildContext context) {
    final DialColors colors = DialColors.of(context);
    final ColorScheme scheme = Theme.of(context).colorScheme;

    Widget step(IconData icon, String tooltip, VoidCallback? onPressed) =>
        IconButton(
          tooltip: tooltip,
          onPressed: onPressed,
          icon: Icon(icon, size: 16),
          style: IconButton.styleFrom(
            fixedSize: const Size.square(34),
            minimumSize: const Size.square(34),
            tapTargetSize: MaterialTapTargetSize.padded,
            backgroundColor: scheme.surfaceContainerLow,
            disabledBackgroundColor: scheme.surfaceContainerLow.withValues(
              alpha: 0.35,
            ),
            foregroundColor: scheme.onSurface,
            disabledForegroundColor: colors.muted,
          ),
        );

    return DecoratedBox(
      decoration: ShapeDecoration(
        color: colors.surface2,
        shape: const StadiumBorder(),
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.only(start: DialSpace.m),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Semantics(
                liveRegion: true,
                child: Text(
                  TrendsSheet.averageLabel(window, stepDays),
                  style: DialTypeScale.bodyL.copyWith(
                    fontSize: 14,
                    color: scheme.onSurface,
                  ),
                ),
              ),
            ),
            step(
              Icons.remove,
              TrendsSheet.shorterAverage,
              window > 1 ? () => onWindow(window - 1) : null,
            ),
            step(
              Icons.add,
              TrendsSheet.longerAverage,
              window < limit ? () => onWindow(window + 1) : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _WhenCard extends StatelessWidget {
  const _WhenCard({
    required this.vice,
    required this.mark,
    required this.range,
    required this.profile,
  });

  final Vice vice;
  final HabitMark mark;
  final UsageRange range;
  final HourProfile profile;

  @override
  Widget build(BuildContext context) {
    final DialColors colors = DialColors.of(context);
    final ThemeData theme = Theme.of(context);
    final bool empty = profile.total == 0;

    return MergeSemantics(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surface2,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: <Widget>[
              HourRing(hours: profile.hours, mark: mark),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      empty
                          ? TrendsSheet.whenEmptyTitle
                          : TrendsSheet.whenTitle(
                              profile,
                              alwaysUse24HourFormat:
                                  MediaQuery.alwaysUse24HourFormatOf(context),
                            ),
                      style: DialTypeScale.label.copyWith(
                        fontSize: 14,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      empty
                          ? TrendsSheet.whenEmptyBody
                          : TrendsSheet.whenBody(vice, range, profile),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.muted,
                      ),
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
