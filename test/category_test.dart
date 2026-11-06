import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/category.dart';
import 'package:tracker/data/unit.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/providers/tracker_writes_provider.dart';
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/providers/vice_list_provider.dart';
import 'package:tracker/writes/category_migration.dart';

import 'fake_writes.dart';
import 'fakes.dart';

Vice _vice(String id, String name, {bool stored = false}) => Vice(
  id: id,
  name: name,
  unit: Unit.item,
  ownerID: ownerID,
  createdAt: Timestamp.fromMillisecondsSinceEpoch(0),
  archived: false,
  category: stored ? ViceCategory.food : ViceCategory.fallback,
  categoryStored: stored,
);

void main() {
  group('guessCategory', () {
    test('maps every starter preset and seed name', () {
      const Map<String, ViceCategory> expected = <String, ViceCategory>{
        'Alcohol': ViceCategory.alcohol,
        'Booze': ViceCategory.alcohol,
        'Coffee': ViceCategory.caffeine,
        'Energy drinks': ViceCategory.caffeine,
        'Cigarettes': ViceCategory.nicotine,
        'Vape': ViceCategory.nicotine,
        'Nicotine': ViceCategory.nicotine,
        'Cannabis': ViceCategory.cannabis,
        'Marijuana': ViceCategory.cannabis,
        'Sweets': ViceCategory.food,
        'Junk Food': ViceCategory.food,
        'Takeaway': ViceCategory.food,
        'Gambling': ViceCategory.gambling,
        'Social media': ViceCategory.other,
        'Video Games': ViceCategory.other,
        '': ViceCategory.other,
      };
      expected.forEach((String name, ViceCategory category) {
        expect(guessCategory(name), category, reason: name);
      });
    });

    test('matches at the start of a word only', () {
      expect(guessCategory('Green tea'), ViceCategory.caffeine);
      expect(guessCategory('Steak'), ViceCategory.other);
    });
  });

  group('Vice.fromJson', () {
    Vice parse(Map<String, dynamic> json) => Vice.fromJson(id: 'v', json: json);

    test('reads a stored category', () {
      final Vice vice = parse(<String, dynamic>{'category': 'nicotine'});
      expect(vice.category, ViceCategory.nicotine);
      expect(vice.categoryStored, isTrue);
    });

    test('defaults a missing or mistyped category to other, as not stored', () {
      for (final Object? value in <Object?>[null, 3]) {
        final Vice vice = parse(<String, dynamic>{'category': ?value});
        expect(vice.category, ViceCategory.other);
        expect(vice.categoryStored, isFalse);
      }
    });

    test('keeps a name a later version wrote as stored', () {
      final Vice vice = parse(<String, dynamic>{'category': 'sugar'});
      expect(vice.category, ViceCategory.other);
      expect(vice.categoryStored, isTrue);
    });
  });

  group('the category migration', () {
    late FakeTrackerWrites writes;
    late StreamController<User?> users;
    late ValueNotifier<AsyncValue<List<Vice>>> vices;

    setUp(() {
      writes = FakeTrackerWrites();
      users = StreamController<User?>.broadcast();
      vices = ValueNotifier<AsyncValue<List<Vice>>>(
        const AsyncLoading<List<Vice>>(),
      );
    });

    tearDown(() async {
      await users.close();
      vices.dispose();
    });

    Future<void> pump(WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            trackerWritesProvider.overrideWithValue(writes),
            userProvider.overrideWith((ref) => users.stream),
            viceListProvider.overrideWith((ref) {
              void changed() => ref.invalidateSelf();
              vices.addListener(changed);
              ref.onDispose(() => vices.removeListener(changed));
              return vices.value;
            }),
          ],
          child: Consumer(
            builder: (BuildContext context, WidgetRef ref, _) {
              ref.watch(categoryMigrationProvider);
              return const SizedBox();
            },
          ),
        ),
      );
      users.add(FakeUser(ownerID));
      await tester.pump();
    }

    Future<void> show(WidgetTester tester, List<Vice> list) async {
      vices.value = AsyncData<List<Vice>>(list);
      await tester.pump();
    }

    testWidgets('writes a guessed category to each vice without one, and '
        'leaves the rest', (WidgetTester tester) async {
      await pump(tester);
      await show(tester, <Vice>[
        _vice('beer', 'Beer'),
        _vice('crisps', 'Crisps', stored: true),
        _vice('games', 'Video Games'),
      ]);

      expect(writes.writes, <Write>[
        const Write('fillViceCategory', 'beer', <String, Object?>{
          'category': ViceCategory.alcohol,
        }),
        const Write('fillViceCategory', 'games', <String, Object?>{
          'category': ViceCategory.other,
        }),
      ]);
    });

    testWidgets('tries each vice once at a time, though later snapshots '
        'still lack the field', (WidgetTester tester) async {
      // The transaction has not answered yet.
      writes.respond = (_) => Completer<void>().future;
      await pump(tester);
      await show(tester, <Vice>[_vice('beer', 'Beer')]);
      await show(tester, <Vice>[_vice('beer', 'Beer'), _vice('vape', 'Vape')]);
      await show(tester, <Vice>[_vice('beer', 'Beer'), _vice('vape', 'Vape')]);

      expect(writes.writes.map((Write w) => w.id), <String>['beer', 'vape']);
    });

    testWidgets('tries again on a later snapshot after failing offline', (
      WidgetTester tester,
    ) async {
      int attempts = 0;
      writes.respond = (_) => ++attempts == 1
          ? Future<void>.error(
              FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'),
            )
          : Future<void>.value();
      writes.server['vices/beer'] = <String, Object?>{};
      await pump(tester);
      await show(tester, <Vice>[_vice('beer', 'Beer')]);
      await tester.pump();
      await show(tester, <Vice>[_vice('beer', 'Beer')]);
      await tester.pump();

      expect(writes.writes, hasLength(2));
      expect(writes.server['vices/beer'], <String, Object?>{
        'category': 'alcohol',
      });
      expect(tester.takeException(), isNull);
    });

    testWidgets('writes nothing once every vice has a category', (
      WidgetTester tester,
    ) async {
      await pump(tester);
      await show(tester, <Vice>[_vice('crisps', 'Crisps', stored: true)]);

      expect(writes.writes, isEmpty);
    });

    testWidgets('a refused write is not retried and throws nothing', (
      WidgetTester tester,
    ) async {
      writes.respond = (_) => Future<void>.error(
        FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'),
      );
      await pump(tester);
      await show(tester, <Vice>[_vice('beer', 'Beer')]);
      await show(tester, <Vice>[_vice('beer', 'Beer')]);

      expect(writes.writes, hasLength(1));
      expect(tester.takeException(), isNull);
    });
  });
}
