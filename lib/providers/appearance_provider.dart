import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  Future<void> _load() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final ThemeMode? saved = parse(prefs.getString(key));
    // A choice made while the read was in flight is newer than what it read.
    if (saved != null && !_chosen) {
      state = saved;
    }
  }

  Future<void> choose(ThemeMode mode) async {
    _chosen = true;
    state = mode;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, mode.name);
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
