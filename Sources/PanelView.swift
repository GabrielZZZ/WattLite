import SwiftUI
import AppKit
import ServiceManagement
import UniformTypeIdentifiers

private enum Style {
    static let accent = Color.teal
    static let inset: CGFloat = 18
    static let cardRadius: CGFloat = 14
    static let surface = Color(nsColor: .controlBackgroundColor)
    static let canvas = Color(nsColor: .windowBackgroundColor)
    // 两张产品卡共用：缩略图同尺寸、文字块同高且顶对齐，保证上下卡片文字对齐、卡片等大
    static let cardThumb = CGSize(width: 76, height: 56)
    static let cardTextHeight: CGFloat = 48
}

// 只缓存命中的图；未命中每秒重探一次，用户放入图片后无需重启
private enum AdapterImages {
    private static var cache: [String: NSImage] = [:]

    static func image(forKeys keys: [String?]) -> NSImage? {
        for key in keys.compactMap({ $0 }) {
            if let hit = image(for: key) { return hit }
        }
        return nil
    }

    static func evict(_ key: String) { cache.removeValue(forKey: key) }

    static func image(for key: String) -> NSImage? {
        if let hit = cache[key] { return hit }
        let dropIn = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("WattLite/adapters/\(key).png")
        let found = dropIn.flatMap { NSImage(contentsOf: $0) }
            ?? Bundle.main.url(forResource: key, withExtension: "png", subdirectory: "Adapters")
                .flatMap { NSImage(contentsOf: $0) }
        if let found { cache[key] = found }
        return found
    }
}

