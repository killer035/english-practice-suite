import Foundation

struct Segment: Codable, Identifiable {
    var id: String
    var title: String
    var en: String
    var zh: String
    var original: String
    var prompt: String
    var promptZh: String
    var sample: String
}
struct Lesson: Codable, Identifiable {
    var id: String
    var title: String
    var subtitle: String
    var source: String
    var segments: [Segment]
    var phrases: [[String]]
    var learningPoints: [LearningPoint]? = nil
    var sentenceBank: [SentencePair]? = nil
    var originalSource: OriginalSource? = nil
    var preparedAudio: PreparedAudio? = nil
}
struct PracticeRecord: Codable, Identifiable {
    var id: String
    var lessonID: String
    var lessonTitle: String
    var questionID: String
    var question: String
    var mode: String
    var date: Date
    var file: String
}
struct SavedData: Codable {
    var lessons: [Lesson]
    var records: [PracticeRecord] = []
    var favorites: Set<String> = []
    var completed: Set<String> = []
}
struct Exercise: Identifiable {
    var id: String
    var chinese: String
    var english: String
    var hint: String
}
enum PracticeMode: String, CaseIterable, Identifiable {
    case read = "原文阅读", draw = "随机抽题", topic = "话题拓展"
    var id: String { rawValue }
    var icon: String {
        switch self { case .read: return "text.book.closed"; case .draw: return "shuffle"; case .topic: return "bubble.left.and.bubble.right" }
    }
}
enum Exercises {
    static func make(_ lesson: Lesson, mode: PracticeMode) -> [Exercise] {
        if mode == .topic {
            return lesson.segments.map { Exercise(id: "topic-\($0.id)", chinese: $0.promptZh, english: $0.prompt, hint: $0.sample) }
        }
        if mode == .draw {
            var seen: Set<String> = []
            return (lesson.learningPoints ?? []).compactMap { point in
                guard let en = point.sentenceEn, let zh = point.sentenceZh,
                      !en.isEmpty, !zh.isEmpty, seen.insert(en.lowercased()).inserted else { return nil }
                let covered = (lesson.learningPoints ?? []).filter { $0.sentenceEn == en }.map(\.term).joined(separator: " · ")
                return Exercise(id: "core-" + point.id, chinese: zh, english: en, hint: "本句巩固：" + covered + (point.note.isEmpty ? "" : "\n" + point.note))
            }
        }
        return lesson.segments.map { Exercise(id: $0.id, chinese: $0.zh, english: $0.en, hint: "先说主要意思，再补充细节。可以使用自己的表达。") }
    }

