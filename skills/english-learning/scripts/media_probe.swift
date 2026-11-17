import Foundation
import AVFoundation
let asset = AVURLAsset(url: URL(fileURLWithPath: CommandLine.arguments[1]))
guard let track = asset.tracks(withMediaType: .audio).first else { fatalError("No audio track") }
let value: [String: Double] = ["duration": CMTimeGetSeconds(asset.duration), "audioStart": CMTimeGetSeconds(track.timeRange.start), "audioDuration": CMTimeGetSeconds(track.timeRange.duration)]
let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
print(String(data: data, encoding: .utf8)!)
