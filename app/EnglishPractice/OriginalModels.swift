import Foundation

struct TimedWord: Codable, Equatable {
    var text: String
    var start: Double
    var end: Double
}
struct OriginalClip: Codable, Identifiable, Equatable {
    var id: String
    var text: String
    var start: Double
    var end: Double
    var score: Double
    var confirmed: Bool
    func valid(duration: Double) -> Bool {
        start.isFinite && end.isFinite && start >= 0 && end > start && end <= duration + 0.01
    }
}
struct OriginalSource: Codable {
    var file: String
    var name: String
    var duration: Double
    var words: [TimedWord] = []
    var clips: [OriginalClip] = []
    var recognitionNote: String = "使用文稿记录的起止时间。"
    var locale: String = "en-US"
}
struct OriginalTarget: Identifiable {
    var id: String
    var title: String
    var en: String
    var zh: String
}
enum OriginalMatching {
    static func tokens(_ text: String) -> [String] { CoreStudy.normalized(text).split(separator: " ").map(String.init) }
    static func textKey(_ text: String) -> String { "text:" + tokens(text).joined(separator: " ") }
    static func targets(_ lesson: Lesson) -> [OriginalTarget] {
        let paragraphs = lesson.segments.map { OriginalTarget(id: "read:" + $0.id, title: $0.title, en: $0.en, zh: $0.zh) }
        var seen = Set(paragraphs.map { textKey($0.en) })
        let sentences = Exercises.make(lesson, mode: .draw).compactMap { exercise -> OriginalTarget? in
            let key = textKey(exercise.english)
            guard seen.insert(key).inserted else { return nil }
            return OriginalTarget(id: key, title: "抽题原句", en: exercise.english, zh: exercise.chinese)
        }
        return paragraphs + sentences
    }
    static func clip(in source: OriginalSource, text: String, preferredID: String? = nil) -> OriginalClip? {
        source.clips.first { $0.confirmed && $0.valid(duration: source.duration) &&
            textKey($0.text) == textKey(text) && (preferredID == nil || $0.id == preferredID) }
        ?? source.clips.first { $0.confirmed && $0.valid(duration: source.duration) && textKey($0.text) == textKey(text) }
    }
}

