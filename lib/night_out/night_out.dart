import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/errors/report_error.dart';
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/providers/vice_activity_day_provider.dart';

/// A night out on the Lock Screen: a Live Activity counting one habit since
/// the night started, with a +1 that queues a log as the widgets do
/// (ios/PenchantWidgets/NightOut.swift). iPhone only.
@immutable
class Night {
  const Night({
    required this.id,
    required this.viceID,
    required this.start,
    required this.endBy,
    required this.showsHabit,
    required this.count,
  });

  factory Night.fromMap(Map<Object?, Object?> map) => Night(
    id: map['id']! as String,
    viceID: map['viceID']! as String,
    start: DateTime.fromMillisecondsSinceEpoch((map['start']! as num).toInt()),
    endBy: DateTime.fromMillisecondsSinceEpoch((map['endBy']! as num).toInt()),
    showsHabit: map['showsHabit'] == true,
    count: map['count']! as num,
  );

  final String id;
  final String viceID;
  final DateTime start;
  final DateTime endBy;
  // Whether the Lock Screen names the habit and shows its colour.
  final bool showsHabit;
  // What the Lock Screen shows: the habit's total since [start].
  final num count;

  @override
  bool operator ==(Object other) =>
      other is Night &&
      other.id == id &&
      other.viceID == viceID &&
      other.start == start &&
      other.endBy == endBy &&
      other.showsHabit == showsHabit &&
      other.count == count;

  @override
  int get hashCode => Object.hash(id, viceID, start, endBy, showsHabit, count);
}

/// Whether a night can start here, and the one running.
@immutable
class NightOutStatus {
  const NightOutStatus({
    required this.supported,
    required this.enabled,
    this.night,
  });

  // Not an iPhone on iOS 17 or later.
  static const NightOutStatus unsupported = NightOutStatus(
    supported: false,
    enabled: false,
  );

  final bool supported;
  // Live Activities allowed for Penchant in Settings.
  final bool enabled;
  final Night? night;

  NightOutStatus withNight(Night? night) =>
      NightOutStatus(supported: supported, enabled: enabled, night: night);

  @override
  bool operator ==(Object other) =>
      other is NightOutStatus &&
      other.supported == supported &&
      other.enabled == enabled &&
      other.night == night;

  @override
  int get hashCode => Object.hash(supported, enabled, night);
}

/// Why "Start a night" cannot run, in one line, or null when it can.
String? nightUnavailableReason(NightOutStatus status) {
  if (!status.supported) {
    return 'Needs iOS 17 or later.';
  }
  if (!status.enabled) {
    return 'Live Activities are off for Penchant in Settings.';
  }
  if (status.night != null) {
    return 'A night is running. End it on Today first.';
  }
  return null;
}

class NightStartRefused implements Exception {
  const NightStartRefused(this.message);

  final String message;
}

/// The method channel to ios/Runner/NightChannel.swift.
class NightOutBridge {
  const NightOutBridge([
    this._channel = const MethodChannel('com.screendead.penchant/night_out'),
  ]);

  final MethodChannel _channel;

  /// Also ends a night that is over or not [uid]'s.
  Future<NightOutStatus> status(String? uid) async {
    try {
      final Map<Object?, Object?>? map = await _channel
          .invokeMethod<Map<Object?, Object?>>('status', <String, Object?>{
            'uid': uid,
          });
      if (map == null || map['supported'] != true) {
        return NightOutStatus.unsupported;
      }
      final Object? night = map['night'];
      return NightOutStatus(
        supported: true,
        enabled: map['enabled'] == true,
        night: night is Map<Object?, Object?> ? Night.fromMap(night) : null,
      );
    } on MissingPluginException {
      return NightOutStatus.unsupported;
    } on PlatformException catch (e, stack) {
      reportError(e, stack, context: 'while reading the night out');
      return NightOutStatus.unsupported;
    }
  }

  /// Starts a night on [viceID] now. [habit] and [slot] go on the Lock Screen
  /// only when the person chose to show them.
  Future<Night> start({
    required String uid,
    required String viceID,
    required String? habit,
    required int? slot,
    required num base,
  }) async {
    try {
      final Map<Object?, Object?>? map = await _channel
          .invokeMethod<Map<Object?, Object?>>('start', <String, Object?>{
            'uid': uid,
            'viceID': viceID,
            'habit': habit,
            'slot': slot,
            'base': base,
          });
      return Night.fromMap(map!);
    } on PlatformException catch (e) {
      throw NightStartRefused(switch (e.code) {
        'already-running' => 'A night is already running.',
        _ =>
          'iOS did not start it. Check that Live Activities are on for '
              'Penchant in Settings.',
      });
    }
  }

