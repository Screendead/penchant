import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/design/dial_theme.dart';
import 'package:tracker/design/tokens.dart';
import 'package:tracker/formats.dart';
import 'package:tracker/insights/photos_source.dart';
import 'package:tracker/insights/place_times.dart';
import 'package:tracker/insights/places.dart';
import 'package:tracker/insights/places_source.dart';
import 'package:tracker/providers/photos_provider.dart';
import 'package:tracker/providers/places_provider.dart';

// The place's coordinates and photos stay on the device unless the person
// taps Show on map, which sends the location to Apple to draw it. Nothing
// here is written to disk.

/// Opens the sheet that shows [place] and names it. Answers the name typed,
/// or null when cancelled.
Future<String?> showPlaceSheet(
  BuildContext context, {
  required Place place,
  required List<PlaceStay> stays,
}) => showModalBottomSheet<String>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) => PlaceSheet(place: place, stays: stays),
);

class PlaceSheet extends ConsumerStatefulWidget {
  const PlaceSheet({super.key, required this.place, required this.stays});

  final Place place;
  final List<PlaceStay> stays;

  static const String title = 'Name this place';

  /// The most stays whose photos are looked for, spread across time.
  static const int photoSpans = 60;
  static const String showOnMap = 'Show on map';
  static const String mapCaption =
      'Shows this place on Apple Maps. Its location is sent to Apple to draw '
      'the map.';
  static const String mapFailed = 'The map couldn’t be loaded.';
  static const String photosLoading = 'Looking for photos taken here';

  /// Across the map, in metres.
  static const double mapSpan = 600;
  static const int photoLimit = 12;
  static const int photoPixels = 240;

  static String photoLabel(DateTime at) => 'Photo taken ${formatDate(at)}';

  @override
  ConsumerState<PlaceSheet> createState() => _PlaceSheetState();
}

sealed class _MapState {
  const _MapState();
}

class _MapIdle extends _MapState {
  const _MapIdle();
}

class _MapLoading extends _MapState {
  const _MapLoading();
}

class _MapShown extends _MapState {
  const _MapShown(this.png);

  final Uint8List png;
}

class _MapFailed extends _MapState {
  const _MapFailed();
}

class _PlaceSheetState extends ConsumerState<PlaceSheet> {
  late final TextEditingController _name = TextEditingController(
    text: widget.place.name ?? '',
  );

  /// False until photo access is known to be granted; then null while the
  /// thumbnails load.
  bool _photosAllowed = false;
  List<PlacePhoto>? _photos;
  _MapState _map = const _MapIdle();

