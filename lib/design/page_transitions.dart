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
    // animations 3 reads its default fill from package:material_ui's Theme,
    // which never sees this app's Theme, so it would fill with Material's
    // light default: a white flash mid-transition in dark mode.
    return Builder(
      builder: (BuildContext context) => FadeThroughTransition(
        animation: animation,
        secondaryAnimation: secondaryAnimation,
        fillColor: Theme.of(context).canvasColor,
        child: child,
      ),
    );
  }
}

// A page route whose clock ignores the platform's Reduce Motion flag, which
// scales a default controller to 5%. The Reduce motion setting decides instead:
// DialPageTransitionsBuilder reads it through MediaQuery.
class DialPageRoute<T> extends MaterialPageRoute<T> {
  DialPageRoute({
    required super.builder,
    super.settings,
    super.fullscreenDialog,
  });

  @override
  AnimationController createAnimationController() {
    return AnimationController(
      duration: transitionDuration,
      reverseDuration: reverseTransitionDuration,
      debugLabel: debugLabel,
      animationBehavior: AnimationBehavior.preserve,
      vsync: navigator!,
    );
  }
}
