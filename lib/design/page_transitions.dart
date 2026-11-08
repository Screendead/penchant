import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import 'package:tracker/design/tokens.dart';

// Pages push with a fade-through. Under reduce motion the new page fades in
// over the first 150 ms and nothing scales: a route reads its length once,
// before it has a context, so the route itself still runs the full 320 ms.
class DialPageTransitionsBuilder extends PageTransitionsBuilder {
  const DialPageTransitionsBuilder();

  static final Curve _reducedCurve = Interval(
    0,
    DialMotion.reducedFade.inMicroseconds /
        DialMotion.fadeThrough.inMicroseconds,
  );

  @override
  Duration get transitionDuration => DialMotion.fadeThrough;

  @override
  Widget buildTransitions<T>(
    PageRoute<T>? route,
    BuildContext? context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (context != null && MediaQuery.disableAnimationsOf(context)) {
      return FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: _reducedCurve),
        child: child,
      );
    }
    return FadeThroughTransition(
      animation: animation,
      secondaryAnimation: secondaryAnimation,
      child: child,
    );
  }
}
