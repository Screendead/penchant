import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/letter/letter_checks.dart';

// functions/letter_fixture.json: functions/letter.test.js runs the same cases
// through the server's checks.
final Map<String, Object?> fixture = jsonDecode(
  File('functions/letter_fixture.json').readAsStringSync(),
) as Map<String, Object?>;

Map<String, Object?> get payload => fixture['payload']! as Map<String, Object?>;

Map<String, Object?> section(String heading, String body) => <String, Object?>{
  'heading': heading,
  'body': body,
};

void main() {
  test('the deny-list and number words match the server\'s', () {
    expect(letterDeniedTerms.toSet(), (fixture['terms']! as List).toSet());
    expect(letterDeniedTerms, hasLength((fixture['terms']! as List).length));
    expect(letterNumberWords, fixture['numberWords']);
  });

  test('each shared case gives the server\'s reason', () {
    final LetterContext context = LetterContext.of(payload);
    for (final Object? c in fixture['cases']! as List<Object?>) {
      final Map<String, Object?> m = c! as Map<String, Object?>;
      expect(
        checkPassage(m['text']! as String, context),
        m['expect'],
        reason: m['text'] as String?,
      );
    }
  });

  group('checkLetter', () {
    final Map<String, Object?> good = section(
      'What you wrote about most',
      'Wine came to 3.5 glasses over 2 days.',
    );

    test('keeps a letter that passes', () {
      final CheckedLetter? l = checkLetter(<String, Object?>{
        'sections': <Object?>[good, good, good],
        'toTest': <Object?>[
          <String, Object?>{
            'title': 'Evenings after a long day',
            'why': 'Long day comes up in your notes.',
          },
        ],
        'quotes': <Object?>[],
      }, payload);
      expect(l, isNotNull);
      expect(l!.sections, hasLength(3));
      expect(l.toTest, hasLength(1));
      expect(l.withheld, 0);
    });

    test('withholds a failing section and counts it', () {
      final CheckedLetter? l = checkLetter(<String, Object?>{
        'sections': <Object?>[
          good,
          section('What shifted', 'You should drink less.'),
          good,
        ],
        'toTest': <Object?>[
          <String, Object?>{'title': 'Count', 'why': 'You logged 9 times.'},
        ],
        'quotes': <Object?>[],
      }, payload);
      expect(l!.sections, hasLength(2));
      expect(l.toTest, isEmpty);
      expect(l.withheld, 2);
    });

    test('adds what the server withheld', () {
      final CheckedLetter? l = checkLetter(<String, Object?>{
        'sections': <Object?>[good, good],
        'toTest': <Object?>[],
        'quotes': <Object?>[],
        'withheld': 1,
      }, payload);
      expect(l!.withheld, 1);
    });

    test('shows nothing with fewer than two sections left', () {
      expect(
        checkLetter(<String, Object?>{
          'sections': <Object?>[
            good,
            section('A', 'That was a problem.'),
            section('B', 'Wine came to 7 glasses.'),
          ],
          'toTest': <Object?>[],
          'quotes': <Object?>[],
        }, payload),
        isNull,
      );
    });

    test('refuses too few or too many sections, or a malformed reply', () {
      expect(
        checkLetter(<String, Object?>{
          'sections': <Object?>[good, good],
          'toTest': <Object?>[],
        }, payload),
        isNull,
      );
      expect(
        checkLetter(<String, Object?>{
          'sections': List<Object?>.filled(6, good),
          'toTest': <Object?>[],
        }, payload),
        isNull,
      );
      expect(checkLetter('text', payload), isNull);
    });
  });
}
