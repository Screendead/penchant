import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/providers/vice_activity_day_provider.dart';
import 'package:tracker/providers/vice_list_provider.dart';

import 'fakes.dart';

Future<void> _settle() async {
  for (int i = 0; i < 3; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  final DateTime day = DateTime(2026, 3, 29);
  late StreamController<User?> users;
  late Map<String, StreamController<List<Vice>>> vicesByUser;
  late Map<String, StreamController<List<ViceActivity>>> activitiesByUser;
  late List<String> cancelled;

  setUp(() {
    users = StreamController<User?>();
    cancelled = <String>[];
    StreamController<T> controllerFor<T>(String uid) =>
        StreamController<T>(onCancel: () => cancelled.add(uid));
    vicesByUser = {'a': controllerFor('a'), 'b': controllerFor('b')};
    activitiesByUser = {'a': controllerFor('a'), 'b': controllerFor('b')};
  });

  ProviderContainer container() {
    final ProviderContainer container = ProviderContainer(
      overrides: [
        userProvider.overrideWith((ref) => users.stream),
        viceListForUserProvider.overrideWith(
          (ref, String uid) => vicesByUser[uid]!.stream,
        ),
        viceActivityDayForUserProvider.overrideWith(
          (ref, ({String uid, DateTime day}) key) =>
              activitiesByUser[key.uid]!.stream,
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  final Map<String, ProviderListenable<AsyncValue<List<Object>>>> providers = {
    'vice list': viceListProvider,
    'day activities': viceActivityDayProvider(day),
  };

  void emitFor(String uid, String name) {
    vicesByUser[uid]!.add([fakeVice(name)]);
    activitiesByUser[uid]!.add([fakeActivity(name, 1, day)]);
  }

  String? shownID(Object? item) => switch (item) {
    Vice(:final String id) => id,
    ViceActivity(:final String viceID) => viceID,
    _ => null,
  };

  for (final MapEntry(key: String name, value: provider) in providers.entries) {
    group('the $name provider', () {
      test('is loading, with no value, while nobody is signed in', () async {
        final ProviderContainer c = container();
        c.listen(provider, (_, _) {});
        users.add(null);
        await _settle();

        expect(c.read(provider).isLoading, isTrue);
        expect(c.read(provider).value, isNull);
      });

      test("never returns the previous user's data after a sign-out", () async {
        final ProviderContainer c = container();
        final List<AsyncValue<List<Object>>> seen = [];
        c.listen(provider, (_, next) => seen.add(next));

        users.add(FakeUser('a'));
        await _settle();
        emitFor('a', 'from-a');
        await _settle();
        expect(c.read(provider).value?.map(shownID), ['from-a']);

        final int afterA = seen.length;
        users.add(null);
        await _settle();
        users.add(FakeUser('b'));
        await _settle();

        expect(c.read(provider).isLoading, isTrue);
        expect(c.read(provider).value, isNull);

        emitFor('b', 'from-b');
        await _settle();

        expect(
          [
            for (final AsyncValue<List<Object>> value in seen.skip(afterA))
              ...?value.value?.map(shownID),
          ],
          ['from-b'],
        );
      });

      test(
        "never returns the previous user's data on a direct switch",
        () async {
          final ProviderContainer c = container();
          c.listen(provider, (_, _) {});

          users.add(FakeUser('a'));
          await _settle();
          emitFor('a', 'from-a');
          await _settle();
          expect(c.read(provider).value?.map(shownID), ['from-a']);

          users.add(FakeUser('b'));
          await _settle();

          expect(c.read(provider).isLoading, isTrue);
          expect(c.read(provider).value, isNull);
        },
      );

      test("closes the previous user's query", () async {
        final ProviderContainer c = container();
        c.listen(provider, (_, _) {});

        users.add(FakeUser('a'));
        await _settle();
        users.add(FakeUser('b'));
        await _settle();

        expect(cancelled, contains('a'));
        expect(cancelled, isNot(contains('b')));
      });
    });
  }
}