// Versioned prepared data is stored in Word, independent of the imported video audio.
struct PreparedAudio: Codable {
    var videoSHA256: String
    var videoDuration: Double
    var clips: [OriginalClip]
    func apply(to source: OriginalSource) throws -> OriginalSource {
        guard clips.allSatisfy({ $0.valid(duration: source.duration) }) else {
            throw PreparedLesson.failure("文稿时间超出视频音轨，请重新核对配套文稿。")
        }
        var result = source
        result.clips = clips
        result.recognitionNote = "已读取文稿时间，可直接朗读，无需语音识别；若句首句尾不合适，可微调。"
        return result
    }
}
struct PreparedLesson: Decodable {
    struct Paragraph: Decodable { var id: String; var title: String; var sentenceIDs: [String]; var en: String; var zh: String; var start: Double; var end: Double }
    struct Sentence: Decodable { var id: String; var paragraph: String; var en: String; var zh: String; var start: Double; var end: Double }
    struct Point: Decodable { var id: String; var category: String; var term: String; var ipa: String; var pos: String; var meaning: String; var sentenceID: String; var sentenceEn: String; var sentenceZh: String }
    var title: String
    var videoSHA256: String
    var videoDuration: Double
    var paragraphs: [Paragraph]
    var sentences: [Sentence]
    var learningPoints: [Point]
    static func failure(_ message: String) -> NSError { NSError(domain: "PreparedLesson", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    static func compact(_ text: String) -> String { text.components(separatedBy: .whitespacesAndNewlines).joined() }
    func validate() throws {
        guard !title.isEmpty, videoSHA256.range(of: "^[a-fA-F0-9]{64}$", options: .regularExpression) != nil,
              videoDuration.isFinite, videoDuration > 0, videoDuration <= 1200,
              !paragraphs.isEmpty, paragraphs.count <= 200, !sentences.isEmpty, sentences.count <= 2000,
              learningPoints.count <= 1000,
              Set(paragraphs.map(\.id)).count == paragraphs.count,
              Set(sentences.map(\.id)).count == sentences.count,
              Set(learningPoints.map(\.id)).count == learningPoints.count else {
            throw Self.failure("文稿配套数据不完整，请使用含完整时间索引的原始 Word。")
        }
        func valid(_ en: String, _ zh: String, _ start: Double, _ end: Double) -> Bool {
            !en.isEmpty && !zh.isEmpty && start.isFinite && end.isFinite && start >= 0 && start < end && end <= videoDuration && en.count <= 30000 && zh.count <= 30000
        }
        let bank = Dictionary(uniqueKeysWithValues: sentences.map { ($0.id, $0) })
        var used: [String] = []
        for p in paragraphs {
            let items = p.sentenceIDs.compactMap { bank[$0] }
            guard valid(p.en, p.zh, p.start, p.end), !items.isEmpty, items.count == p.sentenceIDs.count,
                  items.allSatisfy({ $0.paragraph == p.id && valid($0.en, $0.zh, $0.start, $0.end) && $0.start >= p.start && $0.end <= p.end }),
                  Self.compact(items.map(\.en).joined()) == Self.compact(p.en),
                  Self.compact(items.map(\.zh).joined()) == Self.compact(p.zh),
                  p.start == items.first?.start, p.end == items.last?.end,
                  zip(items, items.dropFirst()).allSatisfy({ $0.start <= $1.start }) else {
                throw Self.failure("文稿段落、句子或时间索引不一致，请重新生成配套文稿。")
            }
            used += p.sentenceIDs
        }
        guard used == sentences.map(\.id), zip(paragraphs, paragraphs.dropFirst()).allSatisfy({ $0.end <= $1.start }) else {
            throw Self.failure("文稿时间顺序不正确，请核对段落时间。")
        }
        // Playback is selected by exact source text; never choose an ambiguous repeated sentence.
        for group in Dictionary(grouping: sentences, by: { OriginalMatching.textKey($0.en) }).values {
            guard Set(group.map { "\($0.start):\($0.end)" }).count == 1 else { throw Self.failure("存在重复原句的不同时间，请为这些原句补充上下文后重新生成文稿。") }
        }
        for point in learningPoints {
            guard ["核心单词", "核心词组", "核心句式"].contains(point.category), !point.term.isEmpty, !point.meaning.isEmpty,
                  let sentence = bank[point.sentenceID], Self.compact(point.sentenceEn) == Self.compact(sentence.en), Self.compact(point.sentenceZh) == Self.compact(sentence.zh) else {
                throw Self.failure("学习要点的例句与正文不一致，请重新核对文稿。")
            }
        }
    }
    func makeLesson(title: String, chinese: String, english: String) throws -> Lesson {
        try validate()
        var lesson = try Exercises.parse(title: title, chinese: chinese, english: english)
        guard lesson.segments.count == paragraphs.count,
              zip(lesson.segments, paragraphs).allSatisfy({ Self.compact($0.en) == Self.compact($1.en) && Self.compact($0.zh) == Self.compact($1.zh) }) else {
            throw Self.failure("正文已改变，与预设时间数据不一致。请重新导入原始配套 Word。")
        }
        var clips: [OriginalClip] = []
        for (index, paragraph) in paragraphs.enumerated() {
            lesson.segments[index].title = "第 \(index + 1) 段 · \(paragraph.title)"
            clips.append(OriginalClip(id: "read:" + lesson.segments[index].id, text: paragraph.en, start: paragraph.start, end: paragraph.end, score: 1, confirmed: true))
        }
        var seen = Set<String>()
        for sentence in sentences where seen.insert(OriginalMatching.textKey(sentence.en)).inserted {
            clips.append(OriginalClip(id: OriginalMatching.textKey(sentence.en), text: sentence.en, start: sentence.start, end: sentence.end, score: 1, confirmed: true))
        }
        lesson.learningPoints = learningPoints.map {
            LearningPoint(id: $0.id, category: $0.category, term: [$0.term, $0.ipa, $0.pos].filter { !$0.isEmpty }.joined(separator: " "), meaning: $0.meaning, sentenceEn: $0.sentenceEn, sentenceZh: $0.sentenceZh)
        }
        lesson.sentenceBank = sentences.map { SentencePair(en: $0.en, zh: $0.zh) }
        lesson.preparedAudio = PreparedAudio(videoSHA256: videoSHA256.lowercased(), videoDuration: videoDuration, clips: clips)
        lesson.source = "配套 Word 导入；按文稿时间朗读原文"
        return lesson
    }
}
