import Foundation
import zlib

struct ImportedText {
    var title: String
    var chinese: String
    var english: String
    var note: String
    var learningPoints: [LearningPoint] = []
    var preparedLesson: PreparedLesson? = nil
}
enum WordImport {
    static func parseCore(_ rows: [String]) -> [LearningPoint] {
        var result: [LearningPoint] = []
        var category = ""
        var index = 0
        while index < rows.count {
            let text = rows[index].trimmingCharacters(in: .whitespacesAndNewlines)
            if text.contains("核心单词") { category = "核心单词"; index += 1; continue }
            if text.contains("核心词组") { category = "核心词组"; index += 1; continue }
            if text.contains("核心句式") { category = "核心句式"; index += 1; continue }
            let isPattern = category == "核心句式"
            let numbered = isPattern ? text.range(of: "^[0-9]+[.、]", options: .regularExpression) != nil : Int(text) != nil
            guard !category.isEmpty, numbered else { index += 1; continue }
            var next = index + 1
            while next < rows.count {
                let row = rows[next]
                if row.contains("核心单词") || row.contains("核心词组") || row.contains("核心句式") ||
                    (isPattern ? row.range(of: "^[0-9]+[.、]", options: .regularExpression) != nil : Int(row) != nil) { break }
                next += 1
            }
            let values = Array(rows[(index + 1)..<next])
            if isPattern {
                var point = LearningPoint(id: "pattern-\(result.count)", category: category, term: text.replacingOccurrences(of: "^[0-9]+[.、]\\s*", with: "", options: .regularExpression), meaning: "")
                var unlabeled: [String] = []
                for row in values {
                    if row.hasPrefix("中文：") { point.meaning = String(row.dropFirst(3)) }
                    else if row.hasPrefix("原文：") { point.sentenceEn = String(row.dropFirst(3)) }
                    else if row.hasPrefix("翻译：") { point.sentenceZh = String(row.dropFirst(3)) }
                    else if row.hasPrefix("注：") { point.note = String(row.dropFirst(2)) }
                    else { unlabeled.append(row) }
                }
                if point.meaning.isEmpty && unlabeled.count >= 3 {
                    point.meaning = unlabeled[0]; point.sentenceEn = unlabeled[1]; point.sentenceZh = unlabeled[2]
                }
                result.append(point)
            } else if values.count >= 2 {
                result.append(LearningPoint(id: "\(category)-\(text)", category: category, term: values[0], meaning: values.dropFirst().joined(separator: " ")))
            }
            index = next
        }
        return result
    }
    // Align only when both languages have the same ordered structural anchors.
    // Preserve every paragraph, and require the existing preview before saving.
    static func alignSections(en: [String], zh: [String]) -> (en: [String], zh: [String])? {
        func anchor(_ text: String, english: Bool) -> String? {
            let t = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let rules: [(String, [String])] = english ? [
                ("reflection", ["well honestly", "honestly", "to be honest"]),
                ("first", ["the first thing", "and the first thing", "firstly"]),
                ("second", ["and the second thing", "the second thing", "secondly"]),
                ("third", ["and the third thing", "the third thing", "thirdly"]),
                ("finally", ["and finally", "finally"]),
                ("closing", ["this is jolin", "i'm jolin"])
            ] : [
                ("reflection", ["老实说", "坦白说"]),
                ("first", ["第一件事", "首先"]),
                ("second", ["第二件事", "其次"]),
                ("third", ["第三件事"]),
                ("finally", ["最后"]),
                ("closing", ["这里是乔琳", "我是乔琳"])
            ]
            return rules.first { rule in rule.1.contains { t.hasPrefix($0) } }?.0
        }
        func groups(_ parts: [String], english: Bool) -> [(String, String)] {
            var output: [(String, String)] = []
            for part in parts {
                if let label = anchor(part, english: english) { output.append((label, part)) }
                else if output.isEmpty { output.append(("intro", part)) }
                else { output[output.count - 1].1 += "\n" + part }
            }
            return output
        }
        let e = groups(en, english: true), z = groups(zh, english: false)
        guard e.count >= 4, e.map({ $0.0 }) == z.map({ $0.0 }), Set(e.map({ $0.0 })).count == e.count else { return nil }
        return (e.map({ $0.1 }), z.map({ $0.1 }))
    }
    static func failure(_ text: String) -> NSError {
        NSError(domain: "WordImport", code: 1, userInfo: [NSLocalizedDescriptionKey: text])
    }
    static func read(_ url: URL) throws -> ImportedText {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 20_000_000 else { throw failure("文稿超过 20 MB，请先移除大型图片。") }
        let data = try Data(contentsOf: url)
        let xml = try documentXML(data)
        let delegate = ParagraphReader()
        let parser = XMLParser(data: xml)
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        guard parser.parse() else { throw failure("Word 正文读取失败，请确认文件未损坏。") }
        let boundary = delegate.paragraphs.firstIndex { $0.trimmingCharacters(in: .whitespacesAndNewlines) == "核心学习要点" }
        let body = boundary.map { Array(delegate.paragraphs[..<$0]) } ?? delegate.paragraphs
        var result = try organize(body, title: url.deletingPathExtension().lastPathComponent, titleIndex: delegate.titleIndex)
        guard let preparedXML = try archiveEntry(data, name: "customXml/english-practice.xml") else {
            throw failure("这份 Word 缺少配套时间数据。请导入按《遇到不靠谱的同事》模板制作的完整学习稿；仅复制正文或粘贴时间表不能直接朗读。")
        }
        let reader = PreparedXMLReader()
        let preparedParser = XMLParser(data: preparedXML)
        preparedParser.shouldResolveExternalEntities = false
        preparedParser.shouldProcessNamespaces = true
        preparedParser.delegate = reader
        guard preparedParser.parse(), reader.validRoot, let payload = reader.text.data(using: .utf8),
              let prepared = try? JSONDecoder().decode(PreparedLesson.self, from: payload) else {
            throw failure("配套时间数据损坏或版本不支持，请重新导入原始 Word。")
        }
        let verified = try prepared.makeLesson(title: result.title, chinese: result.chinese, english: result.english)
        // Check visible learning content too: edited Word text must not silently use stale hidden data.
        let visible = PreparedLesson.compact(delegate.paragraphs.joined())
        guard prepared.learningPoints.allSatisfy({ point in
            [point.term, point.ipa, point.pos, point.meaning, point.sentenceEn, point.sentenceZh].allSatisfy { $0.isEmpty || visible.contains(PreparedLesson.compact($0)) }
        }) else { throw failure("学习要点已修改，与配套数据不一致，请重新生成完整学习稿。") }
        func time(_ value: Double) -> String { String(format: "%02d:%05.2f", Int(value) / 60, value.truncatingRemainder(dividingBy: 60)) }
        guard prepared.paragraphs.allSatisfy({ visible.contains(PreparedLesson.compact($0.id + $0.title + time($0.start) + "–" + time($0.end))) }),
              prepared.sentences.allSatisfy({ visible.contains(PreparedLesson.compact($0.id + time($0.start) + "–" + time($0.end) + $0.en)) }) else {
            throw failure("可见时间索引与配套数据不一致，请重新生成完整文稿；导入后可在 App 内微调时间。")
        }
        result.preparedLesson = prepared
        result.learningPoints = verified.learningPoints ?? []
        result.note = "已读取 \(prepared.paragraphs.count) 个中英段落、\(prepared.sentences.count) 组原句时间和\(prepared.learningPoints.count) 项要点。选择对应视频后即可朗读，无需语音识别。"
        return result
    }
    // Read the central directory rather than trusting local header sizes or extracting paths.
    static func documentXML(_ data: Data) throws -> Data {
        guard let xml = try archiveEntry(data, name: "word/document.xml") else { throw failure("文件中没有找到 Word 正文。") }
        return xml
    }
    static func archiveEntry(_ data: Data, name wantedName: String) throws -> Data? {
        let bytes = [UInt8](data)
        func n(_ offset: Int, _ length: Int) throws -> Int {
            guard offset >= 0, offset <= bytes.count - length else { throw failure("Word 压缩结构不完整。") }
            return (0..<length).reduce(0) { $0 | (Int(bytes[offset + $1]) << ($1 * 8)) }
        }
        guard bytes.count >= 22, bytes.count <= 20_000_000 else { throw failure("文件不是受支持的 Word 文稿。") }
        var end: Int?
        for i in stride(from: bytes.count - 22, through: max(0, bytes.count - 65557), by: -1) {
            if try n(i, 4) == 0x06054b50, i + 22 + (try n(i + 20, 2)) == bytes.count { end = i; break }
        }
        guard let end else { throw failure("请选择未加密的 .docx 文件；不支持旧版 .doc。") }
        guard try n(end + 4, 2) == 0, try n(end + 6, 2) == 0 else { throw failure("不支持分卷 Word 文件。") }
        let count = try n(end + 10, 2)
        var cursor = try n(end + 16, 4)
        guard count < 65535 else { throw failure("Word 文件结构过大。") }
        for _ in 0..<count {
            guard try n(cursor, 4) == 0x02014b50 else { throw failure("Word 目录损坏。") }
            let flags = try n(cursor + 8, 2), method = try n(cursor + 10, 2)
            let expectedCRC = try n(cursor + 16, 4)
            let compressed = try n(cursor + 20, 4), expanded = try n(cursor + 24, 4)
            let nameLength = try n(cursor + 28, 2), extra = try n(cursor + 30, 2), comment = try n(cursor + 32, 2)
            let local = try n(cursor + 42, 4)
            let next = cursor + 46 + nameLength + extra + comment
            guard next <= bytes.count else { throw failure("Word 目录不完整。") }
            let name = String(bytes: bytes[(cursor + 46)..<(cursor + 46 + nameLength)], encoding: .utf8)
            cursor = next
            guard name == wantedName else { continue }
            guard flags & 1 == 0, expanded > 0, expanded <= 8_000_000 else { throw failure("文稿已加密或正文过大。") }
            guard try n(local, 4) == 0x04034b50 else { throw failure("Word 正文结构损坏。") }
            let start = local + 30 + (try n(local + 26, 2)) + (try n(local + 28, 2))
            guard start <= bytes.count, compressed <= bytes.count - start else { throw failure("Word 正文不完整。") }
            let input = Array(bytes[start..<(start + compressed)])
            var output: [UInt8]
            if method == 0 { output = input }
            else if method == 8 {
                output = [UInt8](repeating: 0, count: expanded)
                var stream = z_stream()
                guard inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else { throw failure("无法初始化文稿解压。") }
                defer { inflateEnd(&stream) }
                let status = input.withUnsafeBytes { source in
                    output.withUnsafeMutableBytes { destination in
                        stream.next_in = UnsafeMutablePointer<Bytef>(mutating: source.bindMemory(to: Bytef.self).baseAddress)
                        stream.avail_in = uInt(compressed)
                        stream.next_out = destination.bindMemory(to: Bytef.self).baseAddress
                        stream.avail_out = uInt(expanded)
                        return inflate(&stream, Z_FINISH)
                    }
                }
                guard status == Z_STREAM_END, stream.total_out == expanded else { throw failure("Word 正文解压失败。") }
            } else { throw failure("此 Word 压缩格式不受支持，请另存为标准 .docx。") }
            guard output.count == expanded else { throw failure("Word 正文大小不一致。") }
            let checksum = output.withUnsafeBytes { crc32(0, $0.bindMemory(to: Bytef.self).baseAddress, uInt(output.count)) }
            guard checksum == expectedCRC else { throw failure("Word 文件校验失败，请重新复制文件。") }
            return Data(output)
        }
        return nil
    }
    static func organize(_ paragraphs: [String], title: String, titleIndex: Int? = nil) throws -> ImportedText {
        let selectedTitleIndex: Int? = titleIndex ?? paragraphs.first.flatMap { first in
            // A short opening heading without sentence punctuation; otherwise preserve it as body.
            first.count <= 60 && !first.contains(where: { "。！？.!?；;".contains($0) }) && paragraphs.count >= 3 ? 0 : nil
        }
        let extractedTitle = selectedTitleIndex.flatMap { paragraphs.indices.contains($0) ? paragraphs[$0] : nil }
        let displayTitle: String
        if let text = extractedTitle {
            if let start = text.firstIndex(of: "【"), let end = text.lastIndex(of: "】"), start < end {
                displayTitle = String(text[text.index(after: start)..<end])
            } else { displayTitle = text }
        } else { displayTitle = title }

        var zh: [String] = [], en: [String] = []
        var skipped: [String] = []
        for (index, text) in paragraphs.enumerated() {
            let han = text.unicodeScalars.filter { (0x3400...0x9fff).contains(Int($0.value)) }.count
            let latin = text.unicodeScalars.filter { (65...90).contains(Int($0.value)) || (97...122).contains(Int($0.value)) }.count
            if index == selectedTitleIndex { skipped.append(text); continue }
            if han > 0 && han >= latin / 2 { zh.append(text) }
            else if latin > 0 { en.append(text) }
            else { skipped.append(text) }
        }
        // Join only likely sentence continuations when English has extra paragraphs.
        var joins = 0
        if en.count > zh.count {
            var i = 1
            let starters: Set<String> = ["and", "but", "so", "i", "i'm", "take", "how", "what", "then", "the"]
            while i < en.count && en.count > zh.count {
                let first = en[i].split(separator: " ").first.map(String.init) ?? ""
                let previous = en[i - 1].trimmingCharacters(in: .whitespacesAndNewlines)
                if let char = first.first, char.isLowercase, !starters.contains(first.lowercased()), let last = previous.last, !".!?。！？”.".contains(last) {
                    en[i - 1] += " " + en.remove(at: i); joins += 1
                } else { i += 1 }
            }
        }
        var alignmentNote = ""
        if en.count != zh.count, let aligned = alignSections(en: en, zh: zh) {
            alignmentNote = " 原识别英文 \(en.count) 段、中文 \(zh.count) 段；已按双方共有的引入、转折、步骤与结尾标记合并为 \(aligned.en.count) 组，请在预览中核对含义。"
            en = aligned.en; zh = aligned.zh
        }
        guard !zh.isEmpty, !en.isEmpty else { throw failure("未识别出完整的中英文内容，请使用粘贴方式分别添加。") }
        var note = "已读取中文 \(zh.count) 段、英文 \(en.count) 段。请核对语言分类、注释和段落对应后保存。"
        note += alignmentNote
        if joins > 0 { note += "已合并 \(joins) 处疑似英文句中断段，请重点核对。" }
        if !skipped.isEmpty { note += "未放入练习正文的标题或标记：" + skipped.joined(separator: " / ") }
        if extractedTitle == nil { note += "未识别到独立标题，暂用文件名，可手动修改。" }
        return ImportedText(title: displayTitle, chinese: zh.joined(separator: "\n\n"), english: en.joined(separator: "\n\n"), note: note)
    }
}
private final class ParagraphReader: NSObject, XMLParserDelegate {
    var paragraphs: [String] = []
    var titleIndex: Int?
    private var isTitle = false
    private var paragraph = ""
    private var insideText = false
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        let name = elementName.split(separator: ":").last.map(String.init)
        if name == "p" { paragraph = ""; isTitle = false }
        if name == "pStyle" {
            let value = (attributeDict["w:val"] ?? attributeDict["val"] ?? "").lowercased()
            isTitle = ["title", "heading1", "标题", "标题1"].contains(value)
        }
        if name == "t" { insideText = true }
        if name == "tab" || name == "br" { paragraph += " " }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { if insideText { paragraph += string } }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let name = elementName.split(separator: ":").last.map(String.init)
        if name == "t" { insideText = false }
        if name == "p" {
            let text = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                if isTitle && titleIndex == nil && paragraphs.count < 3 { titleIndex = paragraphs.count }
                paragraphs.append(text)
            }
        }
    }
}

private final class PreparedXMLReader: NSObject, XMLParserDelegate {
    var text = ""
    var validRoot = false
    var depth = 0
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        depth += 1
        if depth == 1 { validRoot = name == "lesson" && namespaceURI == "urn:english-practice:lesson:v1" && attributes["version"] == "1" }
        else { validRoot = false }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) { depth -= 1 }
}
