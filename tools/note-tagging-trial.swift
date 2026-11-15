// Asks Apple's on-device model to tag made-up journal notes with the starter
// trigger tree, and prints each note's tags, time and any refusal.
// Run: swift tools/note-tagging-trial.swift   (macOS 26+, Apple Intelligence on)
import Foundation
import FoundationModels

let tags = """
social/friends With friends; social/party Party or event; social/date Date; social/family Family; \
social/offered Offered one; social/alone On my own; feeling/stressed Stressed; feeling/bored Bored; \
feeling/low Low; feeling/anxious Anxious; feeling/lonely Lonely; feeling/happy Happy; \
feeling/restless Restless; work/meeting Meeting; work/deadline Deadline; work/break On a break; \
work/done Finished for the day; work/hard-talk Hard conversation; work/long-day Long day; \
body/tired Tired; body/hungry Hungry; body/pain In pain; body/exercise After exercise; \
body/unwell Unwell; routine/morning Morning; routine/meal With a meal; routine/wind-down Winding down; \
routine/weekend Weekend; routine/habit Out of habit; place/home Home; place/bar Bar or restaurant; \
place/commute Commute; place/travelling Travelling; place/outdoors Outdoors; craving/saw Saw it; \
craving/smelled Smelled it; craving/others Someone else had one; craving/feed Ad or feed; \
craving/wanted Just wanted it
"""
let known = Set(tags.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces).split(separator: " ")[0] }.map(String.init))

let notes = [
  "Rough one. Got out of the quarterly review at six, boss tore into the roadmap, went straight to the pub with Sam and stayed till close.",
  "Had a cigarette on the balcony after dinner, nothing going on really, just what I do.",
  "Couldn't sleep, back was killing me, smoked a joint to take the edge off.",
  "Sarah's wedding. Open bar, everyone was at it, lost count after the speeches.",
  "Third coffee before ten because the baby was up all night.",
  "Scrolling in bed, saw an ad for that gin, ordered a bottle and opened the old one.",
  "Flight delayed four hours, sat in the airport bar on my own.",
  "Deadline Friday. Vaped at my desk all afternoon without noticing.",
  "Nothing unusual. Sunday roast at mum's, a couple of glasses of red.",
  "Argument with Alex about money, then drank most of a bottle of wine on the sofa.",
  "Did a line at Tom's birthday because it was going round, regret it.",
  "Ran 10k this morning, beer in the garden after, felt earned.",
]

let instructions = """
Tag a private journal note about a habit with what set it off. Answer with one to four ids from this list, \
separated by commas, and nothing else (id then meaning): \(tags)
"""

guard case .available = SystemLanguageModel.default.availability else {
  print("model unavailable: \(SystemLanguageModel.default.availability)")
  exit(1)
}

var times: [Double] = []
for note in notes {
  let session = LanguageModelSession(instructions: instructions)
  let start = Date()
  do {
    let text = try await session.respond(to: note).content
    let took = Date().timeIntervalSince(start)
    times.append(took)
    let out = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    let bad = out.filter { !known.contains($0) }
    print(String(format: "%.1fs", took), out, bad.isEmpty ? "" : "NOT IN LIST: \(bad)")
  } catch {
    print(String(format: "%.1fs", Date().timeIntervalSince(start)), "FAILED", error)
  }
  print("   ", note)
}
let sorted = times.sorted()
print("answered \(times.count)/\(notes.count)",
      sorted.isEmpty ? "" : String(format: "median %.1fs max %.1fs", sorted[sorted.count / 2], sorted[sorted.count - 1]))
