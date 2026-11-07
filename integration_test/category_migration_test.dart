import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/category.dart';
import 'package:tracker/data/unit.dart';
import 'package:tracker/firebase_init.dart';
import 'package:tracker/homepage.dart';
import 'package:tracker/main.dart';
import 'package:tracker/providers/tracker_writes_provider.dart';
import 'package:tracker/writes/tracker_writes.dart';

import 'support.dart';

// The real writes, recording each fill the migrator asks for. Past
// [succeeding] fills it fails the rest, as a launch cut short mid-way leaves
// them.
class _MigrationWrites extends TrackerWrites {
  _MigrationWrites({this.succeeding}) : super(FirebaseFirestore.instance);

  final int? succeeding;
  final List<String> asked = <String>[];
  final List<Future<bool>> sent = <Future<bool>>[];

  @override
  Future<bool> fillViceCategory(String viceID, ViceCategory category) {
    asked.add(viceID);
    if (succeeding != null && sent.length >= succeeding!) {
      return Future<bool>.error(
        FirebaseException(
          plugin: 'cloud_firestore',
          code: 'aborted',
          message: 'launch cut short',
        ),
      );
    }
    final Future<bool> write = super.fillViceCategory(viceID, category);
    sent.add(write);
    return write;
  }
}

class _Seed {
  const _Seed(
    this.id,
    this.name,
    this.unit, {
    this.archived,
    this.category,
    required this.expected,
    this.newest = false,
  });

  final String id;
  final String name;
  final Unit unit;
  // Null leaves the field out, as vices written before 2024-08-14 do.
  final bool? archived;
  final String? category;
  final String expected;
  // Sorts first on the Habits page, which the test opens it from.
  final bool newest;

  DateTime get createdAt =>
      newest ? _createdAt.add(const Duration(days: 1)) : _createdAt;

  bool get legacy => category == null;
}

final List<_Seed> _seeds = <_Seed>[
  const _Seed('booze', 'Booze', Unit.drink, expected: 'alcohol', newest: true),
  const _Seed(
    'coffee',
    'Morning coffee',
    Unit.item,
    archived: false,
    expected: 'caffeine',
  ),
  const _Seed('cigs', 'Cigarettes', Unit.puff, expected: 'nicotine'),
  // At the rules' limit, and past it as only a legacy name can be.
  _Seed(
    'sixty',
    'Vape ${'x' * 55}',
    Unit.time,
    archived: false,
    expected: 'nicotine',
  ),
  _Seed('eighty', 'Weed ${'y' * 75}', Unit.minute, expected: 'cannabis'),
  const _Seed('choc', 'Chocolate', Unit.hour, archived: true, expected: 'food'),
  const _Seed('bets', 'Online betting', Unit.item, expected: 'gambling'),
  const _Seed('reading', 'Reading', Unit.time, expected: 'other'),
  // Stored categories stay, even one the name would not guess or one this
  // version does not know.
  const _Seed(
    'beer-money',
    'Beer money',
    Unit.item,
    archived: false,
    category: 'gambling',
    expected: 'gambling',
  ),
  const _Seed(
    'screen',
    'Screen time',
    Unit.hour,
    archived: false,
    category: 'screen',
    expected: 'screen',
  ),
  for (int i = 1; i <= 12; i++)
    _Seed(
      'bulk-$i',
      'Habit $i',
      Unit.values[i % Unit.values.length],
      archived: i.isEven ? false : null,
      expected: 'other',
    ),
];

final DateTime _createdAt = DateTime.utc(2024, 3, 1, 12);

Map<String, Object> _fields(_Seed seed, String uid) => <String, Object>{
  'name': <String, Object>{'stringValue': seed.name},
  'unit': <String, Object>{'stringValue': seed.unit.name},
  'ownerID': <String, Object>{'stringValue': uid},
  'createdAt': <String, Object>{
    'timestampValue': seed.createdAt.toIso8601String(),
  },
  if (seed.archived != null)
    'archived': <String, Object>{'booleanValue': seed.archived!},
  if (seed.category != null)
    'category': <String, Object>{'stringValue': seed.category!},
};

Future<Map<String, Map<String, dynamic>>> _storedVices(String uid) async {
  final QuerySnapshot<Map<String, dynamic>> vices = await FirebaseFirestore
      .instance
      .collection('vices')
      .where('ownerID', isEqualTo: uid)
      .get(const GetOptions(source: Source.server));
  return <String, Map<String, dynamic>>{
    for (final QueryDocumentSnapshot<Map<String, dynamic>> doc in vices.docs)
      doc.id: doc.data(),
  };
}

int _filled(Map<String, Map<String, dynamic>> stored) => _seeds
    .where((_Seed s) => s.legacy && stored[s.id]?['category'] != null)
    .length;

