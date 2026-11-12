import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tracker/design/app_theme.dart';
import 'package:tracker/insights/health_source.dart';
import 'package:tracker/insights/insights_report.dart';
import 'package:tracker/insights/places.dart';
import 'package:tracker/insights/places_source.dart';
import 'package:tracker/insights_page.dart';
import 'package:tracker/providers/insights_provider.dart';
import 'package:tracker/providers/places_provider.dart';

import 'fake_places.dart';
import 'insights_harness.dart';

class _KeptPlaces extends PlacesSync {
  _KeptPlaces(this.store);

  PlaceStore store;
  final List<(int, String)> renames = <(int, String)>[];

  @override
  PlacesState build() => (ready: true, store: store);

  @override
  Future<bool> rename(int placeId, String name) async {
    renames.add((placeId, name));
    state = (ready: true, store: state.store.renamed(placeId, name));
    return true;
  }
}

Future<void> _pump(
  WidgetTester tester,
  FakePlaces places, {
  _KeptPlaces? kept,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    healthConnectedKey: true,
  });
  tester.view.physicalSize = const Size(800, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        ...insightsOverrides(
          health: FakeHealthSource(
            read: HealthValues(insightsJournal().health),
          ),
          runner: (InsightsInput input) async => computeInsights(input),
        ),
        placesSourceProvider.overrideWithValue(places),
        if (kept != null) placesProvider.overrideWith(() => kept),
      ],
      child: MaterialApp(
        theme: appTheme(Brightness.light),
        home: const InsightsPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

PlaceVisit _visit(DateTime arrival, double lat) => PlaceVisit(
  arrival: arrival,
  departure: arrival.add(const Duration(hours: 3)),
  latitude: lat,
  longitude: 0,
  accuracy: 30,
);

void main() {
  testWidgets('location is asked for only on a tap, and findings are said '
      'to be weeks away', (WidgetTester tester) async {
    final FakePlaces places = FakePlaces(PlacesAccess.notDetermined);
    await _pump(tester, places);

    expect(find.text(InsightsPage.placesLabel), findsOneWidget);
    expect(places.asked, 0);

    await tester.tap(find.text(InsightsPage.placesLabel));
    await tester.pumpAndSettle();

    expect(places.asked, 1);
    expect(find.text(InsightsPage.placesLabel), findsNothing);
    expect(find.text(InsightsPage.placesEarly), findsOneWidget);
  });

  testWidgets('refused or While Using says where to change it', (
    WidgetTester tester,
  ) async {
    await _pump(tester, FakePlaces(PlacesAccess.denied));
    expect(find.text(InsightsPage.placesOffBody), findsOneWidget);

    await _pump(tester, FakePlaces(PlacesAccess.whenInUse));
    expect(find.text(InsightsPage.placesWhileUsingBody), findsOneWidget);
  });

  testWidgets('a place is numbered until named on the card', (
    WidgetTester tester,
  ) async {
    final DateTime old = DateTime.now().subtract(const Duration(days: 60));
    final _KeptPlaces kept = _KeptPlaces(
      const PlaceStore().withVisits(<PlaceVisit>[
        _visit(old, 0),
        _visit(old.add(const Duration(days: 1)), 0),
        _visit(old.add(const Duration(days: 2)), 0.02),
      ]),
    );
    await _pump(tester, FakePlaces(PlacesAccess.always), kept: kept);

    expect(find.text(InsightsPage.placesEarly), findsNothing);
    expect(find.text('Place 1'), findsOneWidget);
    expect(find.text('2 visits'), findsOneWidget);

    await tester.tap(find.text('Place 2'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Gym');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(kept.renames, <(int, String)>[(2, 'Gym')]);
    expect(find.text('Gym'), findsOneWidget);
    expect(find.text('Place 2'), findsNothing);
  });
}
