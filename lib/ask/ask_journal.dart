import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/account/claude_access.dart';
import 'package:tracker/ask/ask_journal_setting.dart';
import 'package:tracker/ask/ask_answer.dart';
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

/// One question asked earlier this session and what the server answered: the
/// question and the SQL written for it, never what the SQL found.
class AskTurn {
  const AskTurn(this.question, this.answer);

  final String question;
  final AskAnswer answer;
}

/// Turns a typed question into SQL cards for this device to run.
abstract class AskJournal {
  /// The server's answer to [question], checked whole. [habits] are those
  /// [askHabits] keeps, numbered as the tables number them; [history] the
  /// session's earlier turns, oldest first (the last [CallableAskJournal.
  /// maxHistory] are sent). Throws [AskFailed] when the server answered
  /// nothing usable, or the call's own error.
  Future<AskAnswer> ask(
    String question, {
    required List<({int id, Vice vice})> habits,
    required DateTime today,
    List<AskTurn> history,
  });
}

/// Null while asking is switched off or cannot work here (signed out, an
/// emulator build, a guest or an unverified email).
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

/// The server answered without a usable answer, for [reason] (`refusal`,
/// `max_tokens`, `unparsable`, `api_error`, or `invalid` when the answer did
/// not fit the schema here).
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
/// [call], which answers `{answer, reason}`.
class CallableAskJournal implements AskJournal {
  CallableAskJournal(this.call);

  final Future<Object?> Function(Map<String, Object?> data) call;

  /// Above the function's own 60 s, itself above its 40 s model request.
  static const Duration timeout = Duration(seconds: 65);
  static const int maxQuestion = 300;
  static const int maxHabits = 100;
  static const int maxName = 60;
  static const int maxUnit = 20;
  static const int maxHistory = 5;

  /// Everything sent for [question]. The only way anything leaves: the
  /// question, today's date and weekday, each habit's number, name, unit
  /// words and archived flag, and earlier questions with the server's own
  /// answers. No parameter here can carry a row, result, amount, time, tag,
  /// note or the uid.
  static Map<String, Object?> request(
    String question, {
    required List<({int id, Vice vice})> habits,
    required DateTime today,
    List<AskTurn> history = const <AskTurn>[],
  }) {
    final DateTime day = startOfDay(today);
    String cut(String s, int max) => s.length > max ? s.substring(0, max) : s;
    final List<AskTurn> recent = history.length > maxHistory
        ? history.sublist(history.length - maxHistory)
        : history;
    return <String, Object?>{
      'question': question,
      'today': _isoDate(day),
      'weekday': _weekdays[day.weekday - 1],
      'habits': <Object?>[
        for (final ({int id, Vice vice}) h in habits)
          <String, Object?>{
            'id': h.id,
            'name': cut(h.vice.name, maxName),
            'unit': cut(h.vice.units.plural, maxUnit),
            'unit_one': cut(h.vice.units.singular, maxUnit),
            'archived': h.vice.archived,
          },
      ],
      'history': <Object?>[
        for (final AskTurn t in recent)
          <String, Object?>{
            'question': cut(t.question, maxQuestion),
            'answer': t.answer.toJson(),
          },
      ],
    };
  }

  @override
  Future<AskAnswer> ask(
    String question, {
    required List<({int id, Vice vice})> habits,
    required DateTime today,
    List<AskTurn> history = const <AskTurn>[],
  }) async {
    final String q = question.trim();
    if (q.isEmpty || q.length > maxQuestion) {
      return const AskAnswer(
        kind: AskKind.cannotAnswer,
        reason: AskReason.unclear,
      );
    }
    if (habits.isEmpty || habits.length > maxHabits) {
      return const AskAnswer(
        kind: AskKind.cannotAnswer,
        reason: AskReason.unknownHabit,
      );
    }
    final Object? answer = await call(
      request(q, habits: habits, today: today, history: history),
    ).timeout(timeout);
    final Object? reason = answer is Map ? answer['reason'] : null;
    if (reason != 'ok') {
      throw AskFailed(reason is String ? reason : 'unparsable');
    }
    final AskAnswer? parsed = parseAskAnswer((answer as Map)['answer']);
    if (parsed == null) throw const AskFailed('invalid');
    return parsed;
  }
}
