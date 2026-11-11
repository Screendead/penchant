import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:tracker/crypto/sealed_files.dart';
import 'package:tracker/insights/health_source.dart';

typedef CachedSpan = ({String metric, DateTime start, DateTime end});

/// The hours-after samples of settled days, one sealed file a span. A span's
/// times follow the uses', so each file has a random name and holds its own
/// span inside the seal.
class HealthSampleCache {
  HealthSampleCache(this._files, {Random? random})
    : _random = random ?? Random.secure();

  final SealedFiles _files;
  final Random _random;
  final Map<CachedSpan, String> _names = <CachedSpan, String>{};
  Future<Map<CachedSpan, List<HealthSample>>>? _loaded;
  Future<void> _queue = Future<void>.value();

  static const String prefix = 'samples-';
  static const int version = 1;

  String get uid => _files.uid;

  /// What the device holds, read once. Never throws.
  Future<Map<CachedSpan, List<HealthSample>>> load() => _loaded ??= _load();

  Future<Map<CachedSpan, List<HealthSample>>> _load() async {
    final Map<CachedSpan, List<HealthSample>> got =
        <CachedSpan, List<HealthSample>>{};
    try {
      for (final String name in await _files.names()) {
        if (!name.startsWith(prefix)) continue;
        final Uint8List? bytes = await _files.read(name);
        final (CachedSpan, List<HealthSample>)? span = bytes == null
            ? null
            : decodeSpan(bytes);
        if (span == null || _names.containsKey(span.$1)) {
          await _files.delete(name);
          continue;
        }
        _names[span.$1] = name;
        got[span.$1] = span.$2;
      }
    } catch (_) {
      // What was read so far stands; the rest is read from Health.
    }
    return got;
  }

  /// Leaves the device holding [settled]'s spans that have samples and no
  /// others. An empty span is not kept: access granted later would never be
  /// read. Never throws.
  Future<void> keepOnly(Map<CachedSpan, List<HealthSample>> settled) =>
      _queue = _queue.then((_) => _keepOnly(settled)).catchError((_) {});

  Future<void> _keepOnly(Map<CachedSpan, List<HealthSample>> settled) async {
    await load();
    for (final MapEntry<CachedSpan, List<HealthSample>> e in settled.entries) {
      if (e.value.isEmpty || _names.containsKey(e.key)) continue;
      final String name = '$prefix${_randomHex()}';
      try {
        await _files.write(name, encodeSpan(e.key, e.value));
        _names[e.key] = name;
      } catch (_) {
        // Read from Health again next launch.
      }
    }
    for (final CachedSpan span in _names.keys.toList()) {
      if (settled[span]?.isNotEmpty ?? false) continue;
      try {
        await _files.delete(_names.remove(span)!);
      } catch (_) {
        // Pruned next time.
      }
    }
  }

  /// After a read Health refused, which is kept as no samples. Never throws.
  Future<void> clear() => _queue = _queue
      .then((_) async {
        await load();
        _loaded = Future<Map<CachedSpan, List<HealthSample>>>.value(
          <CachedSpan, List<HealthSample>>{},
        );
        for (final String name in _names.values.toList()) {
          await _files.delete(name);
        }
        _names.clear();
      })
      .catchError((_) {});

  String _randomHex() => <String>[
    for (int i = 0; i < 16; i++)
      _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ].join();

  static Uint8List encodeSpan(CachedSpan span, List<HealthSample> samples) =>
      utf8.encode(
        jsonEncode(<String, Object>{
          'version': version,
          'metric': span.metric,
          'start': span.start.microsecondsSinceEpoch,
          'end': span.end.microsecondsSinceEpoch,
          'samples': <List<num>>[
            for (final HealthSample s in samples)
              <num>[
                s.start.microsecondsSinceEpoch,
                s.end.microsecondsSinceEpoch,
                s.value,
              ],
          ],
        }),
      );

  /// Null for anything but a span this version wrote.
  static (CachedSpan, List<HealthSample>)? decodeSpan(List<int> bytes) {
    final Object? json;
    try {
      json = jsonDecode(utf8.decode(bytes));
    } on FormatException {
      return null;
    }
    if (json case {
      'version': version,
      'metric': final String metric,
      'start': final int start,
      'end': final int end,
      'samples': final List<Object?> rows,
    }) {
      final List<HealthSample> samples = <HealthSample>[];
      for (final Object? row in rows) {
        if (row case [final int s, final int e, final num v] when v.isFinite) {
          samples.add(
            HealthSample(
              DateTime.fromMicrosecondsSinceEpoch(s),
              DateTime.fromMicrosecondsSinceEpoch(e),
              v.toDouble(),
            ),
          );
        } else {
          return null;
        }
      }
      return (
        (
          metric: metric,
          start: DateTime.fromMicrosecondsSinceEpoch(start),
          end: DateTime.fromMicrosecondsSinceEpoch(end),
        ),
        samples,
      );
    }
    return null;
  }
}
