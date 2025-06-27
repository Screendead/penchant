// Simple test to verify the time-series chart functionality
// This would normally be run with flutter test, but we'll keep it simple for now

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/vice_time_series_chart.dart';

void main() {
  group('ViceTimeSeriesChart Widget Tests', () {
    testWidgets('ViceTimeSeriesChart can be created', (WidgetTester tester) async {
      // Test that the widget can be instantiated
      final widget = ViceTimeSeriesChart(
        selectedDate: DateTime.now(),
      );
      
      expect(widget, isNotNull);
      expect(widget.selectedDate, isA<DateTime>());
    });

    test('TimeScale enum has correct values', () {
      expect(TimeScale.day.label, equals('Day'));
      expect(TimeScale.day.breakdown, equals('Hourly'));
      
      expect(TimeScale.week.label, equals('Week'));
      expect(TimeScale.week.breakdown, equals('Daily'));
      
      expect(TimeScale.month.label, equals('Month'));
      expect(TimeScale.month.breakdown, equals('Daily'));
      
      expect(TimeScale.quarter.label, equals('Quarter'));
      expect(TimeScale.quarter.breakdown, equals('Weekly'));
      
      expect(TimeScale.year.label, equals('Year'));
      expect(TimeScale.year.breakdown, equals('Monthly'));
    });
  });
}