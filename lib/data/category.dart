// What a vice is, for the insights. The names are stored and must match
// validCategory in firestore.rules.
enum ViceCategory {
  alcohol('Alcohol'),
  caffeine('Caffeine'),
  nicotine('Nicotine'),
  cannabis('Cannabis'),
  food('Food'),
  gambling('Gambling'),
  other('Other');

  final String label;

  const ViceCategory(this.label);

  static const ViceCategory fallback = ViceCategory.other;

  // Null for a missing value or a name this version does not know.
  static ViceCategory? tryParse(Object? value) =>
      value is String ? ViceCategory.values.asNameMap()[value] : null;

  static ViceCategory fromString(Object? value) => tryParse(value) ?? fallback;
}

// Matched at the start of a word of the vice name, ignoring case; the first
// hit wins. The starter presets (r2-presets) and the seed data's names are
// all here.
const List<(String, ViceCategory)> _keywords = <(String, ViceCategory)>[
  ('alcohol', ViceCategory.alcohol),
  ('booze', ViceCategory.alcohol),
  ('beer', ViceCategory.alcohol),
  ('wine', ViceCategory.alcohol),
  ('spirit', ViceCategory.alcohol),
  ('cocktail', ViceCategory.alcohol),
  ('coffee', ViceCategory.caffeine),
  ('espresso', ViceCategory.caffeine),
  ('caffeine', ViceCategory.caffeine),
  ('energy', ViceCategory.caffeine),
  ('tea', ViceCategory.caffeine),
  ('cigar', ViceCategory.nicotine),
  ('nicotine', ViceCategory.nicotine),
  ('vape', ViceCategory.nicotine),
  ('smok', ViceCategory.nicotine),
  ('tobacco', ViceCategory.nicotine),
  ('snus', ViceCategory.nicotine),
  ('cannabis', ViceCategory.cannabis),
  ('marijuana', ViceCategory.cannabis),
  ('weed', ViceCategory.cannabis),
  ('joint', ViceCategory.cannabis),
  ('sweet', ViceCategory.food),
  ('sugar', ViceCategory.food),
  ('snack', ViceCategory.food),
  ('junk food', ViceCategory.food),
  ('takeaway', ViceCategory.food),
  ('chocolate', ViceCategory.food),
  ('gambl', ViceCategory.gambling),
  ('betting', ViceCategory.gambling),
  ('casino', ViceCategory.gambling),
  ('lottery', ViceCategory.gambling),
];

ViceCategory guessCategory(String name) {
  final String lower = name.toLowerCase();
  for (final (String keyword, ViceCategory category) in _keywords) {
    if (RegExp('\\b${RegExp.escape(keyword)}').hasMatch(lower)) {
      return category;
    }
  }
  return ViceCategory.fallback;
}
