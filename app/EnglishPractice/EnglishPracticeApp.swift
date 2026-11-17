import SwiftUI
import UniformTypeIdentifiers
import UIKit
// Shared adaptive palette: every screen uses the same surface hierarchy.
enum AppTheme {
    private static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let value = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((value >> 16) & 255) / 255,
                           green: CGFloat((value >> 8) & 255) / 255,
                           blue: CGFloat(value & 255) / 255, alpha: 1)
        })
    }
    static let base = adaptive(0xF2F5F4, 0x151B21)
    static let surface = adaptive(0xFFFFFF, 0x252E37)
    static let inset = adaptive(0xE7EFEC, 0x303C46)
    static let border = adaptive(0xD5DFDA, 0x44515D)
    static let text = adaptive(0x202B27, 0xF0F3F6)
    static let secondary = adaptive(0x586A62, 0xBAC6D0)
    static let accent = adaptive(0x216659, 0x8BD5BF)
    static let actionText = adaptive(0xFFFFFF, 0x102E25)
}
private struct PracticePrimaryStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 14).padding(.vertical, 8)
            .foregroundStyle(AppTheme.actionText)
            .background(AppTheme.accent, in: RoundedRectangle(cornerRadius: 16))
            .opacity(enabled ? (configuration.isPressed ? 0.75 : 1) : 0.45)
    }
}
extension View {
    func appCard(_ radius: CGFloat = 20) -> some View {
        background(AppTheme.surface, in: RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(AppTheme.border, lineWidth: 1))
    }
    func appPage() -> some View { modifier(AppPageStyle()) }
}
private struct AppPageStyle: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        content.background(AppTheme.base)
            .toolbarBackground(AppTheme.base, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(scheme, for: .navigationBar)
    }
}


