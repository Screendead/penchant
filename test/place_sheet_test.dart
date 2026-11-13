import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/design/app_theme.dart';
import 'package:tracker/formats.dart';
import 'package:tracker/insights/photos_source.dart';
import 'package:tracker/insights/places.dart';
import 'package:tracker/insights/places_source.dart';
import 'package:tracker/providers/photos_provider.dart';
import 'package:tracker/providers/places_provider.dart';
import 'package:tracker/widgets/place_sheet.dart';

import 'fake_places.dart';

const Place _place = Place(id: 3, latitude: 51.5, longitude: -0.1, visits: 4);

Future<List<String?>> _open(
  WidgetTester tester, {
  required FakePlaces places,
  required FakePhotos photos,
}) async {
  tester.view.physicalSize = const Size(800, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final List<String?> results = <String?>[];
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        placesSourceProvider.overrideWithValue(places),
        photosSourceProvider.overrideWithValue(photos),
      ],
      child: MaterialApp(
        theme: appTheme(Brightness.light),
        home: Builder(
          builder: (BuildContext context) => TextButton(
            onPressed: () async => results.add(
              await showPlaceSheet(
                context,
                place: _place,
                stays: <PlaceStay>[
                  PlaceStay(
                    3,
                    DateTime(2026, 3, 2, 9),
                    DateTime(2026, 3, 2, 17),
                  ),
                ],
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return results;
}

void main() {
  testWidgets('the map is asked for only on a tap, after saying it goes to '
      'Apple, and a failed one says so', (WidgetTester tester) async {
    final FakePlaces places = FakePlaces(PlacesAccess.always);
    await _open(
      tester,
      places: places,
      photos: FakePhotos(PhotosAccess.notDetermined),
    );

    expect(find.text(PlaceSheet.mapCaption), findsOneWidget);
    expect(find.text(PlaceSheet.showOnMap), findsOneWidget);
    expect(places.maps, 0);

    await tester.tap(find.text(PlaceSheet.showOnMap));
    await tester.pumpAndSettle();

    expect(places.maps, 1);
    expect(find.text(PlaceSheet.mapFailed), findsOneWidget);
  });

  testWidgets('a loaded map shows with its pin', (WidgetTester tester) async {
    final FakePlaces places = FakePlaces(PlacesAccess.always)
      ..map = onePixelPng;
    await _open(tester, places: places, photos: FakePhotos(PhotosAccess.full));

    await tester.tap(find.text(PlaceSheet.showOnMap));
    await tester.pumpAndSettle();

    expect(places.maps, 1);
    expect(find.bySemanticsLabel('Map of Place 3'), findsOneWidget);
    expect(find.text(PlaceSheet.mapFailed), findsNothing);
  });

  for (final PhotosAccess access in <PhotosAccess>[
    PhotosAccess.full,
    PhotosAccess.limited,
  ]) {
    testWidgets('with ${access.name} photo access the strip shows the '
        'photos taken there', (WidgetTester tester) async {
      final FakePhotos photos = FakePhotos(access, <PlacePhoto>[
        PlacePhoto(DateTime(2026, 5, 4, 12), onePixelPng),
        PlacePhoto(DateTime(2025, 8, 9, 12), onePixelPng),
      ]);
      await _open(
        tester,
        places: FakePlaces(PlacesAccess.always),
        photos: photos,
      );

      expect(photos.nears, 1);
      expect(photos.asked, 0);
      expect(
        find.bySemanticsLabel(PlaceSheet.photoLabel(DateTime(2026, 5, 4))),
        findsOneWidget,
      );
      expect(find.byType(Image), findsNWidgets(2));
    });
  }

  for (final PhotosAccess access in <PhotosAccess>[
    PhotosAccess.denied,
    PhotosAccess.notDetermined,
  ]) {
    testWidgets('with ${access.name} photo access nothing is read or asked', (
      WidgetTester tester,
    ) async {
      final FakePhotos photos = FakePhotos(access, <PlacePhoto>[
        PlacePhoto(DateTime(2026, 5, 4, 12), onePixelPng),
      ]);
      await _open(
        tester,
        places: FakePlaces(PlacesAccess.always),
        photos: photos,
      );

      expect(photos.nears, 0);
      expect(photos.asked, 0);
      expect(find.byType(Image), findsNothing);
      expect(find.text(PlaceSheet.photosLoading), findsNothing);
    });
  }

  testWidgets('no photos there shows no strip', (WidgetTester tester) async {
    final FakePhotos photos = FakePhotos(PhotosAccess.full);
    await _open(
      tester,
      places: FakePlaces(PlacesAccess.always),
      photos: photos,
    );

    expect(photos.nears, 1);
    expect(find.byType(Image), findsNothing);
    expect(find.text(PlaceSheet.photosLoading), findsNothing);
  });

  testWidgets('Save answers the name typed, Cancel nothing', (
    WidgetTester tester,
  ) async {
    final List<String?> results = await _open(
      tester,
      places: FakePlaces(PlacesAccess.always),
      photos: FakePhotos(PhotosAccess.denied),
    );
    expect(
      find.text('1 visit, on ${formatDate(DateTime(2026, 3, 2))}'),
      findsOneWidget,
    );
    await tester.enterText(find.byType(TextField), 'Office');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(results, <String?>['Office']);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(results, <String?>['Office', null]);
  });
}
