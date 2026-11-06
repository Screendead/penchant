import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/json_fields.dart';
import 'package:tracker/data/unit.dart';
import 'package:tracker/data/usage_series.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/formats.dart';

import 'fakes.dart';

void main() {
  group('parseAmount', () {
    test('reads a point as the decimal mark in en_US, and a whole number as '
        'an int', () {
      expect(parseAmount('1.5', locale: 'en_US'), 1.5);
      expect(parseAmount(' .25 ', locale: 'en_US'), 0.25);
      expect(parseAmount('2', locale: 'en_US'), isA<int>());
      expect(parseAmount('2.0', locale: 'en_US'), isA<int>());
      expect(parseAmount('2.', locale: 'en_US'), 2);
    });

    test("refuses grouping, where intl's parse would read 1,5 as 15", () {
      expect(parseAmount('1,5', locale: 'en_US'), isNull);
      expect(parseAmount('1,000', locale: 'en_US'), isNull);
    });

    test("reads the region's comma, and a point too, in en_ZA", () {
      expect(parseAmount('1,5', locale: 'en_ZA'), 1.5);
      expect(parseAmount('1.5', locale: 'en_ZA'), 1.5);
    });

    test('refuses what is not a number', () {
      for (final String text in <String>['', '.', 'abc', '1.2.3', '1e3']) {
        expect(parseAmount(text, locale: 'en_US'), isNull, reason: text);
      }
      expect(parseAmount('-1', locale: 'en_US'), -1);
    });

    test('reads back what formatAmount shows, in every app locale', () {
      for (final Locale l in appLocales) {
        final String locale = l.toString();
        for (final num value in <num>[1, 1.5, 0.25, 1234.5]) {
          expect(
            parseAmount(formatAmount(value, locale: locale), locale: locale),
            value,
            reason: '$locale $value',
          );
        }
      }
    });
  });

  test('readAmount keeps a positive number and drops anything else', () {
    expect(readAmount(1.5), 1.5);
    expect(readAmount(2), 2.0);
    for (final Object? value in <Object?>[
      null,
      0,
      -1.5,
      '1.5',
      double.nan,
      double.infinity,
    ]) {
      expect(readAmount(value), isNull, reason: '$value');
    }
  });

  test('an activity counts its amount when it has one, else its quantity', () {
    final Timestamp at = Timestamp.fromDate(DateTime(2026, 11, 2));
    final ViceActivity legacy = ViceActivity.fromJson(
      id: 'a',
      json: <String, dynamic>{'viceID': 'v', 'quantity': 2, 'createdAt': at},
    );
    final ViceActivity decimal = ViceActivity.fromJson(
      id: 'b',
      json: <String, dynamic>{
        'viceID': 'v',
        'quantity': 2,
        'amount': 1.5,
        'createdAt': at,
      },
    );
    final ViceActivity mistyped = ViceActivity.fromJson(
      id: 'c',
      json: <String, dynamic>{
        'viceID': 'v',
        'quantity': 2,
        'amount': 'lots',
        'createdAt': at,
      },
    );
    expect(legacy.amount, isNull);
    expect(legacy.measure, 2);
    expect(decimal.measure, 1.5);
    expect(mistyped.amount, isNull);
    expect(mistyped.measure, 2);
  });

  test('storedMeasure keeps whole numbers as a quantity alone', () {
    expect(storedMeasure(3), (quantity: 3, amount: null));
    expect(storedMeasure(1.5), (quantity: 2, amount: 1.5));
    expect(storedMeasure(0.25), (quantity: 1, amount: 0.25));
    expect(storedMeasure(3, keepAmount: true), (quantity: 3, amount: 3.0));
  });

  test('day totals add amounts and quantities together', () {
    final DateTime today = DateTime(2026, 11, 2);
    final UsageRange range = usageRange(today, 1, 1);
    expect(
      bucketTotals(range, <ViceActivity>[
        fakeActivity('v', 2, today, amount: 1.5),
        fakeActivity('v', 1, today.add(const Duration(hours: 1))),
      ]),
      <double>[2.5],
    );
  });

  test('a unit labels a decimal in the plural', () {
    debugFormatLocales = const <Locale>[Locale('en', 'US')];
    addTearDown(() => debugFormatLocales = null);
    expect(Unit.drink.label(1.5), '1.5 drinks');
    expect(Unit.drink.label(1), '1 drink');
  });
}
