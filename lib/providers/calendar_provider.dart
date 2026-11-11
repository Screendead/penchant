import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/insights/after_event.dart';
import 'package:tracker/insights/calendar_source.dart';
import 'package:tracker/insights/insights_timing.dart';

// Calendar events stay on the device: ReportProviderErrors sends every
// provider failure to Crashlytics, so nothing here may fail. Each failure is
// a value instead.

/// Null where the app reads no calendar: everywhere but iOS.
final calendarSourceProvider = Provider<CalendarSource?>(
  (ref) => defaultTargetPlatform == TargetPlatform.iOS
      ? ChannelCalendarSource()
      : null,
);

/// Null where there is no calendar to read or EventKit could not answer.
final calendarAccessProvider = FutureProvider.autoDispose<CalendarAccess?>((
  ref,
) async {
  final CalendarSource? source = ref.watch(calendarSourceProvider);
  if (source == null) return null;
  try {
    return await source.access();
  } catch (_) {
    return null;
  }
});

/// What [calendarEventsProvider] gives without access or after a failure.
const List<CalendarEvent> noCalendarEvents = <CalendarEvent>[];

/// How long the calendar read may hold up Insights before it is left out.
const Duration calendarReadTimeout = Duration(seconds: 30);

typedef CalendarSpan = ({DateTime from, DateTime today});

/// The calendar's timed events from [CalendarSpan.from] to the end of
/// [CalendarSpan.today], read a year at a time.
final calendarEventsProvider = FutureProvider.autoDispose
    .family<List<CalendarEvent>, CalendarSpan>((ref, span) async {
      final CalendarSource? source = ref.watch(calendarSourceProvider);
      final CalendarAccess? access = await ref.watch(
        calendarAccessProvider.future,
      );
      if (source == null || access != CalendarAccess.full) {
        return noCalendarEvents;
      }
      Future<List<CalendarEvent>> readAll() async {
        final List<CalendarEvent> all = <CalendarEvent>[];
        for (final ({DateTime start, DateTime end}) chunk in calendarChunks(
          span.from,
          addDays(startOfDay(span.today), 1),
        )) {
          all.addAll(await source.events(chunk.start, chunk.end));
          if (!ref.mounted) return noCalendarEvents;
        }
        return all;
      }

      try {
        return await timedInsightsStage(
          'calendar read',
          () => readAll().timeout(calendarReadTimeout),
        );
      } catch (_) {
        return noCalendarEvents;
      }
    });

/// Shows the calendar prompt from the Insights screen. Takes the container
/// rather than a page's ref, which may be disposed by the time it closes.
Future<bool> connectCalendar(ProviderContainer container) async {
  final CalendarSource? source = container.read(calendarSourceProvider);
  if (source == null) return false;
  bool granted;
  try {
    granted = await source.requestAccess();
  } catch (_) {
    granted = false;
  }
  container.invalidate(calendarAccessProvider);
  return granted;
}
