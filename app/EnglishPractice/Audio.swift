import Foundation
import AVFoundation

@MainActor
final class AudioController: NSObject, ObservableObject, AVAudioRecorderDelegate, AVAudioPlayerDelegate, AVSpeechSynthesizerDelegate {
    @Published var recording = false
    @Published var requesting = false
    @Published var message: String?
    @Published var pending: PracticeRecord?
    @Published private(set) var playingURL: URL?
    @Published private(set) var speaking = false
    @Published private(set) var playbackError: String?
    @Published private(set) var playingClipID: String?
    private var clipTimer: Timer?
    private var activeUtterance: AVSpeechUtterance?
    private var interruptionObserver: NSObjectProtocol?
    override init() {
        super.init()
        speech.delegate = self
        interruptionObserver = NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] notification in
            let began = (notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt) == AVAudioSession.InterruptionType.began.rawValue
            if began { Task { @MainActor [weak self] in self?.stopPlayback() } }
        }
    }
    deinit { if let interruptionObserver { NotificationCenter.default.removeObserver(interruptionObserver) } }
    func clearPlaybackError() { playbackError = nil }
    var playbackTime: TimeInterval { player?.currentTime ?? 0 }
    var playbackDuration: TimeInterval { player?.duration ?? 0 }
    var outputName: String { AVAudioSession.sharedInstance().currentRoute.outputs.map(\.portName).joined(separator: "、") }
    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    private var current: PracticeRecord?
    private let speech = AVSpeechSynthesizer()
    var busy: Bool { recording || requesting || pending != nil }
    func start(lesson: Lesson, exercise: Exercise, mode: PracticeMode) async {
        guard !busy else { return }
        requesting = true
        defer { requesting = false }
        let allowed = await AVAudioApplication.requestRecordPermission()
        guard allowed else { message = "请在 iPhone 设置中为英语随身练开启麦克风权限。"; return }
        do {
            stopPlayback()
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)
            let id = UUID().uuidString
            let file = "\(id).m4a"
            let url = LibraryStore.folder.appendingPathComponent(file)
            let recorder = try AVAudioRecorder(url: url, settings: [AVFormatIDKey: Int(kAudioFormatMPEG4AAC), AVSampleRateKey: 44100, AVNumberOfChannelsKey: 1, AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue])
            recorder.delegate = self
            guard recorder.record() else { throw CocoaError(.fileWriteUnknown) }
            self.recorder = recorder
            current = PracticeRecord(id: id, lessonID: lesson.id, lessonTitle: lesson.title, questionID: exercise.id, question: exercise.chinese, mode: mode.rawValue, date: Date(), file: file)
            recording = true
            message = "正在录音，说完后点停止。"
        } catch { message = "无法开始录音：\(error.localizedDescription)" }
    }
    func stop() { recorder?.stop() }
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor in
            self.recording = false
            if flag {
                self.pending = self.current
                self.message = "录音已结束，正在保存记录。"
            } else {
                self.message = "录音未正常完成；未标记为已保存，请重新录制。"
            }
            self.current = nil
            self.recorder = nil
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }
    func savePending(to store: LibraryStore) {
        guard let record = pending else { return }
        if store.commit({ $0.records.insert(record, at: 0) }) {
            pending = nil
            message = "录音已保存，可在首页“我的录音与回听”中查看。"
        } else { message = "录音文件已保留，请点重试保存；也可以先分享备份。" }
    }
    func stopPlayback() {
        clipTimer?.invalidate(); clipTimer = nil; playingClipID = nil
        player?.delegate = nil
        player?.stop(); player = nil; playingURL = nil
        activeUtterance = nil; speaking = false
        speech.stopSpeaking(at: .immediate)
        if !recording && !requesting {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }
    private func activatePlayback() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [])
        try session.setActive(true)
    }
    func play(_ url: URL) {
        guard !busy else { return }
        if playingURL == url { stopPlayback(); return }
        stopPlayback()
        playbackError = nil; message = nil
        do {
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw NSError(domain: "Audio", code: 1, userInfo: [NSLocalizedDescriptionKey: "录音文件不存在，可能已被移除。"])
            }
            try activatePlayback()
            let candidate = try AVAudioPlayer(contentsOf: url)
            guard candidate.duration > 0, candidate.prepareToPlay() else { throw CocoaError(.fileReadCorruptFile) }
            candidate.delegate = self
            player = candidate
            guard candidate.play() else { throw CocoaError(.fileReadCorruptFile) }
            playingURL = url
        } catch {
            stopPlayback()
            playbackError = "播放失败：\(error.localizedDescription)"
            message = playbackError
        }
    }
    func playOriginal(_ url: URL, clip: OriginalClip, duration: Double) {
        guard !busy else { return }
        if playingClipID == clip.id && playingURL == url { stopPlayback(); return }
        stopPlayback(); playbackError = nil
        do {
            guard clip.valid(duration: duration) else { throw CocoaError(.validationMissingMandatoryProperty) }
            try activatePlayback()
            let candidate = try AVAudioPlayer(contentsOf: url)
            guard clip.end <= candidate.duration + 0.1 else { throw CocoaError(.fileReadCorruptFile) }
            candidate.delegate = self; candidate.currentTime = clip.start
            player = candidate
            guard candidate.prepareToPlay(), candidate.play() else { throw CocoaError(.fileReadCorruptFile) }
            playingURL = url; playingClipID = clip.id
            clipTimer = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.playingClipID == clip.id else { return }
                    if self.playbackTime >= clip.end { self.stopPlayback() }
                }
            }
        } catch { stopPlayback(); playbackError = "原声播放失败：\(error.localizedDescription)" }
    }
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            guard self.player === player else { return }
            self.stopPlayback()
            if !flag { self.playbackError = "这条录音未能完整播放，请尝试分享后在文件 App 中打开。" }
        }
    }
    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor in
            guard self.player === player else { return }
            self.stopPlayback()
            self.playbackError = "录音解码失败：\(error?.localizedDescription ?? "音频数据异常")"
        }
    }
    func speak(_ text: String) {
        guard !busy else { return }
        if speaking { stopPlayback(); return }
        stopPlayback(); playbackError = nil
        do {
            try activatePlayback()
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
            utterance.rate = 0.43
            activeUtterance = utterance; speaking = true
            speech.speak(utterance)
        } catch { playbackError = "朗读失败：\(error.localizedDescription)"; message = playbackError }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            guard self.activeUtterance === utterance else { return }
            self.activeUtterance = nil; self.speaking = false
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            guard self.activeUtterance === utterance else { return }
            self.activeUtterance = nil; self.speaking = false
        }
    }
}
