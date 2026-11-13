import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/insights/photo_stays.dart';
import 'package:tracker/insights/photos_source.dart';
import 'package:tracker/insights/places.dart';
import 'package:tracker/providers/places_provider.dart';

// Photo times and coordinates stay on the device: ReportProviderErrors sends
// every provider failure to Crashlytics, so nothing here may fail or name a
// place. Each failure is a value instead.

/// Null where the app reads no photo library: everywhere but iOS.
final photosSourceProvider = Provider<PhotosSource?>(
  (ref) => defaultTargetPlatform == TargetPlatform.iOS
      ? ChannelPhotosSource()
      : null,
);

/// Null where there is no photo library to read or it could not answer.
final photosAccessProvider = FutureProvider.autoDispose<PhotosAccess?>((
  ref,
) async {
  final PhotosSource? source = ref.watch(photosSourceProvider);
  if (source == null) return null;
  try {
    return await source.access();
  } catch (_) {
    return null;
  }
});

/// How an import from the photo library ended.
sealed class PhotosImport {
  const PhotosImport();
}

/// Access was refused, or the library could not be read or the result kept.
class PhotosImportFailed extends PhotosImport {
  const PhotosImportFailed(this.access);

  /// Null when the library answered nothing.
  final PhotosAccess? access;
}

/// [places] places with photo-derived stays, from [photos] photos with a
/// location, the earliest stay on [since] (null when none).
class PhotosImported extends PhotosImport {
  const PhotosImported({
    required this.places,
    required this.photos,
    required this.since,
    required this.limited,
  });

  final int places;
  final int photos;
  final DateTime? since;

  /// Only the photos the person shared were readable.
  final bool limited;
}

/// Asks for the photo library where needed, reads when and where each photo
/// was taken, and replaces the photo-derived stays in the places file with
/// those found. Takes the container rather than a page's ref, which may be
/// disposed by the time it ends. Never throws.
Future<PhotosImport> importPlacesFromPhotos(
  ProviderContainer container, {
  void Function(int done, int total)? onProgress,
}) async {
  final PhotosSource? source = container.read(photosSourceProvider);
  if (source == null) return const PhotosImportFailed(null);
  try {
    PhotosAccess access = await source.access();
    if (access == PhotosAccess.notDetermined) {
      access = await source.requestAccess();
      container.invalidate(photosAccessProvider);
    }
    if (access != PhotosAccess.full && access != PhotosAccess.limited) {
      return PhotosImportFailed(access);
    }
    final List<PhotoPoint> points = await source.read(onProgress: onProgress);
    final List<PhotoRun> runs = await Isolate.run(() => photoRuns(points));
    final bool kept = await container
        .read(placesProvider.notifier)
        .update(
          (PlaceStore store) async =>
              store.withPhotoRuns(runs, photos: points.length),
        );
    if (!kept) return PhotosImportFailed(access);
    final PlaceStore store = container.read(placesProvider).store;
    return PhotosImported(
      places: store.places.where((p) => p.photoStays > 0).length,
      photos: points.length,
      since: store.photosSince,
      limited: access == PhotosAccess.limited,
    );
  } catch (_) {
    return const PhotosImportFailed(null);
  }
}

/// Removes every photo-derived stay, and the places only photos gave. False
/// when the result could not be kept.
Future<bool> removePlacesFromPhotos(ProviderContainer container) => container
    .read(placesProvider.notifier)
    .update((PlaceStore store) async => store.withoutPhotos());
