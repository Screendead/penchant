import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tracker/errors/report_error.dart';

/// How the app treats motion: the system's Reduce Motion, always reduced, or
/// always full.
enum MotionPreference {
  system,
  reduce,
  full;

  /// The value for `MediaQueryData.disableAnimations`.
  bool resolve({required bool system}) => switch (this) {
    MotionPreference.system => system,
    MotionPreference.reduce => true,
    MotionPreference.full => false,
  };
}

/// Chosen in Settings and kept on this device only, for whoever is signed in.
final reduceMotionProvider = NotifierProvider<ReduceMotion, MotionPreference>(
  ReduceMotion.new,
);

class ReduceMotion extends Notifier<MotionPreference> {
  static const String key = 'reduceMotion';

  bool _chosen = false;

  @override
  MotionPreference build() {
    _load();
    return MotionPreference.system;
  }

  // A failed read leaves the app following the system.
  Future<void> _load() async {
    final MotionPreference? saved;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      saved = parse(prefs.getString(key));
    } catch (e, stack) {
      reportError(e, stack, context: 'while reading the reduce motion choice');
      return;
    }
    // A choice made while the read was in flight is newer than what it read.
    if (saved != null && !_chosen) {
      state = saved;
    }
  }

  Future<void> choose(MotionPreference preference) async {
    _chosen = true;
    state = preference;
    // A failed save still applies the choice until the app closes.
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, preference.name);
    } catch (e, stack) {
      reportError(e, stack, context: 'while saving the reduce motion choice');
    }
  }

  static MotionPreference? parse(String? name) {
    for (final MotionPreference preference in MotionPreference.values) {
      if (preference.name == name) return preference;
    }
    return null;
  }
}

/// The words Settings uses for each choice; the row's value says which system.
String motionLabel(MotionPreference preference) => switch (preference) {
  MotionPreference.system => 'Follow system',
  MotionPreference.reduce => 'Reduce',
  MotionPreference.full => 'Full',
};

/// The row's value in Settings; the mock-up reads "Follows iOS".
String motionRowValue(MotionPreference preference) => switch (preference) {
  MotionPreference.system =>
    defaultTargetPlatform == TargetPlatform.macOS
        ? 'Follows macOS'
        : 'Follows iOS',
  _ => motionLabel(preference),
};
