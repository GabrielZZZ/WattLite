import AVFoundation
import AppKit

// 把视频按固定 fps 解成 PNG 帧，供 PIL 拼 GIF（本机 ffmpeg 不可用）
let args = CommandLine.arguments
guard args.count >= 4, let fps = Double(args[3]) else { exit(1) }
let asset = AVURLAsset(url: URL(fileURLWithPath: args[1]))
let generator = AVAssetImageGenerator(asset: asset)
generator.appliesPreferredTrackTransform = true
generator.requestedTimeToleranceBefore = .zero
generator.requestedTimeToleranceAfter = .zero
let duration = CMTimeGetSeconds(asset.duration)
var frame = 0
var t = 0.0
while t < duration {
    let time = CMTime(seconds: t, preferredTimescale: 600)
    guard let image = try? generator.copyCGImage(at: time, actualTime: nil) else { t += 1 / fps; continue }
    let rep = NSBitmapImageRep(cgImage: image)
    guard let data = rep.representation(using: .png, properties: [:]) else { t += 1 / fps; continue }
    let name = String(format: "%@/%04d.png", args[2], frame)
    try? data.write(to: URL(fileURLWithPath: name))
    frame += 1
    t += 1 / fps
}
FileHandle.standardError.write("frames=\(frame)\n".data(using: .utf8)!)
