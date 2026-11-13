import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tracker/design/app_theme.dart';
import 'package:tracker/insights/health_source.dart';
import 'package:tracker/insights/insights_report.dart';
import 'package:tracker/insights/photo_stays.dart';
import 'package:tracker/insights/places.dart';
import 'package:tracker/insights/places_source.dart';
import 'package:tracker/insights_page.dart';
import 'package:tracker/providers/insights_provider.dart';
import 'package:tracker/providers/places_provider.dart';
import 'package:tracker/widgets/place_sheet.dart';

import 'fake_places.dart';
import 'insights_harness.dart';

class _KeptPlaces extends PlacesSync {
  _KeptPlaces(this._initial, this._renames);

  final PlaceStore _initial;
  final List<(int, String)> _renames;

  @override
  PlacesState build() => (ready: true, store: _initial);

  @override
  Future<bool> rename(int placeId, String name) async {
    _renames.add((placeId, name));
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
    final List<(int, String)> renames = <(int, String)>[];
    final _KeptPlaces kept = _KeptPlaces(
      const PlaceStore().withVisits(<PlaceVisit>[
        _visit(old, 0),
        _visit(old.add(const Duration(days: 1)), 0),
        _visit(old.add(const Duration(days: 2)), 0.02),
      ]),
      renames,
    );
    await _pump(tester, FakePlaces(PlacesAccess.always), kept: kept);

    expect(find.text(InsightsPage.placesEarly), findsNothing);
    expect(find.text('Place 1'), findsOneWidget);
    expect(find.text('2 visits'), findsOneWidget);

    await tester.tap(find.text('Place 2'));
    await tester.pumpAndSettle();
    expect(find.text(PlaceSheet.title), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Gym');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(renames, <(int, String)>[(2, 'Gym')]);
    expect(find.text('Gym'), findsOneWidget);
    expect(find.text('Place 2'), findsNothing);
  });

  testWidgets('the card lists every place a finding can name before places '
      'with more time from photos', (WidgetTester tester) async {
    final DateTime old = DateTime.now().subtract(const Duration(days: 60));
    final DateTime morning = DateTime(old.year, old.month, old.day, 10);
    final PlaceStore store = const PlaceStore()
        .withVisits(<PlaceVisit>[
          for (int i = 0; i < placeMaxPlaces; i++)
            _visit(morning.add(Duration(hours: i * 25)), i * 0.02),
        ])
        .withPhotoRuns(<PhotoRun>[
          PhotoRun(
            from: morning.subtract(const Duration(days: 10)),
            to: morning.subtract(const Duration(days: 9)),
            latitude: 1,
            longitude: 0,
            photos: 30,
          ),
        ], photos: 30);
    expect(store.places, hasLength(placeMaxPlaces + 1));
    await _pump(
      tester,
      FakePlaces(PlacesAccess.always),
      kept: _KeptPlaces(store, <(int, String)>[]),
    );

    for (final int id in judgedPlaces(
      store.stays,
      through: DateTime.now().subtract(const Duration(days: 1)),
    )) {
      expect(find.text('Place $id'), findsOneWidget);
    }
    expect(find.text('Place ${placeMaxPlaces + 1}'), findsOneWidget);
  });
}
