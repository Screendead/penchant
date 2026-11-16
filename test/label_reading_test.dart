import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/label/label_reading.dart';

List<double> _values(LabelField field) => <double>[
  for (final LabelValue v in field.choices) v.value,
];

void main() {
  group('strength', () {
    for (final (String text, double abv) in <(String, double)>[
      ('4.5% vol', 4.5),
      ('ALC. 13% BY VOL', 13),
      ('alc 5,0 % vol', 5),
      ('ABV 4.5%', 4.5),
      ('5.2% ABV', 5.2),
      ('Alcohol 12.5% by volume', 12.5),
      ('13.5% alc./vol.', 13.5),
      ('ABV: 0.5%', 0.5),
    ]) {
      test('"$text" proposes $abv', () {
        final LabelReading r = readLabel(<String>[text]);
        expect(r.abv.proposed?.value, abv);
        expect(_values(r.abv), <double>[abv]);
      });
    }

    test('"ABV" printed apart from its number still counts', () {
      final LabelReading r = readLabel(<String>['IPA', 'ABV', '6.8%', '440ml']);
      expect(r.abv.proposed?.value, 6.8);
    });

    test('a bare percentage is only a choice', () {
      final LabelReading r = readLabel(<String>['Pale ale', '5.2%']);
      expect(r.abv.proposed, isNull);
      expect(_values(r.abv), <double>[5.2]);
    });

    test('"100% recycled" and 0.0% read as nothing', () {
      expect(readLabel(<String>['100% recycled can']).abv.isEmpty, isTrue);
      expect(readLabel(<String>['Alcohol free 0.0% vol']).abv.isEmpty, isTrue);
    });

    test('two stated strengths are choices, none proposed', () {
      final LabelReading r = readLabel(<String>['5% vol', 'ABV 4.8%']);
      expect(r.abv.proposed, isNull);
      expect(_values(r.abv), <double>[5, 4.8]);
    });

    test('the same strength twice is one value', () {
      final LabelReading r = readLabel(<String>['4.5% vol', 'ALC 4.5% VOL']);
      expect(r.abv.proposed?.value, 4.5);
      expect(r.abv.choices, hasLength(1));
    });

    test('an anchored strength is proposed beside a bare one', () {
      final LabelReading r = readLabel(<String>['12% RI', 'ALC 5% VOL']);
      expect(r.abv.proposed?.value, 5);
      expect(_values(r.abv), <double>[5, 12]);
    });

    test('a number running into a percentage is not read', () {
      expect(readLabel(<String>['1,500% vol']).abv.isEmpty, isTrue);
    });
  });

  group('volume', () {
    for (final (String text, double ml) in <(String, double)>[
      ('330 ml', 330),
      ('330ML', 330),
      ('75 cl', 750),
      ('75cl e', 750),
      ('1.5 L', 1500),
      ('0,5 l', 500),
      ('4 x 440 ml', 440),
      ('Contents 500 ml', 500),
    ]) {
      test('"$text" proposes $ml ml', () {
        final LabelReading r = readLabel(<String>[text]);
        expect(r.volume.proposed?.value, ml);
        expect(_values(r.volume), <double>[ml]);
      });
    }

    test('fluid ounces are offered as US and UK, none proposed', () {
      final LabelReading r = readLabel(<String>['12 fl oz']);
      expect(r.volume.proposed, isNull);
      expect(r.volume.choices.map((LabelValue v) => v.note), <String>[
        'US',
        'UK',
      ]);
      expect(r.volume.choices.first.value, closeTo(354.88, 0.01));
      expect(r.volume.choices.last.value, closeTo(340.96, 0.01));
    });

    test('a pint is offered as UK and US', () {
      final LabelReading r = readLabel(<String>['1 pint']);
      expect(r.volume.proposed, isNull);
      expect(_values(r.volume), <double>[568.26, 473.18]);
      expect(r.volume.choices.first.read, '1 pint');
    });

    test('a metric size said again in fluid ounces is one size', () {
      final LabelReading r = readLabel(<String>['330 ml / 11.2 fl oz']);
      expect(r.volume.proposed?.value, 330);
      expect(r.volume.choices, hasLength(1));
      final LabelReading us = readLabel(<String>['12 FL OZ (355 mL)']);
      expect(us.volume.proposed?.value, 355);
      expect(us.volume.choices, hasLength(1));
    });

    test('"per 100 ml" is not the container', () {
      final LabelReading r = readLabel(<String>[
        'Typical values per 100 ml',
        '250ml',
      ]);
      expect(_values(r.volume), <double>[250]);
      expect(r.volume.proposed?.value, 250);
    });

    test('two sizes are choices, none proposed', () {
      final LabelReading r = readLabel(<String>['330 ml', '500 ml']);
      expect(r.volume.proposed, isNull);
      expect(_values(r.volume), <double>[330, 500]);
    });

    test('a size under 5 ml or over 5 litres is left out', () {
      expect(readLabel(<String>['2 ml']).volume.isEmpty, isTrue);
      expect(readLabel(<String>['10 l']).volume.isEmpty, isTrue);
    });

    test('"l" inside a word is no unit', () {
      expect(readLabel(<String>['12 Lager']).volume.isEmpty, isTrue);
    });
  });

  group('caffeine', () {
    test('"80 mg caffeine" proposes 80', () {
      final LabelReading r = readLabel(<String>['Contains 80 mg caffeine']);
      expect(r.caffeine.proposed?.value, 80);
    });

    test('"Caffeine: 95mg" proposes 95', () {
      expect(
        readLabel(<String>['Caffeine: 95mg']).caffeine.proposed?.value,
        95,
      );
    });

    test('per 100 ml times the one volume', () {
      final LabelReading r = readLabel(<String>[
        'High caffeine content (32 mg/100 ml)',
        '250 ml',
      ]);
      expect(r.caffeine.proposed?.value, 80);
      expect(r.caffeine.proposed?.read, '32 mg per 100 ml × 250 ml');
    });

    test('per 100 ml with no one volume is left out and said', () {
      final LabelReading r = readLabel(<String>['Caffeine 32mg/100ml']);
      expect(r.caffeine.isEmpty, isTrue);
      expect(r.notes.single, contains('32 mg per 100 ml'));
    });

    test('a figure and its per-100 ml working that agree are one value', () {
      final LabelReading r = readLabel(<String>[
        'Caffeine 32mg/100ml, 80mg per can',
        '250ml',
      ]);
      expect(r.caffeine.proposed?.value, 80);
      expect(r.caffeine.choices, hasLength(1));
    });

    test('other nutrients in mg are not caffeine', () {
      final LabelReading r = readLabel(<String>[
        'Sodium 80 mg',
        'Vitamin B6 2.1 mg',
      ]);
      expect(r.caffeine.isEmpty, isTrue);
    });

    test('"Caffeine" over its figure counts; the next nutrient does not', () {
      final LabelReading r = readLabel(<String>[
        'Caffeine',
        '80mg',
        'Sodium',
        '10mg',
      ]);
      expect(_values(r.caffeine), <double>[80]);
      expect(r.caffeine.proposed?.value, 80);
    });

    test('two caffeine figures are choices', () {
      final LabelReading r = readLabel(<String>[
        'Caffeine 80mg',
        'Caffeine 160 mg',
      ]);
      expect(r.caffeine.proposed, isNull);
      expect(_values(r.caffeine), <double>[80, 160]);
    });
  });

  test('a whole can reads as volume and strength', () {
    final LabelReading r = readLabel(<String>[
      'HOP STAR',
      'Session IPA',
      'BREWED AND CANNED IN LONDON',
      '440ml',
      '5.2% ABV',
      'CONTAINS BARLEY',
      'Recycle me 100%',
    ]);
    expect(r.volume.proposed?.value, 440);
    expect(r.abv.proposed?.value, 5.2);
    expect(r.caffeine.isEmpty, isTrue);
    expect(r.found, isTrue);
  });

  test('a wine back label', () {
    final LabelReading r = readLabel(<String>[
      'Côtes du Rhône',
      'PRODUCE OF FRANCE',
      '75cl',
      '14% vol',
      'Contains sulphites',
    ]);
    expect(r.volume.proposed?.value, 750);
    expect(r.abv.proposed?.value, 14);
  });

  test('text with nothing to read finds nothing', () {
    final LabelReading r = readLabel(<String>['Best before', '12 2027', '']);
    expect(r.found, isFalse);
    expect(readLabel(const <String>[]).found, isFalse);
  });
}
