import Foundation
import SwiftUI

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var data: SavedData
    @Published var error: String?
    private var canSave = true
    static var folder: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }
    private let storageFolder: URL
    private var file: URL { storageFolder.appendingPathComponent("library.json") }
    init(folder: URL? = nil) {
        storageFolder = folder ?? Self.folder
        data = SavedData(lessons: [])
        do {
            if FileManager.default.fileExists(atPath: file.path) {
                data = try JSONDecoder().decode(SavedData.self, from: Data(contentsOf: file))
            } else {
                guard let url = Bundle.main.url(forResource: "lesson", withExtension: "json") else {
                    throw CocoaError(.fileNoSuchFile)
                }
                data = SavedData(lessons: [try JSONDecoder().decode(Lesson.self, from: Data(contentsOf: url))])
            }
            // Recover an interrupted delete: the index determines whether to restore or finish removal.
            for staged in try FileManager.default.contentsOfDirectory(at: storageFolder, includingPropertiesForKeys: nil)
                where staged.lastPathComponent.hasPrefix(".deleting-") {
                let name = String(staged.lastPathComponent.dropFirst(".deleting-".count))
                let original = storageFolder.appendingPathComponent(name)
                if data.records.contains(where: { $0.file == name }), !FileManager.default.fileExists(atPath: original.path) {
                    try FileManager.default.moveItem(at: staged, to: original)
                } else { try FileManager.default.removeItem(at: staged) }
            }
            let originalFolder = storageFolder.appendingPathComponent("OriginalAudio")
            let referenced = Set(data.lessons.compactMap { $0.originalSource?.file })
            if let files = try? FileManager.default.contentsOfDirectory(at: originalFolder, includingPropertiesForKeys: nil) {
                for file in files where file.pathExtension == "m4a" && !referenced.contains(file.lastPathComponent) { try? FileManager.default.removeItem(at: file) }
            }
            if let seed = CoreStudy.bundled() {
                var changed = false
                for i in data.lessons.indices {
                    let old = data.lessons[i]
                    if old.learningPoints == nil && old.segments.count == seed.segments.count &&
                        CoreStudy.normalized(old.segments.first?.en ?? "").prefix(70) == CoreStudy.normalized(seed.segments.first?.en ?? "").prefix(70) {
                        data.lessons[i].learningPoints = seed.learningPoints
                        data.lessons[i].sentenceBank = seed.sentenceBank
                        changed = true
                    }
                }
                for i in data.lessons.indices {
                    if let points = data.lessons[i].learningPoints,
                       points.contains(where: { $0.sentenceEn == nil || $0.sentenceZh == nil }) {
                        data.lessons[i].learningPoints = CoreStudy.attach(points, source: data.lessons[i].segments.map(\.en).joined(separator: "\n"), bank: seed.sentenceBank ?? [], paragraphs: data.lessons[i].segments.map { SentencePair(en: $0.en, zh: $0.zh) })
                        changed = true
                    }
                }
                if changed { try JSONEncoder().encode(data).write(to: file, options: .atomic) }
            }
        } catch {
            canSave = false
            self.error = "资料读取失败，已停止写入以保护原有数据：\(error.localizedDescription)"
        }
    }
    func commit(_ change: (inout SavedData) -> Void) -> Bool {
        guard canSave else { error = "资料尚未成功载入，暂时不能保存。"; return false }
        var next = data
        change(&next)
        do {
            try JSONEncoder().encode(next).write(to: file, options: .atomic)
            data = next
            return true
        } catch { self.error = "保存失败：\(error.localizedDescription)"; return false }
    }
    func key(_ lesson: Lesson, _ exercise: Exercise) -> String { lesson.id + ":" + exercise.id }
    func favorite(_ key: String) {
        _ = commit { if $0.favorites.contains(key) { $0.favorites.remove(key) } else { $0.favorites.insert(key) } }
    }
    func deleteRecording(_ record: PracticeRecord) {
        guard data.records.contains(where: { $0.id == record.id }) else { return }
        // Stage the audio first so a failed library save can restore the original file.
        let original = recordURL(record)
        let staged = storageFolder.appendingPathComponent(".deleting-" + record.file)
        let exists = FileManager.default.fileExists(atPath: original.path)
        do {
            if exists { try FileManager.default.moveItem(at: original, to: staged) }
            guard commit({ $0.records.removeAll { $0.id == record.id } }) else {
                if exists { try FileManager.default.moveItem(at: staged, to: original) }
                return
            }
            if exists { try FileManager.default.removeItem(at: staged) }
        } catch {
            self.error = "删除录音时发生错误：\(error.localizedDescription)"
        }
    }
    func setOriginal(_ source: OriginalSource?, for lessonID: String) -> Bool {
        guard let index = data.lessons.firstIndex(where: { $0.id == lessonID }) else { error = "文稿已不存在。"; return false }
        let previous = data.lessons[index].originalSource
        guard commit({ $0.lessons[index].originalSource = source }) else { return false }
        if let previous, previous.file != source?.file {
            try? FileManager.default.removeItem(at: storageFolder.appendingPathComponent("OriginalAudio").appendingPathComponent(previous.file))
        }
        return true
    }
    func recordURL(_ record: PracticeRecord) -> URL { storageFolder.appendingPathComponent(record.file) }
}
