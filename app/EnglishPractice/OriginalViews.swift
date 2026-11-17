import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct OriginalSetupView: View {
    let lesson: Lesson
    let onSave: (OriginalSource?) -> Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var audio: AudioController
    @State private var status = ""
    @State private var source: OriginalSource?
    @State private var initialFile: String?
    @State private var photos: PhotosPickerItem?
    @State private var chooseFile = false
    @State private var busy = false
    @State private var work: Task<Void, Never>?
    @State private var error: String?
    @State private var tab = "段落"
    @State private var didSave = false
    @State private var confirmRemove = false
    private var targets: [OriginalTarget] {
        OriginalMatching.targets(lesson).filter { tab == "段落" ? $0.id.hasPrefix("read:") : !$0.id.hasPrefix("read:") }
    }
    var body: some View {
        List {
            Group {
                Section("1 · 添加对应视频（可选）") {
                    Button { chooseFile = true } label: { Label(source == nil ? "从文件选择视频" : "从文件更换视频", systemImage: "video.badge.plus") }.disabled(busy || lesson.preparedAudio == nil)
                    PhotosPicker(selection: $photos, matching: .videos) { Label("从照片选择视频", systemImage: "photo.on.rectangle") }.disabled(busy || lesson.preparedAudio == nil)
                    Text("提取并保存原声音轨，不改动你的视频与练习录音。限20分钟、600 MB。")
                        .font(.footnote).foregroundStyle(AppTheme.secondary)
                    if lesson.preparedAudio == nil { Text("此文稿缺少预设时间数据，请重新导入配套 Word。").foregroundStyle(.orange) }
                    if let source { Text("\(source.name) · \(Int(source.duration)) 秒").font(.subheadline) }
                }
                if let source {
                    Section("2 · 文稿时间") {
                        Text(source.recognitionNote).font(.footnote).foregroundStyle(AppTheme.secondary)
                        Text("直接按文稿记录播放。切点可试听微调，修改后保存即可生效。")
                            .font(.footnote).foregroundStyle(AppTheme.secondary)
                    }
                    Section("3 · 试听与时间微调") {
                        Picker("查看", selection: $tab) { Text("正文段落").tag("段落"); Text("抽题原句").tag("原句") }.pickerStyle(.segmented)
                        Text("可朗读 \(source.clips.filter(\.confirmed).count) 项，已使用文稿预设时间。")
                            .font(.footnote).foregroundStyle(AppTheme.secondary)
                        if targets.isEmpty { Text("没有额外的抽题原句；与正文相同的题目会直接使用已确认的段落。") }
                        ForEach(targets) { target in
                            NavigationLink {
                                OriginalClipEditor(target: target, source: source) { clip in
                                    self.source?.clips.removeAll { $0.id == clip.id }
                                    self.source?.clips.append(clip)
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(target.title).font(.headline)
                                    Text(target.zh).lineLimit(2)
                                    if let clip = source.clips.first(where: { $0.id == target.id }) {
                                        Text(clip.confirmed ? "可朗读 · \(clip.start.formatted(.number.precision(.fractionLength(1))))–\(clip.end.formatted(.number.precision(.fractionLength(1)))) 秒" : "待核对时间")
                                            .font(.caption).foregroundStyle(clip.confirmed ? AppTheme.accent : .orange)
                                    } else { Text("缺少时间 · 点此设置").font(.caption).foregroundStyle(AppTheme.secondary) }
                                }
                            }.disabled(busy).accessibilityIdentifier("source-target-" + target.id)
                        }
                    }
                    Section { Button("移除这篇文稿的原声", role: .destructive) { confirmRemove = true }.disabled(busy) }
                }
                if busy {
                    Section { ProgressView(status.isEmpty ? "正在提取视频原声…" : status); Button("取消处理") { work?.cancel() } }
                }
                if let error { Section { Text(error).foregroundStyle(.orange) } }
            }.listRowBackground(AppTheme.surface).listRowSeparatorTint(AppTheme.border)
        }.scrollContentBackground(.hidden).appPage()
            .navigationTitle("视频原声设置").navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(busy)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存原声设置") {
                        audio.stopPlayback()
                        if onSave(source) { didSave = true; dismiss() }
                    }.disabled(busy)
                }
            }
            .onAppear {
                if source == nil && initialFile == nil && !didSave { source = lesson.originalSource; initialFile = lesson.originalSource?.file }
            }
            .onDisappear {
                // Navigation to the clip editor also triggers onDisappear: only stop sound here.
                audio.stopPlayback()
            }
            .onChange(of: scenePhase) { _, phase in if phase == .background { work?.cancel() } }
            .fileImporter(isPresented: $chooseFile, allowedContentTypes: [.movie, .video, .mpeg4Movie]) { result in
                switch result { case .success(let url): importVideo(url); case .failure(let e): error = e.localizedDescription }
            }
            .onChange(of: photos) { _, item in
                guard let item else { return }
                busy = true; error = nil; status = "正在从照片读取视频…"
                work = Task { @MainActor in
                    defer { busy = false; photos = nil }
                    do {
                        guard let video = try await item.loadTransferable(type: PickedVideo.self) else { throw OriginalFiles.failure("无法读取这个视频。") }
                        defer { try? FileManager.default.removeItem(at: video.url) }
                        let imported = try await OriginalFiles.extract(video.url, prepared: lesson.preparedAudio)
                        replaceDraft(imported)
                    } catch is CancellationError { error = "已取消，原有原声不变。" }
                    catch { self.error = error.localizedDescription }
                }
            }
            .alert("移除原声？", isPresented: $confirmRemove) {
                Button("移除", role: .destructive) { audio.stopPlayback(); source = nil }
                Button("取消", role: .cancel) { }
            } message: { Text("保存设置后生效，文稿与自己的录音不受影响。") }
    }
    private func replaceDraft(_ imported: OriginalSource) {
        audio.stopPlayback()
        if let previous = source, previous.file != initialFile { try? FileManager.default.removeItem(at: OriginalFiles.url(previous)) }
        source = imported; status = ""
    }
    private func importVideo(_ url: URL) {
        busy = true; error = nil; status = "正在提取视频原声…"
        work = Task { @MainActor in
            defer { busy = false }
            do { replaceDraft(try await OriginalFiles.extract(url, prepared: lesson.preparedAudio)) }
            catch is CancellationError { error = "已取消，原有原声不变。" }
            catch { self.error = error.localizedDescription }
        }
    }

}

