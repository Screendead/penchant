import 'dart:async';
import 'dart:math';

import 'package:clock/clock.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:tracker/data/day.dart';
import 'package:tracker/data/dial_layout.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/design/dial_theme.dart';
import 'package:tracker/design/habit_mark.dart';
import 'package:tracker/design/tokens.dart';
import 'package:tracker/formats.dart';
import 'package:tracker/providers/habit_summary_provider.dart';
import 'package:tracker/providers/vice_activity_day_provider.dart';
import 'package:tracker/providers/vice_list_provider.dart';
import 'package:tracker/widgets/bead_painter.dart';
import 'package:tracker/widgets/day_dial.dart';
import 'package:tracker/widgets/day_picker.dart';
import 'package:tracker/widgets/dial_face_painter.dart';

// An entry's time: a fixed moment, or none while it follows the clock, so an
// untouched new entry is logged at the moment it is saved, to the second.
class EntryTimeController extends ChangeNotifier {
  EntryTimeController({DateTime? at}) : _at = at {
    _arm();
  }

  DateTime? _at;
  Timer? _minute;

  DateTime? get at => _at;
  bool get followsClock => _at == null;
  DateTime get value => _at ?? clock.now();

  set at(DateTime? moment) {
    if (moment == _at) {
      return;
    }
    _at = moment;
    _arm();
    notifyListeners();
  }

  // While it follows the clock, listeners hear each new minute.
  void _arm() {
    _minute?.cancel();
    _minute = null;
    if (_at != null) {
      return;
    }
    final DateTime now = clock.now();
    _minute = Timer(
      Duration(seconds: 60 - now.second, milliseconds: -now.millisecond),
      () {
        _arm();
        notifyListeners();
      },
    );
  }

  @override
  void dispose() {
    _minute?.cancel();
    super.dispose();
  }
}

// The minute of the day [step] steps of [TimeDial.step] from [minute], on the
// step grid, within 0 and [latest].
int stepMinute(int minute, int step, {required int latest}) {
  final int snapped = step > 0
      ? (minute ~/ TimeDial.step + step) * TimeDial.step
      : (minute % TimeDial.step == 0
            ? minute + step * TimeDial.step
            : (minute ~/ TimeDial.step + step + 1) * TimeDial.step);
  return snapped.clamp(0, latest);
}

// The minute of the day at [local] from the dial's centre, snapped to the
// step, on a dial [side] across.
int minuteAtPoint(Offset local, double side) {
  final Offset d = local - Offset(side / 2, side / 2);
  final double turn = ((atan2(d.dy, d.dx) + pi / 2) / (2 * pi)) % 1;
  return (turn * minutesPerDay / TimeDial.step).round() *
      TimeDial.step %
      minutesPerDay;
}

// The amount sheet's mini dial: the day's other entries faded, and a knob
// dragged round the rim to set the time, snapping to 5 minutes.
class TimeDial extends StatefulWidget {
  const TimeDial({
    super.key,
    required this.minute,
    required this.latest,
    required this.onChanged,
    this.ghosts = const <DialEntry>[],
    this.storedTypicals = const <String, double>{},
    this.enabled = true,
    this.alwaysUse24Hour = true,
  });

  static const double side = 216;
  static const int step = 5;
  static const String label = 'Time';
  static const double knobTrack = 112;
  static const double knobRadius = 11;

  // The minute of the day shown.
  final int minute;
  // The last minute that can be picked: now's on today, else the day's last.
  final int latest;
  final ValueChanged<int> onChanged;
  final List<DialEntry> ghosts;
  final Map<String, double> storedTypicals;
  final bool enabled;
  final bool alwaysUse24Hour;

  @override
  State<TimeDial> createState() => _TimeDialState();
}

class _TimeDialState extends State<TimeDial> {
  bool _focused = false;

  void _set(int minute) {
    final int clamped = minute.clamp(0, widget.latest);
    if (clamped == widget.minute) {
      return;
    }
    HapticFeedback.selectionClick();
    widget.onChanged(clamped);
  }

  void _fromLocal(Offset local) => _set(minuteAtPoint(local, TimeDial.side));

