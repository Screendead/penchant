import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/account/claude_access.dart';
import 'package:tracker/ask/ask_journal_setting.dart';
import 'package:tracker/ask/ask_query.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/firebase_init.dart';
import 'package:tracker/providers/user_provider.dart';

/// The habits a question may name, as sent and indexed: oldest first, those
/// whose name will not open (a placeholder) or is blank left out.
List<Vice> askHabits(Iterable<Vice> vices) =>
    vices.where((Vice v) => !v.locked && v.name.trim().isNotEmpty).toList()
      ..sort((Vice a, Vice b) {
        final int byTime = a.createdAt.compareTo(b.createdAt);
        return byTime != 0 ? byTime : a.id.compareTo(b.id);
      });

/// Turns a typed question into a query for this device to run.
abstract class AskJournal {
  /// The server's reading of [question], checked against [habits] (from
  /// [askHabits]) and [today]. Throws [AskFailed] when the server read
  /// nothing, or the call's own error.
  Future<AskParsed> ask(
    String question, {
    required List<Vice> habits,
    required DateTime today,
  });
}

/// Null while asking is switched off or cannot work here (signed out, an
/// emulator build).
final Provider<AskJournal?> askJournalProvider = Provider<AskJournal?>((
  Ref ref,
) {
  // The function exists only in production, which a flagged build must never
  // reach.
  if (useFirebaseEmulators) return null;
  if (!ref.watch(askJournalEnabledProvider)) return null;
  if (ref.watch(userProvider).value == null) return null;
  if (!ref.watch(claudeAllowedProvider)) return null;
  return CallableAskJournal(_callAskJournal);
});

Future<Object?> _callAskJournal(Map<String, Object?> data) =>
    callClaude('askJournal', CallableAskJournal.timeout, data);

/// The server answered without a query, for [reason] (`refusal`,
/// `max_tokens`, `unparsable`, `api_error`).
class AskFailed implements Exception {
  const AskFailed(this.reason);

  final String reason;

  @override
  String toString() => 'AskFailed($reason)';
}

const List<String> _weekdays = <String>[
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

String _isoDate(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-'
    '${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';

/// The `askJournal` Cloud Function (functions/ask_journal.js), through
/// [call], which sends `{question, today, weekday, habits: [{name, unit,
/// archived}]}` and answers `{query, reason}`.
class CallableAskJournal implements AskJournal {
  CallableAskJournal(this.call);

  final Future<Object?> Function(Map<String, Object?> data) call;

  static const Duration timeout = Duration(seconds: 10);
  static const int maxQuestion = 300;
  static const int maxHabits = 100;
  static const int maxName = 60;
  static const int maxUnit = 20;

  /// What is sent for [question]: never an entry, amount, time, tag or note.
  static Map<String, Object?> request(
    String question, {
    required List<Vice> habits,
    required DateTime today,
  }) {
    final DateTime day = startOfDay(today);
    String cut(String s, int max) => s.length > max ? s.substring(0, max) : s;
    return <String, Object?>{
      'question': question,
      'today': _isoDate(day),
      'weekday': _weekdays[day.weekday - 1],
      'habits': <Object?>[
        for (final Vice v in habits)
          <String, Object?>{
            'name': cut(v.name, maxName),
            'unit': cut(v.units.plural, maxUnit),
            'archived': v.archived,
          },
      ],
    };
  }

  @override
  Future<AskParsed> ask(
    String question, {
    required List<Vice> habits,
    required DateTime today,
  }) async {
    final String q = question.trim();
    if (q.isEmpty || q.length > maxQuestion) {
      return const AskCannotAnswer(AskReason.unclear);
    }
    if (habits.isEmpty || habits.length > maxHabits) {
      return const AskCannotAnswer(AskReason.unknownHabit);
    }
    final Object? answer = await call(
      request(q, habits: habits, today: today),
    ).timeout(timeout);
    final Object? reason = answer is Map ? answer['reason'] : null;
    if (reason != 'ok') {
      throw AskFailed(reason is String ? reason : 'unparsable');
    }
    return parseAskQuery(
      (answer as Map)['query'],
      habitCount: habits.length,
      today: today,
    );
  }
}
