import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tracker/errors/report_error.dart';

/// Light, dark or the phone's setting, chosen in Settings and kept on this
/// device only, for whoever is signed in.
final appearanceProvider = NotifierProvider<Appearance, ThemeMode>(
  Appearance.new,
);

class Appearance extends Notifier<ThemeMode> {
  static const String key = 'appearance';

  bool _chosen = false;

  @override
  ThemeMode build() {
    _load();
    return ThemeMode.system;
  }

  // A failed read leaves the app following the phone.
  Future<void> _load() async {
    final ThemeMode? saved;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      saved = parse(prefs.getString(key));
    } catch (e, stack) {
      reportError(e, stack, context: 'while reading the appearance choice');
      return;
    }
    // A choice made while the read was in flight is newer than what it read.
    if (saved != null && !_chosen) {
      state = saved;
    }
  }

  Future<void> choose(ThemeMode mode) async {
    _chosen = true;
    state = mode;
    // A failed save still applies the choice until the app closes.
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, mode.name);
    } catch (e, stack) {
      reportError(e, stack, context: 'while saving the appearance choice');
    }
  }

  static ThemeMode? parse(String? name) {
    for (final ThemeMode mode in ThemeMode.values) {
      if (mode.name == name) return mode;
    }
    return null;
  }
}

/// The words Settings uses for each choice.
String appearanceLabel(ThemeMode mode) => switch (mode) {
  ThemeMode.system => 'Match system',
  ThemeMode.light => 'Light',
  ThemeMode.dark => 'Dark',
};
