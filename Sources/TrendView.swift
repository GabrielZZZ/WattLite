import SwiftUI

struct TrendView: View {
    let points: [PowerPoint]
    let metric: PowerMetric
    let now: Date
    let interval: Double

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
                Text(metric == .input ? "输入功率趋势" : "电池采样点")
                    .font(.system(size: 11, weight: .medium))
                Spacer()
                Text("\(Int(upper)) W").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Canvas { context, size in
                for fraction in [0.0, 0.5, 1.0] {
                    var rule = Path()
                    rule.move(to: CGPoint(x: 0, y: size.height * fraction))
                    rule.addLine(to: CGPoint(x: size.width, y: size.height * fraction))
                    context.stroke(rule, with: .color(.secondary.opacity(0.15)), style: StrokeStyle(lineWidth: 0.5, dash: [3, 4]))
                }
                var line = Path()
                var previous: Date?
                for point in values {
                    let x = size.width * (1 - now.timeIntervalSince(point.date) / 600)
                    let y = size.height * (1 - (point.watts - lower) / (upper - lower))
                    let position = CGPoint(x: x, y: y)
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
                context.stroke(line, with: .color(.teal), style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
            }
            .frame(height: 60)
            .overlay {
                if values.isEmpty {
                    Text("等待有效采样").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            .accessibilityLabel("最近十分钟，\(values.count) 个有效采样，范围 \(Int(lower)) 至 \(Int(upper)) 瓦")
            HStack {
                Text("10 分钟前")
                Spacer()
                Text("\(Int(lower)) W · 现在")
            }.font(.system(size: 9)).foregroundStyle(.secondary)
        }
    }
}
