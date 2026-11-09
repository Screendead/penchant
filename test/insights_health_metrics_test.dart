import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/insights/health_source.dart';
import 'package:tracker/providers/insights_provider.dart';
import 'package:tracker/providers/today_provider.dart';

import 'insights_harness.dart';

void main() {
  test('Insights reads every metric but sleeping heart rate', () async {
    final FakeHealthSource health = FakeHealthSource();
    final ProviderContainer container = ProviderContainer(
      overrides: [
        healthSourceProvider.overrideWithValue(health),
        healthConnectedProvider.overrideWith((ref) async => true),
        todayProvider.overrideWith(() => FixedToday(insightsToday)),
      ],
    );
    addTearDown(container.dispose);
    final ProviderSubscription<AsyncValue<HealthState>> sub = container.listen(
      healthStateProvider,
      (_, _) {},
    );
    addTearDown(sub.close);

    expect(
      await container.read(healthStateProvider.future),
      isA<HealthReady>(),
    );
    expect(health.lastMetrics, {
      for (final m in HealthMetric.values)
        if (m != HealthMetric.sleepingHeartRate) m,
    });
  });
}
