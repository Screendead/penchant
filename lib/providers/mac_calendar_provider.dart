import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tracker/errors/report_error.dart';
import 'package:tracker/insights/after_event.dart';
import 'package:tracker/insights/calendar_source.dart';
import 'package:tracker/providers/calendar_provider.dart';

// The Mac shows no Insights, so its calendar serves the trigger picker alone:
// calendarSourceProvider, which Insights reads, stays null there.

/// The Mac's calendar, whether or not the user has turned suggestions on.
/// Null everywhere but macOS.
final macCalendarSourceProvider = Provider<CalendarSource?>(
  (ref) => defaultTargetPlatform == TargetPlatform.macOS
      ? ChannelCalendarSource()
      : null,
);

/// Null off macOS or where EventKit could not answer.
final macCalendarAccessProvider = FutureProvider.autoDispose<CalendarAccess?>((
  ref,
) async {
  final CalendarSource? source = ref.watch(macCalendarSourceProvider);
  if (source == null) return null;
  try {
    return await source.access();
  } catch (_) {
    return null;
  }
});

/// Where the trigger picker reads the calendar: Insights' source, or on macOS
/// the Mac's calendar, answering no access until Settings turns it on.
final pickerCalendarSourceProvider = Provider<CalendarSource?>((ref) {
  if (defaultTargetPlatform != TargetPlatform.macOS) {
    return ref.watch(calendarSourceProvider);
  }
  final CalendarSource? mac = ref.watch(macCalendarSourceProvider);
  return mac == null ? null : OptedInCalendarSource(mac);
});

/// [source] while [CalendarSuggestions.stored] is on; otherwise it reports
/// access denied, so nothing is read. The choice is read at each ask, since
/// the picker asks once as it opens, before Settings' notifier may have
/// loaded.
class OptedInCalendarSource implements CalendarSource {
  OptedInCalendarSource(this.source);

  final CalendarSource source;

  @override
  Future<CalendarAccess> access() async => await CalendarSuggestions.stored()
      ? source.access()
      : CalendarAccess.denied;

  @override
  Future<bool> requestAccess() => source.requestAccess();

  @override
  Future<List<CalendarEvent>> events(DateTime start, DateTime end) =>
      source.events(start, end);
}

/// Whether the Mac's picker suggests tags from Calendar: off until turned on
/// in Settings, kept on this device only.
final calendarSuggestionsProvider = NotifierProvider<CalendarSuggestions, bool>(
  CalendarSuggestions.new,
);

class CalendarSuggestions extends Notifier<bool> {
  static const String key = 'calendarSuggestions';

  bool _chosen = false;

  /// The saved choice; off when unsaved or unreadable.
  static Future<bool> stored() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      return prefs.getBool(key) ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  bool build() {
    _load();
    return false;
  }

  Future<void> _load() async {
    final bool saved = await stored();
    // A choice made while the read was in flight is newer than what it read.
    if (!_chosen) state = saved;
  }

  /// Turning on asks for full access where it has not been answered. True
  /// when suggestions are on and access is granted.
  Future<bool> choose(bool on) async {
    _chosen = true;
    state = on;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, on);
    } catch (e, stack) {
      reportError(e, stack, context: 'while saving the calendar suggestions');
    }
    if (!on) return false;
    final CalendarSource? source = ref.read(macCalendarSourceProvider);
    bool granted = false;
    if (source != null) {
      try {
        granted = await source.requestAccess();
      } catch (_) {
        granted = false;
      }
    }
    ref.invalidate(macCalendarAccessProvider);
    return granted;
  }
}
