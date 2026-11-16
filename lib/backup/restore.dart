import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';
import 'package:tracker/account/account.dart';
import 'package:tracker/backup/backup_file.dart';
import 'package:tracker/crypto/journal_field_sealer.dart';
import 'package:tracker/data/category.dart';
import 'package:tracker/data/sealed.dart';
import 'package:tracker/data/updated_at.dart';

/// The collections restore can write, in the order it writes them: vices
/// first, since the rules' `ownsVice` reads the stored vice with `get()`,
/// which does not see writes in the same batch.
const List<String> restorableCollections = <String>[
  'vices',
  'activities',
  'dayNotes',
  'urges',
];

// The create rules each collection's plaintext fields must pass, beside
// `sealed` and `ownerID`.
const Map<String, List<String>> _structuralFields = <String, List<String>>{
  'vices': <String>['createdAt', 'archived'],
  'activities': <String>['viceID', 'quantity', 'createdAt', 'amount'],
  'dayNotes': <String>['day', 'createdAt'],
  'urges': <String>['viceID', 'createdAt'],
};

// Rules allow at most 20 document access calls in a batched write
// (firebase.google.com/docs/firestore/security/rules-conditions, "Access
// calls"), and do not promise that repeated get()s of one vice are cached.
// Each activity and urge create calls ownsVice() once.
const Map<String, int> _batchSize = <String, int>{
  'vices': 400,
  'activities': 20,
  'dayNotes': 400,
  'urges': 20,
};

enum SkipReason {
  /// Sealed under a journal key older than the backup's (after "Start a new
  /// journal"), so nothing can open it.
  earlierKey,

  /// Its habit is not in the backup or was itself skipped; the rules refuse an
  /// entry or urge whose habit the writer does not own.
  habitMissing,

  /// No creation time, which every create needs.
  noTime,

  /// A quantity under 1 or not whole, or an amount not above 0, which
  /// today's rules refuse on a new entry.
  badAmount,

  /// A day note whose day is not a `yyyy-MM-dd` date.
  badDay,

  /// Its content is too long for one sealed field.
  tooLong,
}

class RestoreWrite {
  const RestoreWrite(this.collection, this.id, this.data);

  final String collection;
  final String id;

  /// Without `updatedAt`: the writer adds the server time where the
  /// collection is stamped.
  final Map<String, Object> data;
}

class RestorePlan {
  const RestorePlan({
    required this.sourceUid,
    required this.destinationUid,
    required this.writes,
    required this.skipped,
    required this.trimmed,
  });

  final String sourceUid;
  final String destinationUid;

  /// In [restorableCollections] order.
  final Map<String, List<RestoreWrite>> writes;
  final Map<SkipReason, int> skipped;

  /// Documents written without fields today's rules have no place for.
  final int trimmed;

  int get total => writes.values.fold(0, (int n, List<RestoreWrite> w) {
    return n + w.length;
  });

  int count(String collection) => writes[collection]?.length ?? 0;

  Set<String> ids(String collection) => <String>{
    for (final RestoreWrite w in writes[collection] ?? const <RestoreWrite>[])
      w.id,
  };
}

sealed class RestoreRefusal implements Exception {
  const RestoreRefusal();
}

/// The backup holds a collection this build cannot write.
class UnknownCollection extends RestoreRefusal {
  const UnknownCollection(this.collection);

  final String collection;
}

/// The account holds documents that are not this backup's, from an earlier
/// run of it. [counts] is per collection.
class AccountNotEmpty extends RestoreRefusal {
  const AccountNotEmpty(this.counts);

  final Map<String, int> counts;
}

/// Firestore document ids for the restored documents: the same for every run
/// of one backup into one account, so a second run finds what the first
/// wrote. A day note's id is fixed by the rules.
String restoredID(
  String collection,
  StoredDocument doc, {
  required String sourceUid,
  required String destinationUid,
}) {
  if (collection == 'dayNotes') {
    return '${destinationUid}_${doc.data['day']}';
  }
  final List<int> digest = const DartSha256().hashSync(
    utf8.encode(
      'penchant:v1:restore-id:$sourceUid\n$collection\n${doc.id}\n'
      '$destinationUid',
    ),
  ).bytes;
  const String alphabet =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
  return String.fromCharCodes(<int>[
    for (int i = 0; i < 20; i++) alphabet.codeUnitAt(digest[i] % 62),
  ]);
}