@main
struct EnglishPracticeApp: App {
    @StateObject private var store = LibraryStore()
    @StateObject private var audio = AudioController()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            LibraryView()
                .environmentObject(store).environmentObject(audio)
                .tint(AppTheme.accent)
                .foregroundStyle(AppTheme.text)
                .onChange(of: audio.pending?.id) { _, _ in audio.savePending(to: store) }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .background { audio.stop(); audio.stopPlayback() }
                }
                .alert("音频播放提示", isPresented: Binding(get: { audio.playbackError != nil }, set: { if !$0 { audio.clearPlaybackError() } })) {
                    Button("知道了") { audio.clearPlaybackError() }
                } message: { Text(audio.playbackError ?? "") }
                .alert("保存与读取提示", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
                    Button("知道了") { store.error = nil }
                } message: { Text(store.error ?? "") }
        }
    }
}
struct LibraryView: View {
    @EnvironmentObject private var store: LibraryStore
    @State private var importing = false
    @State private var showRecordings = false
    @State private var deleting: Lesson?
    var body: some View {
        NavigationStack {
            List {
            Group {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("把喜欢的文章，说成自己的英语。")
                            .font(.largeTitle.bold())
                        Text("选一篇文稿，今天先开口 10 分钟。")
                            .foregroundStyle(AppTheme.secondary)
                    }.padding(.top)
                    HStack {
                        stat("文稿", store.data.lessons.count)
                        Button { showRecordings = true } label: {
                            stat("录音", store.data.records.count)
                        }.buttonStyle(.plain).accessibilityHint("打开我的录音").accessibilityIdentifier("recordingsShortcut")
                        stat("待复习", store.data.favorites.count)
                    }
                    Text("我的文稿 · 左滑可删除").font(.caption).foregroundStyle(AppTheme.secondary)
                    ForEach(store.data.lessons) { lesson in
                        NavigationLink { LessonView(lesson: lesson) } label: {
                            VStack(alignment: .leading, spacing: 12) {
                                Label("双语文稿 · \(lesson.segments.count) 段", systemImage: "book.closed")
                                    .font(.caption).foregroundStyle(AppTheme.secondary)
                                Text(lesson.title).font(.title2.bold()).foregroundStyle(AppTheme.text)
                                Text(lesson.subtitle).font(.subheadline).foregroundStyle(AppTheme.secondary)
                                Label("开始练习", systemImage: "arrow.right").font(.subheadline.bold())
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(22)
                                .appCard(24)
                        }.buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) { deleting = lesson } label: { Label("删除", systemImage: "trash") }
                        }
                    }
                    if store.data.lessons.isEmpty {
                        ContentUnavailableView("添加第一篇文稿", systemImage: "book.closed", description: Text("点右上角 ＋ 导入 Word 或粘贴中英文。"))
                    }
                    NavigationLink { RecordingList() } label: {
                        Label("我的录音与回听", systemImage: "waveform").frame(maxWidth: .infinity, alignment: .leading).padding()
                    }
                    Text("文稿和录音保存在本机。此版本提供本地抽题和话题提示，不含 AI 自动纠错。")
                        .font(.footnote).foregroundStyle(AppTheme.secondary)
            
            }.listRowBackground(AppTheme.base).listRowSeparator(.hidden)
        }.scrollContentBackground(.hidden).appPage().listStyle(.plain)
                .scrollContentBackground(.hidden)
                .appPage()
                .navigationDestination(isPresented: $showRecordings) { RecordingList() }
                .navigationTitle("英语随身练").navigationBarTitleDisplayMode(.inline)
                .toolbar { Button { importing = true } label: { Label("添加文稿", systemImage: "plus") } }
                .sheet(isPresented: $importing) { ImportView() }
                .alert("删除“\(deleting?.title ?? "")”？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
                    Button("删除文稿，保留录音", role: .destructive) {
                        if let lesson = deleting { _ = store.commit { $0.removeLesson(id: lesson.id) } }
                        deleting = nil
                    }
                    Button("取消", role: .cancel) { deleting = nil }
                } message: {
                    Text("删除文稿及其收藏、完成记录。录音仍保留在“我的录音与回听”中；原始 Word 文件不会删除。")
                }
        }
    }
    func stat(_ label: String, _ count: Int) -> some View {
        VStack(alignment: .leading) { Text("\(count)").font(.title2.bold()); Text(label).font(.caption).foregroundStyle(AppTheme.secondary) }
            .frame(maxWidth: .infinity, alignment: .leading).padding(16).appCard(18)
    }
}
struct LessonView: View {
    let lesson: Lesson
    @EnvironmentObject private var store: LibraryStore
    var body: some View {
        List {
            Group {
            Section {
                Text(lesson.title).font(.title.bold())
                Text(lesson.source).font(.footnote).foregroundStyle(AppTheme.secondary)
            }
            Section("视频原声") {
                NavigationLink {
                    let current = store.data.lessons.first { $0.id == lesson.id } ?? lesson
                    OriginalSetupView(lesson: current) { source in store.setOriginal(source, for: lesson.id) }
                } label: { Label("添加 / 更换视频与核对原声", systemImage: "video") }
            }
            Section("选择练习方式") {
                ForEach(PracticeMode.allCases) { mode in
                    NavigationLink {
                        if mode == .read { ReadingView(lesson: lesson) }
                        else if mode == .draw { CoreStudyView(lessonID: lesson.id) }
                        else { PracticeView(lesson: lesson, mode: mode) }
                    } label: {
                        Label { VStack(alignment: .leading, spacing: 5) {
                            Text(mode.rawValue).font(.headline)
                            Text(description(mode)).font(.caption).foregroundStyle(AppTheme.secondary)
                        }.padding(.vertical, 8) } icon: { Image(systemName: mode.icon) }
                    }
                }
                NavigationLink { PracticeView(lesson: lesson, mode: .draw, favoritesOnly: true) } label: {
                    Label("复习收藏的难题", systemImage: "star")
                }
            }
        
            }.listRowBackground(AppTheme.surface).listRowSeparatorTint(AppTheme.border)
        }.scrollContentBackground(.hidden).appPage().navigationTitle("文稿练习").navigationBarTitleDisplayMode(.inline)
    }
    func description(_ mode: PracticeMode) -> String {
        switch mode {
        case .read: return "逐段阅读中文，开口后展开英文原文"
        case .draw: return "查询核心要点，再按原文整句抽题"
        case .topic: return "从文章出发，讲自己的经历与观点"
        }
    }
}
struct PracticeView: View {
    let lesson: Lesson
    let mode: PracticeMode
    var favoritesOnly = false
    var startIndex = 0
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var audio: AudioController
    @State private var items: [Exercise] = []
    @State private var index = 0
    @State private var revealed = false
    @State private var hint = false
    @State private var followUp = false
    @State private var completedMessage = false
    private var exercise: Exercise? { items.indices.contains(index) ? items[index] : nil }
    var body: some View {
        ScrollView {
            if let exercise {
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        Text("\(index + 1) / \(items.count)").font(.subheadline.monospacedDigit()).foregroundStyle(AppTheme.secondary)
                        Spacer()
                        Button { store.favorite(store.key(lesson, exercise)) } label: {
                            Label("收藏", systemImage: store.data.favorites.contains(store.key(lesson, exercise)) ? "star.fill" : "star")
                        }
                    }
                    ProgressView(value: Double(index + 1), total: Double(items.count))
                    Text(mode == .topic ? "用英语聊一聊" : "看中文，用英语表达")
                        .font(.caption.bold()).foregroundStyle(AppTheme.secondary)
                    Text(exercise.chinese).font(.title3).lineSpacing(9).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(22)
                        .appCard(22)
                    HStack {
                        Button(hint ? "收起提示" : "给我一点提示") { hint.toggle() }
                        Spacer()
                        Button(revealed ? "隐藏英文" : (mode == .topic ? "查看英文问题" : "查看参考英文")) { revealed.toggle() }
                    }.font(.subheadline)
                    if hint { Text(exercise.hint).foregroundStyle(AppTheme.secondary).textSelection(.enabled) }
                    if revealed {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(exercise.english).lineSpacing(6).textSelection(.enabled)
                            OriginalPlaybackButton(lessonID: lesson.id, text: exercise.english)
                            Text(mode == .topic ? "提示可帮助组织思路，不代表你的个人经历。" : "参考英文不是唯一答案；意思准确，也可以用自己的说法。")
                                .font(.caption).foregroundStyle(AppTheme.secondary)
                        }.padding(20).appCard(20)
                    }
                    if mode == .topic {
                        Button(followUp ? "收起延伸问题" : "继续深入聊") { followUp.toggle() }.disabled(audio.busy)
                        if followUp {
                            Text("你为什么这样想？能举一个具体例子吗？下一步你准备怎么做？\n\nWhy do you think so? Can you give a specific example? What will you do next?")
                                .padding().appCard(16)
                            Text("这是本地预设的延伸问题，不会分析你的录音。")
                                .font(.caption).foregroundStyle(AppTheme.secondary)
                        }
                    }
                    Button {
                        if audio.recording { audio.stop() }
                        else { Task { await audio.start(lesson: lesson, exercise: exercise, mode: mode) } }
                    } label: {
                        Label(audio.recording ? "停止并保存录音" : (audio.requesting ? "正在请求麦克风…" : "开始说英文"), systemImage: audio.recording ? "stop.circle.fill" : "mic.fill")
                            .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 12)
                    }.buttonStyle(PracticePrimaryStyle()).disabled(audio.requesting || audio.pending != nil)
                    if let message = audio.message { Text(message).font(.footnote).foregroundStyle(AppTheme.secondary) }
                    if let pending = audio.pending {
                        Button("重试保存") { audio.savePending(to: store) }
                        ShareLink("先备份这次录音", item: store.recordURL(pending))
                    }
                    let records = store.data.records.filter { $0.lessonID == lesson.id && $0.questionID == exercise.id }
                    if !records.isEmpty {
                        Text("本题录音").font(.headline)
                        ForEach(records.prefix(5)) { record in RecordingRow(record: record) }
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        Text("说完后，自己检查").font(.headline)
                        Text("意思说清楚了吗？哪里卡住了？选一个地方改好，再说一遍。")
                            .font(.subheadline).foregroundStyle(AppTheme.secondary)
                        Button(completedMessage ? "已记录本次练习" : "我已完成这道练习") {
                            completedMessage = store.commit { $0.completed.insert(store.key(lesson, exercise)) }
                        }.disabled(audio.busy)
                    }.padding(20).appCard(20)
                    HStack {
                        Button("上一题") { move(-1) }.disabled(index == 0 || audio.busy)
                        Spacer()
                        Button(index == items.count - 1 ? "再练一轮" : "下一题") { move(1) }.disabled(audio.busy)
                    }.buttonStyle(.bordered)
                    if mode == .read, let segment = lesson.segments.first(where: { $0.id == exercise.id }) {
                        DisclosureGroup("查看原始英文稿") { Text(segment.original).font(.footnote).textSelection(.enabled) }
                    }
                }.padding(20)
            } else {
                ContentUnavailableView(favoritesOnly ? "还没有收藏的题目" : "还没有可抽取的整句", systemImage: "text.bubble", description: Text(favoritesOnly ? "练习时点击“收藏”，即可在这里复习。" : "请在核心要点中补充对应的原文句子和中文。"))
            }
        }.appPage()
            .navigationTitle(favoritesOnly ? "难题复习" : mode.rawValue).navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(audio.busy)
            .onAppear {
                guard items.isEmpty else { return }
                var list = Exercises.make(lesson, mode: mode)
                if favoritesOnly {
                    list += Exercises.make(lesson, mode: .topic)
                    list += Exercises.make(lesson, mode: .read)
                    list = list.filter { store.data.favorites.contains(store.key(lesson, $0)) }
                }
                if mode == .draw { list.shuffle() }
                items = list
                index = min(startIndex, max(0, list.count - 1))
            }
            .onChange(of: revealed) { _, visible in if !visible && (audio.speaking || audio.playingClipID != nil) { audio.stopPlayback() } }
            .onDisappear { audio.stopPlayback() }
    }
    private func move(_ direction: Int) {
        audio.stopPlayback()
        if index + direction >= items.count { if mode == .draw { items.shuffle() }; index = 0 }
        else { index = max(0, index + direction) }
        revealed = false; hint = false; followUp = false; completedMessage = false; audio.message = nil
    }
}
struct RecordingRow: View {
    let record: PracticeRecord
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var audio: AudioController
    var body: some View {
        HStack {
            Button { audio.play(store.recordURL(record)) } label: {
                Label(audio.playingURL == store.recordURL(record) ? "停止" : "播放", systemImage: audio.playingURL == store.recordURL(record) ? "stop.circle.fill" : "play.circle.fill")
                    .font(.body).padding(.vertical, 10)
            }.buttonStyle(.borderless).disabled(audio.busy).accessibilityIdentifier("play-" + record.id)
            VStack(alignment: .leading) {
                Text(record.date.formatted(date: .abbreviated, time: .shortened)).font(.caption)
                Text(record.mode == "看中文说英文" ? "原文阅读" : record.mode).font(.caption).foregroundStyle(AppTheme.secondary)
            }
            Spacer()
            ShareLink(item: store.recordURL(record)) { Image(systemName: "square.and.arrow.up") }
        }.buttonStyle(.borderless)
        if audio.playingURL == store.recordURL(record) {
            TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: min(audio.playbackTime, audio.playbackDuration), total: max(audio.playbackDuration, 0.1))
                    Text("播放中 · \(Int(audio.playbackTime)) / \(Int(audio.playbackDuration)) 秒 · \(audio.outputName)")
                        .font(.caption).foregroundStyle(AppTheme.secondary)
                }
            }
        }
    }
}
struct SpeechButton: View {
    let text: String
    @EnvironmentObject private var audio: AudioController
    var body: some View {
        Button { audio.speak(text) } label: {
            Label(audio.speaking ? "停止朗读" : "系统合成朗读", systemImage: audio.speaking ? "stop.circle.fill" : "speaker.wave.2")
        }.buttonStyle(.bordered).foregroundStyle(AppTheme.accent)
            .contentTransition(.identity).animation(nil, value: audio.speaking)
            .disabled(audio.busy).accessibilityIdentifier("speechToggle")
    }
}
struct RecordingList: View {
    @State private var deleting: PracticeRecord?
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var audio: AudioController
    var body: some View {
        List {
            Group {
            if store.data.records.isEmpty { Text("练习后保存的录音会出现在这里。") }
            ForEach(store.data.records) { record in
                VStack(alignment: .leading, spacing: 12) {
                    Text(record.lessonTitle).font(.headline)
                    Text(record.question).font(.caption).foregroundStyle(AppTheme.secondary).lineLimit(3)
                    RecordingRow(record: record)
                }.padding(.vertical, 6)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) { deleting = record } label: { Label("删除", systemImage: "trash") }
                    }
            }
            Section {
                Text("左滑录音可删除。录音可逐条分享到“文件”备份。卸载 App 会删除本机资料，请先备份重要录音和文稿。")
                    .font(.footnote).foregroundStyle(AppTheme.secondary)
            }
        
            }.listRowBackground(AppTheme.surface).listRowSeparatorTint(AppTheme.border)
        }.scrollContentBackground(.hidden).appPage().navigationTitle("我的录音").navigationBarTitleDisplayMode(.inline)
            .toolbar { if audio.playingURL != nil { Button("停止播放") { audio.stopPlayback() } } }
            .alert("删除这条录音？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
                Button("删除录音", role: .destructive) {
                    if let record = deleting {
                        if audio.playingURL == store.recordURL(record) { audio.stopPlayback() }
                        store.deleteRecording(record)
                    }
                    deleting = nil
                }
                Button("取消", role: .cancel) { deleting = nil }
            } message: { Text("录音文件将从本机删除，无法撤销。文稿与其他录音不受影响。") }
            .onDisappear { audio.stopPlayback() }
    }
}
struct ImportView: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectingFile = false
    @State private var loadingFile = false
    @State private var importNote = ""
    @State private var importedPoints: [LearningPoint] = []
    @State private var importedPrepared: PreparedLesson?
    @State private var title = ""
    @State private var chinese = ""
    @State private var english = ""
    @State private var preview: Lesson?
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
            Group {
                if let preview {
                    Section("可选：添加对应视频原声") {
                        NavigationLink {
                            OriginalSetupView(lesson: preview) { source in self.preview?.originalSource = source; return true }
                        } label: { Label(preview.originalSource == nil ? "添加对应视频（可稍后添加）" : "查看视频与朗读时间", systemImage: "video.badge.plus") }
                        Text("文稿时间已读取；添加同一份原视频即可朗读，无需语音识别。").font(.footnote).foregroundStyle(AppTheme.secondary)
                    }
                    Section("核心学习要点") {
                        Text("已读取 \(preview.learningPoints?.count ?? 0) 项。导入后进入“随机抽题”查询与巩固。")
                    }
                    Section("确认中英文一一对应") {
                        ForEach(preview.segments) { segment in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(segment.title).font(.caption.bold())
                                Text(segment.zh)
                                Text(segment.en).foregroundStyle(AppTheme.secondary)
                            }.padding(.vertical, 8)
                        }
                    }
                    Text("请检查上下两种语言是否对应。确认后点击右上角或底部的“完成导入”。")
                        .font(.footnote).foregroundStyle(AppTheme.secondary)
                } else {
                    Section("导入配套 Word") {
                        Button { selectingFile = true } label: { Label(loadingFile ? "正在读取文稿…" : "从文件导入 Word（.docx）", systemImage: "doc.badge.plus") }.disabled(loadingFile)
                        if !importNote.isEmpty { Text(importNote).font(.footnote).foregroundStyle(AppTheme.secondary) }
                        TextField("文稿标题", text: $title)
                        Text("请导入包含正文、学习要点和配套时间数据的完整 Word。视频可在预览页添加。")
                            .font(.footnote).foregroundStyle(AppTheme.secondary)
                    }
                    if importedPrepared != nil {
                        Section("文稿已读取") { Text("点击下一步核对分段、学习要点，并添加对应视频。") }
                    }
                    if let error { Text(error).foregroundStyle(.red) }
                    Button("预览分段") {
                        do { preview = try makePreview(); error = nil }
                        catch { self.error = error.localizedDescription }
                    }.disabled(loadingFile)
                }
            
            }.listRowBackground(AppTheme.surface).listRowSeparatorTint(AppTheme.border)
        }.scrollContentBackground(.hidden).appPage().navigationTitle("添加双语文稿").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(loadingFile) }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(preview == nil ? "下一步" : "完成导入") { advanceImport() }
                            .fontWeight(.semibold).disabled(loadingFile)
                    }
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("收起键盘") { hideKeyboard() }
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    VStack(spacing: 8) {
                        if preview != nil {
                            Button("返回修改分段") { preview = nil }
                                .font(.subheadline)
                        }
                        Button { advanceImport() } label: {
                            Label(preview == nil ? "下一步：核对中英文" : "完成导入，加入文稿库", systemImage: preview == nil ? "arrow.right" : "checkmark.circle.fill")
                                .frame(maxWidth: .infinity).padding(.vertical, 8)
                        }.buttonStyle(PracticePrimaryStyle()).disabled(loadingFile)
                    }.padding().background(AppTheme.surface).overlay(alignment: .top) { Rectangle().fill(AppTheme.border).frame(height: 1) }
                }
        }.interactiveDismissDisabled(loadingFile || !title.isEmpty || !chinese.isEmpty || !english.isEmpty)
        .fileImporter(isPresented: $selectingFile, allowedContentTypes: [UTType(filenameExtension: "docx") ?? .data]) { result in
            switch result {
            case .failure(let failure): error = failure.localizedDescription
            case .success(let url):
                loadingFile = true
                Task {
                    do {
                        let imported = try await Task.detached(priority: .userInitiated) {
                            let access = url.startAccessingSecurityScopedResource()
                            defer { if access { url.stopAccessingSecurityScopedResource() } }
                            return try WordImport.read(url)
                        }.value
                        title = imported.title; chinese = imported.chinese; english = imported.english
                        importNote = imported.note; importedPoints = imported.learningPoints; importedPrepared = imported.preparedLesson; error = nil
                    } catch { self.error = error.localizedDescription }
                    loadingFile = false
                }
            }
        }
    }
    private func makePreview() throws -> Lesson {
        guard let prepared = importedPrepared else { throw WordImport.failure("请先导入带配套时间数据的 Word 文稿。") }
        return try prepared.makeLesson(title: title, chinese: chinese, english: english)
    }
    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
    private func advanceImport() {
        hideKeyboard()
        if let preview {
            if store.commit({ $0.lessons.append(preview) }) { dismiss() }
        } else {
            do {
                preview = try makePreview()
                error = nil
            } catch { self.error = error.localizedDescription }
        }
    }

}

