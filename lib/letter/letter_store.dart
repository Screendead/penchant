import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/crypto/sealed_files.dart';
import 'package:tracker/errors/report_error.dart';
import 'package:tracker/letter/letter_checks.dart';
import 'package:tracker/letter/letter_payload.dart';
import 'package:tracker/letter/letter_writer.dart';
import 'package:tracker/providers/device_files_provider.dart';
import 'package:tracker/providers/user_provider.dart';

/// A letter as kept: what it covered, when it was written, how much was sent
/// (counts only, never the journal) and the letter itself.
class SavedLetter {
  const SavedLetter({
    required this.id,
    required this.writtenAt,
    required this.from,
    required this.to,
    required this.shortened,
    required this.counts,
    required this.sections,
    required this.toTest,
    required this.withheld,
  });

  final String id;
  final DateTime writtenAt;
  final DateTime from;
  final DateTime to;
  final bool shortened;
  final LetterCounts counts;
  final List<LetterSection> sections;
  final List<LetterTest> toTest;
  final int withheld;

  static String newId() {
    final Random random = Random.secure();
    return List<String>.generate(
      16,
      (_) => random.nextInt(16).toRadixString(16),
    ).join();
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'writtenAt': writtenAt.millisecondsSinceEpoch,
    'from': from.millisecondsSinceEpoch,
    'to': to.millisecondsSinceEpoch,
    'shortened': shortened,
    'counts': counts.toJson(),
    'sections': <Object?>[for (final LetterSection s in sections) s.toJson()],
    'toTest': <Object?>[for (final LetterTest t in toTest) t.toJson()],
    'withheld': withheld,
  };

  /// Null for anything unreadable.
  static SavedLetter? fromJson(Object? json) {
    if (json is! Map) return null;
    final Object? id = json['id'];
    final Object? written = json['writtenAt'];
    final Object? from = json['from'];
    final Object? to = json['to'];
    final Object? shortened = json['shortened'];
    final Object? sections = json['sections'];
    final Object? toTest = json['toTest'];
    final Object? withheld = json['withheld'];
    final LetterCounts? counts = LetterCounts.fromJson(json['counts']);
    if (id is! String ||
        written is! int ||
        from is! int ||
        to is! int ||
        shortened is! bool ||
        sections is! List ||
        toTest is! List ||
        withheld is! int ||
        counts == null) {
      return null;
    }
    final List<LetterSection> s = <LetterSection>[
      for (final Object? x in sections)
        if (x case {'heading': final String h, 'body': final String b})
          LetterSection(h, b),
    ];
    final List<LetterTest> t = <LetterTest>[
      for (final Object? x in toTest)
        if (x case {'title': final String a, 'why': final String b})
          LetterTest(a, b),
    ];
    DateTime at(int ms) => DateTime.fromMillisecondsSinceEpoch(ms);
    return SavedLetter(
      id: id,
      writtenAt: at(written),
      from: at(from),
      to: at(to),
      shortened: shortened,
      counts: counts,
      sections: s,
      toTest: t,
      withheld: withheld,
    );
  }
}

/// The sealed file `letters` among the user's kept device files
/// (Application Support): newest first, cleared on sign-out and deletion.
class LetterFile {
  LetterFile(this._files);

  final SealedFiles _files;

  static const String name = 'letters';

  String get uid => _files.uid;

  /// Empty when absent or unreadable.
  Future<List<SavedLetter>> load() async {
    final List<int>? bytes = await _files.read(name);
    if (bytes == null) return const <SavedLetter>[];
    try {
      final Object? json = jsonDecode(utf8.decode(bytes));
      if (json is! Map || json['v'] != 1 || json['letters'] is! List) {
        return const <SavedLetter>[];
      }
      return <SavedLetter>[
        for (final Object? l in json['letters'] as List<Object?>)
          ?SavedLetter.fromJson(l),
      ];
    } catch (_) {
      return const <SavedLetter>[];
    }
  }

  Future<void> save(List<SavedLetter> letters) => letters.isEmpty
      ? _files.delete(name)
      : _files.write(
          name,
          utf8.encode(
            jsonEncode(<String, Object?>{
              'v': 1,
              'letters': <Object?>[
                for (final SavedLetter l in letters) l.toJson(),
              ],
            }),
          ),
        );
}

