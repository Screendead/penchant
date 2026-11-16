import 'dart:async';
import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/claude/claude_working.dart';
import 'package:tracker/crypto/sealed_files.dart';
import 'package:tracker/data/activity_content.dart';
import 'package:tracker/data/day_note.dart';
import 'package:tracker/data/limits.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/errors/report_error.dart';
import 'package:tracker/notes/note_reader.dart';
import 'package:tracker/providers/device_files_provider.dart';
import 'package:tracker/providers/tracker_writes_provider.dart';
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/writes/rejected_writes.dart';
import 'package:tracker/writes/tracker_writes.dart';

// Older notes read into tags for the person to review: which entries were
// read, the tags proposed and not yet decided, and how many notes this device
// sent today. Kept in a sealed device file, since it holds tag proposals and
// quotes from notes.

/// Notes read in one batch the person starts, and shown for review together.
const int olderNotesBatch = 20;

/// Notes this device sends a day for older notes, under readNote's 60 a day
/// per uid, so that new notes can still be read.
const int olderNotesDailyCap = 40;

/// What is known about older notes on this device. [done] holds the ids of
/// entries read (whatever came of it) or decided; [proposals] those read with
/// tags awaiting review, oldest read first.
class OlderNotesProgress {
  const OlderNotesProgress({
    this.done = const <String>{},
    this.proposals = const <String, List<ReadTag>>{},
    this.day = '',
    this.sent = 0,
  });

  factory OlderNotesProgress.fromJson(Object? json) {
    if (json is! Map || json['v'] != 1) return const OlderNotesProgress();
    final Object? done = json['done'];
    final Object? proposals = json['proposals'];
    final Object? day = json['day'];
    final Object? sent = json['sent'];
    return OlderNotesProgress(
      done: <String>{if (done is List) ...done.whereType<String>()},
      proposals: <String, List<ReadTag>>{
        if (proposals is Map)
          for (final MapEntry<Object?, Object?> e in proposals.entries)
            if (e.key is String && e.value is List)
              e.key! as String: <ReadTag>[
                for (final Object? t in e.value! as List)
                  if (t is Map && t['p'] is String && t['q'] is String)
                    (path: t['p']! as String, quote: t['q']! as String),
              ],
      },
      day: day is String ? day : '',
      sent: sent is int ? sent : 0,
    );
  }

  final Set<String> done;
  final Map<String, List<ReadTag>> proposals;

  /// The local day [sent] counts, as [dayKey] writes it.
  final String day;
  final int sent;

  int sentOn(DateTime now) => day == dayKey(now) ? sent : 0;

  int leftToday(DateTime now) =>
      (olderNotesDailyCap - sentOn(now)).clamp(0, olderNotesDailyCap);

  bool seen(String id) => done.contains(id) || proposals.containsKey(id);

  OlderNotesProgress counted(DateTime now) => OlderNotesProgress(
    done: done,
    proposals: proposals,
    day: dayKey(now),
    sent: sentOn(now) + 1,
  );

  /// [id] read, with [tags] to review, or none.
  OlderNotesProgress read(String id, List<ReadTag> tags) => OlderNotesProgress(
    done: tags.isEmpty ? <String>{...done, id} : done,
    proposals: tags.isEmpty
        ? proposals
        : <String, List<ReadTag>>{...proposals, id: tags},
    day: day,
    sent: sent,
  );

  /// [ids] decided, kept or dropped: never proposed again.
  OlderNotesProgress decided(Iterable<String> ids) {
    final Set<String> decided = ids.toSet();
    return OlderNotesProgress(
      done: <String>{...done, ...decided},
      proposals: <String, List<ReadTag>>{
        for (final MapEntry<String, List<ReadTag>> e in proposals.entries)
          if (!decided.contains(e.key)) e.key: e.value,
      },
      day: day,
      sent: sent,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'v': 1,
    'done': done.toList(),
    'proposals': <String, Object?>{
      for (final MapEntry<String, List<ReadTag>> e in proposals.entries)
        e.key: <Object?>[
          for (final ReadTag t in e.value)
            <String, String>{'p': t.path, 'q': t.quote},
        ],
    },
    'day': day,
    'sent': sent,
  };
}

/// The entries whose notes may be sent, newest first, and what was left out.
typedef OlderNotes = ({
  List<ViceActivity> unread,
  int locked,
  int full,
  int read,
});

OlderNotes olderNotes(List<ViceActivity> entries, OlderNotesProgress p) {
  final List<ViceActivity> unread = <ViceActivity>[];
  int locked = 0;
  int full = 0;
  int read = 0;
  for (final ViceActivity e in entries) {
    if (e.locked) {
      locked++;
      continue;
    }
    final String? note = e.note;
    if (note == null || note.trim().isEmpty) continue;
    if (p.seen(e.id)) {
      read++;
    } else if (e.triggers.length >= maxTriggers) {
      full++;
    } else {
      unread.add(e);
    }
  }
  unread.sort((ViceActivity a, ViceActivity b) {
    final int byTime = b.createdAt.compareTo(a.createdAt);
    return byTime != 0 ? byTime : a.id.compareTo(b.id);
  });
  return (unread: unread, locked: locked, full: full, read: read);
}

/// The tags of [proposed] still worth showing on [entry]: quoted in its note
/// as it is now, and not already among its triggers.
List<ReadTag> shownTags(ViceActivity entry, List<ReadTag> proposed) {
  final String note = entry.note ?? '';
  return <ReadTag>[
    for (final ReadTag t in proposed)
      if (note.contains(t.quote) && !entry.triggers.contains(t.path)) t,
  ];
}

/// [triggers] with each of [add] not already there, while there is room.
List<String> withTags(List<String> triggers, Iterable<String> add) {
  final List<String> out = List<String>.of(triggers);
  for (final String path in add) {
    if (out.length >= maxTriggers) break;
    if (!out.contains(path)) out.add(path);
  }
  return out;
}

class OlderNotesFile {
  const OlderNotesFile(this._files);

