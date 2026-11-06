import 'dart:math';
import 'dart:ui' show ImageFilter;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/rendering.dart' show CustomSemanticsAction;
import 'package:flutter/services.dart';
import 'package:tracker/data/fan_layout.dart';
import 'package:tracker/data/unit.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/design/dial_theme.dart';
import 'package:tracker/design/habit_mark.dart';
import 'package:tracker/design/tokens.dart';
import 'package:tracker/formats.dart';
import 'package:tracker/writes/log_one.dart';

typedef FanHabit = ({Vice vice, HabitMark mark});

// The one primary action on Today: a tap opens a fan of the habits. A tap on
// a wedge logs one now, a hold opens the record dialog with that habit, and a
// press on the button dragged onto a wedge logs it on release.
class LogButton extends StatefulWidget {
  const LogButton({
    super.key,
    required this.habits,
    required this.onLog,
    required this.onRecord,
  });

  final List<FanHabit> habits;
  // [from] is where the bead leaves from, in global coordinates.
  final void Function(Vice vice, Offset from) onLog;
  // Opens the record dialog, with [vice] chosen when there is one.
  final void Function(Vice? vice) onRecord;

  static const String label = 'Log an entry';
  static const String hint = 'Tap to log now · hold for amount and time';

  @override
  State<LogButton> createState() => _LogButtonState();
}

class _LogButtonState extends State<LogButton> {
  static const double _dragSlop = 14;

  _FanRoute? _fan;
  Offset? _down;
  bool _moved = false;

  Rect _anchor() {
    final RenderBox box = context.findRenderObject()! as RenderBox;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  void _open() {
    if (_fan != null || widget.habits.isEmpty) {
      return;
    }
    final _FanRoute fan = _FanRoute(
      anchor: _anchor(),
      habits: widget.habits,
      onLog: widget.onLog,
      onRecord: widget.onRecord,
    );
    _fan = fan;
    Navigator.of(context).push(fan).whenComplete(() {
      if (identical(_fan, fan)) {
        _fan = null;
      }
    });
  }

  void _onDown(PointerDownEvent event) {
    _down = event.position;
    _moved = false;
    _open();
  }

  void _onMove(PointerMoveEvent event) {
    final _FanRoute? fan = _fan;
    if (_down == null || fan == null) {
      return;
    }
    if ((event.position - _down!).distance > _dragSlop) {
      _moved = true;
    }
    if (_moved) {
      fan.hot.value = fan.slotAt(event.position);
    }
  }

  void _onUp(PointerUpEvent event) {
    final _FanRoute? fan = _fan;
    _down = null;
    if (fan == null || !_moved) {
      return;
    }
    final int? slot = fan.slotAt(event.position);
    fan.hot.value = null;
    if (slot != null) {
      fan.choose(slot, hold: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Semantics(
      button: true,
      label: LogButton.label,
      onTap: _open,
      customSemanticsActions: <CustomSemanticsAction, VoidCallback>{
        for (final FanHabit h in widget.habits)
          CustomSemanticsAction(label: logOneLabel(h.vice)): () =>
              widget.onLog(h.vice, _anchor().center),
      },
      child: FocusableActionDetector(
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              _open();
              return null;
            },
          ),
        },
        child: Listener(
          onPointerDown: _onDown,
          onPointerMove: _onMove,
          onPointerUp: _onUp,
          onPointerCancel: (_) => _down = null,
          child: ExcludeSemantics(
            child: Container(
              width: DialSize.logButton,
              height: DialSize.logButton,
              decoration: BoxDecoration(
                color: scheme.primary,
                shape: BoxShape.circle,
                // A ring of the ground cuts the button out of what is
                // behind it.
                border: Border.all(
                  color: scheme.surface,
                  width: 6,
                  strokeAlign: BorderSide.strokeAlignOutside,
                ),
              ),
              child: Icon(Icons.add, size: 28, color: scheme.onPrimary),
            ),
          ),
        ),
      ),
    );
  }
}