    static func parse(title: String, chinese: String, english: String) throws -> Lesson {
        func split(_ text: String) -> [String] {
            text.replacingOccurrences(of: "\r\n", with: "\n")
                .components(separatedBy: "\n\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        }
        let zh = split(chinese), en = split(english)
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NSError(domain: "Import", code: 1, userInfo: [NSLocalizedDescriptionKey: "请填写文稿标题。"])
        }
        guard !zh.isEmpty, !en.isEmpty, zh.count == en.count else {
            throw NSError(domain: "Import", code: 2, userInfo: [NSLocalizedDescriptionKey: "当前识别到中文 \(zh.count) 段、英文 \(en.count) 段，尚未一一对应。请按意思合并或拆分段落：空行分隔不同段，同一段内部可直接换行。"])
        }
        let segments = zip(zh, en).enumerated().map { index, pair in
            Segment(id: UUID().uuidString, title: "第 \(index + 1) 段", en: pair.1, zh: pair.0, original: pair.1,
                    prompt: "What do you think about this idea? Give an example from your own experience.",
                    promptZh: "读过下面这段内容后，你赞同其中的观点吗？请用英语说明理由，并举一个自己的例子。\n\n\(pair.0)", sample: "I think … because … For example, …")
        }
        return Lesson(id: UUID().uuidString, title: title, subtitle: "我的双语文稿", source: "本人粘贴导入；请核对分段和译文", segments: segments, phrases: [])
    }
}

// Keep recordings as an independent history; remove only the selected lesson's study state.
extension SavedData {
    mutating func removeLesson(id: String) {
        lessons.removeAll { $0.id == id }
        favorites = favorites.filter { !$0.hasPrefix(id + ":") }
        completed = completed.filter { !$0.hasPrefix(id + ":") }
    }
}

struct SentencePair: Codable {
    var en: String
    var zh: String
}
struct LearningPoint: Codable, Identifiable {
    var id: String
    var category: String
    var term: String
    var meaning: String
    var sentenceEn: String?
    var sentenceZh: String?
    var note: String = ""
    var matchStatus: String? = nil
}
enum CoreStudy {
    static func normalized(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: "\\[[^\\]]*\\]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "/[^/]+/", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
            .split(separator: " ").joined(separator: " ")
    }
    static func tokens(_ text: String) -> [String] {
        let irregular = ["putting":"put", "making":"make", "made":"make", "taking":"take", "took":"take", "taken":"take", "became":"become", "becoming":"become", "building":"build", "built":"build", "moving":"move", "moved":"move", "managing":"manage", "managed":"manage", "people":"person", "deliverables":"delivery", "deliverable":"delivery", "deliveries":"delivery", "belongs":"belong"]
        return normalized(text).split(separator: " ").map { token in
            let t = String(token)
            if let value = irregular[t] { return value }
            if t.count > 4 && t.hasSuffix("ies") { return String(t.dropLast(3)) + "y" }
            if t.count > 5 && t.hasSuffix("ing") { return String(t.dropLast(3)) }
            if t.count > 4 && t.hasSuffix("ed") { return String(t.dropLast(2)) }
            if t.count > 3 && t.hasSuffix("s") && !t.hasSuffix("ss") { return String(t.dropLast()) }
            return t
        }
    }
    static func containsTerm(_ sentence: String, term: String) -> Bool {
        let raw = term.components(separatedBy: "/").first ?? term
        let placeholders: Set<String> = ["someone", "somebody", "one", "s"]
        let wanted = tokens(raw).filter { !placeholders.contains($0) }
        let actual = tokens(sentence)
        guard !wanted.isEmpty else { return false }
        for start in actual.indices where actual[start] == wanted[0] {
            var cursor = start + 1
            var matched = true
            for word in wanted.dropFirst() {
                let end = min(actual.count, cursor + 4)
                guard cursor < end, let found = actual[cursor..<end].firstIndex(of: word) else { matched = false; break }
                cursor = found + 1
            }
            if matched { return true }
        }
        return false
    }
    static func sourceSentences(_ source: String) -> [String] {
        let clean = source.replacingOccurrences(of: "\\[[^\\]]*\\]", with: "", options: .regularExpression)
        let expression = try! NSRegularExpression(pattern: "[^.!?\\n]+(?:[.!?]+|$)", options: [.anchorsMatchLines])
        return expression.matches(in: clean, range: NSRange(clean.startIndex..., in: clean)).compactMap {
            guard let range = Range($0.range, in: clean) else { return nil }
            let sentence = String(clean[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            return tokens(sentence).count >= 4 ? sentence : nil
        }
    }
    static func bundled() -> Lesson? {
        guard let url = Bundle.main.url(forResource: "lesson", withExtension: "json"), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Lesson.self, from: data)
    }
    static func attach(_ points: [LearningPoint], source: String, bank: [SentencePair], paragraphs: [SentencePair] = []) -> [LearningPoint] {
        let explicit = points.compactMap { p -> SentencePair? in
            guard p.matchStatus != "已关联原文中英段落，按整段练习。", let en = p.sentenceEn, let zh = p.sentenceZh, !en.isEmpty, !zh.isEmpty else { return nil }
            return SentencePair(en: en, zh: zh)
        }
        let sentences = sourceSentences(source)
        let sourceWords = Set(tokens(source))
        let verifiedBank = bank.filter { pair in
            // Source guard: most words in this example must occur in a single source sentence.
            let words = Set(tokens(pair.en))
            guard !words.isEmpty, Double(words.intersection(sourceWords).count) / Double(words.count) >= 0.85 else { return false }
            return sentences.contains { Double(words.intersection(Set(tokens($0))).count) / Double(words.count) >= 0.85 }
        }
        return points.map { point in
            var p = point
            if p.matchStatus != "已关联原文中英段落，按整段练习。", let en = p.sentenceEn, let zh = p.sentenceZh, !en.isEmpty, !zh.isEmpty { return p }
            if let pair = (explicit + verifiedBank).first(where: { containsTerm($0.en, term: p.term) }) {
                p.sentenceEn = pair.en; p.sentenceZh = pair.zh; p.matchStatus = nil
            } else if p.matchStatus == "已关联原文中英段落，按整段练习。", p.sentenceZh != nil {
                return p
            } else if let pair = paragraphs.first(where: {
                !$0.zh.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && containsTerm($0.en, term: p.term)
            }) {
                // A bilingual paragraph is a known pair; never infer sentence alignment from counts.
                p.sentenceEn = pair.en; p.sentenceZh = pair.zh
                p.matchStatus = "已关联原文中英段落，按整段练习。"
            } else if let sentence = sentences.first(where: { containsTerm($0, term: p.term) }) {
                p.sentenceEn = sentence
                p.matchStatus = "已找到英文原句，尚未可靠对齐中文译文；点此核对后参与抽题。"
            } else {
                p.matchStatus = "未在英文正文中找到该表达或常见词形；它可能是扩展词。可补充例句，暂不参与抽题。"
            }
            return p
        }
    }
}
