import Foundation
import IOKit

struct PowerReading: Equatable {
    var capturedAt: Date
    var batteryUpdatedAt: Date?
    var connected: Bool?
    var charging: Bool?
    var percentage: Int?
    var remainingMinutes: Int?
    var remainingMah: Int?
    var fullChargeMah: Int?
    var inputWatts: Double?
    var batteryWatts: Double?
    var inputVolts: Double?
    var inputAmps: Double?
    var adapterWatts: Double?
    var adapterName: String?
    var adapterManufacturer: String?
    var adapterModelHex: String?
    var adapterVolts: Double?
    var adapterAmps: Double?
    var adapterVendorHex: String?
    var adapterProductHex: String?
    var inputCounter: Int64?
    var issue: String?
    var inputIsLive = false

    static func unavailable(_ message: String, at date: Date = Date()) -> Self {
        Self(capturedAt: date, issue: message)
    }

    static func decode(_ properties: [String: Any], at now: Date = Date()) -> Self {
        func number(_ dictionary: [String: Any], _ key: String) -> Double? {
            guard let value = dictionary[key] as? NSNumber else { return nil }
            return Double(value.int64Value)
        }
        let telemetry = properties["PowerTelemetryData"] as? [String: Any] ?? [:]
        let adapter = properties["AdapterDetails"] as? [String: Any] ?? [:]
        let batteryData = properties["BatteryData"] as? [String: Any] ?? [:]
        let connected = (properties["ExternalConnected"] as? NSNumber)?.boolValue
        let charging = (properties["IsCharging"] as? NSNumber)?.boolValue
        let updated = number(properties, "UpdateTime").map { Date(timeIntervalSince1970: $0) }
        let batteryFresh = updated.map { (-5...90).contains(now.timeIntervalSince($0)) } ?? false
        var battery: Double?
        if batteryFresh, let mv = number(properties, "Voltage"),
           let ma = number(properties, "InstantAmperage"),
           (1...30000).contains(mv), abs(ma) <= 30000 {
            battery = mv * ma / 1_000_000
        }
        let rawInput = number(telemetry, "SystemPowerIn")
        // PD Discover Identity 上报的 USB-IF 厂商/产品 ID，第三方头唯一的身份线索
        let fed = (properties["FedDetails"] as? [[String: Any]] ?? []).first {
            ($0["FedExternalConnected"] as? NSNumber)?.boolValue == true
                && ($0["FedVendorID"] as? NSNumber)?.int64Value ?? 0 != 0
        }
        let input = connected == true ? rawInput.flatMap { (0...1_000_000).contains($0) ? $0 / 1000 : nil } : nil
        let percent = number(properties, "CurrentCapacity").flatMap { (0...100).contains($0) ? Int($0) : nil }
        return Self(
            capturedAt: now, batteryUpdatedAt: updated, connected: connected,
            charging: charging, percentage: percent,
            remainingMinutes: number(properties, "TimeRemaining")
                .flatMap { (0...60000).contains($0) && $0 != 65535 ? Int($0) : nil },
            remainingMah: number(batteryData, "RemainingCapacity")
                .flatMap { (0...100000).contains($0) ? Int($0) : nil },
            fullChargeMah: number(batteryData, "FullChargeCapacity")
                .flatMap { (0...100000).contains($0) ? Int($0) : nil },
            inputWatts: input,
            batteryWatts: battery,
            inputVolts: connected == true ? number(telemetry, "SystemVoltageIn").map { $0 / 1000 } : nil,
            inputAmps: connected == true ? number(telemetry, "SystemCurrentIn").map { $0 / 1000 } : nil,
            adapterWatts: connected == true ? number(adapter, "Watts") : nil,
            adapterName: connected == true ? (adapter["Name"] as? String ?? adapter["Description"] as? String) : nil,
            adapterManufacturer: connected == true ? adapter["Manufacturer"] as? String : nil,
            adapterModelHex: connected == true ? Self.modelHex(adapter["Model"]) : nil,
            adapterVolts: connected == true ? number(adapter, "AdapterVoltage").map { $0 / 1000 } : nil,
            adapterAmps: connected == true ? number(adapter, "Current").map { $0 / 1000 } : nil,
            adapterVendorHex: connected == true ? fed.flatMap({ Self.hex16($0["FedVendorID"]) }) : nil,
            adapterProductHex: connected == true ? fed.flatMap({ Self.hex16($0["FedProductID"]) }) : nil,
            inputCounter: (telemetry["SystemPowerInAccumulatorCount"] as? NSNumber)?.int64Value,
            issue: connected == nil ? "电源状态不可用" : (!batteryFresh ? "电池采样过期或不可用" : nil)
        )
    }

