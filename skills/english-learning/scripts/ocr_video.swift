import Foundation
import AVFoundation
import Vision
let asset=AVURLAsset(url: URL(fileURLWithPath:CommandLine.arguments[1]))
let g=AVAssetImageGenerator(asset:asset);g.appliesPreferredTrackTransform=true;g.requestedTimeToleranceBefore = .zero;g.requestedTimeToleranceAfter = .zero
let duration=CMTimeGetSeconds(asset.duration)
var rows:[[String:Any]]=[]
for t in stride(from:0.0,to:duration,by:0.5) {
 autoreleasepool {
 do {
 let img=try g.copyCGImage(at:CMTime(seconds:t,preferredTimescale:600),actualTime:nil)
 let req=VNRecognizeTextRequest();req.recognitionLevel = .accurate;req.recognitionLanguages=["en-US","zh-Hans"];req.usesLanguageCorrection=true
 try VNImageRequestHandler(cgImage:img).perform([req])
 let lines=(req.results ?? []).compactMap { o -> [String:Any]? in
 guard let c=o.topCandidates(1).first else{return nil}
 return ["text":c.string,"confidence":c.confidence,"x":o.boundingBox.origin.x,"y":o.boundingBox.origin.y,"h":o.boundingBox.height]
 }
 rows.append(["t":t,"lines":lines])
 } catch {rows.append(["t":t,"error":error.localizedDescription])}
 }
 if Int(t*2)%40 == 0 {print("OCR",t);fflush(stdout)}
}
try JSONSerialization.data(withJSONObject:rows,options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:CommandLine.arguments[2]))