struct OriginalClipEditor: View {
    let target: OriginalTarget
    let source: OriginalSource
    let onSave: (OriginalClip) -> Void
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var audio: AudioController
    @State private var start: Double = 0
    @State private var end: Double = 1
    @State private var listened = false
    private var clip: OriginalClip { OriginalClip(id: target.id, text: target.en, start: start, end: end, score: 1, confirmed: true) }
    var body: some View {
        Form {
            Group {
                Section(target.title) { Text(target.zh); Text(target.en).foregroundStyle(AppTheme.secondary) }
                Section("起止时间（秒）") {
                    HStack { Text("开始（秒）"); TextField("开始秒数", value: $start, format: .number.precision(.fractionLength(2))).keyboardType(.decimalPad).accessibilityIdentifier("clipStart") }
                    Slider(value: $start, in: 0...max(0.1, source.duration - 0.1), step: 0.1)
                    HStack { Text("结束（秒）"); TextField("结束秒数", value: $end, format: .number.precision(.fractionLength(2))).keyboardType(.decimalPad).accessibilityIdentifier("clipEnd") }
                    Slider(value: $end, in: 0.1...max(0.1, source.duration), step: 0.1)
                    Text("范围：\(start.formatted(.number.precision(.fractionLength(1))))–\(end.formatted(.number.precision(.fractionLength(1)))) 秒 / 共\(Int(source.duration))秒")
                    if !clip.valid(duration: source.duration) { Text("开始必须小于结束，且不能超出音轨时长。").foregroundStyle(.orange) }
                }
                Section {
                    Button(audio.playingClipID == target.id ? "停止试听" : "试听当前片段") {
                        audio.playOriginal(OriginalFiles.url(source), clip: clip, duration: source.duration)
                        if audio.playingClipID == target.id { listened = true }
                    }.disabled(!clip.valid(duration: source.duration) || audio.busy).accessibilityIdentifier("previewOriginal")
                    Button("使用当前播放位置作为开始") { start = min(audio.playbackTime, source.duration - 0.1) }.disabled(audio.playingClipID == nil)
                    Button("使用当前播放位置作为结束") { end = min(source.duration, audio.playbackTime) }.disabled(audio.playingClipID == nil)
                    Button("确认此片段") { audio.stopPlayback(); onSave(clip); dismiss() }
                        .disabled(!listened || !clip.valid(duration: source.duration)).accessibilityIdentifier("confirmOriginal")
                    Text("先试听，确认句首句尾没有切断。修改时间后需要重新试听；可随时返回重调。")
                        .font(.footnote).foregroundStyle(AppTheme.secondary)
                }
            }.listRowBackground(AppTheme.surface).listRowSeparatorTint(AppTheme.border)
        }.scrollContentBackground(.hidden).appPage().navigationTitle("核对原声片段").navigationBarTitleDisplayMode(.inline)
            .onAppear {
                let existing = source.clips.first { $0.id == target.id }
                start = existing?.start ?? 0; end = existing?.end ?? min(source.duration, 10)
            }
            .onChange(of: start) { _, _ in listened = false; audio.stopPlayback() }
            .onChange(of: end) { _, _ in listened = false; audio.stopPlayback() }
            .onDisappear { audio.stopPlayback() }
    }
}

struct OriginalPlaybackButton: View {
    let lessonID: String
    let text: String
    var segmentID: String? = nil
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var audio: AudioController
    var body: some View {
        let source = store.data.lessons.first { $0.id == lessonID }?.originalSource
        VStack(alignment: .leading, spacing: 8) {
            if let source, let clip = OriginalMatching.clip(in: source, text: text, preferredID: segmentID.map { "read:" + $0 }) {
                Button {
                    audio.playOriginal(OriginalFiles.url(source), clip: clip, duration: source.duration)
                } label: {
                    Label(audio.playingClipID == clip.id && audio.playingURL == OriginalFiles.url(source) ? "停止朗读" : "朗读原文", systemImage: audio.playingClipID == clip.id ? "stop.circle.fill" : "play.circle.fill")
                }.buttonStyle(.bordered).disabled(audio.busy).accessibilityIdentifier("originalPlayback")
                    .contentTransition(.identity).animation(nil, value: audio.playingClipID)
                    .transaction { $0.animation = nil }
            } else {
                Text(source == nil ? "未添加视频原声，可在文稿页添加。" : "这段内容没有对应原文时间，请在文稿页核对。")
                    .font(.caption).foregroundStyle(AppTheme.secondary)
            }
        }
    }
}
