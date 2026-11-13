import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/insights/calendar_source.dart';
import 'package:tracker/insights/health_source.dart' show DailyOutcome;
import 'package:tracker/insights/insights_timing.dart';
import 'package:tracker/insights/reminders_source.dart';
import 'package:tracker/providers/calendar_provider.dart'
    show eventKitPromptTimeout;

// Reminders stay on the device: ReportProviderErrors sends every provider
// failure to Crashlytics, so nothing here may fail. Each failure is a value
// instead.

/// Null where the app reads no reminders: everywhere but iOS.
final remindersSourceProvider = Provider<RemindersSource?>(
  (ref) => defaultTargetPlatform == TargetPlatform.iOS
      ? ChannelRemindersSource()
      : null,
);

/// Null where there are no reminders to read or EventKit could not answer.
final remindersAccessProvider = FutureProvider.autoDispose<CalendarAccess?>((
  ref,
) async {
  final RemindersSource? source = ref.watch(remindersSourceProvider);
  if (source == null) return null;
  try {
    return await source.access();
  } catch (_) {
    return null;
  }
});

/// What [reminderOutcomesProvider] gives without access or after a failure.
const List<DailyOutcome> noReminderOutcomes = <DailyOutcome>[];

/// How long the Reminders read may hold up Insights before it is left out.
const Duration remindersReadTimeout = Duration(seconds: 30);

/// [reminderOutcomes] through the day before [today]: today is not over.
final reminderOutcomesProvider = FutureProvider.autoDispose
    .family<List<DailyOutcome>, DateTime>((ref, today) async {
      final RemindersSource? source = ref.watch(remindersSourceProvider);
      final CalendarAccess? access = await ref.watch(
        remindersAccessProvider.future,
      );
      if (source == null || access != CalendarAccess.full) {
        return noReminderOutcomes;
      }
      try {
        final List<Reminder> read = await timedInsightsStage(
          'reminders read',
          () => source.reminders().timeout(remindersReadTimeout),
        );
        return reminderOutcomes(read, through: addDays(startOfDay(today), -1));
      } catch (_) {
        return noReminderOutcomes;
      }
    });

/// Shows the Reminders prompt from the Insights screen. Takes the container
/// rather than a page's ref, which may be disposed by the time it closes.
Future<bool> connectReminders(ProviderContainer container) async {
  final RemindersSource? source = container.read(remindersSourceProvider);
  if (source == null) return false;
  bool granted;
  try {
    granted = await source.requestAccess().timeout(eventKitPromptTimeout);
  } catch (_) {
    granted = false;
  }
  container.invalidate(remindersAccessProvider);
  return granted;
}
