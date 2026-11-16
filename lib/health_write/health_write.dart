import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tracker/data/habit_strength.dart';
import 'package:tracker/data/vice_activity.dart';

// Writing a habit's entries to Apple Health, iOS only, per habit and per
// device. Only the person's own entries go in, as alcoholic drinks or
// caffeine; nothing is read back (HealthChannel's read types hold neither
// type). Like health_source.dart, failures stay here: a Health error never
// fails a journal write and never reaches reportError.

enum HealthWriteKind {
  // Apple: "the number of standard alcoholic drinks", where "a standard
  // drink is one beer, glass of wine, or mixed drink made with spirits".
  alcohol,
  // In mg.
  caffeine;

  static HealthWriteKind? of(HabitStrength? strength) => switch (strength) {
    null => null,
    HabitStrength(:final StrengthUnit unit) when unit.alcohol => alcohol,
    _ => caffeine,
  };
}

// What one entry puts in Health: for alcohol its servings, Apple's drinks
// being servings whatever their strength; for caffeine its mg at its own
// strength, else the habit's. Null writes nothing.
double? healthValueOf(HabitStrength strength, ViceActivity activity) {
  final double value = switch (HealthWriteKind.of(strength)!) {
    HealthWriteKind.alcohol => activity.measure.toDouble(),
    HealthWriteKind.caffeine => strength.of(activity) ?? 0,
  };
  return value > 0 ? value : null;
}

// The sync identifier HealthKit replaces a sample by, and the tag every
// sample of one habit carries so that the habit's samples can be removed
// together. Document ids are random and say nothing of the journal.
String healthEntryID(String activityID) => 'penchant.entry.$activityID';
String healthHabitID(String viceID) => 'penchant.habit.$viceID';

bool get healthWriteSupported =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

// Whether the habit form offers the switch; tests and renders override it.
final healthWriteSupportedProvider = Provider<bool>(
  (ref) => healthWriteSupported,
);

class HealthWriter {
  const HealthWriter({
    MethodChannel channel = const MethodChannel(
      'com.screendead.penchant/health',
    ),
  }) : _channel = channel;

  final MethodChannel _channel;

  Future<Object?> _call(String method, Map<String, Object> args) async {
    try {
      return await _channel.invokeMethod<Object?>(method, args);
    } catch (_) {
      // Unavailable, refused, or no channel (the headless engine).
      return null;
    }
  }

  // Asks for permission to write [kind] alone. True only when Health says
  // Penchant may write it.
  Future<bool> requestWrite(HealthWriteKind kind) async =>
      await _call('requestWrite', {'kind': kind.name}) == true;

  // Saves or replaces the entry's sample. The version is the device clock,
  // so a later write replaces an earlier one.
  Future<void> writeEntry({
    required HealthWriteKind kind,
    required String activityID,
    required String viceID,
    required double value,
    required DateTime at,
  }) => _call('writeEntry', {
    'kind': kind.name,
    'syncID': healthEntryID(activityID),
    'habit': healthHabitID(viceID),
    'version': clock.now().millisecondsSinceEpoch,
    'value': value,
    'at': at.millisecondsSinceEpoch,
  });

  // Removes the entry's sample, if Penchant wrote one.
  Future<void> deleteEntry(String activityID) =>
      _call('deleteEntry', {'syncID': healthEntryID(activityID)});

  // Removes every sample Penchant wrote for the habit.
  Future<void> deleteHabit(String viceID) =>
      _call('deleteHabit', {'habit': healthHabitID(viceID)});
}

final healthWriterProvider = Provider<HealthWriter>(
  (ref) => const HealthWriter(),
);

// The habits whose entries this device writes to Health, per signed-in
// user: a choice about this device's Health store, not journal content, so
// it stays in shared_preferences beside the device's other permissions.
final healthWriteChoicesProvider =
    NotifierProvider.family<HealthWriteChoices, Set<String>, String>(
      HealthWriteChoices.new,
    );

class HealthWriteChoices extends Notifier<Set<String>> {
  HealthWriteChoices(this.uid);

  final String uid;

  static String keyOf(String uid) => 'healthWrite.$uid';

  bool _chosen = false;

  @override
  Set<String> build() {
    _load();
    return const <String>{};
  }

  // A failed read leaves every habit off.
  Future<void> _load() async {
    final List<String>? saved;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      saved = prefs.getStringList(keyOf(uid));
    } catch (_) {
      return;
    }
    if (saved != null && !_chosen) {
      state = saved.toSet();
    }
  }

  Future<void> choose(String viceID, {required bool on}) async {
    _chosen = true;
    state = on ? <String>{...state, viceID} : <String>{...state}
      ..remove(viceID);
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(keyOf(uid), state.toList()..sort());
    } catch (_) {
      // The choice holds until the app closes.
    }
  }
}