struct CoreStudyView: View {
    let lessonID: String
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var audio: AudioController
    @State private var query = ""
    @State private var category = "全部"
    private var lesson: Lesson? { store.data.lessons.first { $0.id == lessonID } }
    var body: some View {
        List {
            Group {
            if let lesson {
                Section {
                    NavigationLink { PracticeView(lesson: lesson, mode: .draw) } label: {
                        Label("开始整句抽题 · \(Exercises.make(lesson, mode: .draw).count) 句", systemImage: "shuffle")
                    }.disabled(Exercises.make(lesson, mode: .draw).isEmpty)
                    Text("先巩固要点，再看中文说出完整英文。相同原句合并出题，提示里列出覆盖的要点。")
                        .font(.footnote).foregroundStyle(AppTheme.secondary)
                }
                Section {
                    Picker("分类", selection: $category) {
                        ForEach(["全部", "核心单词", "核心词组", "核心句式"], id: \.self) { Text($0) }
                    }
                }
                ForEach(["核心单词", "核心词组", "核心句式"], id: \.self) { group in
                    let points = (lesson.learningPoints ?? []).filter {
                        $0.category == group && (category == "全部" || category == group) &&
                        (query.isEmpty || ($0.term + $0.meaning + ($0.sentenceEn ?? "") + ($0.sentenceZh ?? "")).localizedCaseInsensitiveContains(query))
                    }
                    if !points.isEmpty {
                        Section("\(group) · \(points.count)") {
                            ForEach(points) { point in
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(point.term).font(.headline)
                                        Text(point.meaning).foregroundStyle(AppTheme.secondary)
                                        if let en = point.sentenceEn, !en.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                            Text(en).font(.subheadline)
                                            OriginalPlaybackButton(lessonID: lessonID, text: en)
                                        }
                                        if let zh = point.sentenceZh { Text(zh).font(.subheadline).foregroundStyle(AppTheme.secondary) }
                                        if point.sentenceEn == nil || point.sentenceZh == nil {
                                            Text(point.matchStatus ?? "尚未关联完整原句，请重新导入含原句及时间数据的文稿。")
                                                .font(.caption).foregroundStyle(.orange)
                                        }
                                        if point.sentenceEn != nil && point.sentenceZh != nil, let status = point.matchStatus { Text(status).font(.caption).foregroundStyle(AppTheme.secondary) }
                                        if !point.note.isEmpty { Text(point.note).font(.caption).foregroundStyle(AppTheme.secondary) }
                                    }.padding(.vertical, 6)
                                    .accessibilityIdentifier("core-point-" + point.id)
                            }
                        }
                    }
                }
                if (lesson.learningPoints ?? []).isEmpty {
                    Text("这篇文稿没有核心学习要点。请导入含“核心学习要点”章节的新版 Word。")
                }
            }
        
            }.listRowBackground(AppTheme.surface).listRowSeparatorTint(AppTheme.border)
        }.scrollContentBackground(.hidden).appPage().navigationTitle("核心要点与抽题").navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "查单词、词组、句式或中文")
            .onDisappear { audio.stopPlayback() }
    }
}
struct CorePointEditor: View {
    let lessonID: String
    let point: LearningPoint
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var en = ""
    @State private var zh = ""
    var body: some View {
        Form {
            Group {
            Section { Text(point.term).font(.headline); Text(point.meaning) }
            Section("对应的原文整句") { TextEditor(text: $en).scrollContentBackground(.hidden).background(AppTheme.surface).frame(minHeight: 150) }
            Section("这句话的中文") { TextEditor(text: $zh).scrollContentBackground(.hidden).background(AppTheme.surface).frame(minHeight: 130) }
            Section { Text("填写该要点在原文中的完整句子与对应译文。保存后用于整句抽题，不会自动翻译。") }
        
            }.listRowBackground(AppTheme.surface).listRowSeparatorTint(AppTheme.border)
        }.scrollContentBackground(.hidden).appPage().navigationTitle("核对原文样句").navigationBarTitleDisplayMode(.inline)
            .onAppear { en = point.sentenceEn ?? ""; zh = point.sentenceZh ?? "" }
            .toolbar { Button("保存") {
                if store.commit({ state in
                    guard let l = state.lessons.firstIndex(where: { $0.id == lessonID }),
                          let p = state.lessons[l].learningPoints?.firstIndex(where: { $0.id == point.id }) else { return }
                    state.lessons[l].learningPoints?[p].sentenceEn = en.trimmingCharacters(in: .whitespacesAndNewlines)
                    state.lessons[l].learningPoints?[p].sentenceZh = zh.trimmingCharacters(in: .whitespacesAndNewlines)
                    state.lessons[l].learningPoints?[p].matchStatus = nil
                }) { dismiss() }
            }.disabled(en.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ").count < 4 || zh.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
    }
}

struct ReadingView: View {
    let lesson: Lesson
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var audio: AudioController
    @State private var index = 0
    @State private var expanded = false
    private var segment: Segment? { lesson.segments.indices.contains(index) ? lesson.segments[index] : nil }
    var body: some View {
        VStack(spacing: 0) {
            if let segment {
                HStack {
                    Text("第 \(index + 1) 段 / 共 \(lesson.segments.count) 段")
                        .font(.subheadline.monospacedDigit()).foregroundStyle(AppTheme.secondary)
                    Spacer()
                    let key = lesson.id + ":" + segment.id
                    Button { store.favorite(key) } label: {
                        Label(store.data.favorites.contains(key) ? "已收藏" : "收藏", systemImage: store.data.favorites.contains(key) ? "star.fill" : "star")
                    }
                }.padding(20)
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        Text(segment.zh).font(.title3).lineSpacing(9).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(22).appCard(22)
                        Button {
                            if audio.recording { audio.stop() }
                            else {
                                let exercise = Exercise(id: segment.id, chinese: segment.zh, english: segment.en, hint: "")
                                Task { await audio.start(lesson: lesson, exercise: exercise, mode: .read) }
                            }
                        } label: {
                            Label(audio.recording ? "停止并保存录音" : (audio.requesting ? "正在请求麦克风…" : "开始说英文"), systemImage: audio.recording ? "stop.circle.fill" : "mic.fill")
                                .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 12)
                        }.buttonStyle(PracticePrimaryStyle()).disabled(audio.requesting || audio.pending != nil)
                        if let message = audio.message {
                            Text(message).font(.footnote).foregroundStyle(AppTheme.secondary)
                        }
                        if let pending = audio.pending {
                            Button("重试保存") { audio.savePending(to: store) }
                            ShareLink("备份本次录音", item: store.recordURL(pending))
                        }
                        DisclosureGroup("查看原始英文稿", isExpanded: $expanded) {
                            Text(segment.original.isEmpty ? segment.en : segment.original)
                                .font(.body).lineSpacing(7).textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 12)
                            OriginalPlaybackButton(lessonID: lesson.id, text: segment.en, segmentID: segment.id)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 12)
                        }.padding(20).appCard(20)
                    }.padding(.horizontal, 20).padding(.bottom, 20)
                }.id(index)
            } else {
                ContentUnavailableView("暂无正文段落", systemImage: "doc.text", description: Text("请重新导入含中英文正文的文稿。"))
            }
        }.appPage()
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Button { change(-1) } label: { Label("上一段", systemImage: "chevron.left") }
                        .disabled(index == 0 || audio.busy)
                    Spacer()
                    Button { change(1) } label: { HStack { Text("下一段"); Image(systemName: "chevron.right") } }
                        .disabled(index >= lesson.segments.count - 1 || audio.busy)
                }.buttonStyle(.bordered).padding().background(AppTheme.surface).overlay(alignment: .top) { Rectangle().fill(AppTheme.border).frame(height: 1) }
            }
            .navigationTitle("原文阅读").navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(audio.busy)
            .onAppear { if !audio.busy { audio.message = nil } }
            .onChange(of: expanded) { _, visible in if !visible && (audio.speaking || audio.playingClipID != nil) { audio.stopPlayback() } }
            .onDisappear { audio.stopPlayback() }
    }
    private func change(_ delta: Int) {
        guard !audio.busy, lesson.segments.indices.contains(index + delta) else { return }
        audio.stopPlayback()
        index += delta
        expanded = false
        audio.message = nil
    }
}
