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
            button.setAccessibilityLabel("WattLite 功率监测")
        }
        popover.behavior = .transient
        popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        popover.delegate = self
        popover.contentSize = NSSize(width: 380, height: 740)
        store.onReading = { [weak self] value in self?.updateStatus(value) }
        updateStatus(store.latest)
        if CommandLine.arguments.contains("--inspect") {
            store.setVisible(true)
            let controller = NSHostingController(rootView: PanelView(store: store))
            let window = NSWindow(contentViewController: controller)
            window.title = "WattLite"
            window.styleMask = [.titled, .closable]
            window.setContentSize(NSSize(width: 380, height: 740))
            window.center()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            inspectionWindow = window
        } else if CommandLine.arguments.contains("--show") { showPanel() }
    }

    private func updateStatus(_ reading: PowerReading) {
        guard let button = statusItem.button else { return }
        let metric = reading.connected == false ? .battery : store.metric
        let cached = metric == .battery || !reading.inputIsLive
        let marker = cached && reading.watts(for: metric) != nil ? "≈" : ""
        let adapter = reading.adapterShort ?? reading.adapterVendorName
        let tag = adapter.map { "\($0) · " } ?? ""
        // 数字等宽、小数位固定，宽度只随指标/适配器前缀变；按最坏串定量一次，跳数不再左右滑动
        let worst = tag + (metric == .input ? "入 ≈88.8 W" : "电池 ≈-88.8 W")
        if worst != statusWidthKey {
            statusWidthKey = worst
            let font = button.font ?? .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            let text = ceil((worst as NSString).size(withAttributes: [.font: font]).width)
            statusItem.length = text + (button.image?.size.width ?? 0) + 8
        }
        let title = "\(tag)\(metric.prefix) \(marker)\(powerText(reading.watts(for: metric))) W"
        if button.title != title { button.title = title }
        var tooltip = "\(metric.title)：\(powerText(reading.watts(for: metric))) W\n\(reading.state)\(cached ? "\n系统缓存采样，非实时值" : "\nSMC 输入侧实时读取")"
        if reading.connected == false, let remaining = reading.remainingText {
            tooltip += "\n预计剩余 \(remaining)"
        }
        let userAdapter = AdapterLibrary.shared.entry(for: reading.adapterIdentityKey)
        if let name = userAdapter?.name.nonEmpty ?? reading.adapterProfile?.name ?? reading.adapterName {
            let model = (userAdapter?.model.nonEmpty ?? reading.adapterMarketingModel ?? reading.adapterProfile?.model).map { " · \($0)" } ?? ""
            tooltip += "\n\(name)\(model)"
        }
        if button.toolTip != tooltip { button.toolTip = tooltip }
        button.setAccessibilityValue(tooltip)
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
        store.setVisible(false)
        popover.contentViewController = nil
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !popover.isShown { showPanel() }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) { store.stop() }
}
