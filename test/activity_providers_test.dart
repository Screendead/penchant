import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/providers/unarchived_vice_list_provider.dart';
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/providers/vice_activity_day_provider.dart';
import 'package:tracker/providers/vice_activity_history_provider.dart';
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
  late Map<String, Completer<ActivityCount>> countsByUser;
  late List<String> cancelled;
  // A count carries no id, so each user's count is told apart by its size.
  const Map<String, int> counts = {'from-a': 1, 'from-b': 2};

  setUp(() {
    users = StreamController<User?>();
    cancelled = <String>[];
    StreamController<T> controllerFor<T>(String uid) =>
        StreamController<T>(onCancel: () => cancelled.add(uid));
    vicesByUser = {'a': controllerFor('a'), 'b': controllerFor('b')};
    activitiesByUser = {'a': controllerFor('a'), 'b': controllerFor('b')};
    countsByUser = {'a': Completer(), 'b': Completer()};
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
        viceActivityGraphForUserProvider.overrideWith(
          (ref, key) => activitiesByUser[key.uid]!.stream,
        ),
        viceActivityHistoryForUserProvider.overrideWith(
          (ref, key) => activitiesByUser[key.uid]!.stream,
        ),
        viceActivityForUserProvider.overrideWith(
          (ref, key) => activitiesByUser[key.uid]!.stream.map(
            (List<ViceActivity> activities) => activities.first,
          ),
        ),
        viceActivityCountForUserProvider.overrideWith((ref, key) {
          ref.onDispose(() => cancelled.add(key.uid));
          return countsByUser[key.uid]!.future;
        }),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  final Map<String, ProviderListenable<AsyncValue<Object?>>> providers = {
    'vice list': viceListProvider,
    'unarchived vice list': unarchivedViceListProvider,
    'day activities': viceActivityDayProvider(day),
    'graph activities': viceActivityGraphProvider((
      viceID: 'coffee',
      start: day,
      end: day.add(const Duration(days: 1)),
    )),
    'history activities': viceActivityHistoryProvider((
      viceID: 'coffee',
      limit: 51,
    )),
    'single activity': viceActivityProvider('entry'),
    'activity count': viceActivityCountProvider('coffee'),
  };

  void emitFor(String uid, String name) {
    vicesByUser[uid]!.add([fakeVice(name)]);
    activitiesByUser[uid]!.add([fakeActivity(name, 1, day)]);
    countsByUser[uid]!.complete((
      count: counts[name]!,
      source: CountSource.server,
    ));
  }

  String? shownID(Object? item) => switch (item) {
    Vice(:final String id) => id,
    ViceActivity(:final String viceID) => viceID,
    (count: final int count, source: _) =>
      counts.entries
          .singleWhere((MapEntry<String, int> e) => e.value == count)
          .key,
    _ => null,
  };

  // What a value shows, by id: a list's items, or the one item.
  Iterable<String?>? shown(AsyncValue<Object?> value) => switch (value.value) {
    null => null,
    final List<Object> items => items.map(shownID),
    final Object item => [shownID(item)],
  };

  test('the unarchived vice list keeps a vice stored without the archived '
      'field and drops an archived one', () async {
    final ProviderContainer c = container();
    c.listen(unarchivedViceListProvider, (_, _) {});
    users.add(FakeUser('a'));
    await _settle();
    vicesByUser['a']!.add([
      Vice.fromJson(
        id: 'legacy',
        json: <String, dynamic>{'name': 'Legacy', 'unit': 'item'},
      ),
      Vice.fromJson(
        id: 'archived',
        json: <String, dynamic>{'name': 'Old', 'archived': true},
      ),
      fakeVice('current'),
    ]);
    await _settle();

    expect(c.read(unarchivedViceListProvider).value?.map(shownID), [
      'legacy',
      'current',
    ]);
  });

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
        final List<AsyncValue<Object?>> seen = [];
        c.listen(provider, (_, next) => seen.add(next));

        users.add(FakeUser('a'));
        await _settle();
        emitFor('a', 'from-a');
        await _settle();
        expect(shown(c.read(provider)), ['from-a']);

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
            for (final AsyncValue<Object?> value in seen.skip(afterA))
              ...?shown(value),
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
          expect(shown(c.read(provider)), ['from-a']);

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

      // Sign-out terminates Firestore, which silences every open listener; a
      // query kept open while no screen shows it would serve the same user
      // nothing after they signed back in.
      test('closes its query once nothing watches it', () async {
        final ProviderContainer c = container();
        final ProviderSubscription<AsyncValue<Object?>> watching = c.listen(
          provider,
          (_, _) {},
        );

        users.add(FakeUser('a'));
        await _settle();
        emitFor('a', 'from-a');
        await _settle();
        watching.close();
        await _settle();

        expect(cancelled, contains('a'));
      });
    });
  }
}
