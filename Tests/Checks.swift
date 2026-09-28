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
        precondition(machine.coreText.contains("核 CPU") && machine.coreText.contains("核 GPU"))
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
        print("PASS: units, capacity vs actual power, zero charging, signed discharge, unplug, stale/missing data, formatting, session energy, machine model lookup")
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
}
