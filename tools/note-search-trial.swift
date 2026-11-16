// Scores note search over made-up journal notes: how often an expected note is
// in the top 3 by Apple's sentence embedding alone, by words alone, and by the
// two combined as lib/notes/note_search.dart combines them.
// Run: swift tools/note-search-trial.swift   (macOS 11+)
import Foundation
import NaturalLanguage

// Index order is age: a later note is more recent, as the app ranks ties.
let notes: [String] = [
  /* 0 */ "Sarah's wedding. Open bar, everyone was at it, lost count after the speeches.",
  /* 1 */ "Rehearsal dinner for the wedding, kept it to two glasses.",
  /* 2 */ "Boss tore into the roadmap in the quarterly review, went to the pub after.",
  /* 3 */ "Horrible day at the office, the client called three times shouting.",
  /* 4 */ "Third coffee before ten because the baby was up all night.",
  /* 5 */ "Couldn't sleep, back was killing me, smoked to take the edge off.",
  /* 6 */ "Flight delayed four hours, sat in the airport bar on my own.",
  /* 7 */ "Sunday roast at mum's, a couple of glasses of red.",
  /* 8 */ "Argument with Alex about money, then most of a bottle on the sofa.",
  /* 9 */ "Ran 10k this morning, beer in the garden after, felt earned.",
  /* 10 */ "Got laid off today. Didn't see it coming.",
  /* 11 */ "Team drinks to celebrate the launch, stayed later than planned.",
  /* 12 */ "Stuck in traffic for two hours on the M25, smoked half a pack.",
  /* 13 */ "Grandad's funeral. Everyone went back to the house afterwards.",
  /* 14 */ "Christmas Eve with the cousins, mulled wine all afternoon.",
  /* 15 */ "Lonely evening, nobody answered the group chat.",
  /* 16 */ "Payday, treated myself to a takeaway and a film.",
  /* 17 */ "Deadline Friday, vaped at my desk all afternoon without noticing.",
  /* 18 */ "Dentist this morning, tooth still aching, no appetite.",
  /* 19 */ "Beach day in Brighton, ice cream and cider in the sun.",
  /* 20 */ "Exam results came through, passed everything.",
  /* 21 */ "Hangover from Saturday, stayed in bed scrolling till three.",
  /* 22 */ "Date with Jamie went well, shared a bottle of prosecco.",
  /* 23 */ "Panic attack on the tube, had to get off two stops early.",
  /* 24 */ "Moved flat today, boxes everywhere, pizza on the floor.",
  /* 25 */ "My manager rejected the proposal in front of everyone. Humiliating.",
  /* 26 */ "Rainy Tuesday, nothing happened, bored out of my mind.",
  /* 27 */ "Birthday party for Tom, someone brought shots.",
  /* 28 */ "Hospital visit for dad, waiting room for six hours.",
  /* 29 */ "Night shift again, energy drinks to stay awake.",
  /* 30 */ "Stag do in Prague, lost track of everything.",
  /* 31 */ "Quiet night in with a book, one cup of tea.",
  /* 32 */ "Performance review went badly, told I'm not meeting expectations.",
  /* 33 */ "Gym session then a protein shake, felt strong.",
  /* 34 */ "Kids were sick all week, barely slept.",
  /* 35 */ "Holiday in Spain, sangria by the pool every afternoon.",
  /* 36 */ "Football final at the pub, we lost on penalties.",
  /* 37 */ "Long call with my sister about mum's diagnosis.",
  /* 38 */ "Worked from home, snacked all day out of boredom.",
  /* 39 */ "Office party, the CEO gave a speech, free bar till nine.",
  /* 40 */ "Missed the train, late for the meeting, frazzled all morning.",
  /* 41 */ "Cooked a proper dinner for friends, wine with the meal.",
  /* 42 */ "Breakup. She moved out this morning.",
  /* 43 */ "Coworker took credit for my work again, so angry I couldn't focus.",
  /* 44 */ "Walked by the river, didn't feel like smoking at all.",
  /* 45 */ "Job interview went well, celebrated with a pint.",
  /* 46 */ "Insomnia again, up at four with my phone.",
  /* 47 */ "Bride's speech had everyone in tears, champagne toast, danced till midnight.",
  /* 48 */ "Festival weekend, music and cans all day.",
  /* 49 */ "Car broke down on the motorway, waited for the recovery truck.",
  /* 50 */ "Budget meeting overran, everyone shouting, came home exhausted and drank.",
  /* 51 */ "Lazy Sunday, brunch with mimosas.",
  /* 52 */ "My cat died this morning. Can't stop crying.",
  /* 53 */ "Promotion came through at work, drinks on me.",
  /* 54 */ "Neighbours partying till 3am, couldn't sleep.",
  /* 55 */ "Overtime till nine, the whole project is falling apart.",
  /* 56 */ "Anniversary dinner, fancy restaurant, wine pairing.",
  /* 57 */ "Snowed in, nowhere to go, three coffees by noon.",
  /* 58 */ "Felt anxious before the presentation, smoked outside first.",
  /* 59 */ "Reunion with uni friends, just like old times.",
]

