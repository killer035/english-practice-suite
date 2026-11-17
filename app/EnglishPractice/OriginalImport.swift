import Foundation
import AVFoundation
import CryptoKit
import PhotosUI
import CoreTransferable
import UniformTypeIdentifiers

struct PickedVideo: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in
            let size = try received.file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 600_000_000 else { throw OriginalFiles.failure("视频超过600 MB，请先裁剪后导入。") }
            let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "." + received.file.pathExtension)
            try FileManager.default.copyItem(at: received.file, to: destination)
            return Self(url: destination)
        }
    }
}
enum OriginalFiles {
    static var folder: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("OriginalAudio", isDirectory: true) }
    static func url(_ source: OriginalSource) -> URL { folder.appendingPathComponent(source.file) }
    static func failure(_ message: String) -> NSError { NSError(domain: "OriginalAudio", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    static func extract(_ url: URL, destinationFolder: URL = folder, prepared: PreparedAudio? = nil) async throws -> OriginalSource {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 600_000_000 else { throw failure("视频超过600 MB，请先裁剪或压缩后再导入。") }
        if let prepared {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            var digest = SHA256()
            while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
                try Task.checkCancellation()
                digest.update(data: chunk)
            }
            let hash = digest.finalize().map { String(format: "%02x", $0) }.joined()
            guard hash == prepared.videoSHA256.lowercased() else {
                throw failure("视频与这份文稿不对应。请选择制作文稿时的原始视频文件；请勿重新剪辑或压缩。若照片传输改变了视频，请改从‘文件’选择原文件。")
            }
        }
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration >= 0.5, duration <= 1200 else { throw failure("请选择时长不超过20分钟、至少半秒的视频。") }
        if let prepared, abs(duration - prepared.videoDuration) > 0.1 { throw failure("视频时长与文稿记录不一致，请重新选择原视频。") }
        guard !(try await asset.loadTracks(withMediaType: .audio)).isEmpty else { throw failure("这个视频没有音轨，请换一个有声音的视频。") }
        try FileManager.default.createDirectory(at: destinationFolder, withIntermediateDirectories: true)
        let file = UUID().uuidString + ".m4a"
        let destination = destinationFolder.appendingPathComponent(file)
        do {
            try await export(asset, to: destination, range: nil)
            try Task.checkCancellation()
            let audioDuration = try await AVURLAsset(url: destination).load(.duration).seconds
            guard audioDuration.isFinite, audioDuration > 0 else { throw failure("视频音轨为空。") }
            let result = OriginalSource(file: file, name: url.deletingPathExtension().lastPathComponent, duration: audioDuration)
            if let prepared { return try prepared.apply(to: result) }
            return result
        } catch { try? FileManager.default.removeItem(at: destination); throw error }
    }
    static func export(_ asset: AVAsset, to destination: URL, range: CMTimeRange?) async throws {
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else { throw failure("无法读取视频音轨。") }
        session.outputURL = destination; session.outputFileType = .m4a
        if let range { session.timeRange = range }
        await withTaskCancellationHandler(operation: {
            await withCheckedContinuation { continuation in
                session.exportAsynchronously { continuation.resume() }
            }
        }, onCancel: { session.cancelExport() })
        try Task.checkCancellation()
        guard session.status == .completed else { throw session.error ?? failure("音轨提取未完成，请重试。") }
    }
}

