import 'package:tracker/data/trigger_tree.dart';
import 'package:tracker/insights/after_event.dart';
import 'package:tracker/insights/calendar_source.dart';

// Only event times reach here; the suggestion is shown in the trigger picker
// and stored only if the user taps it.

/// The starter-tree trigger offered after a calendar event.
const String meetingTrigger = 'work${triggerPathSeparator}meeting';

/// How long the picker waits for the calendar before offering nothing.
const Duration calendarSuggestionTimeout = Duration(seconds: 3);

/// The triggers the calendar suggests for an entry at [at]: Work → Meeting when
/// an event of at least [afterEventMinEventMinutes] ended in the
/// [afterEventMinutes] before it, the window Insights judges.
List<String> calendarSuggestions(DateTime at, Iterable<CalendarEvent> events) {
  const Duration window = Duration(minutes: afterEventMinutes);
  const Duration shortest = Duration(minutes: afterEventMinEventMinutes);
  final bool after = events.any(
    (CalendarEvent e) =>
        e.end.difference(e.start) >= shortest &&
        !at.isBefore(e.end) &&
        at.isBefore(e.end.add(window)),
  );
  return after ? const <String>[meetingTrigger] : const <String>[];
}

/// What [calendarSuggestions] offers for an entry at [at], read from [source]
/// only where full access is already granted; never prompts, and any failure
/// or a read slower than [calendarSuggestionTimeout] offers nothing.
Future<List<String>> readCalendarSuggestions(
  CalendarSource? source,
  DateTime at,
) async {
  if (source == null) return const <String>[];
  try {
    return await () async {
      if (await source.access() != CalendarAccess.full) {
        return const <String>[];
      }
      final List<CalendarEvent> events = await source.events(
        at.subtract(const Duration(minutes: afterEventMinutes)),
        at.add(const Duration(minutes: 1)),
      );
      return calendarSuggestions(at, events);
    }().timeout(calendarSuggestionTimeout);
  } catch (_) {
    return const <String>[];
  }
}
