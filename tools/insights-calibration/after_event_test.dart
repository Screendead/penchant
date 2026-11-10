// Monte Carlo rates for the after-a-calendar-event comparison in
// lib/insights/after_event.dart, on synthetic data only. Slow, so it lives
// outside test/:
//   flutter test tools/insights-calibration/after_event_test.dart
// Each line prints the share of seeds with a finding before the
// false-discovery correction and the floor.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/insights/after_event.dart';

import '../../test/insights/after_event_synthetic.dart';

const int seeds = 400;

void rate(String name, EventDays Function(int seed) make) {
  int found = 0, fitted = 0, more = 0;
  for (int seed = 0; seed < seeds; seed++) {
    final EventDays d = make(seed);
    for (final AfterEvent a in afterEvent(
      uses: d.uses,
      events: d.events,
      through: d.through,
    )) {
      if (a.pValue != null) fitted++;
      if (a.found) {
        found++;
        if (a.effect! > 0) more++;
      }
    }
  }
  stdout.writeln(
    '$name ($seeds seeds, $fitted fitted): '
    '${(100 * found / seeds).toStringAsFixed(1)}% found, $more of them more',
  );
}

void main() {
  test('after a calendar event', () {
    rate('noise: Coffee in work hours, meetings in work hours', eventDays);
    rate('noise, 6 a weekday', (seed) => eventDays(seed, perDay: 6));
    rate('noise, 60 days', (seed) => eventDays(seed, days: 60));
    rate(
      'a use after 30% of meeting blocks',
      (seed) => eventDays(seed, follow: 0.3),
    );
    rate(
      'a use after 15% of meeting blocks, 60 days',
      (seed) => eventDays(seed, days: 60, follow: 0.15),
    );
  });
}