class _Skip implements Exception {
  const _Skip(this.reason);

  final SkipReason reason;
}

final RegExp _day = RegExp(r'^[0-9]{4}-[0-9]{2}-[0-9]{2}$');

/// Opens every document of [backup] at its original path with the backup's
/// key and seals it again for its new path with [destination], the signed-in
/// account's own key. Writes nothing. Throws [UnknownCollection].
Future<RestorePlan> planRestore(
  OpenedBackup backup, {
  required String destinationUid,
  required FieldSealer destination,
  required AesGcm aes256,
  void Function(int done, int total)? onProgress,
}) async {
  for (final String collection in backup.collections.keys) {
    if (!restorableCollections.contains(collection)) {
      throw UnknownCollection(collection);
    }
  }
  final String sourceUid = backup.header.uid;
  final JournalFieldSealer source = JournalFieldSealer(
    backup.journalKey.sealer(aes256),
  );
  final Map<String, String> viceIDs = <String, String>{};
  final Map<String, List<RestoreWrite>> writes = <String, List<RestoreWrite>>{};
  final Map<SkipReason, int> skipped = <SkipReason, int>{};
  int trimmed = 0;
  final int total = backup.collections.values.fold(
    0,
    (int n, List<StoredDocument> docs) => n + docs.length,
  );
  int done = 0;

  for (final String collection in restorableCollections) {
    final List<RestoreWrite> out = writes[collection] = <RestoreWrite>[];
    for (final StoredDocument doc
        in backup.collections[collection] ?? const <StoredDocument>[]) {
      try {
        final String id = restoredID(
          collection,
          doc,
          sourceUid: sourceUid,
          destinationUid: destinationUid,
        );
        final Map<String, Object> fields = _structural(
          collection,
          doc.data,
          viceIDs,
        );
        final Map<String, Object?> content = await _content(
          collection,
          doc,
          source,
        );
        final Blob sealed = await _seal(
          destination,
          content,
          sealContext(collection, id),
        );
        final Set<String> known = <String>{
          'ownerID',
          sealedField,
          updatedAtField,
          ..._structuralFields[collection]!,
          ...?contentFields[collection],
        };
        if (doc.data.keys.any((String key) => !known.contains(key))) {
          trimmed++;
        }
        out.add(
          RestoreWrite(collection, id, <String, Object>{
            ...fields,
            'ownerID': destinationUid,
            sealedField: sealed,
          }),
        );
        if (collection == 'vices') {
          viceIDs[doc.id] = id;
        }
      } on _Skip catch (skip) {
        skipped.update(skip.reason, (int n) => n + 1, ifAbsent: () => 1);
      }
      onProgress?.call(++done, total);
    }
  }
  return RestorePlan(
    sourceUid: sourceUid,
    destinationUid: destinationUid,
    writes: writes,
    skipped: skipped,
    trimmed: trimmed,
  );
}

Map<String, Object> _structural(
  String collection,
  Map<String, dynamic> data,
  Map<String, String> viceIDs,
) {
  final Object? createdAt = data['createdAt'];
  if (createdAt is! Timestamp) {
    throw const _Skip(SkipReason.noTime);
  }
  switch (collection) {
    case 'vices':
      return <String, Object>{
        'createdAt': createdAt,
        'archived': data['archived'] == true,
      };
    case 'activities':
      final Object? quantity = data['quantity'];
      final Object? amount = data['amount'];
      if (quantity is! int || quantity < 1) {
        throw const _Skip(SkipReason.badAmount);
      }
      if (amount != null && (amount is! num || amount <= 0)) {
        throw const _Skip(SkipReason.badAmount);
      }
      return <String, Object>{
        'viceID': _vice(data, viceIDs),
        'quantity': quantity,
        'createdAt': createdAt,
        'amount': ?amount,
      };
    case 'dayNotes':
      final Object? day = data['day'];
      if (day is! String || !_day.hasMatch(day)) {
        throw const _Skip(SkipReason.badDay);
      }
      return <String, Object>{'day': day, 'createdAt': createdAt};
    case 'urges':
      return <String, Object>{
        'viceID': _vice(data, viceIDs),
        'createdAt': createdAt,
      };
  }
  throw UnknownCollection(collection);
}

