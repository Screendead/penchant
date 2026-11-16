import 'package:flutter/foundation.dart';
import 'package:tracker/data/habit_strength.dart';
import 'package:tracker/data/limits.dart';

// Pulls a drink's strength, volume and caffeine out of the lines Apple's
// Vision read from a photo of its label. It never guesses: a value is
// proposed only when the label states exactly one, anything else is offered
// as choices for the person to pick, and what it cannot place is left out.
// Characters are taken as read: an O is never turned into a 0.

/// One value found on a label, with the words it came from.
@immutable
class LabelValue {
  const LabelValue(this.value, this.read, {this.note});

  /// In the field's unit: % ABV, ml, or mg.
  final double value;

  /// As printed, tidied: "5.2%", "75 cl", "12 fl oz".
  final String read;

  /// What a choice assumes, such as "US" for fluid ounces.
  final String? note;

  @override
  bool operator ==(Object other) =>
      other is LabelValue &&
      other.value == value &&
      other.read == read &&
      other.note == note;

  @override
  int get hashCode => Object.hash(value, read, note);

  @override
  String toString() => 'LabelValue($value, $read, $note)';
}

/// What a label says about one field.
@immutable
class LabelField {
  const LabelField(this.choices, {this.proposed});

  static const LabelField none = LabelField(<LabelValue>[]);

  /// Every value the label could mean, in the order read.
  final List<LabelValue> choices;

  /// Filled in at the start only when the label states exactly one value.
  final LabelValue? proposed;

  bool get isEmpty => choices.isEmpty;
}

@immutable
class LabelReading {
  const LabelReading({
    this.abv = LabelField.none,
    this.volume = LabelField.none,
    this.caffeine = LabelField.none,
    this.notes = const <String>[],
  });

  final LabelField abv;
  final LabelField volume;
  final LabelField caffeine;

  /// What was seen but not used, said plainly.
  final List<String> notes;

  bool get found => !abv.isEmpty || !volume.isEmpty || !caffeine.isEmpty;
}

// A drink above this is not a drink; "100% recycled" and the like fall out.
const double _labelMaxAbv = 80;
// Below this a volume is a dose or a typo, not a container.
const double _labelMinMl = 5;

const double _usFlOzMl = 29.5735;
const double _ukFlOzMl = 28.4131;
const double _usPintMl = 473.176;
const double _ukPintMl = 568.261;

final RegExp _abvAnchor = RegExp(
  r'\b(alc|alcohol|abv|vol|volume)\b',
  caseSensitive: false,
);
final RegExp _caffeineWord = RegExp(r'caff?ein', caseSensitive: false);

// A number: digits with at most one decimal mark, a point or a comma. A
// comma followed by three digits is grouping, which no percentage, volume
// or dose on a drink needs, so such a number is not read.
const String _number = r'(\d{1,4}(?:[.,]\d{1,2})?)(?![.,]?\d)';

final RegExp _percent = RegExp('(?<![\\d.,])$_number\\s*%');
final RegExp _volume = RegExp(
  '(?<![\\d.,])$_number\\s*'
  r'(ml|cl|l|litres?|liters?|fl\.?\s*oz|pints?|pt)\b',
  caseSensitive: false,
);
final RegExp _mg = RegExp(
  '(?<![\\d.,])$_number\\s*mg\\b'
  r'(?:\s*(?:/|per)\s*(\d{1,4})?\s*(ml|cl|l)\b)?',
  caseSensitive: false,
);
// A volume that follows "per" or "/" is what a figure is given against
// ("32 mg/100 ml", "per 100 ml"), not the container.
final RegExp _perBefore = RegExp(r'(?:per|/)\s*$', caseSensitive: false);

double? _parse(String digits) => double.tryParse(digits.replaceAll(',', '.'));

String _tidy(double value) {
  final double rounded = roundStrength(value);
  return rounded == rounded.roundToDouble()
      ? rounded.toInt().toString()
      : rounded.toString();
}

bool _near(double a, double b, double tolerance) =>
    (a - b).abs() <= tolerance * (a > b ? a : b);

// Text other than the number and its unit, so "ABV" alone on a line counts
// as a label for the line beside it and "Sodium" does not.
bool _bareLine(String line, Pattern value) =>
    !RegExp('[a-z]', caseSensitive: false).hasMatch(line.replaceAll(value, ''));

List<LabelValue> _distinct(Iterable<LabelValue> values, double tolerance) {
  final List<LabelValue> kept = <LabelValue>[];
  for (final LabelValue v in values) {
    if (!kept.any((LabelValue k) => _near(k.value, v.value, tolerance))) {
      kept.add(v);
    }
  }
  return kept;
}

LabelField _field(List<LabelValue> sure, List<LabelValue> loose) {
  final List<LabelValue> choices = _distinct(<LabelValue>[
    ...sure,
    ...loose,
  ], 0.001);
  final List<LabelValue> sureOnes = _distinct(sure, 0.001);
  return LabelField(
    choices,
    proposed: sureOnes.length == 1 ? sureOnes.single : null,
  );
}

