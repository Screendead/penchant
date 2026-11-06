import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tracker/errors/report_error.dart';
import 'package:tracker/writes/tracker_writes.dart';

// One write the app handed the SDK and has not yet heard the end of, kept on
// the device. The SDK keeps queued writes across launches but answers only
// the launch that made them (sync_engine.cc: "Mutations restored from
// persistence won't have callbacks"), so a later launch learns a write's fate
// only by comparing the server's copy with what the write expected.
class QueuedWrite {
  QueuedWrite({
    required this.uid,
    required this.what,
    required this.collection,
    required this.id,
    required this.op,
    this.fields = const <String, Object>{},
  });

  QueuedWrite.sent(SentWrite write, {required this.uid, required this.what})
    : collection = write.collection,
      id = write.id,
      op = write.op,
      fields = write.fields;

  final String uid;
  final String what;
  final String collection;
  final String id;
  final WriteOp op;
  final Map<String, Object> fields;

  String get document => '$collection/$id';

  Map<String, Object> toJson() => <String, Object>{
    'uid': uid,
    'what': what,
    'collection': collection,
    'id': id,
    'op': op.name,
    'fields': fields,
  };

  static QueuedWrite? fromJson(Object? json) {
    if (json case {
      'uid': final String uid,
      'what': final String what,
      'collection': final String collection,
      'id': final String id,
      'op': final String op,
      'fields': final Map<String, Object?> fields,
    }) {
      final WriteOp? writeOp = WriteOp.values.asNameMap()[op];
      if (writeOp == null) {
        return null;
      }
      return QueuedWrite(
        uid: uid,
        what: what,
        collection: collection,
        id: id,
        op: writeOp,
        fields: <String, Object>{
          for (final MapEntry<String, Object?>(:key, :value) in fields.entries)
            key: ?value,
        },
      );
    }
    return null;
  }
}

/// Of [writes], all to one document and in the order they were made, those
/// the server's copy [server] (null when it holds none) shows were refused.
/// A refused create stands for the changes made after it, which were refused
/// with it. Fields in [ignoring] were set again since, which supersedes what
/// these writes set there.
List<QueuedWrite> refusedAmong(
  List<QueuedWrite> writes,
  Map<String, Object?>? server, {
  Set<String> ignoring = const <String>{},
}) {
  final int lastDelete = writes.lastIndexWhere(
    (QueuedWrite write) => write.op == WriteOp.delete,
  );
  if (lastDelete == writes.length - 1) {
    return server == null ? const <QueuedWrite>[] : <QueuedWrite>[writes.last];
  }
  final List<QueuedWrite> since = writes.sublist(lastDelete + 1);
  if (server == null) {
    return <QueuedWrite>[
      since.firstWhere(
        (QueuedWrite write) => write.op == WriteOp.create,
        orElse: () => since.last,
      ),
    ];
  }
  final Map<String, QueuedWrite> lastToSet = <String, QueuedWrite>{
    for (final QueuedWrite write in since)
      for (final String field in write.fields.keys)
        if (!ignoring.contains(field)) field: write,
  };
  return <QueuedWrite>{
    for (final MapEntry<String, QueuedWrite>(key: field, value: write)
        in lastToSet.entries)
      if (comparableValue(server[field]) != write.fields[field]) write,
  }.toList();
}

abstract interface class JournalStore {
  Future<String?> read();
  Future<void> write(String contents);
}

// One file per Firebase project, so a run against the emulators never
// touches the journal of the app on the same device.
class FileJournalStore implements JournalStore {
  const FileJournalStore(this.projectID);

  final String projectID;

  Future<File> _file() async => File(
    '${(await getApplicationSupportDirectory()).path}/'
    'queued-writes-$projectID.json',
  );

  @override
  Future<String?> read() async {
    final File file = await _file();
    return await file.exists() ? file.readAsString() : null;
  }

  // Through a rename, so a launch killed mid-write finds the old journal
  // rather than half of the new one.
  @override
  Future<void> write(String contents) async {
    final File file = await _file();
    await file.parent.create(recursive: true);
    final File next = File('${file.path}.next');
    await next.writeAsString(contents, flush: true);
    await next.rename(file.path);
  }
}