final letterFileProvider = Provider<LetterFile?>((ref) {
  final SealedFiles? files = ref.watch(keptSealedFilesProvider);
  return files == null ? null : LetterFile(files);
});

/// The signed-in user's letters on this device, newest first; empty while no
/// key is loaded.
final lettersProvider = AsyncNotifierProvider<Letters, List<SavedLetter>>(
  Letters.new,
);

class Letters extends AsyncNotifier<List<SavedLetter>> {
  LetterFile? _file;

  @override
  Future<List<SavedLetter>> build() async {
    final LetterFile? file = _file = ref.watch(letterFileProvider);
    if (file == null) return const <SavedLetter>[];
    return file.load();
  }

  /// Saves [letter] for [uid] only if that user's file is still the current
  /// one, so a letter finished after a sign-out is dropped.
  Future<bool> add(SavedLetter letter, {required String uid}) async {
    await future;
    final LetterFile? file = _file;
    if (file == null || file.uid != uid) return false;
    final List<SavedLetter> next = <SavedLetter>[
      letter,
      ...state.value ?? const <SavedLetter>[],
    ];
    await file.save(next);
    state = AsyncData<List<SavedLetter>>(next);
    return true;
  }

  Future<void> delete(String id) async {
    final LetterFile? file = _file;
    if (file == null) return;
    final List<SavedLetter> next = <SavedLetter>[
      for (final SavedLetter l in state.value ?? const <SavedLetter>[])
        if (l.id != id) l,
    ];
    await file.save(next);
    state = AsyncData<List<SavedLetter>>(next);
  }
}

sealed class LetterRun {
  const LetterRun();
}

final class LetterIdle extends LetterRun {
  const LetterIdle();
}

final class LetterSending extends LetterRun {
  const LetterSending(this.payload);

  final LetterPayload payload;
}

final class LetterWritten extends LetterRun {
  const LetterWritten(this.letter);

  final SavedLetter letter;
}

final class LetterNotWritten extends LetterRun {
  const LetterNotWritten(this.reason);

  /// [LetterFailed.reason], `offline` for a failed call, `not_saved` when it
  /// could not be kept.
  final String reason;
}

/// The letter being written, held outside the page so that leaving it loses
/// nothing: the letter is saved when it arrives while the app stays open.
/// Back to idle on a change of user.
final letterRunProvider = NotifierProvider<LetterRunner, LetterRun>(
  LetterRunner.new,
);

class LetterRunner extends Notifier<LetterRun> {
  int _generation = 0;

  @override
  LetterRun build() {
    ref.watch(userProvider.select((AsyncValue<User?> u) => u.value?.uid));
    _generation++;
    return const LetterIdle();
  }

  /// Sends [payload] unless a letter is already being written.
  Future<void> send(LetterPayload payload) async {
    if (state is LetterSending) return;
    final LetterWriter? writer = ref.read(letterWriterProvider);
    final String? uid = ref.read(userProvider).value?.uid;
    if (writer == null || uid == null) return;
    final int generation = _generation;
    state = LetterSending(payload);
    LetterRun next;
    try {
      final CheckedLetter letter = await writer.write(payload);
      final SavedLetter saved = SavedLetter(
        id: SavedLetter.newId(),
        writtenAt: DateTime.now(),
        from: payload.from,
        to: payload.to,
        shortened: payload.shortened,
        counts: payload.counts,
        sections: letter.sections,
        toTest: letter.toTest,
        withheld: letter.withheld,
      );
      if (generation != _generation) return;
      final bool kept = await ref
          .read(lettersProvider.notifier)
          .add(saved, uid: uid);
      next = kept ? LetterWritten(saved) : const LetterNotWritten('not_saved');
    } on LetterFailed catch (e) {
      next = LetterNotWritten(e.reason);
    } catch (e, stack) {
      reportError(e, stack, context: 'while writing a letter');
      next = const LetterNotWritten('offline');
    }
    if (generation == _generation) state = next;
  }

  /// Back to idle once the page has shown the outcome.
  void clear() {
    if (state is! LetterSending) state = const LetterIdle();
  }
}