class _FanRoute extends PopupRoute<void> {
  _FanRoute({
    required this.anchor,
    required this.habits,
    required this.onLog,
    required this.onRecord,
  }) : slots = fanSlots(habits);

  final Rect anchor;
  final List<FanHabit> habits;
  final ({List<FanHabit> shown, bool more}) slots;
  final void Function(Vice vice, Offset from) onLog;
  final void Function(Vice? vice) onRecord;
  final ValueNotifier<int?> hot = ValueNotifier<int?>(null);

  int get count => slots.shown.length + (slots.more ? 1 : 0);

  // Set by the page once laid out: the fan's centre and scale, globally.
  Offset centre = Offset.zero;
  double scale = 1;

  int? slotAt(Offset global) => wedgeAt(global - centre, count, scale: scale);

  void choose(int slot, {required bool hold}) {
    final Vice? vice = slot < slots.shown.length
        ? slots.shown[slot].vice
        : null;
    final Offset from = centre + wedgeLabelPoint(slot, count, scale);
    if (navigator?.canPop() ?? false) {
      navigator!.pop();
    }
    if (vice != null && !hold) {
      onLog(vice, from);
    } else {
      onRecord(vice);
    }
  }

  @override
  void dispose() {
    hot.dispose();
    super.dispose();
  }

  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => false;

  @override
  String? get barrierLabel => null;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 200);

  @override
  Duration get reverseTransitionDuration => DialMotion.fanClose;

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => FadeTransition(opacity: animation, child: child);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => Material(
    type: MaterialType.transparency,
    child: _FanPage(route: this),
  );
}

class _FanPage extends StatefulWidget {
  const _FanPage({required this.route});

  final _FanRoute route;

  @override
  State<_FanPage> createState() => _FanPageState();
}

