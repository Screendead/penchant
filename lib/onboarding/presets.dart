import 'package:flutter/material.dart';
import 'package:tracker/data/unit.dart';

class HabitPreset {
  const HabitPreset(this.name, this.unit, this.icon);

  final String name;
  final Unit unit;
  final IconData icon;
}

// r2-presets A, the plain names (Jack, 2026-11-06).
const List<HabitPreset> habitPresets = <HabitPreset>[
  HabitPreset('Alcohol', Unit.drink, Icons.wine_bar_outlined),
  HabitPreset('Coffee', Unit.drink, Icons.coffee_outlined),
  HabitPreset('Cigarettes', Unit.item, Icons.smoking_rooms_outlined),
  HabitPreset('Vape', Unit.puff, Icons.cloud_outlined),
  HabitPreset('Cannabis', Unit.time, Icons.grass_outlined),
  HabitPreset('Energy drinks', Unit.drink, Icons.bolt_outlined),
  HabitPreset('Sweets', Unit.item, Icons.cake_outlined),
  HabitPreset('Gambling', Unit.time, Icons.casino_outlined),
];

class OnboardingCopy {
  static const String introHeadline = 'A journal for your habits';
  static const String introBody =
      'Log what you have and when. Over time you\'ll see your patterns, and '
      'what goes with them.';
  static const List<(IconData, String)> introPoints = <(IconData, String)>[
    (Icons.touch_app_outlined, 'Log in a tap, add detail when you like'),
    (Icons.insights_outlined, 'See trends by day and by week'),
    (Icons.lock_outline, 'Private to your account'),
  ];
  static const String start = 'Start';
  static const String skip = 'Skip';
  static const String question = 'What would you like to keep a journal of?';
  static const String pickerHint =
      'Pick any. You can rename, add or archive them later.';
  static const String somethingElse = 'Something else';
  static const String somethingElseHint = 'Name it yourself';
  static const String continueLabel = 'Continue';
  static String continueWith(int count) => 'Continue with $count';
  static String countedIn(Unit unit) => 'Counted in ${unit.plural}';
  static const String disclaimerTitle = 'Before you start';
  // Fixed by ideas/release-blockers/neutral-framing-and-age-rating.md.
  static const String disclaimer =
      'A personal journal, not medical advice. Talk to a doctor about your '
      'health.';
  static const String privacy =
      'Your entries are private to your account. You can export or delete '
      'them at any time from Settings.';
  static const String acknowledge = 'I understand';
  static const String firstLogTitle = 'Anything to log right now?';
  static const String firstLogBody =
      'It\'s logged at the current time. You can add detail or change it '
      'later.';
  static const String log = 'Log';
  static const String logged = 'Logged';
  static const String notNow = 'Not now, go to Today';
  static const String toToday = 'Go to Today';
}