  @override
  void initState() {
    super.initState();
    _loadPhotos();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  // Asks only whether access was already given: this sheet never prompts.
  Future<void> _loadPhotos() async {
    final PhotosSource? source = ref.read(photosSourceProvider);
    if (source == null) return;
    PhotosAccess access;
    try {
      access = await source.access();
    } catch (_) {
      return;
    }
    if (access != PhotosAccess.full && access != PhotosAccess.limited) return;
    if (!mounted) return;
    setState(() => _photosAllowed = true);
    final List<PlacePhoto> photos = await source.near(
      latitude: widget.place.latitude,
      longitude: widget.place.longitude,
      radius: placeRadiusMeters,
      during: _stays(),
      limit: PlaceSheet.photoLimit,
      pixels: PlaceSheet.photoPixels,
    );
    if (mounted) setState(() => _photos = photos);
  }

  // The library is asked only for photos taken during the place's stays:
  // reading every photo's location took seconds on a large library.
  List<(DateTime, DateTime)> _stays() {
    final DateTime now = DateTime.now();
    final List<(DateTime, DateTime)> all = <(DateTime, DateTime)>[
      for (final PlaceStay s in widget.stays)
        if (s.placeId == widget.place.id)
          (
            s.arrival.subtract(const Duration(seconds: 1)),
            (s.departure ?? now).add(const Duration(seconds: 1)),
          ),
    ]..sort((a, b) => b.$1.compareTo(a.$1));
    const int most = PlaceSheet.photoSpans;
    if (all.length <= most) return all;
    return <(DateTime, DateTime)>[
      for (int i = 0; i < most; i++)
        all[(i * (all.length - 1) / (most - 1)).round()],
    ];
  }

  Future<void> _showMap(Size size) async {
    final PlacesSource? source = ref.read(placesSourceProvider);
    final double scale = MediaQuery.devicePixelRatioOf(context);
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    setState(() => _map = const _MapLoading());
    Uint8List? png;
    try {
      png = await source?.mapSnapshot(
        latitude: widget.place.latitude,
        longitude: widget.place.longitude,
        span: PlaceSheet.mapSpan,
        width: size.width,
        height: size.height,
        scale: scale,
        dark: dark,
      );
    } catch (_) {
      png = null;
    }
    if (!mounted) return;
    setState(() => _map = png == null ? const _MapFailed() : _MapShown(png));
  }

  void _save() => Navigator.of(context).pop(_name.text);

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DialColors colors = DialColors.of(context);
    final TextStyle? muted = theme.textTheme.bodyMedium?.copyWith(
      color: colors.muted,
    );
    final List<String> times = placeTimesLines(
      widget.stays,
      widget.place.id,
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
    final List<PlacePhoto>? photos = _photos;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            DialSpace.xl,
            DialSpace.xl,
            DialSpace.xl,
            DialSpace.xl,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Semantics(
                header: true,
                child: Text(
                  PlaceSheet.title,
                  style: theme.textTheme.headlineSmall,
                ),
              ),
              const SizedBox(height: DialSpace.m),
              TextField(
                controller: _name,
                maxLength: placeNameMaxLength,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: 'Place ${widget.place.id}',
                ),
                onSubmitted: (_) => _save(),
              ),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: DialSpace.xs,
                children: <Widget>[
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(onPressed: _save, child: const Text('Save')),
                ],
              ),
              if (times.isNotEmpty) ...<Widget>[
                const SizedBox(height: DialSpace.m),
                for (final String line in times)
                  Padding(
                    padding: const EdgeInsets.only(bottom: DialSpace.xxs),
                    child: Text(line, style: muted),
                  ),
              ],
              if (_photosAllowed &&
                  (photos == null || photos.isNotEmpty)) ...<Widget>[
                const SizedBox(height: DialSpace.m),
                if (photos == null)
                  _PhotosPlaceholder(style: muted)
                else
                  _PhotoStrip(photos: photos),
              ],
              const SizedBox(height: DialSpace.l),
              LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  final Size size = Size(
                    constraints.maxWidth,
                    (constraints.maxWidth * 0.6).roundToDouble(),
                  );
                  return switch (_map) {
                    _MapIdle() => Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(44, 44),
                          ),
                          onPressed: () => _showMap(size),
                          child: const Text(PlaceSheet.showOnMap),
                        ),
                        const SizedBox(height: DialSpace.xs),
                        Text(PlaceSheet.mapCaption, style: muted),
                      ],
                    ),
                    _MapLoading() => SizedBox.fromSize(
                      size: size,
                      child: const Center(child: CircularProgressIndicator()),
                    ),
                    _MapShown(:final Uint8List png) => _MapImage(
                      png: png,
                      size: size,
                      label: 'Map of ${widget.place.label}',
                    ),
                    _MapFailed() => Text(PlaceSheet.mapFailed, style: muted),
                  };
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PhotosPlaceholder extends StatelessWidget {
  const _PhotosPlaceholder({required this.style});

  final TextStyle? style;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: _PhotoStrip.thumb,
    child: Row(
      spacing: DialSpace.s,
      children: <Widget>[
        const SizedBox.square(
          dimension: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        Flexible(child: Text(PlaceSheet.photosLoading, style: style)),
      ],
    ),
  );
}

class _PhotoStrip extends StatelessWidget {
  const _PhotoStrip({required this.photos});

  final List<PlacePhoto> photos;

  static const double thumb = 96;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DialColors colors = DialColors.of(context);
    final TextStyle? date = theme.textTheme.bodySmall?.copyWith(
      color: colors.muted,
    );
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: DialSpace.xs,
        children: <Widget>[
          for (final PlacePhoto p in photos)
            Semantics(
              image: true,
              label: PlaceSheet.photoLabel(p.at),
              excludeSemantics: true,
              child: SizedBox(
                width: thumb,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(DialRadius.tile / 2),
                      child: Image.memory(
                        p.jpeg,
                        width: thumb,
                        height: thumb,
                        fit: BoxFit.cover,
                        cacheWidth: PlaceSheet.photoPixels,
                        errorBuilder: (_, _, _) => ColoredBox(
                          color: colors.surface2,
                          child: const SizedBox.square(dimension: thumb),
                        ),
                      ),
                    ),
                    const SizedBox(height: DialSpace.xxs),
                    Text(formatShortDay(p.at), style: date),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MapImage extends StatelessWidget {
  const _MapImage({required this.png, required this.size, required this.label});

  final Uint8List png;
  final Size size;
  final String label;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Semantics(
      image: true,
      label: label,
      excludeSemantics: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(DialRadius.tile),
        child: SizedBox.fromSize(
          size: size,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              Image.memory(
                png,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) =>
                    ColoredBox(color: DialColors.of(context).surface2),
              ),
              CustomPaint(
                painter: _PinPainter(
                  fill: scheme.primary,
                  ring: scheme.surface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A dot with a ring at the centre, where the place is.
class _PinPainter extends CustomPainter {
  const _PinPainter({required this.fill, required this.ring});

  final Color fill;
  final Color ring;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset c = size.center(Offset.zero);
    canvas.drawCircle(c, 10, Paint()..color = ring);
    canvas.drawCircle(c, 7, Paint()..color = fill);
  }

  @override
  bool shouldRepaint(_PinPainter old) => old.fill != fill || old.ring != ring;
}
