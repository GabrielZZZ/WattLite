import CoreGraphics
import Foundation

// 打印目标进程的窗口 id 与尺寸，供 screencapture -l 使用
let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
guard let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { exit(1) }
for window in info {
    guard let owner = window[kCGWindowOwnerName as String] as? String,
          let pid = window[kCGWindowOwnerPID as String] as? Int,
          let number = window[kCGWindowNumber as String] as? Int,
          let layer = window[kCGWindowLayer as String] as? Int,
          owner == "WattLite", layer == 0 else { continue }
    let bounds = window[kCGWindowBounds as String] as? [String: CGFloat] ?? [:]
    print(pid, number, Int(bounds["Width"] ?? 0), Int(bounds["Height"] ?? 0))
}
