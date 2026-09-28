import SwiftUI

struct TrendView: View {
    let points: [PowerPoint]
    let metric: PowerMetric
    let now: Date
    let interval: Double
    @ObservedObject private var l10n = L10n.shared

    private var samples: [(date: Date, watts: Double)] {
        points.compactMap { point in point.watts(for: metric).map { (point.date, $0) } }
            .filter { now.timeIntervalSince($0.date) >= 0 && now.timeIntervalSince($0.date) <= 600 }
            .sorted { $0.date < $1.date }
    }

    var body: some View {
        let values = samples
        let upper = max(10, ceil((values.map(\.watts).max() ?? 0) / 10) * 10)
        let lower = min(0, floor((values.map(\.watts).min() ?? 0) / 10) * 10)
        VStack(spacing: 8) {
            HStack {
                Text(T(metric == .input ? "输入功率趋势" : "电池采样点"))
                    .font(.system(size: 11, weight: .medium))
                Spacer()
                Text("\(Int(upper)) W").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Canvas { context, size in
                // ponytail: 上下各留 3pt，值贴上/下界的点不被裁半
                let pad: CGFloat = 3
                let plotH = size.height - 2 * pad
                for fraction in [0.0, 0.5, 1.0] {
                    var rule = Path()
                    rule.move(to: CGPoint(x: 0, y: pad + plotH * fraction))
                    rule.addLine(to: CGPoint(x: size.width, y: pad + plotH * fraction))
                    context.stroke(rule, with: .color(.secondary.opacity(0.15)), style: StrokeStyle(lineWidth: 0.5, dash: [3, 4]))
                }
                var line = Path()
                var previous: Date?
                var firstX: CGFloat?
                var lastX: CGFloat = 0
                for point in values {
                    let x = size.width * (1 - now.timeIntervalSince(point.date) / 600)
                    let y = pad + plotH * (1 - (point.watts - lower) / (upper - lower))
                    let position = CGPoint(x: x, y: y)
                    if firstX == nil { firstX = x }
                    lastX = x
                    if metric == .input {
                        if let previous, point.date.timeIntervalSince(previous) <= max(5, interval * 3) {
                            line.addLine(to: position)
                        } else { line.move(to: position) }
                    }
                    if metric == .battery || point.date == values.last?.date {
                        context.fill(Path(ellipseIn: CGRect(x: x - 2.5, y: y - 2.5, width: 5, height: 5)), with: .color(.teal))
                    }
                    previous = point.date
                }
                if let firstX, metric == .input {
                    var area = line
                    area.addLine(to: CGPoint(x: lastX, y: pad + plotH))
                    area.addLine(to: CGPoint(x: firstX, y: pad + plotH))
                    area.closeSubpath()
                    context.fill(area, with: .linearGradient(
                        Gradient(colors: [.teal.opacity(0.22), .teal.opacity(0.02)]),
                        startPoint: .zero, endPoint: CGPoint(x: 0, y: pad + plotH)))
                }
                var glow = context
                glow.addFilter(.shadow(color: .teal.opacity(0.5), radius: 3))
                glow.stroke(line, with: .color(.teal), style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                context.stroke(line, with: .color(.teal), style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
            }
            .frame(minHeight: 56, maxHeight: .infinity)
            .overlay {
                if values.count < 2 {
                    Text(T("等待有效采样")).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            .accessibilityLabel(TF("最近十分钟，%d 个有效采样，范围 %d 至 %d 瓦",
                                   values.count, Int(lower), Int(upper)))
            HStack {
                Text(T("10 分钟前"))
                Spacer()
                Text(TF("%d W · 现在", Int(lower)))
            }.font(.system(size: 9)).foregroundStyle(.secondary)
        }
    }
}
