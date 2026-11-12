import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';
import 'package:tracker/providers/reduce_motion_provider.dart';

/// Makes the saved motion choice reach `SemanticsBinding.disableAnimations`,
/// which every `AnimationController` reads: routes, sheets, dialogs and
/// implicit animations scale their durations by it, not by `MediaQuery`.
mixin MotionOverride on SemanticsBinding {
  MotionPreference motion = MotionPreference.system;

  @override
  bool get disableAnimations => motion.resolve(system: super.disableAnimations);
}

class PenchantBinding extends WidgetsFlutterBinding with MotionOverride {
  /// Must run before anything else creates a binding.
  static WidgetsBinding ensureInitialized() {
    try {
      return WidgetsBinding.instance;
    } catch (_) {
      PenchantBinding();
      return WidgetsBinding.instance;
    }
  }
}
