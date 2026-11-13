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
  bool _allowed = false;
  bool _started = false;

  @override
  PlacesState build() {
    final PlacesSource? source = _source = ref.watch(placesSourceProvider);
    // Where no location is read, the key and the files are never asked for.
    if (source == null) return _none;
    final SealedFiles? files = _files = ref.watch(sealedFilesProvider);
    _started = false;
    // Listened, not watched: the Insights page re-reads access on every
    // resume, and a rebuild would read the file again and hold Insights
    // back until it had.
    ref.listen<AsyncValue<PlacesAccess?>>(placesAccessProvider, (
      _,
      AsyncValue<PlacesAccess?> next,
    ) {
      final PlacesAccess? access = next.value;
      final bool was = _allowed;
      _allowed =
          access == PlacesAccess.always || access == PlacesAccess.whenInUse;
      if (_allowed && !was && _files != null) unawaited(_begin());
    }, fireImmediately: true);
    if (files == null) return _none;
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
    unawaited(_load(files));
    return (ready: false, store: const PlaceStore());
  }

  Future<void> _load(SealedFiles files) => _queue = _queue
      .then((_) async {
        final Uint8List? bytes = await files.read(placesFileName);
        if (!identical(files, _files)) return;
        final PlaceStore store =
            (bytes == null ? null : PlaceStore.decode(bytes)) ??
            const PlaceStore();
        state = (ready: true, store: store);
        if (_allowed) await _startAndDrain();
      })
      .catchError((Object _) {
        if (identical(files, _files)) {
          state = (ready: true, store: state.store);
        }
      });

  // Access granted after the file was read; before, the load starts them.
  Future<void> _begin() => _queue = _queue
      .then((_) async {
        if (state.ready) await _startAndDrain();
      })
      .catchError((Object _) {});

  Future<void> _startAndDrain() async {
    if (!_started) {
      _started = true;
      try {
        await _source?.start();
      } catch (_) {
        // Tried again on the next launch.
      }
    }
    await _drain();
  }

  /// Adds the visits Core Location reported since the last drain. Never
  /// throws.
  Future<void> drain() =>
      _queue = _queue.then((_) => _drain()).catchError((Object _) {});

  Future<void> _drain() async {
    final SealedFiles? files = _files;
    final PlacesSource? source = _source;
    if (files == null || source == null || !_allowed || !state.ready) return;
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

  /// Replaces the store with [change] of it, in turn with every other write.
  /// False when the result could not be kept.
  Future<bool> update(Future<PlaceStore> Function(PlaceStore) change) {
    final Completer<bool> done = Completer<bool>();
    _queue = _queue
        .then((_) async {
          final SealedFiles? files = _files;
          if (files == null || !state.ready) return done.complete(false);
          final PlaceStore next = await change(state.store);
          await files.write(placesFileName, next.encode());
          if (!identical(files, _files)) return done.complete(false);
          state = (ready: true, store: next);
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
