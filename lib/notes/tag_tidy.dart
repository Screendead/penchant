import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/account/claude_access.dart';
import 'package:tracker/data/day_note.dart';
import 'package:tracker/data/trigger_tree.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/firebase_init.dart';
import 'package:tracker/providers/user_provider.dart';

// Own-words tags (free-text triggers) gathered from the journal, sent alone to
// be tidied, and the person's approved changes applied back to the entries
// and day notes holding them.

/// The most labels one request may carry (functions/tag_tidy.js).
const int tidyMaxLabels = 200;

/// Each own-words label and where it is used, most used first. Locked
/// entries and day notes are left out: their tags cannot be read here.
typedef OwnWords = ({String label, int entries, int dayNotes});

final Set<String> _treePaths = triggerPaths().toSet();

bool isOwnWords(String trigger) => !_treePaths.contains(trigger);

/// What the server accepts as a label (functions/tag_tidy.js): 1 to 60
/// UTF-16 units, not blank, no line break. Sealed triggers pass no rules
/// check, so an older build's odd label is kept out rather than refused
/// whole.
bool sendableLabel(String label) =>
    label.trim().isNotEmpty &&
    label.length <= 60 &&
    !label.contains('\n') &&
    !label.contains('\r');

List<OwnWords> ownWords(List<ViceActivity> entries, List<DayNote> dayNotes) {
  final Map<String, int> onEntries = <String, int>{};
  final Map<String, int> onNotes = <String, int>{};
  for (final ViceActivity e in entries) {
    if (e.locked) continue;
    for (final String t in e.triggers.toSet()) {
      if (isOwnWords(t)) onEntries[t] = (onEntries[t] ?? 0) + 1;
    }
  }
  for (final DayNote n in dayNotes) {
    if (n.locked) continue;
    for (final String t in n.triggers.toSet()) {
      if (isOwnWords(t)) onNotes[t] = (onNotes[t] ?? 0) + 1;
    }
  }
  final List<OwnWords> out = <OwnWords>[
    for (final String label in <String>{...onEntries.keys, ...onNotes.keys})
      (
        label: label,
        entries: onEntries[label] ?? 0,
        dayNotes: onNotes[label] ?? 0,
      ),
  ];
  out.sort((OwnWords a, OwnWords b) {
    final int byUse = (b.entries + b.dayNotes).compareTo(
      a.entries + a.dayNotes,
    );
    return byUse != 0 ? byUse : a.label.compareTo(b.label);
  });
  return out;
}

/// One proposed change: every label of [from] becomes the starter tag [path],
/// or, for a merge, the label [label], one of [from].
class TidySuggestion {
  const TidySuggestion({required this.from, this.path, this.label});

  final List<String> from;
  final String? path;
  final String? label;

  /// What each label of [from] becomes.
  String get into => path ?? label!;

  @override
  bool operator ==(Object other) =>
      other is TidySuggestion &&
      other.path == path &&
      other.label == label &&
      other.from.length == from.length &&
      Iterable<int>.generate(
        from.length,
      ).every((int i) => other.from[i] == from[i]);

  @override
  int get hashCode => Object.hash(path, label, Object.hashAll(from));
}

/// Each approved label and what it becomes; a label in two suggestions keeps
/// the first.
Map<String, String> tidyMap(Iterable<TidySuggestion> approved) {
  final Map<String, String> map = <String, String>{};
  for (final TidySuggestion s in approved) {
    for (final String from in s.from) {
      if (from != s.into) map.putIfAbsent(from, () => s.into);
    }
  }
  return map;
}

/// [triggers] with each label of [map] replaced, order kept, each trigger
/// once. Never longer than [triggers], so the limit still holds.
List<String> tidied(List<String> triggers, Map<String, String> map) {
  final List<String> out = <String>[];
  for (final String t in triggers) {
    final String next = map[t] ?? t;
    if (!out.contains(next)) out.add(next);
  }
  return out;
}

bool touches(List<String> triggers, Map<String, String> map) =>
    triggers.any(map.containsKey);

/// The `tidyTags` function failed to answer usefully, for [reason]
/// (`refusal`, `max_tokens`, `unparsable`, `api_error`).
class TidyFailed implements Exception {
  const TidyFailed(this.reason);

  final String reason;

  @override
  String toString() => 'TidyFailed($reason)';
}

abstract class TagTidier {
  /// Proposals for [labels]; each one already checked against them.
  Future<List<TidySuggestion>> tidy(List<String> labels);
}

/// Null unless a verified account is signed in and this is not an emulator
/// build. Sending needs no switch: the page shows the labels and sends them
/// only when the person says so.
final Provider<TagTidier?> tagTidierProvider = Provider<TagTidier?>((Ref ref) {
  if (useFirebaseEmulators) return null;
  if (ref.watch(userProvider).value == null) return null;
  if (!ref.watch(claudeAllowedProvider)) return null;
  return CallableTagTidier(
    (Map<String, Object?> data) =>
        callClaude('tidyTags', CallableTagTidier.timeout, data),
  );
});

/// The `tidyTags` Cloud Function (functions/tag_tidy.js): sends `{labels}`
/// and answers `{suggestions: [{from, path, label}], reason}`.
class CallableTagTidier implements TagTidier {
  const CallableTagTidier(this.call);

  final Future<Object?> Function(Map<String, Object?> data) call;

  /// Above the function's 30 s.
  static const Duration timeout = Duration(seconds: 35);
  static const int maxSuggestions = 40;

  static final Set<String> _leaves = triggerPaths()
      .where((String p) => p.contains(triggerPathSeparator))
      .toSet();

  @override
  Future<List<TidySuggestion>> tidy(List<String> labels) async {
    final Object? answer = await call(<String, Object?>{
      'labels': labels,
    }).timeout(timeout);
    final Object? reason = answer is Map ? answer['reason'] : null;
    if (reason is String && reason != 'ok') throw TidyFailed(reason);
    return suggestionsIn(answer, labels);
  }

  /// The suggestions of [answer] that [labels] and the tree bear out, by the
  /// server's rules: each label sent and in one suggestion at most; a path a
  /// leaf of the tree; a kept label one of those merged, from two or more.
  /// Nothing the server sends is shown unchecked.
  static List<TidySuggestion> suggestionsIn(
    Object? answer,
    List<String> labels,
  ) {
    final Object? list = answer is Map ? answer['suggestions'] : null;
    if (list is! List) return const <TidySuggestion>[];
    final Set<String> sent = labels.toSet();
    final Set<String> used = <String>{};
    final List<TidySuggestion> out = <TidySuggestion>[];
    for (final Object? s in list) {
      if (out.length == maxSuggestions) break;
      if (s is! Map) continue;
      final Object? from = s['from'];
      final Object? path = s['path'];
      final Object? label = s['label'];
      if (from is! List || from.isEmpty) continue;
      final List<String> names = from.whereType<String>().toList();
      if (names.length != from.length) continue;
      if (names.toSet().length != names.length) continue;
      if (!names.every(sent.contains) || names.any(used.contains)) continue;
      final TidySuggestion suggestion;
      if (path is String && label == null) {
        if (!_leaves.contains(path)) continue;
        suggestion = TidySuggestion(from: names, path: path);
      } else if (label is String && path == null) {
        if (names.length < 2 || !names.contains(label)) continue;
        suggestion = TidySuggestion(from: names, label: label);
      } else {
        continue;
      }
      used.addAll(names);
      out.add(suggestion);
    }
    return out;
  }
}
