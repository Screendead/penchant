import 'package:animations/animations.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tracker/design/tokens.dart';

// Pages push with a fade-through. Under reduce motion the new page fades in
// over the first 150 ms and nothing scales: a route reads its length once,
// before it has a context, so the route itself still runs the full 320 ms.
//
// With backGesture, a page that is not a fullscreen dialog also goes back on a
// drag from the left edge, as on iOS. Flutter's edge detector is private and
// reachable only through CupertinoRouteTransitionMixin.buildPageTransitions,
// which puts it inside a CupertinoPageTransition, so that slide is always in
// the tree: held still at rest (a button's push and pop keep the fade-through),
// driven by the route only while a back gesture moves it (the page follows the
// finger). Changing which animations it gets keeps the tree's shape, so the
// page's state survives the switch. The gesture is user-driven, so it slides
// under reduce motion too, without the page below sliding alongside.
class DialPageTransitionsBuilder extends PageTransitionsBuilder {
  const DialPageTransitionsBuilder({this.backGesture = false});

  final bool backGesture;

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
    final bool reduced =
        context != null && MediaQuery.disableAnimationsOf(context);
    if (!backGesture ||
        route == null ||
        context == null ||
        route.fullscreenDialog) {
      return _fade(reduced, animation, secondaryAnimation, child);
    }
    final bool swiping = route.popGestureInProgress;
    return CupertinoRouteTransitionMixin.buildPageTransitions<T>(
      route,
      context,
      swiping ? animation : kAlwaysCompleteAnimation,
      swiping && !reduced ? secondaryAnimation : kAlwaysDismissedAnimation,
      _fade(
        reduced,
        swiping ? kAlwaysCompleteAnimation : animation,
        swiping ? kAlwaysDismissedAnimation : secondaryAnimation,
        child,
      ),
    );
  }

  Widget _fade(
    bool reduced,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (reduced) {
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
