import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:tracker/design/tokens.dart';

// A status pill that drops in from above on the landing spring and lifts away
// when it goes. The space it takes grows and shrinks with it, so what is
// below eases rather than jumps. Under reduce motion it only fades.
class PillDrop extends StatefulWidget {
  const PillDrop({super.key, required this.shown, required this.child});

  final bool shown;
  final Widget child;

  // The mock-up's drop height, and its lift: 60 pt over 220 ms (100 ms under
  // reduce motion), easing in.
  static const double dropFrom = -70;
  static const double liftTo = -60;
  static const Duration lift = Duration(milliseconds: 220);
  static const Duration reducedLift = Duration(milliseconds: 100);
  static const Curve liftCurve = Cubic(0.4, 0, 1, 1);
  static const double radius = 22;

  @override
  State<PillDrop> createState() => _PillDropState();
}

class _PillDropState extends State<PillDrop> with TickerProviderStateMixin {
  // The pill's offset from its place, in logical pixels.
  late final AnimationController _y = AnimationController.unbounded(
    vsync: this,
    value: widget.shown ? 0 : PillDrop.dropFrom,
  );
  late final AnimationController _fade = AnimationController(
    vsync: this,
    value: widget.shown ? 1 : 0,
  );
  late Widget _child = widget.child;
  bool _lifting = false;

  bool get _reduced => MediaQuery.disableAnimationsOf(context);

  @override
  void didUpdateWidget(PillDrop old) {
    super.didUpdateWidget(old);
    if (widget.shown) {
      _child = widget.child;
    }
    if (widget.shown == old.shown) {
      return;
    }
    if (widget.shown) {
      _lifting = false;
      if (_reduced) {
        _y.value = 0;
        _fade.duration = DialMotion.reducedFade;
        _fade.forward(from: 0);
      } else {
        _fade.value = 1;
        _y.animateWith(
          SpringSimulation(DialMotion.landing, PillDrop.dropFrom, 0, 0),
        );
      }
    } else {
      _lifting = true;
      if (_reduced) {
        _fade.duration = PillDrop.reducedLift;
        _fade.reverse(from: 1);
      } else {
        _y
            .animateTo(
              PillDrop.liftTo,
              duration: PillDrop.lift,
              curve: PillDrop.liftCurve,
            )
            .whenCompleteOrCancel(() {
              if (mounted && !widget.shown) {
                _fade.value = 0;
              }
            });
      }
    }
  }

  @override
  void dispose() {
    _y.dispose();
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge(<Listenable>[_y, _fade]),
    builder: (BuildContext context, Widget? child) {
      if (!widget.shown && _fade.value == 0) {
        return const SizedBox.shrink();
      }
      final double y = _y.value;
      final double travel = _lifting ? PillDrop.liftTo : PillDrop.dropFrom;
      final double k = (1 - y / travel).clamp(0, 1);
      final double opacity = _lifting
          ? k * _fade.value
          : (1 + y / 50).clamp(0, 1) * _fade.value;
      return Align(
        alignment: Alignment.bottomCenter,
        heightFactor: _reduced ? _fade.value : k,
        child: Transform.translate(
          offset: Offset(0, y),
          child: Opacity(opacity: opacity, child: child),
        ),
      );
    },
    child: _child,
  );
}
