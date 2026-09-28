import AppKit
import SwiftUI

@main
struct WattLiteMain {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(CommandLine.arguments.contains("--inspect") ? .regular : .accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var store: PowerStore!
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var inspectionWindow: NSWindow?
    private var statusWidthKey = ""
    private var statusBolt: NSImage?

    func applicationDidFinishLaunching(_ notification: Notification) {
        store = PowerStore()
        // ponytail: system_profiler 首次调用较慢，后台预热避免断电时面板卡顿
        DispatchQueue.global(qos: .utility).async { _ = MachineInfo.shared }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePanel)
            button.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            button.imagePosition = .imageLeading
            button.image = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: nil)
            button.image?.isTemplate = true
            statusBolt = button.image
        }
        popover.behavior = .transient
        popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        popover.delegate = self
        // 尺寸必须钉死：SwiftUI 的 fitting size 会随粒子/趋势图弹性高度反复变，popover 就一路抖
        popover.contentSize = NSSize(width: 380, height: 724)
        store.onReading = { [weak self] value in self?.updateStatus(value) }
        updateStatus(store.latest)
        if CommandLine.arguments.contains("--inspect") {
            store.setVisible(true)
            let controller = NSHostingController(rootView: PanelView(store: store))
            let window = NSWindow(contentViewController: controller)
            window.title = "WattLite"
            window.styleMask = [.titled, .closable]
            window.setContentSize(NSSize(width: 380, height: 724))
            window.center()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            inspectionWindow = window
        } else if CommandLine.arguments.contains("--show") { showPanel() }
    }

    private func updateStatus(_ reading: PowerReading) {
        guard let button = statusItem.button else { return }
        button.setAccessibilityLabel(T("WattLite 功率监测"))
        let metric = reading.connected == false ? .battery : store.metric
        let cached = metric == .battery || !reading.inputIsLive
        let marker = cached && reading.watts(for: metric) != nil ? "≈" : ""
        let adapter = reading.adapterShort ?? reading.adapterVendorName
        let tag = adapter.map { "\($0) · " } ?? ""
        // 数字等宽、小数位固定，宽度只随指标/适配器前缀变；按最坏串定量一次，跳数不再左右滑动
        let worst = tag + (metric == .input ? T("入 ≈88.8 W") : T("电池 ≈-88.8 W"))
        if worst != statusWidthKey {
            statusWidthKey = worst
            let font = button.font ?? .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            let text = ceil((worst as NSString).size(withAttributes: [.font: font]).width)
            statusItem.length = text + (button.image?.size.width ?? 0) + 8
        }
        let title = "\(tag)\(metric.prefix) \(marker)\(powerText(reading.watts(for: metric))) W"
        if button.title != title { button.title = title }
        var tooltip = "\(metric.title)：\(powerText(reading.watts(for: metric))) W\n\(reading.state)\(cached ? "\n\(T("系统缓存采样，非实时值"))" : "\n\(T("SMC 输入侧实时读取"))")"
        if reading.connected == false, let remaining = reading.remainingText {
            tooltip += "\n\(T("预计剩余")) \(remaining)"
        }
        let userAdapter = AdapterLibrary.shared.entry(for: reading.adapterIdentityKey)
        if let name = userAdapter?.name.nonEmpty ?? reading.adapterProfile?.name ?? reading.adapterName {
            let model = (userAdapter?.model.nonEmpty ?? reading.adapterMarketingModel ?? reading.adapterProfile?.model).map { " · \($0)" } ?? ""
            tooltip += "\n\(name)\(model)"
        }
        if button.toolTip != tooltip { button.toolTip = tooltip }
        button.setAccessibilityValue(tooltip)
        updateBoltAnimation(reading, on: button)
    }

    // 菜单栏 bolt 能量流动画：充电=光带快速上行，电池供电=下行，接电未充=慢速环境流。
    // ponytail: 帧表查表播放。CA 自循环在菜单栏实测不合成（系统快照托管，动画冻住且蒙版错位），
    // 只能逐帧设 image；实测 ~2% CPU/fps，故充/放电 12fps、待机环境流 6fps。减弱动态时静态。
    private var animationMode = ""
    private var chargeAnimator: Timer?
    private var boltFrames: [NSImage] = []

    private func updateBoltAnimation(_ reading: PowerReading, on button: NSStatusBarButton) {
        guard let base = statusBolt else { return }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            chargeAnimator?.invalidate()
            chargeAnimator = nil
            if button.image !== base { button.image = base }
            return
        }
        let charging = reading.connected == true && reading.charging == true
        let onBattery = reading.connected == false
        let period = charging ? 1.5 : onBattery ? 2.2 : 6.0
        let upward = !onBattery
        let mode = "\(period)\(upward)"
        guard mode != animationMode else { return }
        animationMode = mode
        chargeAnimator?.invalidate()
        let fps = (charging || onBattery) ? 12.0 : 6.0
        let frameCount = max(12, Int(period * fps))
        boltFrames = (0..<frameCount).map { Self.boltFrame(base: base, progress: Double($0) / Double(frameCount), upward: upward) }
        var index = 0
        chargeAnimator = Timer.scheduledTimer(withTimeInterval: 1.0 / fps, repeats: true) { [weak self, weak button] timer in
            MainActor.assumeIsolated {
                guard let button, let self, !self.boltFrames.isEmpty else { timer.invalidate(); return }
                button.image = self.boltFrames[index % self.boltFrames.count]
                index += 1
            }
        }
    }

    private static func boltFrame(base: NSImage, progress: Double, upward: Bool) -> NSImage {
        let size = base.size
        let rect = NSRect(origin: .zero, size: size)
        let bandHeight = size.height * 0.7
        let travel = size.height + bandHeight * 2
        let centerY = upward
            ? -bandHeight + CGFloat(progress) * travel
            : size.height + bandHeight - CGFloat(progress) * travel
        // 光带裁进 bolt 形状：先画纵向 alpha 峰光带，再用 destinationIn 以 bolt 为蒙版裁切
        let band = NSImage(size: size)
        band.lockFocus()
        let clear = NSColor.white.withAlphaComponent(0)
        let peak = NSColor.white.withAlphaComponent(1)
        NSGradient(colorsAndLocations: (clear, 0), (peak, 0.5), (clear, 1))?
            .draw(in: NSRect(x: 0, y: centerY - bandHeight / 2, width: size.width, height: bandHeight), angle: 90)
        base.draw(in: rect, from: .zero, operation: .destinationIn, fraction: 1)
        band.unlockFocus()
        let frame = NSImage(size: size)
        frame.lockFocus()
        base.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 0.5)
        band.draw(in: rect, from: .zero, operation: .plusLighter, fraction: 0.9)
        frame.unlockFocus()
        frame.isTemplate = true
        return frame
    }

    @objc private func togglePanel() {
        if popover.isShown { popover.performClose(nil) }
        else { showPanel() }
    }

    private func showPanel() {
        guard let button = statusItem.button else { return }
        store.setVisible(true)
        popover.contentViewController = NSHostingController(rootView: PanelView(store: store))
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        let window = popover.contentViewController?.view.window
        // ponytail: popover 窗口默认不进全屏 Space，show 后补 collectionBehavior 才能在他人全屏时弹出
        window?.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window?.makeKey()
    }

    func popoverDidClose(_ notification: Notification) {
        // ponytail: 巡检窗口读的是 store.reading，它只在 visible 时发布；关掉 popover 别把它冻住
        if inspectionWindow == nil { store.setVisible(false) }
        popover.contentViewController = nil
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !popover.isShown { showPanel() }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) { store.stop() }
}