    var state: String {
        guard let connected else { return "数据不可用" }
        if !connected { return "电池供电" }
        if let batteryWatts, batteryWatts < -0.05 { return "已接电 · 电池辅助供电" }
        if charging == true { return "正在充电" }
        return charging == false ? "已接电 · 未充电" : "已接电 · 状态未知"
    }

    static func modelHex(_ value: Any?) -> String? {
        if let text = value as? String { return text }
        if let number = value as? NSNumber { return String(format: "0x%X", number.int64Value) }
        return nil
    }

    static func hex16(_ value: Any?) -> String? {
        guard let number = value as? NSNumber, number.int64Value != 0 else { return nil }
        return String(format: "%04X", number.int64Value)
    }

    var adapterShort: String? {
        guard let token = adapterName?.split(separator: " ").first, token.hasSuffix("W"),
              token.dropLast().allSatisfy(\.isNumber) else { return nil }
        return String(token)
    }

    // 系统 Model 编号 → 外壳印的市场型号（67W 实测 0x7016=A2518；0x7002 见 powerlog 96W 档纪录，用户确认持有 A2166）
    static let marketingModels = ["0x7016": "A2518", "0x7002": "A2166"]
    // USB-IF VID → 品牌（22D9 经用户实物确认为 OPPO；公开数据库对该 VID 记载冲突，不猜）
    static let usbVendors = ["22D9": "OPPO"]

    struct AdapterProfile {
        let name: String
        let model: String
        let protocols: String
    }

    // VID:PID → 用户提供的产品参数（2026-09-17 参数表截图）
    static let knownAdapters: [String: AdapterProfile] = [
        "22D9:001B": AdapterProfile(name: "OPPO SUPERVOOC 100W 小方瓶 Pro",
                                    model: "OSA00CB9BC",
                                    protocols: "SUPERVOOC · PD · PPS · UFCS · QC3.0")
    ]

    var adapterVendorName: String? {
        adapterVendorHex.flatMap { Self.usbVendors[$0] }
    }

    var adapterMarketingModel: String? {
        adapterModelHex.flatMap { Self.marketingModels[$0] }
    }

    var adapterProfile: AdapterProfile? {
        guard let vendor = adapterVendorHex, let product = adapterProductHex else { return nil }
        return Self.knownAdapters["\(vendor):\(product)"]
    }

    // 用户自定义资料/图片的键：第三方头用 VID:PID（唯一稳定），其余退回图片键
    var adapterIdentityKey: String? {
        if let vendor = adapterVendorHex, let product = adapterProductHex { return "\(vendor):\(product)" }
        return adapterImageKey
    }

    var adapterImageKey: String? {
        if let short = adapterShort?.lowercased() {
            let apple = adapterManufacturer?.lowercased().contains("apple") == true
            return apple ? "apple-\(short)" : short
        }
        return adapterName?.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber }).joined(separator: "-")
    }

    var batteryLabel: String {
        abs(batteryWatts ?? 0) < 0.05 ? "待机放电" : ((batteryWatts ?? 0) < 0 ? "电池净放电" : "电池净充电")
    }

    var remainingText: String? {
        guard let minutes = remainingMinutes else { return nil }
        return minutes >= 60 ? "\(minutes / 60) 小时 \(minutes % 60) 分" : "\(minutes) 分"
    }
    var capacityText: String? {
        guard let remaining = remainingMah else { return nil }
        return fullChargeMah.map { "\(remaining) / \($0) mAh" } ?? "\(remaining) mAh"
    }

    func watts(for metric: PowerMetric) -> Double? {
        metric == .input ? inputWatts : batteryWatts
    }
}

enum PowerMetric: String, CaseIterable, Identifiable {
    case input, battery
    var id: String { rawValue }
    var title: String { self == .input ? "Mac 输入" : "电池净功率" }
    var prefix: String { self == .input ? "入" : "电池" }
}

