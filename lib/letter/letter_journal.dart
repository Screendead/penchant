import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/data/day_note.dart';
import 'package:tracker/data/sealed.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/providers/insights_session.dart';

/// The entries and day notes of a period, read once for a letter's preview.
typedef LetterJournalData = ({
  List<ViceActivity> activities,
  List<DayNote> dayNotes,
});

abstract class LetterJournal {
  /// Everything logged from local midnight [start] to before [end].
  Future<LetterJournalData> read(DateTime start, DateTime end);
}

/// Null while nobody is signed in.
final letterJournalProvider = Provider<LetterJournal?>((ref) {
  final String? uid = ref.watch(insightsUidProvider);
  if (uid == null) return null;
  return FirestoreLetterJournal(uid, SealedOpener(ref.watch(sealerProvider)));
});

/// One-time reads, as Insights reads its range: the activities query is the
/// day query's shape (ownerID, createdAt range, createdAt descending), and
/// the day notes are the owner's ids between the period's first and last day,
/// ordered by id as the day note query is, so no new index is needed.
class FirestoreLetterJournal implements LetterJournal {
  FirestoreLetterJournal(this.uid, this.opener);

  final String uid;
  final SealedOpener opener;

  @override
  Future<LetterJournalData> read(DateTime start, DateTime end) async {
    final QuerySnapshot<Map<String, dynamic>> entries = await FirebaseFirestore
        .instance
        .collection('activities')
        .where('ownerID', isEqualTo: uid)
        .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('createdAt', isLessThan: Timestamp.fromDate(end))
        .orderBy('createdAt', descending: true)
        .get();
    final QuerySnapshot<Map<String, dynamic>> notes = await FirebaseFirestore
        .instance
        .collection(dayNotesCollection)
        .where('ownerID', isEqualTo: uid)
        .orderBy(FieldPath.documentId)
        .startAt(<Object>[dayNoteID(uid, dayKey(start))])
        .endAt(<Object>[dayNoteID(uid, dayKey(addDays(end, -1)))])
        .get();
    return (
      activities: await ViceActivity.openQuerySnapshot(entries, opener),
      dayNotes: <DayNote>[
        for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
            in notes.docs)
          await DayNote.open(doc, doc.data(), opener),
      ],
    );
  }
}