class _FanPageState extends State<_FanPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _open = AnimationController(
    vsync: this,
    duration:
        DialMotion.fanStagger * widget.route.count +
        const Duration(milliseconds: 700),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _open.value = 1;
    } else if (!_open.isAnimating && _open.value == 0) {
      _open.forward();
    }
  }

  @override
  void dispose() {
    _open.dispose();
    super.dispose();
  }

  // How far wedge [i] has sprung out, from 0 to about 1.
  double _wedge(int i) {
    final Duration total = _open.duration!;
    final double seconds =
        _open.value * total.inMicroseconds / 1e6 -
        i * DialMotion.fanStagger.inMicroseconds / 1e6;
    if (_open.value >= 1) {
      return 1;
    }
    if (seconds <= 0) {
      return 0;
    }
    return SpringSimulation(DialMotion.landing, 0, 1, 0).x(seconds);
  }

  @override
  Widget build(BuildContext context) {
    final _FanRoute route = widget.route;
    final MediaQueryData media = MediaQuery.of(context);
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final DialColors colors = DialColors.of(context);
    final double scale = min(
      1,
      (media.size.width / 2 - 8) / (FanGeometry.outer + 16),
    );
    final double reach = FanGeometry.outer * scale;
    final Offset centre = Offset(
      route.anchor.center.dx,
      max(
        route.anchor.center.dy - FanGeometry.lift,
        media.padding.top + reach + 56,
      ),
    );
    route
      ..centre = centre
      ..scale = scale;
    final int n = route.count;
    final TextScaler labels = media.textScaler.clamp(maxScaleFactor: 1.3);

    void close() => Navigator.of(context).maybePop();

    // The route below keeps no focus: Escape closes the fan, and Tab walks
    // the wedges clockwise, then Close.
    return Actions(
      actions: <Type, Action<Intent>>{
        DismissIntent: CallbackAction<DismissIntent>(
          onInvoke: (_) {
            close();
            return null;
          },
        ),
      },
      child: Focus(
        autofocus: true,
        skipTraversal: true,
        child: FocusTraversalGroup(
          policy: OrderedTraversalPolicy(),
          child: Stack(
            children: <Widget>[
              Positioned.fill(
                child: Semantics(
                  button: true,
                  label: 'Close',
                  onTap: () => Navigator.of(context).pop(),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.of(context).pop(),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                      child: ColoredBox(color: colors.scrim),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: DialSpace.m,
                right: DialSpace.m,
                top: centre.dy - reach - 52,
                child: Center(child: _Hint(scheme: scheme)),
              ),
              AnimatedBuilder(
                animation: Listenable.merge(<Listenable>[_open, route.hot]),
                builder: (BuildContext context, _) => Stack(
                  children: <Widget>[
                    for (int k = 0; k < n; k++)
                      FocusTraversalOrder(
                        order: NumericFocusOrder(k.toDouble()),
                        child: _placedWedge(
                          context,
                          k,
                          n,
                          centre,
                          scale,
                          labels,
                        ),
                      ),
                    Positioned.fromRect(
                      rect: Rect.fromCircle(center: centre, radius: reach + 18),
                      child: IgnorePointer(
                        child: Opacity(
                          opacity: (_open.value * 3).clamp(0, 1),
                          child: CustomPaint(
                            painter: _SpokesPainter(
                              count: n,
                              scale: scale,
                              color: scheme.onSurface.withValues(alpha: 0.45),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Positioned.fromRect(
                rect: Rect.fromCircle(
                  center: centre,
                  radius: (FanGeometry.inner - 6) * scale,
                ),
                child: IgnorePointer(
                  child: _FanHub(scheme: scheme, colors: colors),
                ),
              ),
              Positioned.fromRect(
                rect: route.anchor,
                child: FocusTraversalOrder(
                  order: NumericFocusOrder(n.toDouble()),
                  child: Semantics(
                    button: true,
                    label: 'Close',
                    excludeSemantics: true,
                    child: Material(
                      color: scheme.surfaceContainerLow,
                      shape: const CircleBorder(),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: close,
                        customBorder: const CircleBorder(),
                        child: Icon(
                          Icons.close,
                          size: 28,
                          color: scheme.onSurface,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _placedWedge(
    BuildContext context,
    int k,
    int n,
    Offset centre,
    double scale,
    TextScaler labels,
  ) {
    final _FanRoute route = widget.route;
    final double v = _wedge(k);
    final double box = (FanGeometry.outer + 8) * scale;
    final double rise = (route.anchor.center.dy - centre.dy) * (1 - v);
    final FanHabit? habit = k < route.slots.shown.length
        ? route.slots.shown[k]
        : null;
    final bool hot = route.hot.value == k;

    return Positioned.fromRect(
      rect: Rect.fromCircle(center: centre, radius: box),
      child: Opacity(
        opacity: (v * 1.6).clamp(0, 1),
        child: Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..translateByDouble(0, rise, 0, 1)
            ..rotateZ(-14 * pi / 180 * (1 - v))
            ..scaleByDouble(
              (0.2 + 0.8 * v) * (hot ? 1.04 : 1),
              (0.2 + 0.8 * v) * (hot ? 1.04 : 1),
              1,
              1,
            ),
          child: _Wedge(
            key: ValueKey<String>('fan-wedge-${habit?.vice.id ?? 'more'}'),
            index: k,
            count: n,
            scale: scale,
            habit: habit,
            labels: labels,
            onTap: () => route.choose(k, hold: false),
            onHold: () {
              HapticFeedback.mediumImpact();
              route.choose(k, hold: true);
            },
          ),
        ),
      ),
    );
  }
}

// One wedge of the fan. It is hit only inside its own shape. With a keyboard,
// Enter or Space on a focused wedge does what a tap does.
class _Wedge extends StatefulWidget {
  const _Wedge({
    super.key,
    required this.index,
    required this.count,
    required this.scale,
    required this.habit,
    required this.labels,
    required this.onTap,
    required this.onHold,
  });

  final int index;
  final int count;
  final double scale;
  final FanHabit? habit;
  final TextScaler labels;
  final VoidCallback onTap;
  final VoidCallback onHold;

  static String amount(Unit unit) =>
      '+${unit.label(defaultQuantity)}'.replaceAll(RegExp(r'minutes?'), 'min');

  @override
  State<_Wedge> createState() => _WedgeState();
}

class _WedgeState extends State<_Wedge> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final int index = widget.index;
    final int count = widget.count;
    final double scale = widget.scale;
    final FanHabit? habit = widget.habit;
    final TextScaler labels = widget.labels;
    final VoidCallback onTap = widget.onTap;
    final VoidCallback onHold = widget.onHold;
    final DialColors colors = DialColors.of(context);
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Vice? vice = habit?.vice;
    final String name = vice?.name ?? 'More';
    final String detail = vice == null
        ? 'all habits'
        : _Wedge.amount(vice.unit);
    final double chord =
        2 * FanGeometry.label * scale * sin(pi / max(count, 2)) * 0.9;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final Offset middle = constraints.biggest.center(Offset.zero);
        final Offset label = middle + wedgeLabelPoint(index, count, scale);
        final double width = min(chord, 104 * scale);

        return Semantics(
          button: true,
          label: vice == null ? 'More habits' : logOneLabel(vice),
          hint: vice == null ? null : 'Hold to set amount and time',
          onTap: onTap,
          onLongPress: onHold,
          excludeSemantics: true,
          // Inside the clip, so the detector's mouse region takes no hits
          // outside the wedge.
          child: ClipPath(
            clipper: _WedgeClipper(index, count, scale),
            child: FocusableActionDetector(
              actions: <Type, Action<Intent>>{
                ActivateIntent: CallbackAction<ActivateIntent>(
                  onInvoke: (_) {
                    onTap();
                    return null;
                  },
                ),
              },
              onShowFocusHighlight: (bool on) => setState(() => _focused = on),
              child: RawGestureDetector(
                behavior: HitTestBehavior.opaque,
                gestures: <Type, GestureRecognizerFactory>{
                  TapGestureRecognizer:
                      GestureRecognizerFactoryWithHandlers<
                        TapGestureRecognizer
                      >(
                        TapGestureRecognizer.new,
                        (TapGestureRecognizer t) => t.onTap = onTap,
                      ),
                  LongPressGestureRecognizer:
                      GestureRecognizerFactoryWithHandlers<
                        LongPressGestureRecognizer
                      >(
                        () => LongPressGestureRecognizer(
                          duration: DialMotion.holdForAmount,
                        ),
                        (LongPressGestureRecognizer l) =>
                            l.onLongPress = onHold,
                      ),
                },
                child: CustomPaint(
                  painter: _WedgePainter(
                    index: index,
                    count: count,
                    scale: scale,
                    fill: habit == null
                        ? scheme.surfaceContainerLow
                        : colors.habit(habit.mark),
                    rim: habit == null
                        ? colors.line
                        : colors
                              .habitInk(habit.mark)
                              .withValues(alpha: colors.bead.rimAlpha),
                    rimWidth: habit == null ? 1 : colors.bead.rimWidth,
                    gap: scheme.surface,
                    focus: _focused ? scheme.onSurface : null,
                  ),
                  child: Stack(
                    children: <Widget>[
                      Positioned(
                        left: label.dx - width / 2,
                        top: label.dy - 18 * scale,
                        width: width,
                        child: MediaQuery(
                          data: MediaQuery.of(
                            context,
                          ).copyWith(textScaler: labels),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Text(
                                name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: DialTypeScale.label.copyWith(
                                  fontSize: 12.5,
                                  height: 1.2,
                                  color: habit == null
                                      ? scheme.onSurface
                                      : colors.wedgeInk,
                                ),
                              ),
                              Text(
                                detail,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: DialTypeScale.monoM.copyWith(
                                  fontSize: 11,
                                  height: 1.3,
                                  color: habit == null
                                      ? colors.muted
                                      : colors.wedgeInk,
                                ),
                              ),
                            ],
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

class _WedgeClipper extends CustomClipper<Path> {
  _WedgeClipper(this.index, this.count, this.scale);

  final int index;
  final int count;
  final double scale;

  @override
  Path getClip(Size size) =>
      wedgePath(index, count, scale).shift(size.center(Offset.zero));

  @override
  bool shouldReclip(_WedgeClipper old) =>
      old.index != index || old.count != count || old.scale != scale;
}

class _WedgePainter extends CustomPainter {
  _WedgePainter({
    required this.index,
    required this.count,
    required this.scale,
    required this.fill,
    required this.rim,
    required this.rimWidth,
    required this.gap,
    this.focus,
  });

  final int index;
  final int count;
  final double scale;
  final Color fill;
  final Color rim;
  final double rimWidth;
  final Color gap;
  // The keyboard focus ring's colour, while the wedge has focus.
  final Color? focus;

  @override
  void paint(Canvas canvas, Size size) {
    final Path path = wedgePath(
      index,
      count,
      scale,
    ).shift(size.center(Offset.zero));
    canvas.drawPath(path, Paint()..color = fill);
    canvas.save();
    canvas.clipPath(path);
    // The ground's gap between wedges, then the rim inside it; clipped to the
    // wedge, each stroke shows only its inner half.
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = 3
        ..color = gap,
    );
    if (rimWidth > 0) {
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = 3 + 2 * rimWidth
          ..color = rim,
      );
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = 3
          ..color = gap,
      );
    }
    if (focus case final Color ring) {
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = 3 + 2 * 3
          ..color = ring,
      );
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = 3
          ..color = gap,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_WedgePainter old) =>
      old.fill != fill ||
      old.rim != rim ||
      old.gap != gap ||
      old.focus != focus ||
      old.scale != scale ||
      old.index != index ||
      old.count != count;
}

class _SpokesPainter extends CustomPainter {
  _SpokesPainter({
    required this.count,
    required this.scale,
    required this.color,
  });

  final int count;
  final double scale;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (count < 2) {
      return;
    }
    final Offset c = size.center(Offset.zero);
    final Paint paint = Paint()
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..color = color;
    for (int k = 0; k < count; k++) {
      final double a = wedgeStart(k, count);
      canvas.drawLine(
        c + Offset(cos(a), sin(a)) * FanGeometry.inner * scale,
        c + Offset(cos(a), sin(a)) * (FanGeometry.outer + 16) * scale,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_SpokesPainter old) =>
      old.count != count || old.scale != scale || old.color != color;
}

class _FanHub extends StatelessWidget {
  const _FanHub({required this.scheme, required this.colors});

  final ColorScheme scheme;
  final DialColors colors;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: scheme.surfaceContainerLow,
      shape: BoxShape.circle,
    ),
    child: FittedBox(
      fit: BoxFit.scaleDown,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              formatClock(DateTime.now()),
              style: DialTypeScale.monoM.copyWith(color: scheme.onSurface),
            ),
            Text(
              'now',
              style: DialTypeScale.bodyS.copyWith(
                fontSize: 10,
                color: colors.muted,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _Hint extends StatelessWidget {
  const _Hint({required this.scheme});

  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    const TextStyle bold = TextStyle(fontWeight: FontWeight.w600);
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: scheme.surfaceContainerLow,
        shape: const StadiumBorder(),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
        child: Text.rich(
          const TextSpan(
            children: <InlineSpan>[
              TextSpan(text: 'Tap', style: bold),
              TextSpan(text: ' to log now · '),
              TextSpan(text: 'hold', style: bold),
              TextSpan(text: ' for amount and time'),
            ],
          ),
          textAlign: TextAlign.center,
          style: DialTypeScale.bodyS.copyWith(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: scheme.onSurface,
          ),
        ),
      ),
    );
  }
}