String _vice(Map<String, dynamic> data, Map<String, String> viceIDs) =>
    viceIDs[data['viceID']] ?? (throw const _Skip(SkipReason.habitMissing));

// A sealed document's fields as its envelope holds them, unread and passed on
// whole, so fields this build does not know survive; a legacy plaintext one's
// content fields, with the category the first-launch migrator would guess.
Future<Map<String, Object?>> _content(
  String collection,
  StoredDocument doc,
  JournalFieldSealer source,
) async {
  final Object? envelope = doc.data[sealedField];
  if (envelope is Blob) {
    try {
      return await source.open(
        envelope.bytes,
        context: sealContext(collection, doc.id),
      );
    } on Object {
      throw const _Skip(SkipReason.earlierKey);
    }
  }
  final Object? name = doc.data['name'];
  return <String, Object?>{
    for (final String field in contentFields[collection] ?? const <String>[])
      if (doc.data.containsKey(field)) field: doc.data[field],
    if (collection == 'vices' &&
        !doc.data.containsKey('category') &&
        name is String)
      'category': guessCategory(name).name,
  };
}

Future<Blob> _seal(
  FieldSealer sealer,
  Map<String, Object?> content,
  String context,
) async {
  try {
    return Blob(await sealer.seal(content, context: context));
  } on ArgumentError {
    throw const _Skip(SkipReason.tooLong);
  } on JsonUnsupportedObjectError {
    throw const _Skip(SkipReason.tooLong);
  }
}

/// What a run will write after [existing], the ids the account already holds
/// per collection: those of an earlier, cut-short run are left as they are.
/// Throws [AccountNotEmpty] when any other document is there.
({RestorePlan plan, int alreadyThere}) checkAgainst(
  RestorePlan plan,
  Map<String, Set<String>> existing,
) {
  final Map<String, int> foreign = <String, int>{};
  for (final MapEntry<String, Set<String>>(:key, :value) in existing.entries) {
    final Set<String> mine = plan.ids(key);
    final int others = value.where((String id) => !mine.contains(id)).length;
    if (others > 0) {
      foreign[key] = others;
    }
  }
  if (foreign.isNotEmpty) {
    throw AccountNotEmpty(foreign);
  }
  int alreadyThere = 0;
  final Map<String, List<RestoreWrite>> remaining =
      <String, List<RestoreWrite>>{};
  for (final MapEntry<String, List<RestoreWrite>>(:key, :value)
      in plan.writes.entries) {
    final Set<String> there = existing[key] ?? const <String>{};
    remaining[key] = <RestoreWrite>[
      for (final RestoreWrite w in value)
        if (!there.contains(w.id)) w,
    ];
    alreadyThere += value.length - remaining[key]!.length;
  }
  return (
    plan: RestorePlan(
      sourceUid: plan.sourceUid,
      destinationUid: plan.destinationUid,
      writes: remaining,
      skipped: plan.skipped,
      trimmed: plan.trimmed,
    ),
    alreadyThere: alreadyThere,
  );
}

abstract interface class RestoreTarget {
  /// From the server: the ids of [uid]'s documents in [collection].
  Future<Set<String>> ownedIDs(String collection, String uid);

  /// One atomic batch of creates.
  Future<void> commit(List<RestoreWrite> writes);
}

class FirestoreRestoreTarget implements RestoreTarget {
  FirestoreRestoreTarget(this._firestore);

  final FirebaseFirestore _firestore;

  // A batch the server has not acknowledged by then is reported as cut
  // short; it may still land, and a second run then finds it there.
  static const Duration commitTimeout = Duration(seconds: 60);

