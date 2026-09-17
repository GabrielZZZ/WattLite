import AppKit
import Combine
import IOKit.ps
import ServiceManagement

@MainActor
final class PowerStore: ObservableObject {
    @Published private(set) var reading = PowerReading.unavailable("正在读取")
    @Published private(set) var history: [PowerPoint] = []
    @Published var metric: PowerMetric {
        didSet {
            UserDefaults.standard.set(metric.rawValue, forKey: "metric")
            onReading?(latest)
        }
    }
    @Published var interval: Double {
        didSet {
            UserDefaults.standard.set(interval, forKey: "interval")
            schedule()
        }
    }
    @Published private(set) var loginEnabled = SMAppService.mainApp.status == .enabled
    @Published var loginMessage: String?
    var onReading: ((PowerReading) -> Void)?
    private(set) var latest = PowerReading.unavailable("正在读取")
    private var points: [PowerPoint] = []
    private let reader = PowerReader()
    private var timer: Timer?
    private var source: CFRunLoopSource?
    private var busy = false
    private var sleeping = false
    private var generation = 0
    private var visible = false

    init() {
        metric = PowerMetric(rawValue: UserDefaults.standard.string(forKey: "metric") ?? "") ?? .input
        let saved = UserDefaults.standard.double(forKey: "interval")
        interval = [1.0, 2.0, 5.0].contains(saved) ? saved : 2
        let context = Unmanaged.passUnretained(self).toOpaque()
        source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let store = Unmanaged<PowerStore>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in store.sample() }
        }, context)?.takeRetainedValue()
        if let source { CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes) }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
        schedule()
        sample()
    }

    func setVisible(_ value: Bool) {
        visible = value
        if value {
            reading = latest
            history = points
            refreshLoginState()
            sample()
        }
        schedule()
    }

    private func schedule() {
        timer?.invalidate()
        guard !sleeping else { return }
        let seconds = visible ? 1 : interval
        let timer = Timer(timeInterval: seconds, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sample() }
        }
        timer.tolerance = seconds * 0.15
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func sample() {
        guard !busy, !sleeping else { return }
        busy = true
        let ticket = generation
        Task {
            let next = await reader.read()
            busy = false
            guard !sleeping, generation == ticket else { return }
            let changed = next.inputCounter != latest.inputCounter || next.connected != latest.connected
            if next.inputIsLive || changed || next.inputWatts == nil {
                points.append(PowerPoint(date: next.capturedAt, input: next.inputWatts, battery: nil))
            }
            if next.batteryUpdatedAt != latest.batteryUpdatedAt, let updated = next.batteryUpdatedAt {
                points.append(PowerPoint(date: updated, input: nil, battery: next.batteryWatts))
            }
            points.removeAll { next.capturedAt.timeIntervalSince($0.date) > 600 }
            if points.count > 1300 { points.removeFirst(points.count - 1300) }
            latest = next
            if visible {
                reading = next
                history = points
            }
            onReading?(next)
        }
    }

    @objc private func willSleep() {
        sleeping = true
        generation += 1
        timer?.invalidate()
    }

    @objc private func didWake() {
        sleeping = false
        generation += 1
        latest = .unavailable("唤醒后重新采样")
        reading = latest
        onReading?(latest)
        Task {
            await reader.reset()
            schedule()
            sample()
        }
    }

    func refreshLoginState() {
        loginEnabled = SMAppService.mainApp.status == .enabled
        if SMAppService.mainApp.status == .requiresApproval {
            loginMessage = "请在系统设置的登录项中允许 WattLite。"
        }
    }

    func setLoginEnabled(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            loginMessage = nil
        } catch {
            loginMessage = "无法更改登录启动：\(error.localizedDescription)"
        }
        refreshLoginState()
    }

    func stop() {
        sleeping = true
        generation += 1
        timer?.invalidate()
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
}
