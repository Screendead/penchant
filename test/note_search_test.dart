import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/day_note.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/notes/follow_up.dart';
import 'package:tracker/notes/note_meaning.dart';
import 'package:tracker/notes/note_search.dart';

import 'fakes.dart';

SearchableNote _note(String key, String text, DateTime at) => SearchableNote(
  key: key,
  source: NoteSource.entry,
  text: text,
  at: at,
  day: DateTime(at.year, at.month, at.day),
  route: '/vices/v/activities/$key',
  viceID: 'v',
);

List<IndexedNote> _index(List<SearchableNote> notes) => <IndexedNote>[
  for (final SearchableNote n in notes) IndexedNote(n),
];

String _marked(NoteMatch m) {
  final StringBuffer out = StringBuffer();
  int at = 0;
  for (final (int s, int e) in m.highlights) {
    out
      ..write(m.note.text.substring(at, s))
      ..write('[')
      ..write(m.note.text.substring(s, e))
      ..write(']');
    at = e;
  }
  return (out..write(m.note.text.substring(at))).toString();
}

class _FakeEmbedder implements SentenceEmbedder {
  final List<List<String>> calls = <List<String>>[];

  @override
  Future<bool> available() async => true;

  @override
  Future<List<Float32List?>> embed(List<String> texts) async {
    calls.add(texts);
    return <Float32List?>[
      for (final String t in texts)
        Float32List.fromList(<double>[
          t.contains('awful') || t.contains('shouting') ? 1 : 0,
          t.contains('beach') ? 1 : 0,
          1,
        ]),
    ];
  }
}

