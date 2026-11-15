import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/data/trigger_tree.dart';
import 'package:tracker/firebase_init.dart';
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
  return CallableNoteReader(_callReadNote);
});

Future<Object?> _callReadNote(Map<String, Object?> data) async {
  final HttpsCallable callable = FirebaseFunctions.instance.httpsCallable(
    'readNote',
    options: HttpsCallableOptions(timeout: CallableNoteReader.timeout),
  );
  return (await callable.call<Object?>(data)).data;
}

/// The server read the note but found nothing it could stand behind, for
/// [reason] (`refusal`, `max_tokens`, `unparsable`, `api_error`).
class NoteReadFailed implements Exception {
  const NoteReadFailed(this.reason);

  final String reason;

  @override
  String toString() => 'NoteReadFailed($reason)';
}

/// The `readNote` Cloud Function (functions/index.js), through [call], which
/// sends `{note}` and answers the function's `{tags: [{path, quote}], reason}`.
/// The tags come in one answer, so they are emitted together.
class CallableNoteReader implements NoteReader {
  CallableNoteReader(this.call);

  final Future<Object?> Function(Map<String, Object?> data) call;

  static const Duration timeout = Duration(seconds: 10);
  static const int maxTags = 4;
  static const int maxNote = 500;

  static final Set<String> _paths = triggerPaths().toSet();

  @override
  Stream<ReadTag> read(String note) async* {
    if (note.trim().isEmpty || note.length > maxNote) return;
    final Object? answer = await call(<String, Object?>{
      'note': note,
    }).timeout(timeout);
    final Object? reason = answer is Map ? answer['reason'] : null;
    if (reason is String && reason != 'ok') throw NoteReadFailed(reason);
    yield* Stream<ReadTag>.fromIterable(tagsIn(answer, note));
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