// Expected notes per query; the first group is answered by wording, the
// second only by meaning.
let queries: [(String, [Int])] = [
  ("the wedding", [0, 1, 47]),
  ("airport", [6]),
  ("funeral", [13]),
  ("coffee", [4, 57]),
  ("pub", [2, 36]),
  ("couldn't sleep", [5, 54, 46]),
  ("panic", [23]),
  ("when work was awful", [3, 25, 32, 43, 50, 55, 2]),
  ("grief and loss", [13, 52, 42, 37]),
  ("celebrating good news", [20, 45, 53, 11]),
  ("feeling alone", [15, 6, 42]),
  ("travel abroad", [30, 35, 6]),
  ("tired from no sleep", [34, 46, 29, 4, 54, 5]),
  ("money worries", [8, 10]),
  ("romantic evening", [22, 56]),
]

// Mirrors lib/notes/note_search.dart's word side.
let stopWords: Set<String> = [
  "a", "an", "and", "the", "of", "to", "in", "on", "at", "for", "with", "by", "from", "about", "as", "is",
  "was", "were", "be", "been", "am", "are", "it", "its", "i", "me", "my", "we", "our", "you", "your", "he",
  "she", "they", "them", "this", "that", "these", "those", "when", "what", "where", "who", "how", "why",
  "then", "than", "so", "or", "but", "if", "not", "no", "do", "did", "had", "has", "have", "just", "very",
]

func fold(_ s: String) -> String {
  s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    .replacingOccurrences(of: "\u{2019}", with: "'")
}

func words(_ s: String) -> [String] {
  fold(s).split(whereSeparator: { !($0.isLetter || $0.isNumber || $0 == "'") })
    .map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: "'")) }
    .filter { !$0.isEmpty }
}

func queryWords(_ q: String) -> [String] {
  let all = words(q)
  let kept = all.filter { !stopWords.contains($0) }
  return kept.isEmpty ? all : kept
}

func matches(_ q: String, _ w: String) -> Bool { q.count >= 3 ? w.hasPrefix(q) : w == q }

// 0 none, 1 some words, 2 all words, 3 the whole query as written.
func wordTier(_ query: String, _ note: String) -> (Int, Double) {
  let qs = queryWords(query)
  if qs.isEmpty { return (0, 0) }
  let ws = words(note)
  let hit = qs.filter { q in ws.contains { matches(q, $0) } }.count
  if hit == 0 { return (0, 0) }
  if fold(note).contains(fold(query).trimmingCharacters(in: .whitespaces)) { return (3, 1) }
  return (hit == qs.count ? 2 : 1, Double(hit) / Double(qs.count))
}

func cosine(_ a: [Double], _ b: [Double]) -> Double {
  var dot = 0.0, na = 0.0, nb = 0.0
  for i in 0..<a.count { dot += a[i] * b[i]; na += a[i] * a[i]; nb += b[i] * b[i] }
  return na == 0 || nb == 0 ? 0 : dot / (na.squareRoot() * nb.squareRoot())
}

guard let embedding = NLEmbedding.sentenceEmbedding(for: .english) else {
  print("no English sentence embedding on this system")
  exit(1)
}
print("English sentence embedding: dimension \(embedding.dimension), revision \(embedding.revision)")
let languages: [NLLanguage] = [
  .english, .french, .german, .spanish, .italian, .portuguese, .dutch, .simplifiedChinese, .japanese, .korean,
  .russian, .swedish, .danish, .norwegian, .finnish, .polish, .turkish, .arabic,
]
print("sentence embeddings here for:", languages.filter { NLEmbedding.sentenceEmbedding(for: $0) != nil }.map(\.rawValue).joined(separator: " "))

