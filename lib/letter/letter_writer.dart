import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/account/claude_access.dart';
import 'package:tracker/firebase_init.dart';
import 'package:tracker/letter/letter_checks.dart';
import 'package:tracker/letter/letter_payload.dart';
import 'package:tracker/letter/letter_setting.dart';
import 'package:tracker/providers/user_provider.dart';

/// Sends a payload to be written up as a letter.
abstract class LetterWriter {
  /// The letter for [payload], checked on this device. Throws [LetterFailed]
  /// when none can be shown, or the call's own error.
  Future<CheckedLetter> write(LetterPayload payload);
}

/// Null while the letter is switched off or cannot work here (signed out, a
/// guest or unverified email, an emulator build).
final Provider<LetterWriter?> letterWriterProvider = Provider<LetterWriter?>((
  Ref ref,
) {
  // The function exists only in production, which a flagged build must never
  // reach.
  if (useFirebaseEmulators) return null;
  if (!ref.watch(letterEnabledProvider)) return null;
  if (ref.watch(userProvider).value == null) return null;
  if (!ref.watch(claudeAllowedProvider)) return null;
  return CallableLetterWriter(_callWriteLetter);
});

Future<Object?> _callWriteLetter(Map<String, Object?> data) =>
    callClaude('writeLetter', CallableLetterWriter.timeout, data);

/// No letter to show, for [reason]: the server's (`refusal`, `max_tokens`,
/// `unparsable`, `sections`, `too_few_sections`, `api_error`) or this
/// device's check (`checks`).
class LetterFailed implements Exception {
  const LetterFailed(this.reason);

  final String reason;

  @override
  String toString() => 'LetterFailed($reason)';
}

/// The `writeLetter` Cloud Function (functions/letter.js), through [call],
/// which sends [LetterPayload.json] and answers `{letter, reason}`.
class CallableLetterWriter implements LetterWriter {
  CallableLetterWriter(this.call);

  final Future<Object?> Function(Map<String, Object?> data) call;

  /// Past the function's 220 s, so its own answer arrives first.
  static const Duration timeout = Duration(seconds: 240);

  @override
  Future<CheckedLetter> write(LetterPayload payload) async {
    final Object? answer = await call(payload.json);
    final Object? reason = answer is Map ? answer['reason'] : null;
    if (reason != 'ok') {
      throw LetterFailed(reason is String ? reason : 'unparsable');
    }
    final CheckedLetter? letter = checkLetter(
      (answer as Map)['letter'],
      payload.json,
    );
    if (letter == null) throw const LetterFailed('checks');
    return letter;
  }
}