  // The export's query shape: ownerID equality ordered by document id, served
  // by the automatic single-field index.
  @override
  Future<Set<String>> ownedIDs(String collection, String uid) async {
    final Set<String> ids = <String>{};
    Query<Map<String, dynamic>> page = _firestore
        .collection(collection)
        .where('ownerID', isEqualTo: uid)
        .orderBy(FieldPath.documentId)
        .limit(Account.pageSize);
    while (true) {
      final QuerySnapshot<Map<String, dynamic>> snapshot = await page.get(
        const GetOptions(source: Source.server),
      );
      ids.addAll(snapshot.docs.map((doc) => doc.id));
      if (snapshot.docs.length < Account.pageSize) {
        return ids;
      }
      page = page.startAfterDocument(snapshot.docs.last);
    }
  }

  @override
  Future<void> commit(List<RestoreWrite> writes) {
    final WriteBatch batch = _firestore.batch();
    for (final RestoreWrite w in writes) {
      batch.set(_firestore.collection(w.collection).doc(w.id), <String, Object>{
        ...w.data,
        if (stampedCollections.contains(w.collection)) ...updatedNow,
      });
    }
    return batch.commit().timeout(commitTimeout);
  }
}

class RestoreResult {
  const RestoreResult({
    required this.written,
    required this.alreadyThere,
    required this.skipped,
    required this.trimmed,
    required this.planned,
    this.stoppedBy,
  });

  /// Per collection, by this run.
  final Map<String, int> written;
  final int alreadyThere;
  final Map<SkipReason, int> skipped;
  final int trimmed;

  /// What this run set out to write.
  final int planned;

  /// Why it stopped before the end; null once everything is written.
  final Object? stoppedBy;

  int get writtenTotal => written.values.fold(0, (int a, int b) => a + b);
}

/// Reads what [plan]'s account holds, refuses unless it is empty or holds only
/// an earlier run of this plan, then writes the rest in batches. Throws
/// [AccountNotEmpty] before writing anything; a failed batch stops the run and
/// is reported in the result.
Future<RestoreResult> runRestore(
  RestorePlan plan,
  RestoreTarget target, {
  void Function(int written, int total)? onProgress,
}) async {
  final ({RestorePlan plan, int alreadyThere}) checked = checkAgainst(
    plan,
    await existingIDs(target, plan.destinationUid),
  );
  return writePlan(
    checked.plan,
    target,
    alreadyThere: checked.alreadyThere,
    onProgress: onProgress,
  );
}

Future<Map<String, Set<String>>> existingIDs(
  RestoreTarget target,
  String uid,
) async => <String, Set<String>>{
  for (final String collection in Account.ownedCollections)
    collection: await target.ownedIDs(collection, uid),
};

/// Writes [plan] as checked by [checkAgainst].
Future<RestoreResult> writePlan(
  RestorePlan plan,
  RestoreTarget target, {
  required int alreadyThere,
  void Function(int written, int total)? onProgress,
}) async {
  final Map<String, int> written = <String, int>{};
  final int total = plan.total;
  int done = 0;
  Object? stoppedBy;
  outer:
  for (final String collection in restorableCollections) {
    final List<RestoreWrite> all =
        plan.writes[collection] ?? const <RestoreWrite>[];
    final int size = _batchSize[collection]!;
    for (int start = 0; start < all.length; start += size) {
      final List<RestoreWrite> batch = all.sublist(
        start,
        start + size > all.length ? all.length : start + size,
      );
      try {
        await target.commit(batch);
      } on Object catch (e) {
        stoppedBy = e;
        break outer;
      }
      written.update(
        collection,
        (int n) => n + batch.length,
        ifAbsent: () => batch.length,
      );
      done += batch.length;
      onProgress?.call(done, total);
    }
  }
  return RestoreResult(
    written: written,
    alreadyThere: alreadyThere,
    skipped: plan.skipped,
    trimmed: plan.trimmed,
    planned: total,
    stoppedBy: stoppedBy,
  );
}
