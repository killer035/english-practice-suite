import Foundation

let seed = try JSONDecoder().decode(Lesson.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
precondition(seed.id == "daily-english-demo")
precondition(seed.segments.count == 2)
precondition(seed.originalSource == nil && seed.preparedAudio == nil)
precondition(seed.learningPoints?.count == 3)
let questions = Exercises.make(seed, mode: .draw)
precondition(questions.count == 2)
for question in questions {
    precondition(seed.segments.contains { $0.en == question.english && $0.zh == question.chinese })
}
let saved = SavedData(lessons: [seed])
let decoded = try JSONDecoder().decode(SavedData.self, from: JSONEncoder().encode(saved))
precondition(decoded.lessons.first?.id == seed.id)
print("PASS original seed: 2 bilingual segments, 3 points, 2 full-sentence questions, no fabricated audio, saved-data roundtrip")
