import Foundation

struct LoggedPoint: Identifiable, Equatable {
    let date: Date
    let input: Double?
    let battery: Double?
    let percent: Int?
    let fullChargeMah: Int?
    let connected: Bool
    var id: Date { date }
}

// 分钟级聚合落盘：2 秒采样直接存一年上千万行，按分钟均值存一年约 50 万行 <20MB，
// CSV 本身即导出格式。时间戳为整分钟的 Unix 秒。
actor PowerLog {
    private static let header = "ts,input_w,battery_w,percent,full_charge_mah,connected\n"
    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private var handle: FileHandle?
    private var handleDay = ""
    private var bucketMinute: Int64 = -1
    private var inputSamples: [Double] = []
    private var batterySamples: [Double] = []
    private var percent: Int?
    private var fullChargeMah: Int?
    private var connected = false

    static var directory: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("WattLite/history", isDirectory: true)
    }

    func record(_ reading: PowerReading) {
        let minute = Int64(reading.capturedAt.timeIntervalSince1970 / 60)
        if bucketMinute >= 0, minute != bucketMinute { flushBucket() }
        bucketMinute = minute
        if let value = reading.inputWatts { inputSamples.append(value) }
        if let value = reading.batteryWatts { batterySamples.append(value) }
        if let value = reading.percentage { percent = value }
        if let value = reading.fullChargeMah { fullChargeMah = value }
        connected = connected || reading.connected == true
    }

    func flush() { flushBucket() }

    private func flushBucket() {
        guard bucketMinute >= 0, !inputSamples.isEmpty || !batterySamples.isEmpty || percent != nil else { return }
        func average(_ samples: [Double]) -> String {
            guard !samples.isEmpty else { return "" }
            return String(format: "%.2f", samples.reduce(0, +) / Double(samples.count))
        }
        let line = [
            "\(bucketMinute * 60)",
            average(inputSamples),
            average(batterySamples),
            percent.map(String.init) ?? "",
            fullChargeMah.map(String.init) ?? "",
            connected ? "1" : "0",
        ].joined(separator: ",")
        append(line, day: Date(timeIntervalSince1970: Double(bucketMinute * 60)))
        inputSamples.removeAll(keepingCapacity: true)
        batterySamples.removeAll(keepingCapacity: true)
        percent = nil
        fullChargeMah = nil
        connected = false
    }

    private func append(_ line: String, day: Date) {
        guard let directory = Self.directory else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = Self.dayFormatter.string(from: day)
        let url = directory.appendingPathComponent("\(name).csv")
        if handleDay != name {
            try? handle?.close()
            handle = nil
            handleDay = name
            if !FileManager.default.fileExists(atPath: url.path) {
                try? Self.header.write(to: url, atomically: true, encoding: .utf8)
            }
            handle = try? FileHandle(forWritingTo: url)
            _ = try? handle?.seekToEnd()
        }
        try? handle?.write(contentsOf: Data((line + "\n").utf8))
    }

    func load(day: Date) -> [LoggedPoint] {
        parse(fileURL(for: day))
    }

    func load(from start: Date, to end: Date, hourly: Bool) -> [LoggedPoint] {
        var points: [LoggedPoint] = []
        var day = Calendar.current.startOfDay(for: start)
        let lastDay = Calendar.current.startOfDay(for: end)
        while day <= lastDay {
            points.append(contentsOf: parse(fileURL(for: day)))
            day = Calendar.current.date(byAddingDay: day) ?? day.addingTimeInterval(86400)
        }
        let filtered = points.filter { $0.date >= start && $0.date <= end }
        return hourly ? Self.aggregateHourly(filtered) : filtered
    }

    private func fileURL(for day: Date) -> URL? {
        Self.directory?.appendingPathComponent("\(Self.dayFormatter.string(from: day)).csv")
    }

    private func parse(_ url: URL?) -> [LoggedPoint] {
        guard let url, let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        var points: [LoggedPoint] = []
        for line in text.split(separator: "\n").dropFirst() {
            let fields = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            guard fields.count == 6, let ts = Double(fields[0]) else { continue }
            points.append(LoggedPoint(
                date: Date(timeIntervalSince1970: ts),
                input: Double(fields[1]),
                battery: Double(fields[2]),
                percent: Int(fields[3]),
                fullChargeMah: Int(fields[4]),
                connected: fields[5] == "1"))
        }
        return points
    }

    private static func aggregateHourly(_ points: [LoggedPoint]) -> [LoggedPoint] {
        var buckets: [Int64: (input: [Double], battery: [Double], percent: Int?, fcc: Int?, connected: Bool)] = [:]
        for point in points {
            let hour = Int64(point.date.timeIntervalSince1970 / 3600)
            var bucket = buckets[hour] ?? ([], [], nil, nil, false)
            if let value = point.input { bucket.input.append(value) }
            if let value = point.battery { bucket.battery.append(value) }
            if let value = point.percent { bucket.percent = value }
            if let value = point.fullChargeMah { bucket.fcc = value }
            bucket.connected = bucket.connected || point.connected
            buckets[hour] = bucket
        }
        return buckets.keys.sorted().map { hour in
            let bucket = buckets[hour]!
            func average(_ samples: [Double]) -> Double? {
                samples.isEmpty ? nil : samples.reduce(0, +) / Double(samples.count)
            }
            return LoggedPoint(
                date: Date(timeIntervalSince1970: Double(hour * 3600)),
                input: average(bucket.input), battery: average(bucket.battery),
                percent: bucket.percent, fullChargeMah: bucket.fcc, connected: bucket.connected)
        }
    }
}

private extension Calendar {
    func date(byAddingDay date: Date) -> Date? {
        self.date(byAdding: .day, value: 1, to: date)
    }
}
