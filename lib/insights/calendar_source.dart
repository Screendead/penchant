import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/insights/after_event.dart';

// The Swift side is ios/Runner/CalendarChannel.swift. Only each event's start
// and end cross the channel, and nothing read here leaves the device.

/// What EventKit says the app may do with the calendar.
enum CalendarAccess {
  full,

  /// iOS 17's add-only access: no events can be read.
  writeOnly,
  denied,
  restricted,
  notDetermined,
}

abstract interface class CalendarSource {
  Future<CalendarAccess> access();

  /// Shows the system's calendar prompt where it has not been answered.
  /// True when full access is now granted.
  Future<bool> requestAccess();

  /// The timed events from [start] to [end], sorted by start; all-day,
  /// cancelled and declined events left out. The span must be under four
  /// years.
  Future<List<CalendarEvent>> events(DateTime start, DateTime end);
}

class ChannelCalendarSource implements CalendarSource {
  ChannelCalendarSource({MethodChannel? channel})
    : _channel =
          channel ?? const MethodChannel('com.screendead.penchant/calendar');

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
  Future<List<CalendarEvent>> events(DateTime start, DateTime end) async {
    final Float64List? flat = await _channel.invokeMethod<Float64List>(
      'events',
      <String, int>{
        'start': start.microsecondsSinceEpoch,
        'end': end.microsecondsSinceEpoch,
      },
    );
    return calendarEventsFrom(flat ?? Float64List(0));
  }
}

/// The channel's answer, start and end in microseconds since 1970 in turn, as
/// events.
List<CalendarEvent> calendarEventsFrom(Float64List flat) => <CalendarEvent>[
  for (int i = 0; i + 1 < flat.length; i += 2)
    CalendarEvent(
      DateTime.fromMicrosecondsSinceEpoch(flat[i].round()),
      DateTime.fromMicrosecondsSinceEpoch(flat[i + 1].round()),
    ),
];

/// The reads covering [start] to [end], a calendar year each at most, oldest
/// first: EventKit refuses a span over four years.
List<({DateTime start, DateTime end})> calendarChunks(
  DateTime start,
  DateTime end,
) {
  final List<({DateTime start, DateTime end})> chunks =
      <({DateTime start, DateTime end})>[];
  DateTime from = startOfDay(start);
  while (from.isBefore(end)) {
    final DateTime next = DateTime(from.year + 1);
    final DateTime to = next.isBefore(end) ? next : end;
    chunks.add((start: from, end: to));
    from = to;
  }
  return chunks;
}
