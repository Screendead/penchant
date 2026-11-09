import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/category.dart';
import 'package:tracker/data/unit.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/homepage.dart';
import 'package:tracker/main.dart';
import 'package:tracker/onboarding/onboarding.dart';
import 'package:tracker/onboarding/presets.dart';
import 'package:tracker/providers/offline_provider.dart';
import 'package:tracker/providers/tracker_writes_provider.dart';
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/providers/vice_activity_day_provider.dart';
import 'package:tracker/providers/vice_list_provider.dart';
import 'package:tracker/vice_form.dart';
import 'package:tracker/vice_tracker.dart';

import 'fake_writes.dart';
import 'fakes.dart';

class _KeyLoaded extends Notifier<bool> {
  @override
  bool build() => false;

  void load() => state = true;
}

final _keyLoaded = NotifierProvider<_KeyLoaded, bool>(_KeyLoaded.new);

void main() {
  late StreamController<List<Vice>> habits;
  late FakeTrackerWrites writes;

  setUp(() {
    habits = StreamController<List<Vice>>.broadcast();
    writes = FakeTrackerWrites();
  });
  tearDown(() => habits.close());

  final StreamProvider<List<Vice>> liveHabits = StreamProvider<List<Vice>>(
    (ref) => habits.stream,
  );

  // The habit list follows [habits]; nothing is emitted until a test adds.
  Future<void> pumpHome(
    WidgetTester tester, {
    List<Vice>? initial,
    Stream<bool>? offline,
    Override? writesOverride,
  }) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          userProvider.overrideWith((ref) => Stream.value(FakeUser(ownerID))),
          viceListProvider.overrideWith((ref) => ref.watch(liveHabits)),
          if (offline == null)
            offlineProvider.overrideWithValue(const AsyncData(false))
          else
            offlineProvider.overrideWith((ref) => offline),
          writesOverride ?? trackerWritesProvider.overrideWithValue(writes),
          memoryJournal(),
          viceActivityDayProvider.overrideWith(
            (ref, DateTime day) => const AsyncData(<ViceActivity>[]),
          ),
        ],
        child: const MaterialApp(
          home: Homepage(),
          onGenerateRoute: generateRoute,
        ),
      ),
    );
    await tester.pump();
    if (initial != null) {
      habits.add(initial);
      await tester.pumpAndSettle();
    }
  }

  Vice created(Write write) => Vice(
    id: write.id,
    name: write.fields['name']! as String,
    unit: write.fields['unit']! as Unit,
    ownerID: ownerID,
    createdAt: Timestamp.now(),
    archived: false,
  );

  testWidgets('an account with no habits sees the onboarding', (
    WidgetTester tester,
  ) async {
    await pumpHome(tester, initial: const <Vice>[]);

    expect(find.byType(Onboarding), findsOneWidget);
    expect(find.text(OnboardingCopy.introHeadline), findsOneWidget);
  });

  testWidgets('nothing is decided while the habits load', (
    WidgetTester tester,
  ) async {
    await pumpHome(tester);

    expect(find.byType(Onboarding), findsNothing);
    expect(find.text(OnboardingCopy.introHeadline), findsNothing);
  });

  testWidgets('an empty list waits for the server before deciding', (
    WidgetTester tester,
  ) async {
    final StreamController<bool> offline = StreamController<bool>();
    addTearDown(offline.close);
    await pumpHome(tester, offline: offline.stream);

    // An empty cache, as on a reinstall with the session kept: no server
    // answer yet, then offline.
    habits.add(const <Vice>[]);
    await tester.pump();
    expect(find.byType(Onboarding), findsNothing);
    offline.add(true);
    await tester.pump();
    expect(find.byType(Onboarding), findsNothing);
    expect(find.byType(ViceTracker), findsOneWidget);

    offline.add(false);
    await tester.pump();
    expect(find.byType(Onboarding), findsOneWidget);
  });

  testWidgets('an existing account never sees it', (WidgetTester tester) async {
    await pumpHome(tester, initial: <Vice>[fakeVice('coffee')]);

    expect(find.byType(Onboarding), findsNothing);
    expect(find.byType(ViceTracker), findsOneWidget);
  });

  testWidgets('nor does one whose habits are all archived', (
    WidgetTester tester,
  ) async {
    final Vice archived = fakeVice('tea');
    await pumpHome(
      tester,
      initial: <Vice>[
        Vice(
          id: archived.id,
          name: archived.name,
          unit: archived.unit,
          ownerID: ownerID,
          createdAt: archived.createdAt,
          archived: true,
        ),
      ],
    );

    expect(find.byType(Onboarding), findsNothing);
  });

  testWidgets('picking two presets creates two habits with their units', (
    WidgetTester tester,
  ) async {
    await pumpHome(tester, initial: const <Vice>[]);
    await tester.tap(find.text(OnboardingCopy.start));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Coffee'));
    await tester.tap(find.text('Vape'));
    await tester.pump();
    expect(find.text(OnboardingCopy.continueWith(2)), findsOneWidget);

    // Twice before a frame: the second tap must not create them again.
    await tester.tap(find.text(OnboardingCopy.continueWith(2)));
    await tester.tap(find.text(OnboardingCopy.continueWith(2)));
    await tester.pumpAndSettle();

    expect(writes.writes, const <Write>[
      Write('addVice', 'vice-1', <String, Object?>{
        'ownerID': ownerID,
        'name': 'Coffee',
        'unit': Unit.drink,
        'category': ViceCategory.caffeine,
      }),
      Write('addVice', 'vice-2', <String, Object?>{
        'ownerID': ownerID,
        'name': 'Vape',
        'unit': Unit.puff,
        'category': ViceCategory.nicotine,
      }),
    ]);
    expect(find.text(OnboardingCopy.disclaimer), findsOneWidget);
  });

  testWidgets('without the journal key Continue waits, keeping the picks, '
      'and creates them once the key loads', (WidgetTester tester) async {
    final FakeTrackerWrites keyless = FakeTrackerWrites()..canCreate = false;
    await pumpHome(
      tester,
      initial: const <Vice>[],
      writesOverride: trackerWritesProvider.overrideWith(
        (ref) => ref.watch(_keyLoaded) ? writes : keyless,
      ),
    );
    await tester.tap(find.text(OnboardingCopy.start));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Coffee'));
    await tester.pump();

    final Finder waiting = find.widgetWithText(
      FilledButton,
      OnboardingCopy.waitingForKey,
    );
    expect(waiting, findsOneWidget);
    expect(tester.widget<FilledButton>(waiting).onPressed, isNull);

    ProviderScope.containerOf(
      tester.element(find.byType(Homepage)),
    ).read(_keyLoaded.notifier).load();
    await tester.pump();
    await tester.tap(find.text(OnboardingCopy.continueWith(1)));
    await tester.pumpAndSettle();

    expect(keyless.writes, isEmpty);
    expect(writes.writes.map((Write w) => w.fields['name']), <String>[
      'Coffee',
    ]);
    expect(find.text(OnboardingCopy.disclaimer), findsOneWidget);
  });

  testWidgets('the flow stays up once its habits arrive, and ends with a log', (
    WidgetTester tester,
  ) async {
    await pumpHome(tester, initial: const <Vice>[]);
    await tester.tap(find.text(OnboardingCopy.start));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Coffee'));
    await tester.pump();
    await tester.tap(find.text(OnboardingCopy.continueWith(1)));
    await tester.pumpAndSettle();

    // The new habit reaches the list from the cache before the server says.
    habits.add(<Vice>[created(writes.writes.single)]);
    await tester.pumpAndSettle();
    expect(find.text(OnboardingCopy.disclaimer), findsOneWidget);

    await tester.tap(find.text(OnboardingCopy.acknowledge));
    await tester.pumpAndSettle();
    expect(find.text(OnboardingCopy.firstLogTitle), findsOneWidget);

    await tester.tap(find.byTooltip('More Coffee'));
    await tester.pump();
    expect(find.text(Unit.drink.label(2)), findsOneWidget);
    await tester.tap(find.byKey(Onboarding.logKey('Coffee')));
    await tester.pumpAndSettle();

    final Write logged = writes.writes.last;
    expect(logged.op, 'recordActivity');
    expect(logged.fields['viceID'], writes.writes.first.id);
    expect(logged.fields['quantity'], 2);
    expect(find.text(OnboardingCopy.logged), findsOneWidget);

    await tester.tap(find.text(OnboardingCopy.toToday));
    await tester.pumpAndSettle();
    expect(find.byType(Onboarding), findsNothing);
    expect(find.byType(ViceTracker), findsOneWidget);
  });

  testWidgets('Skip shows the disclaimer, then the empty Today', (
    WidgetTester tester,
  ) async {
    await pumpHome(tester, initial: const <Vice>[]);
    await tester.tap(find.byKey(Onboarding.skipKey));
    await tester.pumpAndSettle();
    expect(find.text(OnboardingCopy.disclaimer), findsOneWidget);

    await tester.tap(find.text(OnboardingCopy.acknowledge));
    await tester.pumpAndSettle();

    expect(find.byType(Onboarding), findsNothing);
    expect(find.text(ViceTracker.noHabits), findsOneWidget);
    expect(writes.writes, isEmpty);
  });

  testWidgets('"Something else" opens the add-habit form', (
    WidgetTester tester,
  ) async {
    await pumpHome(tester, initial: const <Vice>[]);
    await tester.tap(find.text(OnboardingCopy.start));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text(OnboardingCopy.somethingElse));
    await tester.pumpAndSettle();
    await tester.tap(find.text(OnboardingCopy.somethingElse));
    await tester.pumpAndSettle();

    expect(find.byType(ViceForm), findsOneWidget);
  });

  test('every preset has a unique name of 1 to 60', () {
    expect(
      habitPresets.map((HabitPreset p) => p.name).toSet(),
      hasLength(habitPresets.length),
    );
    for (final HabitPreset p in habitPresets) {
      expect(p.name.length, inInclusiveRange(1, 60));
    }
  });
}
