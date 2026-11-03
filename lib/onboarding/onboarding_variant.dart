import 'package:flutter/material.dart';
import 'package:tracker/data/unit.dart';

class VicePreset {
  const VicePreset(this.name, this.unit, this.icon);

  final String name;
  final Unit unit;
  final IconData icon;
}

class OnboardingVariant {
  const OnboardingVariant({
    required this.id,
    required this.introHeadline,
    required this.introBody,
    required this.introPoints,
    required this.question,
    required this.pickerHint,
    required this.presets,
    required this.disclaimerTitle,
    required this.acknowledge,
    required this.firstLogTitle,
    required this.firstLogBody,
  });

  final String id;
  final String introHeadline;
  final String introBody;
  final List<(IconData, String)> introPoints;
  final String question;
  final String pickerHint;

  /// Empty when the user names every vice themselves.
  final List<VicePreset> presets;
  final String disclaimerTitle;
  final String acknowledge;
  final String firstLogTitle;
  final String firstLogBody;

  // Fixed by ideas/release-blockers/neutral-framing-and-age-rating.md.
  static const String disclaimer =
      'A personal journal, not medical advice. Talk to a doctor about your '
      'health.';
}

const OnboardingVariant plainNames = OnboardingVariant(
  id: 'plain',
  introHeadline: 'A journal for your habits',
  introBody:
      'Log what you have and when. Over time you\'ll see your patterns, and '
      'what goes with them.',
  introPoints: [
    (Icons.touch_app_outlined, 'Log in a tap, add detail when you like'),
    (Icons.insights_outlined, 'See trends by day and by week'),
    (Icons.lock_outline, 'Private to your account'),
  ],
  question: 'What would you like to keep a journal of?',
  pickerHint: 'Pick any. You can rename, add or archive them later.',
  presets: [
    VicePreset('Alcohol', Unit.drink, Icons.wine_bar_outlined),
    VicePreset('Coffee', Unit.drink, Icons.coffee_outlined),
    VicePreset('Cigarettes', Unit.item, Icons.smoking_rooms_outlined),
    VicePreset('Vape', Unit.puff, Icons.cloud_outlined),
    VicePreset('Cannabis', Unit.time, Icons.grass_outlined),
    VicePreset('Energy drinks', Unit.drink, Icons.bolt_outlined),
    VicePreset('Sweets', Unit.item, Icons.cake_outlined),
    VicePreset('Gambling', Unit.time, Icons.casino_outlined),
  ],
  disclaimerTitle: 'Before you start',
  acknowledge: 'I understand',
  firstLogTitle: 'Anything to log right now?',
  firstLogBody:
      'It\'s logged at the current time. You can add detail or change it '
      'later.',
);

const OnboardingVariant everydayHabits = OnboardingVariant(
  id: 'everyday',
  introHeadline: 'Get to know your habits',
  introBody:
      'Note things down as they happen. Week by week you\'ll see when they '
      'happen and what goes with them.',
  introPoints: [
    (Icons.edit_note_outlined, 'Coffee, screens, drinks, anything'),
    (Icons.calendar_view_week_outlined, 'Patterns by time of day and week'),
    (Icons.lock_outline, 'Private to your account'),
  ],
  question: 'What do you do out of habit?',
  pickerHint: 'Start with one or two. Add more whenever you like.',
  presets: [
    VicePreset('Coffee', Unit.drink, Icons.coffee_outlined),
    VicePreset('Sweets', Unit.item, Icons.cake_outlined),
    VicePreset('Social media', Unit.minute, Icons.phone_iphone_outlined),
    VicePreset('Gaming', Unit.hour, Icons.sports_esports_outlined),
    VicePreset('Takeaway', Unit.time, Icons.takeout_dining_outlined),
    VicePreset('Late nights', Unit.time, Icons.bedtime_outlined),
    VicePreset('Alcohol', Unit.drink, Icons.wine_bar_outlined),
    VicePreset('Nicotine', Unit.time, Icons.smoking_rooms_outlined),
  ],
  disclaimerTitle: 'One thing first',
  acknowledge: 'Got it',
  firstLogTitle: 'Log your first one?',
  firstLogBody: 'One tap and it\'s in today\'s journal.',
);

const OnboardingVariant ownWords = OnboardingVariant(
  id: 'own-words',
  introHeadline: 'A private journal',
  introBody:
      'Keep track of anything you do or have by habit, and see the patterns '
      'over time.',
  introPoints: [
    (Icons.edit_outlined, 'Name it in your own words'),
    (Icons.insights_outlined, 'See trends by day and by week'),
    (Icons.lock_outline, 'Private to your account'),
  ],
  question: 'What would you like to keep a journal of?',
  pickerHint: 'Anything at all, in your own words.',
  presets: [],
  disclaimerTitle: 'Before you start',
  acknowledge: 'I understand',
  firstLogTitle: 'Anything to log right now?',
  firstLogBody:
      'It\'s logged at the current time. You can add detail or change it '
      'later.',
);

const List<OnboardingVariant> onboardingVariants = [
  plainNames,
  everydayHabits,
  ownWords,
];
