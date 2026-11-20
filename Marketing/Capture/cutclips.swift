// Cuts a simulator recording into named clips using the CAPTURE-MARK lines
// printed by MarketingCaptureTests.
// Usage: cutclips <recording.mp4> <recording-start-epoch> <xcodebuild.log> <output-dir>
import AVFoundation
import Foundation

let args = CommandLine.arguments
guard args.count == 5, let t0 = Double(args[2]) else {
    print("usage: cutclips <recording.mp4> <recording-start-epoch> <xcodebuild.log> <output-dir>")
    exit(1)
}

let log = try String(contentsOfFile: args[3], encoding: .utf8)
let pattern = try NSRegularExpression(pattern: #"CAPTURE-MARK (\S+) (start|end) ([0-9.]+)"#)
var starts: [String: Double] = [:]
var clips: [(name: String, start: Double, end: Double)] = []
for match in pattern.matches(in: log, range: NSRange(log.startIndex..., in: log)) {
    func group(_ i: Int) -> String { String(log[Range(match.range(at: i), in: log)!]) }
    let name = group(1), time = Double(group(3))! - t0
    if group(2) == "start" {
        if starts[name] == nil { starts[name] = time }
    } else if let start = starts[name], !clips.contains(where: { $0.name == name }) {
        clips.append((name, start, time))
    }
}
guard !clips.isEmpty else {
    print("no CAPTURE-MARK lines in \(args[3])")
    exit(1)
}

let asset = AVURLAsset(url: URL(fileURLWithPath: args[1]))
let duration = try await CMTimeGetSeconds(asset.load(.duration))
let outDir = URL(fileURLWithPath: args[4])
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

for clip in clips {
    // A little air on both sides; editors trim to taste.
    let start = max(0, clip.start - 0.25), end = min(duration, clip.end + 0.25)
    guard end > start else { print("✗ \(clip.name): outside the recording"); continue }
    let url = outDir.appendingPathComponent("\(clip.name).mp4")
    try? FileManager.default.removeItem(at: url)
    guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else { continue }
    export.timeRange = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600),
                                   end: CMTime(seconds: end, preferredTimescale: 600))
    do {
        try await export.export(to: url, as: .mp4)
        print("✓ \(clip.name) (\(String(format: "%.1f", end - start)) s)")
    } catch {
        print("✗ \(clip.name): \(error.localizedDescription)")
    }
}
