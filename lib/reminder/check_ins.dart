import 'dart:math';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/errors/report_error.dart';
import 'package:tracker/reminder/daily_nudge.dart';
import 'package:tracker/reminder/heavy_day.dart';

/// Prompts a day.
const int checkInsPerDay = 3;

/// Days drawn ahead. iOS keeps 64 pending notifications for the whole app,
/// shared with the reminder, the review, experiments and urges' check-ins.
const int checkInDaysAhead = 5;

/// The shortest waking window: an hour for each prompt.
const Duration minCheckInWindow = Duration(hours: checkInsPerDay);

// Each prompt keeps its own id in [checkInNoticeBase, + checkInNoticeCount):
// clear of the reminder's 1 to 3, the experiment's 1000 to 1999 and urges'
// 3000 to 3999. Ids roll over, so a prompt still in Notification Centre is
// not replaced by a new one for a long while.
const int checkInNoticeBase = 5000;
const int checkInNoticeCount = 1000;

/// One random moment to ask at. [id] is the answer's document id, drawn now,
/// so a press heard twice writes one document.
@immutable
class CheckInPrompt {
  const CheckInPrompt({
    required this.id,
    required this.at,
    required this.notificationId,
  });

  final String id;
  final DateTime at;
  final int notificationId;

  String encode() => '$notificationId|$id|${at.millisecondsSinceEpoch}';

  static CheckInPrompt? decode(String s) {
    final List<String> parts = s.split('|');
    if (parts.length != 3) return null;
    final int? n = int.tryParse(parts[0]);
    final int? ms = int.tryParse(parts[2]);
    if (n == null || ms == null || parts[1].isEmpty) return null;
    return CheckInPrompt(
      id: parts[1],
      at: DateTime.fromMillisecondsSinceEpoch(ms),
      notificationId: n,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CheckInPrompt &&
      other.id == id &&
      other.at == at &&
      other.notificationId == notificationId;

  @override
  int get hashCode => Object.hash(id, at, notificationId);
}

const String _checkInPrefix = 'check-in:';

// The document id and the prompt's time alone: nothing personal.
String checkInPayload(CheckInPrompt p) =>
    '$_checkInPrefix${p.id}:${p.at.millisecondsSinceEpoch}';

({String id, DateTime promptedAt})? checkInOfPayload(String? payload) {
  if (payload == null || !payload.startsWith(_checkInPrefix)) return null;
  final List<String> parts = payload
      .substring(_checkInPrefix.length)
      .split(':');
  if (parts.length != 2 || parts[0].isEmpty) return null;
  final int? ms = int.tryParse(parts[1]);
  if (ms == null) return null;
  return (id: parts[0], promptedAt: DateTime.fromMillisecondsSinceEpoch(ms));
}

/// The waking hours prompts fall in, on the same day.
@immutable
class CheckInWindow {
  const CheckInWindow(this.start, this.end);

  static const CheckInWindow fallback = CheckInWindow(
    TimeOfDay(hour: 9, minute: 0),
    TimeOfDay(hour: 21, minute: 0),
  );

  final TimeOfDay start;
  final TimeOfDay end;

  int get minutes =>
      (end.hour * 60 + end.minute) - (start.hour * 60 + start.minute);

  bool get valid => minutes >= minCheckInWindow.inMinutes;

  @override
  bool operator ==(Object other) =>
      other is CheckInWindow && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);
}

/// [checkInsPerDay] moments on [day] within [window]: the window cut into
/// equal blocks and one moment drawn uniformly, to the second, in each, so
/// every moment of the window is equally likely and no two prompts bunch.
List<DateTime> drawCheckInTimes(
  DateTime day,
  CheckInWindow window,
  Random random,
) {
  final int seconds = window.minutes * 60;
  final int block = seconds ~/ checkInsPerDay;
  return <DateTime>[
    for (int i = 0; i < checkInsPerDay; i++)
      // Built from wall-clock fields, so a DST day keeps its window.
      DateTime(
        day.year,
        day.month,
        day.day,
        window.start.hour,
        window.start.minute,
        i * block + random.nextInt(block),
      ),
  ];
}

const String _idChars =
    'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';

/// A Firestore-style 20-character document id.
String drawCheckInID(Random random) => String.fromCharCodes(<int>[
  for (int i = 0; i < 20; i++) _idChars.codeUnitAt(random.nextInt(62)),
]);

@immutable
class CheckInSettings {
  const CheckInSettings({required this.enabled, required this.window});