  void _step(int steps) =>
      _set(stepMinute(widget.minute, steps, latest: widget.latest));

  String _spoken(int minute) => formatTime(
    DateTime(2000, 1, 1, minute ~/ 60, minute % 60),
    alwaysUse24HourFormat: widget.alwaysUse24Hour,
  );

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (!widget.enabled || event is KeyUpEvent) {
      return KeyEventResult.ignored;
    }
    final int? steps = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowUp || LogicalKeyboardKey.arrowRight => 1,
      LogicalKeyboardKey.arrowDown || LogicalKeyboardKey.arrowLeft => -1,
      LogicalKeyboardKey.pageUp => 60 ~/ TimeDial.step,
      LogicalKeyboardKey.pageDown => -60 ~/ TimeDial.step,
      _ => null,
    };
    if (steps == null) {
      return KeyEventResult.ignored;
    }
    _step(steps);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final DialColors colors = DialColors.of(context);
    final DialType type = DialType.of(context);
    final Brightness brightness = Theme.of(context).brightness;
    final TextScaler textScaler = MediaQuery.textScalerOf(
      context,
    ).clamp(maxScaleFactor: 1.35);
    final int up = stepMinute(widget.minute, 1, latest: widget.latest);
    final int down = stepMinute(widget.minute, -1, latest: widget.latest);
    final bool enabled = widget.enabled;

    return Semantics(
      slider: true,
      label: TimeDial.label,
      value: _spoken(widget.minute),
      increasedValue: up != widget.minute ? _spoken(up) : null,
      decreasedValue: down != widget.minute ? _spoken(down) : null,
      onIncrease: enabled && up != widget.minute ? () => _step(1) : null,
      onDecrease: enabled && down != widget.minute ? () => _step(-1) : null,
      enabled: enabled,
      excludeSemantics: true,
      child: Focus(
        canRequestFocus: enabled,
        onKeyEvent: _onKey,
        onFocusChange: (bool focused) => setState(() => _focused = focused),
        child: RawGestureDetector(
          gestures: <Type, GestureRecognizerFactory>{
            // Claims the pointer on contact, so a drag on the dial never
            // scrolls the editor or pulls the sheet down.
            if (enabled)
              EagerGestureRecognizer:
                  GestureRecognizerFactoryWithHandlers<EagerGestureRecognizer>(
                    EagerGestureRecognizer.new,
                    (_) {},
                  ),
          },
          child: Listener(
            onPointerDown: enabled
                ? (PointerDownEvent e) => _fromLocal(e.localPosition)
                : null,
            onPointerMove: enabled
                ? (PointerMoveEvent e) => _fromLocal(e.localPosition)
                : null,
            child: RepaintBoundary(
              child: CustomPaint(
                size: const Size.square(TimeDial.side),
                painter: DialFacePainter(
                  colors: colors,
                  surface: scheme.surfaceContainerLow,
                  numeralStyle: type.dialNumeral,
                  textScaler: textScaler,
                  clear: 0,
                  shadows: DialShadows.disc(brightness),
                  ringAlpha: 0,
                ),
                foregroundPainter: _TimeDialPainter(
                  minute: widget.minute,
                  ghosts: widget.ghosts,
                  layout: DayDial.layout(
                    widget.ghosts,
                    stored: widget.storedTypicals,
                  ),
                  colors: colors,
                  accent: scheme.primary,
                  surface: scheme.surface,
                  knobShadows: DialShadows.knob(brightness),
                  hubStyle: type.monoL.copyWith(
                    fontSize: 21,
                    color: scheme.onSurface,
                  ),
                  textScaler: textScaler,
                  focused: _focused,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TimeDialPainter extends CustomPainter {
  _TimeDialPainter({
    required this.minute,
    required this.ghosts,
    required this.layout,
    required this.colors,
    required this.accent,
    required this.surface,
    required this.knobShadows,
    required this.hubStyle,
    required this.textScaler,
    required this.focused,
  });

  // The mock-up's ghost dial draws its beads at 40%.
  static const double ghostAlpha = 0.4;

  final int minute;
  final List<DialEntry> ghosts;
  final Map<String, BeadPlacement> layout;
  final DialColors colors;
  final Color accent;
  final Color surface;
  final List<BoxShadow> knobShadows;
  final TextStyle hubStyle;
  final TextScaler textScaler;
  final bool focused;

  @override
  void paint(Canvas canvas, Size size) {
    final double scale = size.shortestSide / DialFace.side;
    canvas
      ..save()
      ..translate(size.width / 2, size.height / 2)
      ..scale(scale);

    if (ghosts.isNotEmpty) {
      canvas.saveLayer(
        Rect.fromCircle(center: Offset.zero, radius: DialFace.side / 2),
        Paint()..color = surface.withValues(alpha: ghostAlpha),
      );
      for (final DialEntry e in ghosts) {
        if (layout[e.id] case final BeadPlacement p) {
          paintHabitMark(canvas, p.position, p.radius, e.mark, colors);
        }
      }
      for (final MapEntry<int, List<DialEntry>>(key: hour, value: inHour)
          in DayDial.denseHourEntries(ghosts).entries) {
        final List<({Vice vice, HabitMark mark, int count, num total})> shares =
            DayDial.arcShares(inHour);
        final List<Path> pieces = HourArc(
          hour,
        ).shares(<int>[for (final s in shares) s.count]);
        for (int i = 0; i < shares.length; i++) {
          paintHabitBand(canvas, pieces[i], shares[i].mark, colors);
        }
      }
      canvas.restore();
    }

    final double angle = dialAngle(minute.toDouble());
    final Offset knob = dialPoint(angle, TimeDial.knobTrack);
    canvas.drawLine(
      knob * 0.42,
      knob * 0.9,
      Paint()
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..color = accent,
    );
    for (final BoxShadow shadow in knobShadows) {
      canvas.drawCircle(
        knob + shadow.offset,
        TimeDial.knobRadius + shadow.spreadRadius,
        shadow.toPaint(),
      );
    }
    canvas
      ..drawCircle(knob, TimeDial.knobRadius, Paint()..color = accent)
      ..drawCircle(
        knob,
        TimeDial.knobRadius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = surface,
      );

    canvas.drawCircle(Offset.zero, DialFace.hub, Paint()..color = surface);
    final TextPainter hub = TextPainter(
      text: TextSpan(
        text: formatClock(DateTime(2000, 1, 1, minute ~/ 60, minute % 60)),
        style: hubStyle,
      ),
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
    )..layout();
    hub.paint(canvas, Offset(-hub.width / 2, -hub.height / 2));
    hub.dispose();

    if (focused) {
      canvas.drawCircle(
        Offset.zero,
        DialFace.disc + 6,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = accent,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_TimeDialPainter old) =>
      old.minute != minute ||
      old.ghosts != ghosts ||
      old.colors != colors ||
      old.accent != accent ||
      old.surface != surface ||
      old.hubStyle != hubStyle ||
      old.textScaler != textScaler ||
      old.focused != focused;
}

// The time dial with the day's other entries, and the line under it: the day,
// which opens the calendar, and how long ago the time is, with a way back to
// now.
class EntryTimeField extends ConsumerWidget {
  const EntryTimeField({
    super.key,
    required this.controller,
    this.editing,
    this.enabled = true,
  });

  // The entry being edited, left off the faded ones.
  final String? editing;
  final EntryTimeController controller;
  final bool enabled;

  static const String nowLabel = 'Now';
  static const String dragHint = 'drag the hand to change the time';
  static const String chooseDay = 'Choose the day';
  // An entry dated ahead of the clock, as a wrong clock can leave one.
  static const String laterText = 'later today';

  // "2 h 40 min ago", or null within the mock-up's 3 minutes of now.
  static String? agoText(DateTime at, DateTime now) {
    final int ago = now.difference(at).inMinutes;
    if (at.isAfter(now)) {
      return laterText;
    }
    if (ago < 3) {
      return null;
    }
    return '${ago >= 60 ? '${ago ~/ 60} h ' : ''}${ago % 60} min ago';
  }

  static String dayText(DateTime day, DateTime today) {
    if (day == today) {
      return dayWord(day, today);
    }
    if (daysBetween(day, today) < 2) {
      return '${dayWord(day, today)}, ${dayPillDate(day, today)}';
    }
    return (day.year == today.year
            ? DateFormat.MMMEd(formatLocale)
            : DateFormat.yMMMEd(formatLocale))
        .format(day);
  }

  void _setMinute(int minute, DateTime day, DateTime now) {
    final DateTime at = DateTime(
      day.year,
      day.month,
      day.day,
      minute ~/ 60,
      minute % 60,
    );
    // Back at the current minute on today, the entry follows the clock again.
    controller.at = startOfDay(now) == day && minuteOfDay(now).floor() <= minute
        ? null
        : at;
  }

  Future<void> _chooseDay(
    BuildContext context,
    DateTime day,
    DateTime today,
    List<Vice> habits,
  ) async {
    final DateTime? picked = await showModalBottomSheet<DateTime>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (BuildContext context) => CalendarSheet(
        selected: day,
        today: today,
        habits: <Vice>[
          for (final Vice v in habits)
            if (!v.archived) v,
        ],
        marks: habitMarks(habits),
        footnote: CalendarSheet.timeFootnote,
      ),
    );
    if (picked == null || picked == day) {
      return;
    }
    final DateTime now = clock.now();
    final DateTime shown = controller.value;
    final int minute = shown.hour * 60 + shown.minute;
    _setMinute(minute, picked, now);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, _) {
        final DateTime now = clock.now();
        final DateTime today = startOfDay(now);
        final DateTime at = controller.value;
        final DateTime day = startOfDay(at);
        final bool isToday = day == today;
        final List<Vice> habits =
            ref.watch(viceListProvider).value ?? const <Vice>[];
        final Map<String, HabitMark> marks = habitMarks(habits);
        final List<ViceActivity> activities =
            ref.watch(viceActivityDayProvider(day)).value ??
            const <ViceActivity>[];
        final List<DialEntry> ghosts = dialEntries(habits, <ViceActivity>[
          for (final ViceActivity a in activities)
            if (a.id != editing) a,
        ], (Vice v) => marks[v.id]!);
        final DialColors colors = DialColors.of(context);
        final ColorScheme scheme = Theme.of(context).colorScheme;
        final TextStyle meta = DialTypeScale.bodyS.copyWith(
          fontSize: 12.5,
          height: 1.4,
          color: colors.muted,
        );
        final ButtonStyle link = TextButton.styleFrom(
          minimumSize: const Size(DialSize.minTapTarget, DialSize.minTapTarget),
          padding: const EdgeInsets.symmetric(horizontal: 6),
          foregroundColor: scheme.onSurface,
          textStyle: meta.copyWith(
            fontWeight: FontWeight.w600,
            decoration: TextDecoration.underline,
          ),
        );
        final String? ago = isToday ? agoText(at, now) : null;
        final Widget dot = Text(' · ', style: meta);

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Center(
              child: TimeDial(
                minute: at.hour * 60 + at.minute,
                latest: isToday ? minuteOfDay(now).floor() : minutesPerDay - 1,
                onChanged: (int minute) => _setMinute(minute, day, now),
                ghosts: ghosts,
                storedTypicals: ref.watch(storedTypicalsProvider),
                enabled: enabled,
                alwaysUse24Hour: MediaQuery.alwaysUse24HourFormatOf(context),
              ),
            ),
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                Semantics(
                  hint: chooseDay,
                  child: TextButton(
                    style: link,
                    onPressed: enabled
                        ? () => _chooseDay(context, day, today, habits)
                        : null,
                    child: Text(dayText(day, today)),
                  ),
                ),
                if (isToday) ...<Widget>[
                  dot,
                  if (ago == null)
                    Text('$nowLabel · $dragHint', style: meta)
                  else ...<Widget>[
                    Text(ago, style: meta),
                    dot,
                    TextButton(
                      style: link,
                      onPressed: enabled ? () => controller.at = null : null,
                      child: const Text(nowLabel),
                    ),
                  ],
                ],
              ],
            ),
          ],
        );
      },
    );
  }
}
