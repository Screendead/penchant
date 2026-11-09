import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:tracker/insights/last_night.dart';
import 'package:tracker/providers/last_night_provider.dart';

class FixedMorning extends Morning {
  FixedMorning(this._morning);

  final bool _morning;

  @override
  bool build() => _morning;
}

/// Today's line with [night] read and the clock [morning] or not.
List<Override> lastNightLineOverrides(
  LastNight? night, {
  bool morning = true,
}) => <Override>[
  morningProvider.overrideWith(() => FixedMorning(morning)),
  lastNightProvider.overrideWith((Ref ref) async => night),
];