// A fresh ProviderScope is a fresh migrator, as a relaunch gives; the
// signed-in user carries over.
Future<void> _launch(WidgetTester tester, _MigrationWrites writes) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [trackerWritesProvider.overrideWithValue(writes)],
      child: const MyApp(),
    ),
  );
}

void main() {
  ensureE2EBinding();

  setUpAll(() async {
    requireEmulators();
    await initializeFirebase();
    await clearEmulators();
  });

  testWidgets('a launch cut short leaves legacy vices half filled, and the '
      'next fills the rest once each, writing nothing but category', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: MyApp()));
    await register(tester, 'e2e-category@example.com');
    final String uid = FirebaseAuth.instance.currentUser!.uid;
    // No migrator listens while the legacy data goes in.
    await tester.pumpWidget(const SizedBox());
    for (final _Seed seed in _seeds) {
      await createBypassingRules('vices', seed.id, _fields(seed, uid));
    }
    for (int i = 0; i < 3; i++) {
      await createBypassingRules('activities', 'booze-$i', <String, Object>{
        'viceID': <String, Object>{'stringValue': 'booze'},
        'quantity': <String, Object>{'integerValue': '${i + 1}'},
        'ownerID': <String, Object>{'stringValue': uid},
        'createdAt': <String, Object>{
          'timestampValue': _createdAt.toIso8601String(),
        },
      });
    }
    final Set<String> legacy = <String>{
      for (final _Seed s in _seeds)
        if (s.legacy) s.id,
    };

    const int succeeding = 5;
    final _MigrationWrites first = _MigrationWrites(succeeding: succeeding);
    await _launch(tester, first);
    await pumpUntilTrue(
      tester,
      () => first.asked.length >= legacy.length,
      () =>
          'the first launch to ask for ${legacy.length} fills, '
          'asked ${first.asked}',
    );
    await Future.wait(first.sent);
    // Long enough for a stray retry to show.
    await pumpFor(tester, const Duration(seconds: 2));
    expect(first.asked, hasLength(legacy.length));
    expect(first.asked.toSet(), legacy);
    expect(_filled(await _storedVices(uid)), succeeding);

    final _MigrationWrites second = _MigrationWrites();
    await _launch(tester, second);
    Map<String, Map<String, dynamic>> stored = <String, Map<String, dynamic>>{};
    Future<void>? reading;
    await pumpUntilTrue(tester, () {
      reading ??= _storedVices(uid).then((Map<String, Map<String, dynamic>> v) {
        stored = v;
        reading = null;
      });
      return _filled(stored) == legacy.length;
    }, () => 'every legacy vice to hold a category, saw $stored');
    await Future.wait(second.sent);
    await pumpFor(tester, const Duration(seconds: 2));
    expect(
      second.asked,
      unorderedEquals(first.asked.skip(succeeding)),
      reason: 'the second launch fills only what the first left, once each',
    );

    expect(stored.keys.toSet(), <String>{for (final _Seed s in _seeds) s.id});
    for (final _Seed seed in _seeds) {
      final Map<String, dynamic> data = stored[seed.id]!;
      expect(data['category'], seed.expected, reason: seed.id);
      expect(data.keys.toSet(), <String>{
        'name',
        'unit',
        'ownerID',
        'createdAt',
        'category',
        if (seed.archived != null) 'archived',
      }, reason: seed.id);
      expect(data['name'], seed.name, reason: seed.id);
      expect(data['unit'], seed.unit.name, reason: seed.id);
      expect(data['ownerID'], uid, reason: seed.id);
      expect(
        (data['createdAt'] as Timestamp).toDate().toUtc(),
        seed.createdAt,
        reason: seed.id,
      );
      expect(data['archived'], seed.archived, reason: seed.id);
    }
    final QuerySnapshot<Map<String, dynamic>> activities =
        await FirebaseFirestore.instance
            .collection('activities')
            .where('ownerID', isEqualTo: uid)
            .get(const GetOptions(source: Source.server));
    expect(
      activities.docs.map((QueryDocumentSnapshot<Object?> d) => d.id).toSet(),
      <String>{'booze-0', 'booze-1', 'booze-2'},
    );

    await openFromMenu(tester, Homepage.habitsItem);
    await scrollIntoView(tester, find.text('Booze'));
    await tap(tester, find.text('Booze'));
    await pumpUntilRouteSettled(tester, historyTitle('Booze'));
    await tap(tester, find.byTooltip('Edit habit'));
    await pumpUntilRouteSettled(tester, find.text('Edit Habit'));
    expect(find.text(ViceCategory.alcohol.label), findsOneWidget);
  });
}