  static const String name = 'older-notes';

  final SealedFiles _files;

  String get uid => _files.uid;

  Future<OlderNotesProgress> load() async {
    final List<int>? bytes = await _files.read(name);
    if (bytes == null) return const OlderNotesProgress();
    try {
      return OlderNotesProgress.fromJson(jsonDecode(utf8.decode(bytes)));
    } catch (_) {
      return const OlderNotesProgress();
    }
  }

  Future<void> save(OlderNotesProgress p) =>
      _files.write(name, utf8.encode(jsonEncode(p.toJson())));
}

/// Under Application Support: losing it would send every note again.
final olderNotesFileProvider = Provider<OlderNotesFile?>((ref) {
  final SealedFiles? files = ref.watch(keptSealedFilesProvider);
  return files == null ? null : OlderNotesFile(files);
});

/// Why a batch stopped early.
enum OlderNotesProblem { enoughToday, failed, noKey }

class OlderNotesState {
  const OlderNotesState({this.progress, this.reading = false, this.problem});

  /// Null until the file has been read.
  final OlderNotesProgress? progress;
  final bool reading;
  final OlderNotesProblem? problem;
}

final olderNotesProvider = NotifierProvider<OlderNotesRunner, OlderNotesState>(
  OlderNotesRunner.new,
);

/// Reads batches of older notes outside the page, so a batch keeps going and
/// its results are kept when the person leaves it; Stop drops what is in
/// flight.
class OlderNotesRunner extends Notifier<OlderNotesState> {
  int _generation = 0;
  OlderNotesFile? _file;
  ClaudeWork? _work;

  /// Tests set the clock.
  DateTime Function() now = DateTime.now;

  @override
  OlderNotesState build() {
    ref.watch(userProvider.select((AsyncValue<User?> u) => u.value?.uid));
    final OlderNotesFile? file = _file = ref.watch(olderNotesFileProvider);
    _generation++;
    if (file != null) unawaited(_load(file, _generation));
    return const OlderNotesState();
  }

  Future<void> _load(OlderNotesFile file, int generation) async {
    final OlderNotesProgress p = await file.load();
    if (generation != _generation || !ref.mounted) return;
    state = OlderNotesState(progress: p);
  }

  Future<void> _save(OlderNotesProgress p) async {
    state = OlderNotesState(
      progress: p,
      reading: state.reading,
      problem: state.problem,
    );
    try {
      await _file?.save(p);
    } catch (e, stack) {
      reportError(e, stack, context: 'while saving older notes progress');
    }
  }

  /// Stops the batch; a note in flight is dropped and stays unread.
  void stop() {
    if (!state.reading) return;
    _generation++;
    _work?.finish(ClaudeWorkEnd.stopped);
    _work = null;
    state = OlderNotesState(progress: state.progress);
  }

  void clearProblem() =>
      state = OlderNotesState(progress: state.progress, reading: state.reading);

