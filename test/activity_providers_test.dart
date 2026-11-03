import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/providers/vice_activity_day_provider.dart';
import 'package:tracker/providers/vice_activity_list_provider.dart';
import 'package:tracker/providers/vice_list_provider.dart';

import 'fakes.dart';

void main() {
  final DateTime day = DateTime(2026, 3, 29);

  ProviderContainer containerWith(Stream<List<Vice>?> vices) {
    final ProviderContainer container = ProviderContainer(
      overrides: [
        userProvider.overrideWith((ref) => Stream.value(FakeUser(ownerID))),
        viceListProvider.overrideWith((ref) => vices),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<AsyncValue<List<ViceActivity>?>> settle(
    ProviderContainer container,
    ProviderListenable<AsyncValue<List<ViceActivity>?>> provider,
  ) async {
    container.listen(provider, (_, _) {});
    await container.read(userProvider.future);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    return container.read(provider);
  }

  final Map<String, ProviderListenable<AsyncValue<List<ViceActivity>?>>>
  providers = {
    'day': viceActivityDayProvider(day),
    'list': viceActivityListProvider,
  };

  for (final MapEntry(key: String name, value: provider) in providers.entries) {
    group('$name activity provider', () {
      test(
        'emits an empty list once the vice list is known to be empty',
        () async {
          final AsyncValue<List<ViceActivity>?> value = await settle(
            containerWith(Stream.value(const <Vice>[])),
            provider,
          );

          expect(value.hasValue, isTrue);
          expect(value.value, isEmpty);
        },
      );

      test('stays loading while the vice list is loading', () async {
        final StreamController<List<Vice>?> vices = StreamController();
        addTearDown(vices.close);

        final AsyncValue<List<ViceActivity>?> value = await settle(
          containerWith(vices.stream),
          provider,
        );

        expect(value.isLoading, isTrue);
        expect(value.value, isNull);
      });

      test('surfaces a vice list error instead of loading forever', () async {
        final AsyncValue<List<ViceActivity>?> value = await settle(
          containerWith(Stream.error(StateError('vices failed'))),
          provider,
        );

        expect(value.error, isA<StateError>());
      });
    });
  }
}
