import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/crypto/sealed_files.dart';
import 'package:tracker/insights/places.dart';
import 'package:tracker/insights/places_source.dart';
import 'package:tracker/providers/device_files_provider.dart';

// Coordinates stay on the device: ReportProviderErrors sends every provider
// failure to Crashlytics, so nothing here may fail or name a place. Each
// failure is a value instead.

/// Null where the app reads no location: everywhere but iOS.
final placesSourceProvider = Provider<PlacesSource?>(
  (ref) => defaultTargetPlatform == TargetPlatform.iOS
      ? ChannelPlacesSource()
      : null,
);

/// Null where there is no location to read or Core Location could not
/// answer.
final placesAccessProvider = FutureProvider.autoDispose<PlacesAccess?>((
  ref,
) async {
  final PlacesSource? source = ref.watch(placesSourceProvider);
  if (source == null) return null;
  try {
    return await source.access();
  } catch (_) {
    return null;
  }
});

/// The sealed device file holding the places and stays.
const String placesFileName = 'places';

/// The person's places, kept up to date from Core Location's visits while
/// the app runs. [ready] is false until the sealed file has been read, or
/// there is nothing to read.
typedef PlacesState = ({bool ready, PlaceStore store});

const PlacesState _none = (ready: true, store: PlaceStore());

class PlacesSync extends Notifier<PlacesState> {
  // Takes, saves and acknowledges one batch of visits at a time.
  Future<void> _queue = Future<void>.value();
  SealedFiles? _files;
  PlacesSource? _source;

  @override
  PlacesState build() {
    final PlacesSource? source = ref.watch(placesSourceProvider);
    final SealedFiles? files = ref.watch(sealedFilesProvider);
    final PlacesAccess? access = ref.watch(placesAccessProvider).value;
    _source = source;
    _files = files;
    if (source == null || files == null) return _none;
    final bool allowed =
        access == PlacesAccess.always || access == PlacesAccess.whenInUse;
    final AppLifecycleListener lifecycle = AppLifecycleListener(
      onResume: drain,
    );
    final StreamSubscription<void> reported = source.reported.listen(
      (_) => drain(),
    );
    ref.onDispose(() {
      lifecycle.dispose();
      reported.cancel();
    });
    unawaited(_load(files, start: allowed));
    return (ready: false, store: const PlaceStore());
  }

  Future<void> _load(SealedFiles files, {required bool start}) =>
      _queue = _queue
          .then((_) async {
            final Uint8List? bytes = await files.read(placesFileName);
            if (!identical(files, _files)) return;
            final PlaceStore store =
                (bytes == null ? null : PlaceStore.decode(bytes)) ??
                const PlaceStore();
            state = (ready: true, store: store);
            if (start) {
              try {
                await _source?.start();
              } catch (_) {
                // Tried again on the next launch.
              }
              await _drain();
            }
          })
          .catchError((Object _) {
            if (identical(files, _files)) {
              state = (ready: true, store: state.store);
            }
          });

  /// Adds the visits Core Location reported since the last drain. Never
  /// throws.
  Future<void> drain() =>
      _queue = _queue.then((_) => _drain()).catchError((Object _) {});

  Future<void> _drain() async {
    final SealedFiles? files = _files;
    final PlacesSource? source = _source;
    if (files == null || source == null || !state.ready) return;
    final List<PlaceVisit> visits = await source.take();
    if (visits.isEmpty) return;
    final PlaceStore next = state.store.withVisits(visits);
    await files.write(placesFileName, next.encode());
    if (!identical(files, _files)) return;
    state = (ready: true, store: next);
    await source.ack(visits.length);
  }

  /// Names [placeId]; an empty [name] numbers it again. False when the name
  /// could not be kept.
  Future<bool> rename(int placeId, String name) async {
    final Completer<bool> done = Completer<bool>();
    _queue = _queue
        .then((_) async {
          final SealedFiles? files = _files;
          if (files == null || !state.ready) return done.complete(false);
          final PlaceStore next = state.store.renamed(placeId, name);
          await files.write(placesFileName, next.encode());
          if (identical(files, _files)) state = (ready: true, store: next);
          done.complete(true);
        })
        .catchError((Object _) {
          if (!done.isCompleted) done.complete(false);
        });
    return done.future;
  }
}

/// Built at launch by [MyApp], so visits reported while the app was closed
/// are kept as soon as the journal key loads.
final placesProvider = NotifierProvider<PlacesSync, PlacesState>(
  PlacesSync.new,
);

/// Shows the location prompts from the Insights screen: When In Use first,
/// then the upgrade to Always. Takes the container rather than a page's ref,
/// which may be disposed by the time it closes.
Future<PlacesAccess?> connectPlaces(ProviderContainer container) async {
  final PlacesSource? source = container.read(placesSourceProvider);
  if (source == null) return null;
  PlacesAccess? access;
  try {
    access = await source.requestAccess();
  } catch (_) {
    access = null;
  }
  container.invalidate(placesAccessProvider);
  return access;
}