  /// The habit's entries since the night started: their total and ids. Null
  /// when no night runs any more.
  Future<Night?> reconcile({
    required String uid,
    required num base,
    required List<String> seen,
  }) async {
    try {
      final Map<Object?, Object?>? map = await _channel
          .invokeMethod<Map<Object?, Object?>>('reconcile', <String, Object?>{
            'uid': uid,
            'base': base,
            'seen': seen,
          });
      return map == null ? null : Night.fromMap(map);
    } on PlatformException catch (e, stack) {
      reportError(e, stack, context: 'while updating the night out');
      return null;
    }
  }

  Future<void> end() async {
    try {
      await _channel.invokeMethod<void>('end');
    } on PlatformException catch (e, stack) {
      reportError(e, stack, context: 'while ending the night out');
    }
  }
}

final nightOutBridgeProvider = Provider<NightOutBridge>(
  (ref) => const NightOutBridge(),
);

bool get nightOutPlatform =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

/// The night out, read from native for the signed-in user at sign-in and on
/// every resume; null until known. A user change re-reads, and native ends a
/// night that is not the new user's, so signing out or deleting the account
/// ends it.
final nightOutProvider = NotifierProvider<NightOutNotifier, NightOutStatus?>(
  NightOutNotifier.new,
);

class NightOutNotifier extends Notifier<NightOutStatus?> {
  String? _uid;

  @override
  NightOutStatus? build() {
    if (!nightOutPlatform) {
      return NightOutStatus.unsupported;
    }
    final AsyncValue<User?> user = ref.watch(userProvider);
    if (!user.hasValue) {
      return null;
    }
    _uid = user.value?.uid;
    final AppLifecycleListener lifecycle = AppLifecycleListener(
      onResume: () => unawaited(refresh()),
    );
    ref.onDispose(lifecycle.dispose);
    unawaited(refresh());
    return null;
  }

  NightOutBridge get _bridge => ref.read(nightOutBridgeProvider);

  Future<void> refresh() async {
    final String? uid = _uid;
    final NightOutStatus status = await _bridge.status(uid);
    if (ref.mounted && uid == _uid) {
      state = status;
    }
  }

  /// Throws [NightStartRefused] when iOS or a running night refuses it.
  Future<void> start({
    required String viceID,
    required String? habit,
    required int? slot,
  }) async {
    final String? uid = _uid;
    final NightOutStatus? status = state;
    if (uid == null || status == null) {
      throw const NightStartRefused('Not signed in.');
    }
    // A new night counts from now, so nothing is in it yet.
    final Night night = await _bridge.start(
      uid: uid,
      viceID: viceID,
      habit: habit,
      slot: slot,
      base: 0,
    );
    if (ref.mounted && uid == _uid) {
      state = status.withNight(night);
    }
  }

  Future<void> end() async {
    await _bridge.end();
    if (ref.mounted) {
      state = state?.withNight(null);
    }
  }

  void _reconciled(Night? night) {
    final NightOutStatus? status = state;
    if (status != null && status.night?.id != null) {
      state = status.withNight(night);
    }
  }
}

/// The habit's total since the night started and the ids it is made of.
({num base, List<String> seen}) nightTotal(
  Iterable<ViceActivity> activities,
  String viceID,
) {
  num base = 0;
  final List<String> seen = <String>[];
  for (final ViceActivity a in activities) {
    if (a.viceID == viceID) {
      base += a.measure;
      seen.add(a.id);
    }
  }
  return (base: base, seen: seen);
}

/// Keeps the Lock Screen's count to the entries the app has while it runs: a
/// log, an Undo, an edit or a delete in the app shows there at once. Kept
/// alive by MyApp.
final nightOutSyncProvider = Provider<void>((ref) {
  final ({String id, String viceID, DateTime start, DateTime endBy})? night =
      ref.watch(
        nightOutProvider.select(
          (NightOutStatus? s) => switch (s?.night) {
            null => null,
            final Night n => (
              id: n.id,
              viceID: n.viceID,
              start: n.start,
              endBy: n.endBy,
            ),
          },
        ),
      );
  final String? uid = ref.watch(userProvider).value?.uid;
  if (night == null || uid == null) {
    return;
  }
  final List<ViceActivity>? activities = ref
      .watch(
        viceActivitySinceForUserProvider((
          uid: uid,
          start: night.start,
          end: night.endBy,
        )),
      )
      .value;
  if (activities == null) {
    return;
  }
  final ({num base, List<String> seen}) total = nightTotal(
    activities,
    night.viceID,
  );
  unawaited(
    ref
        .read(nightOutBridgeProvider)
        .reconcile(uid: uid, base: total.base, seen: total.seen)
        .then((Night? updated) {
          if (ref.mounted) {
            ref.read(nightOutProvider.notifier)._reconciled(updated);
          }
        }),
  );
});
