import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tracker/errors/report_error.dart';
import 'package:tracker/reminder/daily_nudge.dart';

/// Whether an urge noted on this device is followed by its "Still there?"
/// check-in: off until the person turns it on in the urge sheet, which is
/// the first time notifications are asked for on its account.
final urgeCheckInProvider = NotifierProvider<UrgeCheckIn, bool>(
  UrgeCheckIn.new,
);

class UrgeCheckIn extends Notifier<bool> {
  static const String enabledKey = 'urge.checkIn';

  late Future<void> _loaded;

  @override
  bool build() {
    _loaded = _load();
    return false;
  }

  Future<void> _load() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      state = prefs.getBool(enabledKey) ?? false;
    } catch (e, stack) {
      reportError(e, stack, context: 'while reading the urge check-in');
    }
  }

  /// Turns it on, asking for permission first. False if refused.
  Future<bool> turnOn() async {
    await _loaded;
    final bool granted;
    try {
      granted = await ref.read(nudgeSchedulerProvider).requestPermission();
    } catch (e, stack) {
      reportError(e, stack, context: 'while asking to send notifications');
      return false;
    }
    if (!granted) return false;
    state = true;
    await _save();
    return true;
  }

  // Check-ins already waiting still come; each is answered or cancelled on
  // its own.
  Future<void> turnOff() async {
    await _loaded;
    state = false;
    await _save();
  }

  Future<void> _save() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setBool(enabledKey, state);
    } catch (e, stack) {
      reportError(e, stack, context: 'while saving the urge check-in');
    }
  }
}