  /// Sends each of [batch]'s notes in turn, keeping [work] current.
  Future<void> read(List<ViceActivity> batch, {ClaudeWork? work}) async {
    final NoteReader? reader = ref.read(olderNoteReaderProvider);
    if (state.reading || reader == null || state.progress == null) {
      work?.finish(ClaudeWorkEnd.failed);
      return;
    }
    final int generation = ++_generation;
    _work = work;
    state = OlderNotesState(progress: state.progress, reading: true);
    OlderNotesProblem? problem;
    int sent = 0;
    for (final ViceActivity entry in batch) {
      final OlderNotesProgress p = state.progress!;
      if (p.leftToday(now()) == 0) {
        problem = OlderNotesProblem.enoughToday;
        break;
      }
      final String note = entry.note ?? '';
      await _save(p.counted(now()));
      sent++;
      work?.say(
        OlderNotesCopy.reading,
        detail: OlderNotesCopy.sentSoFar(sent),
        stepsDone: sent - 1,
      );
      List<ReadTag> tags;
      try {
        tags = await reader.read(note).toList();
      } on NoteReadFailed catch (e) {
        // The model's own refusal or a reply that failed its checks: nothing
        // to offer, and asking again would cost the same. A failed call is
        // tried again another time.
        if (e.reason == 'api_error') {
          problem = OlderNotesProblem.failed;
          break;
        }
        tags = const <ReadTag>[];
      } on FirebaseFunctionsException catch (e) {
        problem = e.code == 'resource-exhausted'
            ? OlderNotesProblem.enoughToday
            : OlderNotesProblem.failed;
        break;
      } catch (_) {
        problem = OlderNotesProblem.failed;
        break;
      }
      if (generation != _generation || !ref.mounted) return;
      await _save(state.progress!.read(entry.id, shownTags(entry, tags)));
    }
    if (generation != _generation || !ref.mounted) return;
    state = OlderNotesState(progress: state.progress, problem: problem);
    _work = null;
    work?.finish(
      problem == OlderNotesProblem.failed
          ? ClaudeWorkEnd.failed
          : ClaudeWorkEnd.answered,
    );
  }

  /// Saves [keep] (entry id to the tag paths kept) to their entries and marks
  /// every id in it decided, kept or not. Returns how many saves failed at
  /// once; a later refusal reaches the rejected-writes banner.
  Future<TagSaves> decide(
    Map<String, List<String>> keep,
    Map<String, ViceActivity> entries, {
    required String Function(ViceActivity) what,
  }) async {
    final OlderNotesProgress? p = state.progress;
    if (p == null) return const (saved: 0, queued: 0, failed: 0, skipped: 0);
    await _save(p.decided(keep.keys));
    final TrackerWrites writes = ref.read(trackerWritesProvider);
    final RejectedWrites rejected = ref.read(rejectedWritesProvider.notifier);
    final List<Future<TagSave>> saves = <Future<TagSave>>[
      for (final MapEntry<String, List<String>> k in keep.entries)
        if (k.value.isNotEmpty && entries[k.key] != null)
          addTags(
            writes,
            rejected,
            entries[k.key]!,
            k.value,
            what(entries[k.key]!),
          ),
    ];
    return countSaves(await Future.wait(saves));
  }
}

enum TagSave { saved, queued, failed, skipped }

typedef TagSaves = ({int saved, int queued, int failed, int skipped});

TagSaves countSaves(Iterable<TagSave> saves) {
  int saved = 0, queued = 0, failed = 0, skipped = 0;
  for (final TagSave s in saves) {
    switch (s) {
      case TagSave.saved:
        saved++;
      case TagSave.queued:
        queued++;
      case TagSave.failed:
        failed++;
      case TagSave.skipped:
        skipped++;
    }
  }
  return (saved: saved, queued: queued, failed: failed, skipped: skipped);
}

/// Writes [triggers] in place of [entry]'s, through the entry's whole content
/// as this device holds it, so nothing else in its envelope is lost.
Future<TagSave> setTriggers(
  TrackerWrites writes,
  RejectedWrites rejected,
  ViceActivity entry,
  List<String> Function(List<String> current) change,
  String what,
) async {
  if (entry.locked) return TagSave.skipped;
  final ActivityContent held =
      await writes.cachedContent(entry.id) ?? entry.content;
  final List<String> next = change(held.triggers);
  if (_same(next, held.triggers)) return TagSave.skipped;
  if (triggersError(next) != null) return TagSave.skipped;
  final ActivityContent content = held.withAnswers(
    triggers: next,
    urge: held.urge,
    note: held.note,
  );
  if (!writes.canWrite(content)) return TagSave.failed;
  try {
    return await rejected.settle(
          writes.updateActivity(entry.id, content: content),
          what,
        )
        ? TagSave.saved
        : TagSave.queued;
  } on FirebaseException catch (e, stack) {
    reportError(e, stack, context: 'while saving tags on an older entry');
    return TagSave.failed;
  }
}

/// Adds [paths] to [entry]'s triggers, as far as the limit allows.
Future<TagSave> addTags(
  TrackerWrites writes,
  RejectedWrites rejected,
  ViceActivity entry,
  List<String> paths,
  String what,
) => setTriggers(
  writes,
  rejected,
  entry,
  (List<String> current) => withTags(current, paths),
  what,
);

bool _same(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

abstract final class OlderNotesCopy {
  static const String reading = 'Reading your notes';
  static String sentSoFar(int n) =>
      n == 1 ? 'Sent 1 note, one at a time' : 'Sent $n notes, one at a time';
}
