import Foundation

@main
struct Checks {
    static func main() async {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var properties: [String: Any] = [
            "ExternalConnected": true, "IsCharging": true,
            "CurrentCapacity": 80, "UpdateTime": now.timeIntervalSince1970,
            "Voltage": 12000, "InstantAmperage": 2000,
            "AdapterDetails": ["Watts": 65, "Name": "67W USB-C Power Adapter",
                               "Manufacturer": "Apple Inc.", "Model": 0x7016],
            "PowerTelemetryData": ["SystemPowerIn": 40000, "SystemVoltageIn": 20000,
                                   "SystemCurrentIn": 2000, "SystemPowerInAccumulatorCount": 100],
            "BatteryData": ["RemainingCapacity": 5650, "FullChargeCapacity": 6247]
        ]
        let charging = PowerReading.decode(properties, at: now)
        precondition(charging.capacityText == "5650 / 6247 mAh")
        precondition(charging.inputWatts == 40 && charging.batteryWatts == 24)
        precondition(charging.adapterWatts == 65 && charging.state == "正在充电")
        precondition(charging.adapterShort == "67W" && charging.adapterModelHex == "0x7016")
        precondition(charging.adapterMarketingModel == "A2518" && charging.adapterImageKey == "apple-67w")
        precondition(charging.inputVolts == 20 && charging.inputAmps == 2)
        properties["IsCharging"] = false
        properties["InstantAmperage"] = 0
        let idle = PowerReading.decode(properties, at: now)
        precondition(idle.batteryWatts == 0 && idle.inputWatts == 40)
        precondition(idle.state == "已接电 · 未充电")
        properties["InstantAmperage"] = NSNumber(value: UInt64(bitPattern: Int64(-1500)))
        let assisting = PowerReading.decode(properties, at: now)
        precondition(assisting.batteryWatts == -18 && assisting.state == "已接电 · 电池辅助供电")
        properties["ExternalConnected"] = false
        properties["TimeRemaining"] = 200
        let unplugged = PowerReading.decode(properties, at: now)
        precondition(unplugged.inputWatts == nil && unplugged.adapterWatts == nil)
        precondition(unplugged.remainingMinutes == 200 && unplugged.remainingText == "3 小时 20 分")
        properties["TimeRemaining"] = 65535
        precondition(PowerReading.decode(properties, at: now).remainingMinutes == nil)
        properties["TimeRemaining"] = 200
        precondition(unplugged.adapterName == nil && unplugged.adapterImageKey == nil)
        precondition(unplugged.batteryWatts == -18 && unplugged.state == "电池供电")
        let stale = PowerReading.decode(properties, at: now.addingTimeInterval(91))
        precondition(stale.batteryWatts == nil)
        let missing = PowerReading.decode([:], at: now)
        precondition(missing.batteryWatts == nil && missing.inputWatts == nil && missing.connected == nil)
        properties["InstantAmperage"] = "invalid"
        precondition(PowerReading.decode(properties, at: now).batteryWatts == nil)
        properties["ExternalConnected"] = true
        properties["AdapterDetails"] = ["Watts": 65, "Description": "pd charger",
                                        "AdapterVoltage": 20000, "Current": 3250]
        properties["FedDetails"] = [["FedExternalConnected": true,
                                     "FedVendorID": 8921, "FedProductID": 27]]
        let generic = PowerReading.decode(properties, at: now)
        precondition(generic.adapterName == "pd charger" && generic.adapterShort == nil)
        precondition(generic.adapterVolts == 20 && generic.adapterAmps == 3.25)
        precondition(generic.adapterVendorHex == "22D9" && generic.adapterVendorName == "OPPO")
        precondition(generic.adapterProfile?.model == "OSA00CB9BC")
        precondition(generic.adapterMarketingModel == nil && generic.adapterImageKey == "pd-charger")
        properties.removeValue(forKey: "FedDetails")
        properties["AdapterDetails"] = ["Watts": 94, "Name": "96W USB-C Power Adapter",
                                        "Manufacturer": "Apple Inc.", "Model": 0x7002]
        let apple96 = PowerReading.decode(properties, at: now)
        precondition(apple96.adapterShort == "96W" && apple96.adapterWatts == 94)
        precondition(apple96.adapterMarketingModel == "A2166" && apple96.adapterImageKey == "apple-96w")
        precondition(powerText(-0.001) == "0.0" && powerText(nil) == "—")
        precondition(MacModels.names.count == 72)
        precondition(MacModels.name(for: "Mac16,8") == "MacBook Pro (14-inch, 2024)")
        precondition(MacModels.name(for: "MacBookPro18,3") == "MacBook Pro (14-inch, 2021)")
        precondition(MacModels.name(for: "Mac15,14") == "Mac Studio (M3 Ultra, 2025)")
        precondition(MacModels.name(for: "Mac18,5") == "Mac mini (M6, 2026)")
        precondition(MacModels.name(for: "iMac21,2") == "iMac (24-inch, M1, 2021)")
        precondition(MacModels.name(for: "Mac99,1") == nil)
        // 图片按标识符命名（Assets/Adapters/<slug>.png），标识符里的逗号必须被 slug 吃掉
        for id in MacModels.names.keys {
            let key = MachineInfo.slug(id)
            precondition(!key.isEmpty && !key.contains(",") && !key.contains(" ") && key == key.lowercased())
        }
        let machine = MachineInfo.shared
        precondition(!machine.name.isEmpty && !machine.imageKey.isEmpty && !machine.familyImageKey.isEmpty)
        // 端到端：本机标识符若在表里，展示名必须等于表里的营销名
        precondition(MacModels.name(for: machine.identifier) == nil
                     || machine.name == MacModels.name(for: machine.identifier))
        // 语言表：占位符种类与数量必须一一对应，切英文才不会崩格式
        for (zh, en) in Strings.en where zh.contains("%") {
            precondition(Self.placeholders(zh) == Self.placeholders(en), zh)
        }
        L10n.shared.lang = .en
        precondition(T("正在充电") == "Charging" && TF("%d 小时 %d 分", 3, 20) == "3h 20m")
        precondition(charging.state == "Charging" && machine.coreText.contains("-core CPU"))
        precondition(T("表里没有的串") == "表里没有的串")
        L10n.shared.lang = .zh
        precondition(charging.state == "正在充电" && machine.coreText.contains("核 CPU")
                     && machine.coreText.contains("核 GPU"))
        var session = SessionEnergy()
        let step = Double(10) / 3600
        session.add(connected: true, watts: 60, at: now)
        precondition(session.wh == 0)
        session.add(connected: true, watts: 60, at: now.addingTimeInterval(10))
        precondition(abs(session.wh - 60 * step) < 1e-9 && session.seconds == 10
                     && abs((session.averageWatts ?? 0) - 60) < 1e-9)
        session.add(connected: true, watts: 60, at: now.addingTimeInterval(100))
        precondition(abs(session.wh - 60 * step) < 1e-9)
        session.add(connected: false, watts: 18, at: now.addingTimeInterval(110))
        precondition(session.wh == 0 && session.seconds == 0 && session.averageWatts == nil)
        session.add(connected: false, watts: 18, at: now.addingTimeInterval(120))
        precondition(abs(session.wh - 18 * step) < 1e-9)
        // 能量参照物：档位递增、每档计数 ≥ 1、动态键必须有英文（T() 扫描抓不到它们）
        var previousMin = 0.0
        for tier in SessionEnergy.references {
            precondition(tier.minWh > previousMin && tier.minWh >= tier.unitWh, tier.zh)
            precondition(Strings.en[tier.zh] != nil, tier.zh)
            previousMin = tier.minWh
        }
        precondition(SessionEnergy.comparison(0.05) == nil)
        for wh in [0.122, 2.9, 3.0, 8.9, 23.3, 59.9, 93.0, 249.9, 1000.0, 2999.9, 3000.0, 5000.0] {
            guard let found = SessionEnergy.comparison(wh) else { preconditionFailure("缺档位: \(wh)") }
            precondition(found.count >= 1, "档位边界会让计数小于 1: \(wh) → \(found)")
        }
        L10n.shared.lang = .en
        precondition(TF(SessionEnergy.comparison(15.9)!.zh, SessionEnergy.comparison(15.9)!.count) == "💡 ≈ 1.8 h LED bulb")
        L10n.shared.lang = .zh
        precondition(TF(SessionEnergy.comparison(15.9)!.zh, SessionEnergy.comparison(15.9)!.count) == "💡 ≈ 1.8 小时 LED 灯")
        // 覆盖检查：Sources 里每个 T("…")/TF("…") 的中文键都必须有英文，否则英文界面会漏出中文
        var untranslated: [String] = []
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Sources")
        let files = (try? FileManager.default.contentsOfDirectory(at: sources, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension == "swift" && $0.lastPathComponent != "Strings.swift" } ?? []
        for file in files.sorted(by: { $0.path < $1.path }) {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            for marker in ["T(\"", "TF(\""] {
                var cursor = text.startIndex
                while let hit = text.range(of: marker, range: cursor..<text.endIndex) {
                    var index = hit.upperBound
                    var key = ""
                    while index < text.endIndex, text[index] != "\"" {
                        if text[index] == "\\", index < text.endIndex {
                            let next = text.index(after: index)
                            if next < text.endIndex, text[next] == "n" { key.append("\n"); index = text.index(after: next); continue }
                            if next < text.endIndex, text[next] == "\"" { key.append("\""); index = text.index(after: next); continue }
                        }
                        key.append(text[index])
                        index = text.index(after: index)
                    }
                    cursor = index < text.endIndex ? text.index(after: index) : text.endIndex
                    if key.unicodeScalars.contains(where: { (0x4E00...0x9FFF).contains($0.value) }),
                       Strings.en[key] == nil {
                        untranslated.append("\(file.lastPathComponent): \(key)")
                    }
                }
            }
        }
        precondition(untranslated.isEmpty, "缺英文译文：\n" + untranslated.joined(separator: "\n"))
        print("PASS: units, capacity vs actual power, zero charging, signed discharge, unplug, stale/missing data, formatting, session energy, machine model lookup, zh/en strings")
        if CommandLine.arguments.contains("--live") {
            let reader = PowerReader()
            for index in 0..<8 {
                let value = await reader.read()
                let vi = value.inputVolts.flatMap { v in value.inputAmps.map { v * $0 } }
                print("SMC=\(value.inputIsLive) input=\(powerText(value.inputWatts))W V×I=\(powerText(vi))W battery=\(powerText(value.batteryWatts))W \(value.state)")
                if index < 7 { try? await Task.sleep(for: .seconds(1)) }
            }
        }
    }

    /// 格式串里的占位符类型序列（%% 不算），用于校验中英两边逐一对应
    static func placeholders(_ text: String) -> [String] {
        let chars = Array(text)
        var out: [String] = []
        var index = 0
        while index < chars.count {
            guard chars[index] == "%" else { index += 1; continue }
            var next = index + 1
            if next < chars.count, chars[next] == "%" { index = next + 1; continue }
            while next < chars.count, !chars[next].isLetter, chars[next] != "@" { next += 1 }
            precondition(next < chars.count, text)
            out.append(String(chars[next]))
            index = next + 1
        }
        return out
    }
}