// The journal of [QueuedWrite]s. An instance is one launch: what it loads
// came from earlier launches, and what it adds has a live future that will
// report its own refusal.
class QueuedWriteJournal {
  QueuedWriteJournal(this._store);

  final JournalStore _store;
  List<QueuedWrite>? _entries;
  Future<void> _last = Future<void>.value();
  final Set<QueuedWrite> _added = Set<QueuedWrite>.identity();
  final Set<QueuedWrite> _claimed = Set<QueuedWrite>.identity();
  // For each document this launch wrote, the fields its edits set, or null
  // once it created or deleted the document.
  final Map<String, Set<String>?> _written = <String, Set<String>?>{};

  // Every read and change runs after the one before, on the loaded list.
  Future<T> _serially<T>(FutureOr<T> Function(List<QueuedWrite> entries) op) {
    final Future<T> result = _last.then(
      (_) async => op(_entries ??= await _load()),
    );
    _last = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  Future<List<QueuedWrite>> _load() async {
    try {
      final String? contents = await _store.read();
      if (contents == null) {
        return <QueuedWrite>[];
      }
      return <QueuedWrite>[
        for (final Object? json in jsonDecode(contents) as List<Object?>)
          ?QueuedWrite.fromJson(json),
      ];
    } catch (e, stack) {
      reportError(e, stack, context: 'while reading the queued-write journal');
      return <QueuedWrite>[];
    }
  }

  Future<void> _change(void Function(List<QueuedWrite> entries) change) =>
      _serially((List<QueuedWrite> entries) async {
        change(entries);
        try {
          await _store.write(
            jsonEncode(<Object>[
              for (final QueuedWrite entry in entries) entry.toJson(),
            ]),
          );
        } catch (e, stack) {
          reportError(
            e,
            stack,
            context: 'while saving the queued-write journal',
          );
        }
      });

  Future<void> add(QueuedWrite entry) {
    _added.add(entry);
    if (entry.op != WriteOp.update) {
      _written[entry.document] = null;
    } else if (_written.containsKey(entry.document)) {
      _written[entry.document]?.addAll(entry.fields.keys);
    } else {
      _written[entry.document] = <String>{...entry.fields.keys};
    }
    return _change((List<QueuedWrite> entries) => entries.add(entry));
  }

  Future<void> remove(Iterable<QueuedWrite> resolved) {
    final Set<QueuedWrite> gone = Set<QueuedWrite>.identity()..addAll(resolved);
    _claimed.removeAll(gone);
    return _change(
      (List<QueuedWrite> entries) => entries.removeWhere(gone.contains),
    );
  }

  Future<void> clear() {
    _claimed.clear();
    return _change((List<QueuedWrite> entries) => entries.clear());
  }

  /// The entries earlier launches left for [uid], grouped by document in the
  /// order they were made, and held from any other call until [remove]d or
  /// [release]d.
  Future<Map<String, List<QueuedWrite>>> claimEarlier(String uid) => _serially((
    List<QueuedWrite> entries,
  ) {
    final Map<String, List<QueuedWrite>> byDocument =
        <String, List<QueuedWrite>>{};
    for (final QueuedWrite entry in entries) {
      if (entry.uid == uid && !_added.contains(entry) && _claimed.add(entry)) {
        (byDocument[entry.document] ??= <QueuedWrite>[]).add(entry);
      }
    }
    return byDocument;
  });

  void release(Iterable<QueuedWrite> entries) => _claimed.removeAll(entries);

  /// Whether this launch has created or deleted [document]. That write's own
  /// answer then says what became of the document, and the server's copy no
  /// longer shows what became of an earlier launch's writes to it.
  bool replaced(String document) =>
      _written.containsKey(document) && _written[document] == null;

  /// The fields this launch's edits have set on [document].
  Set<String> fieldsSet(String document) =>
      _written[document] ?? const <String>{};
}

final queuedWriteJournalProvider = Provider<QueuedWriteJournal>(
  (ref) =>
      QueuedWriteJournal(FileJournalStore(Firebase.app().options.projectId)),
);
