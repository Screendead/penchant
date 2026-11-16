import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/account/claude_access.dart';
import 'package:tracker/data/limits.dart';
import 'package:tracker/data/trigger_tree.dart';
import 'package:tracker/firebase_init.dart';
import 'package:tracker/notes/follow_up.dart';
import 'package:tracker/notes/follow_up_setting.dart';
import 'package:tracker/notes/note_reader_setting.dart';
import 'package:tracker/providers/user_provider.dart';

/// A starter-tree trigger [path] a note supports, with the words of the note
/// that support it ([quote], copied from the note exactly).
typedef ReadTag = ({String path, String quote});

/// Reads a free-text note into triggers for the person to confirm.
abstract class NoteReader {
  /// Each tag as it is found, closing once the note is read. An error means
  /// the rest could not be read; callers then ask for tags by hand. A tag
  /// whose path is not in the tree or whose quote is not in [note] is never
  /// emitted.
  Stream<ReadTag> read(String note);
}

/// A [NoteReader] that may also ask one follow-up question about the note,
/// from the same read as its tags.
abstract interface class QuestioningNoteReader implements NoteReader {
  /// The question about [note], or null: when follow-up questions are off,
  /// nothing in the note invited one, the server's checks dropped it, or the
  /// read failed. Never an error. A question whose quote is not in [note], or
  /// that breaks a rule the device can check, is never given.
  Future<NoteQuestion?> question(String note);
}

/// Null while reading notes is switched off or cannot work here (signed out,
/// offline, an emulator build): tags are then picked by hand.
final Provider<NoteReader?> noteReaderProvider = Provider<NoteReader?>((
  Ref ref,
) {
  // The function exists only in production, which a flagged build must never
  // reach.
  if (useFirebaseEmulators) return null;
  if (!ref.watch(noteReaderEnabledProvider)) return null;
  if (ref.watch(userProvider).value == null) return null;
  if (!ref.watch(claudeAllowedProvider)) return null;
  return CallableNoteReader(
    _callReadNote,
    askQuestions: ref.watch(followUpEnabledProvider),
  );
});

Future<Object?> _callReadNote(Map<String, Object?> data) =>
    callClaude('readNote', CallableNoteReader.timeout, data);

/// The server read the note but found nothing it could stand behind, for
/// [reason] (`refusal`, `max_tokens`, `unparsable`, `api_error`).
class NoteReadFailed implements Exception {
  const NoteReadFailed(this.reason);

  final String reason;

  @override
  String toString() => 'NoteReadFailed($reason)';
}

/// The `readNote` Cloud Function (functions/index.js), through [call], which
/// sends `{note}` (with `question: true` when [askQuestions]) and answers the
/// function's `{tags: [{path, quote}], reason, question: {question, quote}?}`.
/// The tags come in one answer, so they are emitted together. [read] and
/// [question] of one note share that one call, since the server counts calls
/// against a daily cap.
class CallableNoteReader implements QuestioningNoteReader {
  CallableNoteReader(this.call, {this.askQuestions = false});

  final Future<Object?> Function(Map<String, Object?> data) call;
  final bool askQuestions;

  ({String note, Future<Object?> answer})? _last;

  static const Duration timeout = Duration(seconds: 10);
  static const int maxTags = 4;
  static const int maxNote = 2000;

  static final Set<String> _paths = triggerPaths().toSet();

  @override
  Stream<ReadTag> read(String note) async* {
    if (note.trim().isEmpty || note.length > maxNote) return;
    final Object? answer = await _answer(note);
    final Object? reason = answer is Map ? answer['reason'] : null;
    if (reason is String && reason != 'ok') throw NoteReadFailed(reason);
    yield* Stream<ReadTag>.fromIterable(tagsIn(answer, note));
  }

  @override
  Future<NoteQuestion?> question(String note) async {
    if (!askQuestions || note.trim().isEmpty || note.length > maxNote) {
      return null;
    }
    try {
      return questionIn(await _answer(note), note);
    } catch (_) {
      return null;
    }
  }

  // The one call for [note]; a failed one is forgotten, so the next read
  // asks again.
  Future<Object?> _answer(String note) {
    if (_last case (
      note: final String n,
      answer: final Future<Object?> a,
    ) when n == note) {
      return a;
    }
    final Future<Object?> answer = call(<String, Object?>{
      'note': note,
      if (askQuestions) 'question': true,
    }).timeout(timeout);
    final ({String note, Future<Object?> answer}) last = (
      note: note,
      answer: answer,
    );
    _last = last;
    answer.then<void>(
      (_) {},
      onError: (Object _) {
        if (identical(_last, last)) _last = null;
      },
    );
    return answer;
  }

  /// The question of [answer], if it keeps the rules the device can check:
  /// one question of at most [maxFollowUpQuestionLength] units ending in its
  /// only "?", no digit, and a quote of [note] copied exactly. The server
  /// checks these and more; nothing it sends is shown unchecked.
  static NoteQuestion? questionIn(Object? answer, String note) {
    final Object? asked = answer is Map ? answer['question'] : null;
    if (asked is! Map) return null;
    final Object? question = asked['question'];
    final Object? quote = asked['quote'];
    if (question is! String || quote is! String) return null;
    final String q = question.trim();
    if (q.isEmpty || q.length > maxFollowUpQuestionLength) return null;
    if (!q.endsWith('?') || '?'.allMatches(q).length != 1) return null;
    if (q.contains(RegExp(r'[0-9\r\n]'))) return null;
    if (quote.trim().isEmpty || quote.length > maxFollowUpQuoteLength) {
      return null;
    }
    if (!note.contains(quote)) return null;
    return (question: q, quote: quote);
  }

  /// The tags of [answer] that the tree and [note] bear out, the first of
  /// each path, at most [maxTags]. The server checks the same; nothing it
  /// sends is shown unchecked.
  static List<ReadTag> tagsIn(Object? answer, String note) {
    final Object? tags = answer is Map ? answer['tags'] : null;
    if (tags is! List) return const <ReadTag>[];
    final List<ReadTag> out = <ReadTag>[];
    final Set<String> seen = <String>{};
    for (final Object? tag in tags) {
      if (out.length == maxTags) break;
      if (tag is! Map) continue;
      final Object? path = tag['path'];
      final Object? quote = tag['quote'];
      if (path is! String || quote is! String) continue;
      if (!_paths.contains(path) || seen.contains(path)) continue;
      if (quote.trim().isEmpty || !note.contains(quote)) continue;
      seen.add(path);
      out.add((path: path, quote: quote));
    }
    return out;
  }
}