  static const CheckInSettings off = CheckInSettings(
    enabled: false,
    window: CheckInWindow.fallback,
  );

  final bool enabled;
  final CheckInWindow window;

  @override
  bool operator ==(Object other) =>
      other is CheckInSettings &&
      other.enabled == enabled &&
      other.window == window;

  @override
  int get hashCode => Object.hash(enabled, window);
}

/// The random generator prompts are drawn from; seeded in tests.
final checkInRandomProvider = Provider<Random>((Ref ref) => Random.secure());

/// Settings › Reminder › Random check-ins: off by default, kept on this device
/// only. The drawn prompts are kept too, so a launch adds days and never
/// redraws a prompt already scheduled: redrawing on each open would tie
/// prompt times to when the app is used.
final checkInsProvider = NotifierProvider<CheckIns, CheckInSettings>(
  CheckIns.new,
);

class CheckIns extends Notifier<CheckInSettings> {
  static const String enabledKey = 'checkIns.enabled';
  static const String startKey = 'checkIns.start';
  static const String endKey = 'checkIns.end';
  static const String promptsKey = 'checkIns.prompts';
  static const String drawnThroughKey = 'checkIns.drawnThrough';
  static const String nextIdKey = 'checkIns.nextId';

  late Future<void> _loaded;

  @override
  CheckInSettings build() {
    _loaded = _load();
    return CheckInSettings.off;
  }

  Future<void> _load() async {
    final CheckInSettings saved;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final int? start = prefs.getInt(startKey);
      final int? end = prefs.getInt(endKey);
      final CheckInWindow window = start == null || end == null
          ? CheckInWindow.fallback
          : CheckInWindow(_time(start), _time(end));
      saved = CheckInSettings(
        enabled: prefs.getBool(enabledKey) ?? false,
        window: window.valid ? window : CheckInWindow.fallback,
      );
    } catch (e, stack) {
      reportError(e, stack, context: 'while reading the check-in setting');
      return;
    }
    state = saved;
    if (saved.enabled) {
      await _topUp();
    }
  }

  static TimeOfDay _time(int minutes) =>
      TimeOfDay(hour: minutes ~/ 60 % 24, minute: minutes % 60);

  static int _minutes(TimeOfDay t) => t.hour * 60 + t.minute;

