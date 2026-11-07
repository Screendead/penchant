// Every read and write of an activity's `triggers` field goes through here,
// so that sealing it (r2-e2ee) changes this file alone. Each entry is a
// trigger_tree.dart path or a free-text label; firestore.rules and
// lib/data/limits.dart bound the list.

const String triggersField = 'triggers';

/// A missing or mistyped field reads as no triggers, and a non-string entry is
/// dropped, so a legacy or malformed document still parses.
List<String> readTriggers(Object? value) => value is List<Object?>
    ? List<String>.unmodifiable(value.whereType<String>())
    : const <String>[];

/// The stored form of [triggers], for a create or an update.
Object writeTriggers(List<String> triggers) => List<String>.of(triggers);
