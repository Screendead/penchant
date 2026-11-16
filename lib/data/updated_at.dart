import 'package:cloud_firestore/cloud_firestore.dart';

// The server's time of a document's last write, for the delta read
// (lib/providers/journal_read.dart). Plaintext, never content: it says only
// when an entry changed, which `createdAt` and the sync already show. Builds
// before it do not stamp, so it is optional and a document may lack it. A
// pending write holds an unresolved timestamp, so it is read only from the
// server, never parsed into a model.
const String updatedAtField = 'updatedAt';

const Set<String> stampedCollections = <String>{'activities', 'dayNotes'};

Map<String, Object> get updatedNow => <String, Object>{
  updatedAtField: FieldValue.serverTimestamp(),
};
