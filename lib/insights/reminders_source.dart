import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/insights/calendar_source.dart';
import 'package:tracker/insights/health_source.dart' show DailyOutcome;
import 'package:tracker/insights/insights_report.dart' show minSessionDays;

// The Swift side is ios/Runner/RemindersChannel.swift. Only each reminder's
// due and completion times cross the channel, and nothing read here leaves
// the device or is kept on it.

/// The reminders completed on each day.
const String remindersCompletedId = 'remindersCompleted';

/// The reminders due on each day and not completed by its end.
const String remindersMissedId = 'remindersMissed';

/// One reminder as the channel gives it: either time may be absent, never
/// both.
@immutable
class Reminder {
  const Reminder({this.due, this.completed});

  /// When it is due; an all-day due date is local midnight of its day.
  final DateTime? due;

  /// When it was completed; null while it is not.
  final DateTime? completed;

  @override
  bool operator ==(Object other) =>
      other is Reminder && other.due == due && other.completed == completed;

  @override
  int get hashCode => Object.hash(due, completed);
}

abstract interface class RemindersSource {
  /// EventKit's answer for reminders, in the calendar's terms; never
  /// [CalendarAccess.writeOnly] in practice.
  Future<CalendarAccess> access();

  /// Shows the system's Reminders prompt where it has not been answered.
  /// True when full access is now granted.
  Future<bool> requestAccess();

  /// Every reminder in every list, done or not, that has a due or a
  /// completion time.
  Future<List<Reminder>> reminders();
}

class ChannelRemindersSource implements RemindersSource {
  ChannelRemindersSource({MethodChannel? channel})
    : _channel =
          channel ?? const MethodChannel('com.screendead.penchant/reminders');

  final MethodChannel _channel;

  @override
  Future<CalendarAccess> access() async {
    final String? name = await _channel.invokeMethod<String>('access');
    return CalendarAccess.values.firstWhere(
      (a) => a.name == name,
      orElse: () => CalendarAccess.denied,
    );
  }

  @override
  Future<bool> requestAccess() async =>
      await _channel.invokeMethod<bool>('requestAccess') ?? false;

  @override
  Future<List<Reminder>> reminders() async => remindersFrom(
    await _channel.invokeMethod<Float64List>('reminders') ?? Float64List(0),
  );
}

/// The channel's answer, due and completion in microseconds since 1970 in
/// turn, NaN for one absent, as reminders.
List<Reminder> remindersFrom(Float64List flat) {
  DateTime? at(double micros) =>
      micros.isNaN ? null : DateTime.fromMicrosecondsSinceEpoch(micros.round());
  return <Reminder>[
    for (int i = 0; i + 1 < flat.length; i += 2)
      if (!flat[i].isNaN || !flat[i + 1].isNaN)
        Reminder(due: at(flat[i]), completed: at(flat[i + 1])),
  ];
}

/// Two daily series from [reminders], each from its first day above 0
/// through [through] with every day between, 0 where none: the reminders
/// completed that day ([remindersCompletedId]), and those due that day and
/// not completed by its end ([remindersMissedId]). A series with fewer than
/// [minSessionDays] days above 0 is left out, as Health's session metrics
/// are: nearly all zeros would only add comparisons to the false-discovery
/// family that cannot find anything.
List<DailyOutcome> reminderOutcomes(
  List<Reminder> reminders, {
  required DateTime through,
}) {
  final DateTime last = startOfDay(through);
  final Map<DateTime, int> completed = <DateTime, int>{};
  final Map<DateTime, int> missed = <DateTime, int>{};
  for (final Reminder r in reminders) {
    if (r.completed case final DateTime done) {
      final DateTime day = startOfDay(done);
      if (!day.isAfter(last)) completed[day] = (completed[day] ?? 0) + 1;
    }
    if (r.due case final DateTime due) {
      final DateTime day = startOfDay(due);
      final DateTime end = addDays(day, 1);
      final DateTime? done = r.completed;
      if (!day.isAfter(last) && (done == null || !done.isBefore(end))) {
        missed[day] = (missed[day] ?? 0) + 1;
      }
    }
  }
  return <DailyOutcome>[
    ..._series(remindersCompletedId, completed, last),
    ..._series(remindersMissedId, missed, last),
  ];
}

List<DailyOutcome> _series(
  String metricId,
  Map<DateTime, int> counts,
  DateTime through,
) {
  if (counts.length < minSessionDays) return const <DailyOutcome>[];
  final DateTime first = counts.keys.reduce((a, b) => a.isBefore(b) ? a : b);
  return <DailyOutcome>[
    for (DateTime day = first; !day.isAfter(through); day = addDays(day, 1))
      DailyOutcome(day, metricId, (counts[day] ?? 0).toDouble()),
  ];
}