  /// Turns check-ins on, asking for permission first. False if refused.
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
    state = CheckInSettings(enabled: true, window: state.window);
    await _save();
    await _clearPrompts();
    await _topUp();
    return true;
  }

  /// Turns them off and withdraws every prompt, waiting or shown.
  Future<void> turnOff() async {
    await _loaded;
    state = CheckInSettings(enabled: false, window: state.window);
    await _save();
    await _clearPrompts();
    await _cancel();
  }

  /// False, and nothing changes, for a window under [minCheckInWindow].
  Future<bool> setWindow(CheckInWindow window) async {
    await _loaded;
    if (!window.valid) return false;
    state = CheckInSettings(enabled: state.enabled, window: window);
    await _save();
    if (state.enabled) {
      await _clearPrompts();
      await _cancel();
      await _topUp();
    }
    return true;
  }

  /// On sign-out: off, nothing kept, nothing waiting, so the next account on
  /// this device is never asked on this one's say-so.
  Future<void> forget() async {
    await _loaded;
    state = CheckInSettings.off;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      for (final String key in <String>[
        enabledKey,
        startKey,
        endKey,
        promptsKey,
        drawnThroughKey,
        nextIdKey,
      ]) {
        await prefs.remove(key);
      }
    } catch (e, stack) {
      reportError(e, stack, context: 'while forgetting the check-ins');
    }
    await _cancel();
  }

  /// Keeps [checkInDaysAhead] days of prompts waiting: at launch, and after
  /// each answer, since an app left in memory never launches.
  Future<void> topUp() async {
    await _loaded;
    if (state.enabled) await _topUp();
  }

  Future<void> _topUp() async {
    final DateTime now = clock.now();
    final List<CheckInPrompt> prompts;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final List<CheckInPrompt> kept = <CheckInPrompt>[
        for (final String s
            in prefs.getStringList(promptsKey) ?? const <String>[])
          ?CheckInPrompt.decode(s),
      ].where((CheckInPrompt p) => p.at.isAfter(now)).toList();
      final DateTime today = startOfDay(now);
      final DateTime? through = DateTime.tryParse(
        prefs.getString(drawnThroughKey) ?? '',
      );
      DateTime day = through == null || through.isBefore(today)
          ? today
          : addDays(startOfDay(through), 1);
      final DateTime last = addDays(today, checkInDaysAhead - 1);
      final Random random = ref.read(checkInRandomProvider);
      int next = prefs.getInt(nextIdKey) ?? 0;
      while (!day.isAfter(last)) {
        for (final DateTime at in drawCheckInTimes(day, state.window, random)) {
          if (!at.isAfter(now)) continue;
          kept.add(
            CheckInPrompt(
              id: drawCheckInID(random),
              at: at,
              notificationId: checkInNoticeBase + next % checkInNoticeCount,
            ),
          );
          next++;
        }
        day = addDays(day, 1);
      }
      prompts = kept;
      await prefs.setStringList(promptsKey, <String>[
        for (final CheckInPrompt p in prompts) p.encode(),
      ]);
      await prefs.setString(drawnThroughKey, localDateString(last));
      await prefs.setInt(nextIdKey, next % checkInNoticeCount);
    } catch (e, stack) {
      reportError(e, stack, context: 'while drawing check-ins');
      return;
    }
    try {
      await ref.read(nudgeSchedulerProvider).scheduleCheckIns(prompts);
    } catch (e, stack) {
      reportError(e, stack, context: 'while scheduling check-ins');
    }
  }

  Future<void> _clearPrompts() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.remove(promptsKey);
      await prefs.remove(drawnThroughKey);
    } catch (e, stack) {
      reportError(e, stack, context: 'while clearing check-ins');
    }
  }

  Future<void> _cancel() async {
    try {
      await ref.read(nudgeSchedulerProvider).cancelCheckIns();
    } catch (e, stack) {
      reportError(e, stack, context: 'while cancelling check-ins');
    }
  }

  // A failed save still applies the choice until the app closes.
  Future<void> _save() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setBool(enabledKey, state.enabled);
      await prefs.setInt(startKey, _minutes(state.window.start));
      await prefs.setInt(endKey, _minutes(state.window.end));
    } catch (e, stack) {
      reportError(e, stack, context: 'while saving the check-in setting');
    }
  }
}

/// A check-in's answer, or a tap on it, waiting for Today: it needs sign-in
/// and the journal key to seal the answer. [heardAt] is when the press came,
/// the answer's time however late the key loads.
@immutable
class PendingCheckIn {
  const PendingCheckIn({
    required this.id,
    required this.promptedAt,
    required this.heardAt,
    this.strength,
  });

  final String id;
  final DateTime promptedAt;
  final DateTime heardAt;

  /// Null for a tap on the notification itself, which opens the sheet.
  final int? strength;
}

final pendingCheckInProvider =
    NotifierProvider<PendingCheckInNotifier, PendingCheckIn?>(
      PendingCheckInNotifier.new,
    );

class PendingCheckInNotifier extends Notifier<PendingCheckIn?> {
  // The launch press can be heard by both the plugin's callback and its
  // launch details; each prompt is answered once a session.
  final Set<String> _heard = <String>{};

  @override
  PendingCheckIn? build() => null;

  void request(String id, DateTime promptedAt, {int? strength}) {
    if (strength != null && !_heard.add(id)) return;
    state = PendingCheckIn(
      id: id,
      promptedAt: promptedAt,
      heardAt: clock.now(),
      strength: strength,
    );
  }

  /// Whether [id] was answered this session (from the sheet as well).
  bool answered(String id) => _heard.contains(id);

  void markAnswered(String id) => _heard.add(id);

  void clear() => state = null;
}