void main() {
  final DateTime old = DateTime(2026, 3, 1, 20);
  final DateTime recent = DateTime(2026, 11, 10, 21);

  test('folds case and diacritics, keeping the original spans', () {
    expect(foldText('Café CRÈME Straße'), 'cafe creme strasse');
    // A decomposed accent and a curly apostrophe.
    expect(foldText('Café couldn’t'), "cafe couldn't");
    final FoldedText f = FoldedText('Café bar');
    expect(f.original(0, 4), (0, 5));
    final FoldedText ss = FoldedText('Straße x');
    expect(ss.original(4, 6), (4, 5));
  });

  test('drops stop words unless the query is nothing else', () {
    expect(queryWords('when work was AWFUL'), <String>['work', 'awful']);
    expect(queryWords('the'), <String>['the']);
    expect(queryWords('  '), isEmpty);
  });

  test('ranks every word (or the phrase), then some, recent first', () {
    final List<IndexedNote> index = _index(<SearchableNote>[
      _note('some-old', 'Work again', old),
      _note('all-old', 'Awful, the work today', old),
      _note('phrase', 'Lunch: work awful as ever', old),
      _note('all-new', 'The work was awful', recent),
      _note('some-new', 'Awful weather', recent),
      _note('none', 'Beach day', recent),
    ]);
    final List<NoteMatch> found = searchNotes(index, 'work awful');
    expect(found.map((NoteMatch m) => m.note.key), <String>[
      'all-new',
      'all-old',
      'phrase',
      'some-new',
      'some-old',
    ]);
    expect(found.map((NoteMatch m) => m.tier), <MatchTier>[
      MatchTier.allWords,
      MatchTier.allWords,
      MatchTier.phrase,
      MatchTier.someWords,
      MatchTier.someWords,
    ]);
  });

  test('matches across accents and case, and highlights the original', () {
    final List<IndexedNote> index = _index(<SearchableNote>[
      _note('a', 'Coffee at the CAFÉ before the wedding', recent),
    ]);
    expect(
      _marked(searchNotes(index, 'cafe').single),
      'Coffee at the [CAFÉ] before the wedding',
    );
    expect(
      _marked(searchNotes(index, 'the wedding').single),
      'Coffee at the CAFÉ before [the wedding]',
    );
    // A word of three letters or more finds longer words it begins.
    expect(
      _marked(searchNotes(index, 'wed').single),
      'Coffee at the CAFÉ before the [wedding]',
    );
    // Shorter ones only match whole.
    expect(searchNotes(index, 'co'), isEmpty);
  });

  test('highlights a decomposed accent whole', () {
    final List<IndexedNote> index = _index(<SearchableNote>[
      _note('a', 'Rosé by the river', recent),
    ]);
    expect(_marked(searchNotes(index, 'ROSÉ').single), '[Rosé] by the river');
  });

  test('meaning-only notes follow every word match, above the floor', () {
    final List<IndexedNote> index = _index(<SearchableNote>[
      _note('word', 'A meeting, nothing more', old),
      _note('close', 'Everyone shouting', recent),
      _note('loose', 'Quiet night in', recent),
    ]);
    final List<NoteMatch> found = searchNotes(
      index,
      'meeting',
      similarities: <String, double>{
        // Closer in meaning than the word match, and still placed after it.
        'word': 0.2,
        'close': 0.9,
        'loose': meaningFloor - 0.01,
      },
    );
    expect(found.map((NoteMatch m) => m.note.key), <String>['word', 'close']);
    expect(found.last.tier, MatchTier.meaning);
  });

  test('gathers notes, answers and day notes, counting locked ones', () {
    final DateTime at = DateTime(2026, 11, 3, 22, 15);
    final NoteCorpus corpus = noteCorpus(
      <ViceActivity>[
        ViceActivity(
          id: 'e1',
          viceID: 'wine',
          quantity: 1,
          ownerID: ownerID,
          createdAt: Timestamp.fromDate(at),
          note: ' After the wedding ',
          followUp: const FollowUp(
            question: 'What made it a big night?',
            answer: 'Open bar',
          ),
        ),
        ViceActivity(
          id: 'e2',
          viceID: 'wine',
          quantity: 1,
          ownerID: ownerID,
          createdAt: Timestamp.fromDate(at),
          locked: true,
        ),
        fakeActivity('wine', 2, at),
      ],
      <DayNote>[
        DayNote(
          id: 'd1',
          ownerID: ownerID,
          day: '2026-11-02',
          createdAt: Timestamp.fromDate(at),
          text: 'Long day',
        ),
        DayNote(
          id: 'd2',
          ownerID: ownerID,
          day: '',
          createdAt: Timestamp.fromDate(at),
          text: 'No day',
        ),
        DayNote(
          id: 'd3',
          ownerID: ownerID,
          day: '2026-11-01',
          createdAt: Timestamp.fromDate(at),
          locked: true,
        ),
      ],
    );
    expect(corpus.locked, 2);
    expect(
      corpus.notes.map((SearchableNote n) => (n.key, n.text, n.route)),
      <(String, String, String)>[
        ('a/e1/note', 'After the wedding', '/vices/wine/activities/e1'),
        ('a/e1/answer', 'Open bar', '/vices/wine/activities/e1'),
        ('d/d1/note', 'Long day', '/day-notes/2026-11-02'),
      ],
    );
    expect(corpus.notes[1].question, 'What made it a big night?');
    expect(corpus.notes[2].day, DateTime(2026, 11, 2));
  });

  test('the meaning index embeds each note once, in batches', () async {
    final _FakeEmbedder embedder = _FakeEmbedder();
    final MeaningIndex index = MeaningIndex(embedder);
    final List<SearchableNote> notes = <SearchableNote>[
      for (int i = 0; i < MeaningIndex.batchSize + 1; i++)
        _note('n$i', i == 0 ? 'everyone shouting' : 'beach $i', recent),
    ];
    final Map<String, double> first = await index.similarities('awful', notes);
    // Two batches of notes, then the query.
    expect(embedder.calls.map((List<String> c) => c.length), <int>[
      MeaningIndex.batchSize,
      1,
      1,
    ]);
    expect(first['n0']!, greaterThan(first['n1']!));
    await index.similarities('beach', notes);
    expect(embedder.calls.length, 4);
  });
}