struct PanelView: View {
    @ObservedObject var store: PowerStore
    @ObservedObject private var library = AdapterLibrary.shared
    @State private var settings = false
    @State private var editingAdapter = false
    @State private var information = false
    private var reading: PowerReading { store.reading }
    // 接电时输入为主数字、电池降为副行；断接时输入侧无数据，回落电池口径
    private var effectiveMetric: PowerMetric { reading.connected == false ? .battery : .input }
    private var watts: Double? { reading.watts(for: effectiveMetric) }
    private var isCharging: Bool { reading.connected == true && reading.charging == true }
    @State private var dotPulse = false
    private static let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Style.accent)
                    .symbolEffect(.pulse, options: .repeating, isActive: isCharging && !Self.reduceMotion)
                    .frame(width: 32, height: 32)
                    .background(Style.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                Text("WattLite").font(.system(size: 15, weight: .semibold))
                Spacer()
                if let percentage = reading.percentage {
                    Label("\(percentage)%", systemImage: batterySymbol)
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                        .accessibilityLabel("电量 \(percentage)%")
                }
            }
            // ponytail: 仪表盘不滚动——卡片拉伸吃掉空白；只有会溢出的设置/编辑走 ScrollView。
            // 外层高度必须固定：popover 跟 SwiftUI ideal size 走，maxHeight 会让 ScrollView ideal 反馈震荡。
            if editingAdapter {
                ScrollView(.vertical, showsIndicators: false) {
                    AdapterEditor(reading: reading) { editingAdapter = false }
                }
            } else if settings {
                ScrollView(.vertical, showsIndicators: false) { settingsContent }
            } else {
                dashboard
            }
            Divider()
            HStack {
                Text(settings ? "本地运行 · 无网络请求" : sourceCaption)
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer()
                Button { settings.toggle() } label: {
                    Image(systemName: settings ? "arrow.left" : "gearshape")
                        .frame(width: 28, height: 28)
                }
                .help(settings ? "返回功率面板" : "设置")
                .accessibilityLabel(settings ? "返回功率面板" : "设置")
                Button { NSApp.terminate(nil) } label: {
                    Image(systemName: "power").frame(width: 28, height: 28)
                }.help("退出 WattLite").accessibilityLabel("退出 WattLite")
            }
            .buttonStyle(.borderless)
        }
        .padding(Style.inset)
        .frame(width: 380, height: 740)
        .background(Style.canvas)
        .tint(Style.accent)
    }

    private var sourceCaption: String {
        reading.inputIsLive ? "SMC 直读 · 输入侧功率" : "系统缓存 · 非实时输入"
    }

    private var batterySymbol: String {
        let level: String
        switch reading.percentage ?? 0 {
        case 95...: level = "100"
        case 70..<95: level = "75"
        case 45..<70: level = "50"
        case 20..<45: level = "25"
        default: level = "0"
        }
        return "battery.\(level)percent\(reading.charging == true ? ".bolt" : "")"
    }

    private var dashboard: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(powerText(watts))
                        .font(.system(size: 62, weight: .light, design: .rounded))
                        .monospacedDigit().tracking(-2)
                    Text("W").font(.system(size: 22, weight: .regular)).foregroundStyle(.secondary)
                    Spacer()
                    Button { information.toggle() } label: {
                        Image(systemName: "info.circle").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain).accessibilityLabel("功率数据说明")
                    .popover(isPresented: $information) {
                        Text("Mac 输入：优先读取 SMC PDTR，包含机器运行与充电所需电能，不是插座端功率。\n\n电池净功率：电池电压 × 有符号电流。正值充电，负值放电；系统通常约每分钟更新，不能与输入瞬时值直接相减。\n\n适配器容量是供电能力，不是实时功率。传感器为未公开接口，精度未经外部功率计校准；不可用时不估造数据。")
                            .font(.system(size: 12)).lineSpacing(4).padding(20).frame(width: 310)
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("\(effectiveMetric.title) \(powerText(watts)) 瓦")
                HStack(spacing: 6) {
                    Circle().fill(reading.connected == true ? Style.accent : Color.secondary)
                        .frame(width: 6, height: 6)
                        .scaleEffect(isCharging && dotPulse && !Self.reduceMotion ? 1.45 : 1)
                        .shadow(color: isCharging && !Self.reduceMotion ? Style.accent.opacity(dotPulse ? 0.9 : 0.3) : .clear,
                                radius: dotPulse ? 5 : 2)
                        .onAppear {
                            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { dotPulse = true }
                        }
                    Text(reading.state).font(.system(size: 12, weight: .medium))
                    Spacer()
                    Text(effectiveMetric == .input && reading.inputIsLive ? "实时读取" : "系统采样")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Text(batteryLine).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            // 粒子跟电池数据走，常驻主数字块（动效包规格：动效落在带电池数字的面上）
            .background(CardParticles(watts: reading.batteryWatts ?? 0, animate: !Self.reduceMotion)
                .clipShape(RoundedRectangle(cornerRadius: Style.cardRadius)))
            TrendView(points: store.history, metric: effectiveMetric, now: reading.capturedAt, interval: store.interval)
            VStack(spacing: 5) {
                detail("输入电压", reading.inputVolts.map { String(format: "%.2f V", $0) } ?? "—")
                detail("输入电流", reading.inputAmps.map { String(format: "%.2f A", $0) } ?? "—")
                detail("电池剩余容量", reading.capacityText ?? "—")
            }
            if reading.connected == true {
                let name = adapterDisplayName
                HStack(spacing: 12) {
                    productThumbnail(keys: [reading.adapterImageKey, reading.adapterIdentityKey],
                                     emptyLabel: "暂无充电头产品图", emptyIcon: "powerplug.fill")
                    VStack(alignment: .leading, spacing: 3) {
                        Text(name).font(.system(size: 12, weight: .medium)).lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(adapterSubtitle).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(height: Style.cardTextHeight, alignment: .top)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 6) {
                        Text(reading.adapterWatts.map { String(format: "%.0f W", $0) } ?? "—")
                            .font(.system(size: 15, weight: .medium, design: .rounded)).monospacedDigit()
                            .foregroundStyle(.secondary)
                        Button { editingAdapter = true } label: {
                            Image(systemName: "square.and.pencil")
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        .help("编辑适配器图案与信息")
                        .accessibilityLabel("编辑适配器图案与信息")
                    }
                }
                .padding(10)
                .background(Style.surface, in: RoundedRectangle(cornerRadius: Style.cardRadius))
                .accessibilityElement(children: .combine)
                .accessibilityLabel("充电头 \(name)，\(adapterSubtitle)")
            }
            machineCard
            if let issue = reading.issue {
                Text(issue).font(.system(size: 10)).foregroundStyle(.secondary)
            } else {
                Text("电池净功率正值为充电、负值为放电；与输入采样不同步，不作差值推算。")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            sessionCard
        }
    }

    private var batteryAge: String {
        guard let date = reading.batteryUpdatedAt else { return "系统采样时间未知" }
        return "系统采样 · \(max(0, Int(reading.capturedAt.timeIntervalSince(date)))) 秒前"
    }

    private var batteryLine: String {
        guard reading.connected == true, reading.batteryWatts != nil else { return batteryAge }
        return "\(reading.batteryLabel) \(powerText(reading.batteryWatts.map(abs))) W · \(batteryAge)"
    }

    private var sessionCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(reading.connected == true ? "本次接通输入能量" : "本次断接放出能量")
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Text("\(String(format: "%.1f", store.session.wh)) Wh")
                    .font(.system(size: 22, weight: .medium, design: .rounded)).monospacedDigit()
            }
            Spacer(minLength: 0)
            HStack(alignment: .firstTextBaseline, spacing: 18) {
                sessionStat("时长", durationText(store.session.seconds))
                sessionStat("平均功率", store.session.averageWatts.map { "\(String(format: "%.1f", $0)) W" } ?? "—")
                Spacer()
                Text(sessionEta).font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Style.surface, in: RoundedRectangle(cornerRadius: Style.cardRadius))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("本次会话能量 \(String(format: "%.1f", store.session.wh)) 瓦时")
    }

    private func sessionStat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 10)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 13, weight: .medium)).monospacedDigit()
        }
    }

    private func durationText(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        return minutes >= 60 ? "\(minutes / 60) 小时 \(minutes % 60) 分" : "\(minutes) 分"
    }

    private var sessionEta: String {
        if reading.connected == true {
            if reading.charging == true, let eta = reading.remainingText { return "系统预计 \(eta)充满" }
            return "未充电"
        }
        return reading.remainingText.map { "预计剩余 \($0)" } ?? "电池供电"
    }

    // 用户条目只要有任一文字字段就算“有资料”，纯图片条目仍回落到系统/内置信息
    private var userAdapterEntry: AdapterLibrary.Entry? {
        guard let entry = library.entry(for: reading.adapterIdentityKey) else { return nil }
        return [entry.name, entry.model, entry.protocols].allSatisfy(\.isEmpty) ? nil : entry
    }

    private var adapterDisplayName: String {
        userAdapterEntry?.name.nonEmpty ?? reading.adapterProfile?.name ?? reading.adapterName ?? "未知适配器"
    }

    private var adapterSubtitle: String {
        var parts: [String] = []
        let builtIn = reading.adapterProfile
        if let user = userAdapterEntry {
            if let model = user.model.nonEmpty ?? builtIn?.model { parts.append("型号 \(model)") }
            if let protocols = user.protocols.nonEmpty ?? builtIn?.protocols { parts.append(protocols) }
        } else if builtIn != nil {
            parts.append("型号 \(builtIn!.model)")
            parts.append(builtIn!.protocols)
        } else {
            if let maker = reading.adapterManufacturer { parts.append(maker) }
            else if let brand = reading.adapterVendorName { parts.append(brand) }
            if let marketing = reading.adapterMarketingModel { parts.append("型号 \(marketing)") }
            else if let hex = reading.adapterModelHex { parts.append("型号 \(hex)") }
        }
        if userAdapterEntry == nil, reading.adapterProfile == nil, reading.adapterModelHex == nil,
           let volts = reading.adapterVolts, let amps = reading.adapterAmps {
            parts.append(String(format: "额定 %.1f V · %.2f A", volts, amps))
        }
        if let vendor = reading.adapterVendorHex, reading.adapterVendorName == nil {
            parts.append("USB \(vendor):\(reading.adapterProductHex ?? "----")")
        }
        return parts.joined(separator: " · ")
    }

    private var machineCard: some View {
        let machine = MachineInfo.shared
        return HStack(spacing: 12) {
            productThumbnail(keys: [machine.imageKey], emptyLabel: "暂无本机图", emptyIcon: "laptopcomputer")
            VStack(alignment: .leading, spacing: 3) {
                Text(machine.title).font(.system(size: 12, weight: .medium)).lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(machine.coreText).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(machine.subtitle).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(height: Style.cardTextHeight, alignment: .top)
            Spacer()
            if reading.connected == false {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("预计剩余").font(.system(size: 9)).foregroundStyle(.secondary)
                    Text(reading.remainingText ?? "—")
                        .font(.system(size: 15, weight: .medium, design: .rounded)).monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .background(Style.surface, in: RoundedRectangle(cornerRadius: Style.cardRadius))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("本机 \(machine.title)，\(machine.coreText)，\(machine.subtitle)")
    }

    @ViewBuilder
    private func productThumbnail(keys: [String?], emptyLabel: String, emptyIcon: String,
                                  size: CGSize = Style.cardThumb) -> some View {
        if let image = AdapterImages.image(forKeys: keys) {
            Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                .frame(width: size.width, height: size.height)
                .clipShape(RoundedRectangle(cornerRadius: 9))
                .accessibilityLabel("产品图")
        } else {
            VStack(spacing: 2) {
                Image(systemName: emptyIcon).font(.system(size: 15)).foregroundStyle(.secondary)
                Text("无产品图").font(.system(size: 8)).foregroundStyle(.secondary)
            }
            .frame(width: size.width, height: size.height)
            .background(Style.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
            .help("点击卡片右侧铅笔按钮可上传产品图，或手动放到 ~/Library/Application Support/WattLite/adapters/")
            .accessibilityLabel(emptyLabel)
        }
    }

    private func detail(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit()
        }.font(.system(size: 12))
    }

    private var settingsContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("保持轻巧。\n只看重要的功率。")
                .font(.system(size: 27, weight: .medium)).lineSpacing(4).padding(.vertical, 8)
            VStack(alignment: .leading, spacing: 10) {
                Text("菜单栏显示").font(.headline)
                Picker("菜单栏显示", selection: $store.metric) {
                    ForEach(PowerMetric.allCases) { metric in Text(metric.title).tag(metric) }
                }.labelsHidden().pickerStyle(.segmented)
                Text("电池净功率为系统缓存，菜单栏用 ≈ 标记。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("后台采样间隔").font(.headline)
                Picker("后台采样间隔", selection: $store.interval) {
                    Text("1 秒").tag(1.0)
                    Text("2 秒").tag(2.0)
                    Text("5 秒").tag(5.0)
                }.labelsHidden().pickerStyle(.segmented)
                Text("面板展开时每秒读取；睡眠时停止采集。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Toggle("登录时启动", isOn: Binding(get: { store.loginEnabled }, set: { store.setLoginEnabled($0) }))
                .toggleStyle(.switch)
            if let message = store.loginMessage {
                Text(message).font(.caption).foregroundStyle(.secondary)
                if SMAppService.mainApp.status == .requiresApproval {
                    Button("打开登录项设置") { SMAppService.openSystemSettingsLoginItems() }
                }
            }
            Text("WattLite 1.0\n只读电源数据，不控制充电，不保存历史到磁盘。")
                .font(.caption).foregroundStyle(.secondary).lineSpacing(5)
        }
    }
}

// 电池卡粒子场，移植自 wattlite-battery-card 组件：充电上行、放电下沉、待机低速下沉，
// 密度/速度/亮度随功率增长；文字区按组件的 fade 带避让。深浅色 tint 同组件。
// ponytail: 无状态版——位置由 (t*speed+offset) mod 行程 算出，省掉粒子数组、随机游走与簇状重生，观感等价。
private struct CardParticles: View {
    var watts: Double
    var animate: Bool
    @Environment(\.colorScheme) private var scheme

    private var charging: Bool { watts > 0.05 }
    private var intensity: CGFloat {
        charging ? CGFloat(min(1, max(0, watts / 65)))
                 : (abs(watts) < 0.05 ? 0.24 : CGFloat(min(1, max(0.18, abs(watts) / 65))))
    }
    private var tint: Color {
        if charging {
            return Color(red: 0, green: (scheme == .dark ? 211 : 169) / 255, blue: (scheme == .dark ? 220 : 190) / 255)
        }
        return Color(red: (scheme == .dark ? 132 : 105) / 255, green: (scheme == .dark ? 163 : 132) / 255,
                     blue: (scheme == .dark ? 231 : 198) / 255)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !animate)) { timeline in
            Canvas { context, size in
                let t = CGFloat(timeline.date.timeIntervalSinceReferenceDate)
                let w = size.width, h = size.height
                let widthFactor = min(1.3, max(0.65, w / 680))
                let density: CGFloat = (charging ? 24 + 48 * intensity : 17 + 33 * intensity) * widthFactor
                let span = h * (charging ? 0.77 : 0.94)
                for i in 0..<Int(density) {
                    let h1 = Self.hash(i, 1), h2 = Self.hash(i, 2), h3 = Self.hash(i, 3), h4 = Self.hash(i, 4)
                    let h5 = Self.hash(i, 5), h6 = Self.hash(i, 6), h7 = Self.hash(i, 7), h8 = Self.hash(i, 8)
                    let fast = h1 < 0.17, slow = !fast && h2 < 0.24
                    let band: CGFloat = slow ? 11 + 8 * h3 : fast ? 43 + 23 * h3 : 21 + 16 * h3
                    let speed = band * (0.84 + intensity * 0.48) * (charging ? 1 : 0.68)
                    let radius = (1.25 + 1.55 * h4) * (h5 < 0.12 ? 1.35 : 1)
                    let wobble = CGFloat(sin(Double(t) * Double(1.2 + 2.6 * h7) + Double(i))) * 5
                    let x = w * (0.03 + 0.94 * h6) + wobble
                    let travel = (t * speed + h * h8).truncatingRemainder(dividingBy: span)
                    let y = charging ? h * 1.02 - travel : -h * 0.02 + travel
                    let progress = y / h
                    let fade: CGFloat = charging
                        ? min(1, max(0, (progress - 0.25) / 0.38)) * min(1, max(0, (1.02 - progress) / 0.10))
                        : min(1, max(0, progress / 0.10)) * min(1, max(0, (0.92 - progress) / 0.28))
                    let alpha = Double((0.55 + 0.29 * h4) * fade)
                    guard alpha > 0.01 else { continue }
                    if fast || h7 < 0.29 {
                        let len = radius * (speed > 39 ? 8 : 5)
                        let tailY = y + (charging ? len : -len)
                        var tail = Path()
                        tail.move(to: CGPoint(x: x, y: y + (charging ? 1 : -1)))
                        tail.addLine(to: CGPoint(x: x, y: tailY))
                        context.stroke(tail, with: .linearGradient(
                            Gradient(colors: [tint.opacity(alpha * 0.42), tint.opacity(0)]),
                            startPoint: CGPoint(x: x, y: y), endPoint: CGPoint(x: x, y: tailY)),
                            style: StrokeStyle(lineWidth: max(1, radius * 0.65), lineCap: .round))
                    }
                    let glow = h8 < 0.61
                    if glow {
                        let outer = radius * 5.8
                        context.fill(Path(ellipseIn: CGRect(x: x - outer, y: y - outer, width: outer * 2, height: outer * 2)),
                                     with: .radialGradient(
                                        Gradient(stops: [.init(color: tint.opacity(alpha * 0.44), location: 0),
                                                         .init(color: tint.opacity(alpha * 0.15), location: 0.38),
                                                         .init(color: tint.opacity(0), location: 1)]),
                                        center: CGPoint(x: x, y: y), startRadius: 0, endRadius: outer))
                    }
                    context.fill(Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)),
                                 with: .color(tint.opacity(alpha)))
                    if glow && radius > 2.1 {
                        let c = radius * 0.32
                        context.fill(Path(ellipseIn: CGRect(x: x - c, y: y - c, width: c * 2, height: c * 2)),
                                     with: .color(Color(red: 213 / 255, green: 1, blue: 1).opacity(alpha * 0.77)))
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private static func hash(_ i: Int, _ salt: Int) -> CGFloat {
        let v = sin(Double(i + 1) * 127.1 + Double(salt) * 311.7) * 43758.5453
        return CGFloat(v - floor(v))
    }
}

private struct AdapterEditor: View {
    let reading: PowerReading
    let onClose: () -> Void
    @ObservedObject private var library = AdapterLibrary.shared
    @State private var name: String
    @State private var model: String
    @State private var protocols: String
    @State private var pickedImage: NSImage?

    init(reading: PowerReading, onClose: @escaping () -> Void) {
        self.reading = reading
        self.onClose = onClose
        let user = AdapterLibrary.shared.entry(for: reading.adapterIdentityKey)
        let builtIn = reading.adapterProfile
        _name = State(initialValue: user?.name ?? builtIn?.name ?? reading.adapterName ?? "")
        _model = State(initialValue: user?.model ?? builtIn?.model ?? reading.adapterMarketingModel ?? "")
        _protocols = State(initialValue: user?.protocols ?? builtIn?.protocols ?? "")
    }

    private var key: String? { reading.adapterIdentityKey }
    private var isCustomized: Bool { library.entry(for: key) != nil }
    private var canSave: Bool {
        key != nil && (!name.trimmingCharacters(in: .whitespaces).isEmpty || pickedImage != nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Button(action: onClose) {
                    Image(systemName: "arrow.left").frame(width: 24, height: 24)
                }
                .buttonStyle(.borderless).help("返回功率面板").accessibilityLabel("返回功率面板")
                Text("适配器资料").font(.system(size: 14, weight: .semibold))
                Spacer()
            }
            if let key {
                HStack(spacing: 12) {
                    Group {
                        if let pickedImage {
                            Image(nsImage: pickedImage).resizable().aspectRatio(contentMode: .fit)
                        } else if let existing = AdapterImages.image(forKeys: [reading.adapterImageKey, key]) {
                            Image(nsImage: existing).resizable().aspectRatio(contentMode: .fit)
                        } else {
                            VStack(spacing: 2) {
                                Image(systemName: "powerplug.fill").font(.system(size: 15)).foregroundStyle(.secondary)
                                Text("无产品图").font(.system(size: 8)).foregroundStyle(.secondary)
                            }
                            .frame(width: Style.cardThumb.width, height: Style.cardThumb.height)
                            .background(Style.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
                        }
                    }
                    .frame(width: Style.cardThumb.width, height: Style.cardThumb.height)
                    .clipShape(RoundedRectangle(cornerRadius: 9))
                    VStack(alignment: .leading, spacing: 6) {
                        Button("选择图片…") { pickImage() }
                        if pickedImage != nil {
                            Button("撤销新图") { pickedImage = nil }
                        }
                        Text("保存时转为 PNG，存到本地 adapters 目录")
                            .font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                field("名称", text: $name, prompt: "如 OPPO SUPERVOOC 100W 小方瓶 Pro")
                field("型号", text: $model, prompt: "外壳印的型号，如 OSA00CB9BC")
                field("快充协议", text: $protocols, prompt: "如 SUPERVOOC · PD · PPS · QC3.0")
                HStack(spacing: 10) {
                    Button("保存") { save() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(!canSave)
                    if isCustomized {
                        Button("删除自定义", role: .destructive) { remove() }
                    }
                    Spacer()
                }
                Text("识别键 \(key) · 资料仅保存在本机 ~/Library/Application Support/WattLite/")
                    .font(.system(size: 9)).foregroundStyle(.secondary)
            } else {
                Text("当前适配器没有可用的识别信息（无 USB ID 与名称），无法保存自定义资料。请插上适配器后再试。")
                    .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4)
            }
        }
        .padding(.vertical, 4)
    }

    private func field(_ title: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 11)).foregroundStyle(.secondary)
            TextField(prompt, text: text).textFieldStyle(.roundedBorder).font(.system(size: 12))
        }
    }

    private func pickImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        let completion: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url, let image = NSImage(contentsOf: url) else { return }
            pickedImage = image
        }
        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window, completionHandler: completion)
        } else {
            completion(panel.runModal())
        }
    }

    private func save() {
        guard let key else { return }
        let entry = AdapterLibrary.Entry(
            name: name.trimmingCharacters(in: .whitespaces),
            model: model.trimmingCharacters(in: .whitespaces),
            protocols: protocols.trimmingCharacters(in: .whitespaces))
        library.save(entry, key: key, image: pickedImage)
        AdapterImages.evict(key)
        onClose()
    }

    private func remove() {
        guard let key else { return }
        library.remove(key: key)
        AdapterImages.evict(key)
        onClose()
    }
}