LabelReading readLabel(List<String> lines) {
  final List<String> text = <String>[
    for (final String line in lines)
      if (line.trim().isNotEmpty) line.trim(),
  ];

  // Strength.
  final List<LabelValue> sureAbv = <LabelValue>[];
  final List<LabelValue> looseAbv = <LabelValue>[];
  for (int i = 0; i < text.length; i++) {
    final String line = text[i];
    final Iterable<RegExpMatch> found = _percent.allMatches(line);
    if (found.isEmpty) continue;
    bool anchoredBeside(int j) =>
        j >= 0 &&
        j < text.length &&
        _abvAnchor.hasMatch(text[j]) &&
        !_percent.hasMatch(text[j]) &&
        !_volume.hasMatch(text[j]);
    final bool anchored =
        _abvAnchor.hasMatch(line) ||
        (_bareLine(line, _percent) &&
            (anchoredBeside(i - 1) || anchoredBeside(i + 1)));
    for (final RegExpMatch m in found) {
      final double? value = _parse(m.group(1)!);
      if (value == null || value <= 0 || value > _labelMaxAbv) continue;
      final LabelValue v = LabelValue(value, '${_tidy(value)}%');
      (anchored ? sureAbv : looseAbv).add(v);
    }
  }

  // Volume. Metric is sure; fluid ounces and pints differ between the US and
  // the UK, so each is offered both ways unless a metric figure says which.
  final List<LabelValue> metric = <LabelValue>[];
  // Each imperial figure's readings, kept together so that a metric figure
  // beside it drops both.
  final List<List<LabelValue>> imperial = <List<LabelValue>>[];
  for (final String line in text) {
    for (final RegExpMatch m in _volume.allMatches(line)) {
      if (_perBefore.hasMatch(line.substring(0, m.start))) continue;
      final double? amount = _parse(m.group(1)!);
      if (amount == null || amount <= 0) continue;
      final String unit = m
          .group(2)!
          .toLowerCase()
          .replaceAll(RegExp(r'[.\s]'), '');
      final String shown = _tidy(amount);
      void add(List<LabelValue> into, double ml, String read, {String? note}) {
        if (ml >= _labelMinMl && ml <= maxServingMl) {
          into.add(LabelValue(roundStrength(ml), read, note: note));
        }
      }

      if (unit == 'ml') {
        add(metric, amount, '$shown ml');
      } else if (unit == 'cl') {
        add(metric, amount * 10, '$shown cl');
      } else if (unit == 'l' || unit.startsWith('lit')) {
        add(metric, amount * 1000, '$shown l');
      } else if (unit == 'floz') {
        final List<LabelValue> both = <LabelValue>[];
        add(both, amount * _usFlOzMl, '$shown fl oz', note: 'US');
        add(both, amount * _ukFlOzMl, '$shown fl oz', note: 'UK');
        imperial.add(both);
      } else {
        final String read = '$shown ${amount == 1 ? 'pint' : 'pints'}';
        final List<LabelValue> both = <LabelValue>[];
        add(both, amount * _ukPintMl, read, note: 'UK');
        add(both, amount * _usPintMl, read, note: 'US');
        imperial.add(both);
      }
    }
  }
  final List<LabelValue> metricOnes = _distinct(metric, 0.001);
  // "330 ml / 11.2 fl oz" is one size said twice.
  final List<LabelValue> otherImperial = <LabelValue>[
    for (final List<LabelValue> readings in imperial)
      if (!readings.any(
        (LabelValue v) =>
            metricOnes.any((LabelValue m) => _near(m.value, v.value, 0.02)),
      ))
        ...readings,
  ];
  final LabelField volume = _field(metricOnes, otherImperial);

  // Caffeine: only an mg figure that the word caffeine labels, on its line
  // or alone on the line after it.
  final List<String> notes = <String>[];
  final List<LabelValue> caffeine = <LabelValue>[];
  for (int i = 0; i < text.length; i++) {
    final String line = text[i];
    final bool labelled =
        _caffeineWord.hasMatch(line) ||
        (i > 0 &&
            _caffeineWord.hasMatch(text[i - 1]) &&
            !_mg.hasMatch(text[i - 1]) &&
            _bareLine(line, _mg));
    if (!labelled) continue;
    for (final RegExpMatch m in _mg.allMatches(line)) {
      final double? mg = _parse(m.group(1)!);
      if (mg == null || mg <= 0) continue;
      final String? perUnit = m.group(3)?.toLowerCase();
      if (perUnit == null) {
        if (mg <= maxCaffeineMg) {
          caffeine.add(LabelValue(roundStrength(mg), '${_tidy(mg)} mg'));
        }
        continue;
      }
      final double per =
          (_parse(m.group(2) ?? '1') ?? 1) *
          switch (perUnit) {
            'cl' => 10,
            'l' => 1000,
            _ => 1,
          };
      final String perText =
          '${_tidy(mg)} mg per '
          '${m.group(2) == null ? '' : '${m.group(2)} '}$perUnit';
      final LabelValue? size = volume.proposed;
      if (size == null || volume.choices.length != 1) {
        notes.add(
          'Caffeine is given as $perText, and the label shows no one '
          'volume to work out a serving from.',
        );
        continue;
      }
      final double total = mg * size.value / per;
      if (total > 0 && total <= maxCaffeineMg) {
        caffeine.add(
          LabelValue(roundStrength(total), '$perText × ${size.read}'),
        );
      }
    }
  }

  return LabelReading(
    abv: _field(sureAbv, looseAbv),
    volume: volume,
    caffeine: _field(caffeine, const <LabelValue>[]),
    notes: notes,
  );
}