actor PowerReader {
    private var smc = smc_open()

    deinit { smc_close(smc) }

    func reset() {
        smc_close(smc)
        smc = smc_open()
    }

    private func sensor(_ key: String) -> Double? {
        var value = 0.0
        return smc_read(smc, key, &value) != 0 ? value : nil
    }

    func read() -> PowerReading {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return .unavailable("未找到内置电池") }
        defer { IOObjectRelease(service) }
        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dictionary = properties?.takeRetainedValue() as? [String: Any] else {
            return .unavailable("无法读取电源遥测")
        }
        var value = PowerReading.decode(dictionary)
        if value.connected == true, let watts = sensor("PDTR"), (0...1000).contains(watts) {
            value.inputWatts = watts
            value.inputVolts = sensor("VD0R").flatMap { (0...60).contains($0) ? $0 : nil }
            value.inputAmps = sensor("ID0R").flatMap { (0...20).contains($0) ? $0 : nil }
            value.inputIsLive = true
        } else if value.connected == true {
            value.issue = "输入为系统缓存，并非实时采样"
            if value.batteryUpdatedAt.map({ value.capturedAt.timeIntervalSince($0) > 90 }) ?? true {
                value.inputWatts = nil
                value.inputVolts = nil
                value.inputAmps = nil
            }
        }
        return value
    }
}

struct PowerPoint: Identifiable {
    let id = UUID()
    let date: Date
    let input: Double?
    let battery: Double?
    func watts(for metric: PowerMetric) -> Double? { metric == .input ? input : battery }
}

func powerText(_ value: Double?) -> String {
    guard let value, value.isFinite else { return "—" }
    return String(format: "%.1f", abs(value) < 0.05 ? 0 : value)
}

// 本机身份只读这四个字段；序列号/UUID 不取不显示
struct MachineInfo {
    static let shared = MachineInfo()
    let name: String
    let chip: String
    let memory: String
    let processors: String
    let gpuCores: Int

    init() {
        var fields: [String: String] = [:]
        var gpu = 0
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPHardwareDataType", "SPDisplaysDataType", "-json"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        if (try? process.run()) != nil {
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let top = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let entry = (top["SPHardwareDataType"] as? [[String: Any]])?.first {
                    for key in ["machine_name", "chip_type", "physical_memory", "number_processors"] {
                        fields[key] = entry[key] as? String
                    }
                }
                let gpuAny = (top["SPDisplaysDataType"] as? [[String: Any]])?.first?["sppci_cores"]
                gpu = (gpuAny as? Int) ?? Int(gpuAny as? String ?? "") ?? 0
            }
        }
        name = fields["machine_name"] ?? "这台 Mac"
        chip = fields["chip_type"] ?? ""
        memory = fields["physical_memory"] ?? ""
        processors = fields["number_processors"] ?? ""
        gpuCores = gpu
    }

    var title: String { [name, chip].filter { !$0.isEmpty }.joined(separator: " · ") }
    // number_processors 形如 "proc 14:0:10:4" = 总核:?:性能:能效
    var coreText: String {
        let parts = processors.split(separator: " ").last?.split(separator: ":").compactMap { Int($0) } ?? []
        let cpu = parts.count == 4 ? "\(parts[0]) 核 CPU（\(parts[2]) 性能 + \(parts[3]) 能效）" : ""
        return [cpu, gpuCores > 0 ? "\(gpuCores) 核 GPU" : ""].filter { !$0.isEmpty }.joined(separator: " · ")
    }
    var subtitle: String { memory.isEmpty ? "" : "\(memory) 统一内存" }
    var imageKey: String {
        name.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).joined(separator: "-")
    }
}

// ponytail: 矩形积分（上次功率 × dt）；>30s 的缺口（睡眠、采样中断）不计，
// 所以睡过一觉的接通累计会偏低——要准就得落盘记起点，YAGNI。
struct SessionEnergy {
    private(set) var wh = 0.0
    private(set) var seconds = 0.0
    private var lastAt: Date?
    private var lastConnected: Bool?

    mutating func add(connected: Bool, watts: Double, at: Date) {
        if let lastAt, connected == lastConnected {
            let dt = at.timeIntervalSince(lastAt)
            if dt > 0, dt < 30 {
                wh += watts * dt / 3600
                seconds += dt
            }
        } else {
            wh = 0
            seconds = 0
        }
        self.lastAt = at
        lastConnected = connected
    }

    var averageWatts: Double? { seconds > 0 ? wh / (seconds / 3600) : nil }
}
