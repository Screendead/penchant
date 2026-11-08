import 'dart:math';

import 'package:flutter/widgets.dart';

// The iOS engine eases the keyboard inset along a spring and, on a display
// link that arrives late, evaluates it at a negative time, which reports an
// inset taller than the screen (or below zero) for a frame. Every Scaffold
// then has no room above the keyboard, and Flutter's floating SnackBar
// asserts it is off screen. A landscape iPhone keyboard with its suggestion
// bar is under 60% of the view's height, so no real one reaches the ceiling,
// and the third left above it holds the undo bar lifted over Today's Log
// button (245 pt of an 874 pt iPhone at the default text size).
class KeyboardInsetClamp extends StatelessWidget {
  const KeyboardInsetClamp({super.key, required this.child});

  static const double ceiling = 2 / 3;

  final Widget child;

  static double clamp(double inset, double height) =>
      inset.clamp(0.0, max(0.0, height * ceiling));

  @override
  Widget build(BuildContext context) {
    final MediaQueryData data = MediaQuery.of(context);
    final double bottom = clamp(data.viewInsets.bottom, data.size.height);
    if (bottom == data.viewInsets.bottom) {
      return child;
    }
    return MediaQuery(
      data: data.copyWith(viewInsets: data.viewInsets.copyWith(bottom: bottom)),
      child: child,
    );
  }
}