let start = Date()
let noteVectors = notes.map { embedding.vector(for: $0) ?? [] }
print(String(format: "embedded %d notes in %.2fs", notes.count, Date().timeIntervalSince(start)))

// The combined rank's constants, as in lib/notes/note_search.dart.
let meaningFloor = 0.40
let shown = 3

struct Scored { let note: Int; let tier: Int; let score: Double }

func ordered(_ a: Scored, _ b: Scored) -> Bool {
  if a.tier != b.tier { return a.tier > b.tier }
  if a.score != b.score { return a.score > b.score }
  return a.note > b.note
}

func rankWords(_ q: String) -> [Int] {
  let scored: [Scored] = notes.indices.map { i in
    let (tier, share) = wordTier(q, notes[i])
    return Scored(note: i, tier: tier, score: share)
  }
  return scored.filter { $0.tier > 0 }.sorted(by: ordered).map(\.note)
}

func similarities(_ q: String) -> [Double] {
  guard let qv = embedding.vector(for: q) else { return notes.map { _ in 0 } }
  return noteVectors.map { $0.isEmpty ? 0 : cosine(qv, $0) }
}

func rankMeaning(_ q: String) -> [Int] {
  let s = similarities(q)
  return notes.indices.sorted { s[$0] > s[$1] }
}

func relativeSimilarities(_ q: String) -> [Double] {
  let s = similarities(q)
  let sorted = s.sorted()
  let median = sorted[sorted.count / 2]
  let top = sorted.last ?? 0
  return s.map { top > median ? ($0 - median) / (top - median) : 0 }
}

// All words first (whole query, then all words); below them, some words and
// meaning share one score; a note matching no word shows only above the floor.
func rankCombined(_ q: String) -> [Int] {
  let rel = relativeSimilarities(q)
  let sims = similarities(q)
  var scored: [Scored] = []
  for i in notes.indices {
    let (tier, share) = wordTier(q, notes[i])
    if tier > 0 {
      scored.append(Scored(note: i, tier: tier, score: share + 0.01 * rel[i]))
    } else if sims[i] >= meaningFloor {
      scored.append(Scored(note: i, tier: 0, score: sims[i]))
    }
  }
  return scored.sorted(by: ordered).map(\.note)
}

func hits(_ ranked: [Int], _ expected: [Int]) -> Int { ranked.prefix(shown).filter(expected.contains).count }

// Meaning-only results above the floor, anywhere in the list: how many were
// expected notes.
var meaningShown = 0, meaningRight = 0
for (q, expected) in queries {
  let sims = similarities(q)
  for i in notes.indices where wordTier(q, notes[i]).0 == 0 && sims[i] >= meaningFloor {
    meaningShown += 1
    if expected.contains(i) { meaningRight += 1 }
  }
}

var totals: [String: (any: Int, found: Int, possible: Int)] = [:]
for (q, expected) in queries {
  var line = "\(q):"
  for (name, rank) in [("words", rankWords), ("meaning", rankMeaning), ("combined", rankCombined)] {
    let r = rank(q)
    let h = hits(r, expected)
    let t = totals[name] ?? (0, 0, 0)
    totals[name] = (t.any + (h > 0 ? 1 : 0), t.found + h, t.possible + min(shown, expected.count))
    if name == "meaning" { let s = similarities(q); line += " [" + r.prefix(shown).map { String(format: "%.2f", s[$0]) }.joined(separator: " ") + "]" }
    line += "  \(name) \(h)/\(min(shown, expected.count)) \(r.prefix(shown).map(String.init).joined(separator: ","))"
  }
  print(line)
}
print("")
for name in ["words", "meaning", "combined"] {
  let t = totals[name]!
  print(String(format: "%-9@ an expected note in the top %d for %2d of %d queries; %2d of %d top-%d places filled by expected notes",
               name as NSString, shown, t.any, queries.count, t.found, t.possible, shown))
}
print("meaning-only results above the floor \(meaningFloor): \(meaningRight) of \(meaningShown) were expected notes")
