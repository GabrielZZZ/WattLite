import AppKit
import Combine
import CryptoKit
import Foundation

enum UpdatePhase: Equatable {
    case idle
    case checking
    case upToDate
    case downloading
    case ready
    case failed
    case unsupported
    case manual
    case applying
}

struct UpdateInstallResult: Codable, Equatable {
    var status: String
    var message: String?
    var version: String?
    var build: Int?
    var at: String?
}

// 清单和更新包都由离线私钥签名；App 只带公钥，SHA-256 之外再验一层，避免更新源被替换。
@MainActor
final class UpdateStore: ObservableObject {
    static let primaryManifest = "https://gabrielzzz.github.io/WattLite/updates/macos.json"
    static let fallbackManifest = "https://cdn.jsdelivr.net/gh/GabrielZZZ/WattLite@main/docs/updates/macos.json"
    static let downloadPage = URL(string: "https://gabrielzzz.github.io/WattLite/#download")!
    private static let productionPublicKey = "BJv6XS95bB96D4D7KX2g0T8sDgmqb6CkIjoTmL5iVSC2OAv0S/LE2tsPPKJxqHximpc959zfAXO0Fj+NzjePyAM="

    private static let firstCheckDelay: UInt64 = 20 * 1_000_000_000
    private static let checkInterval: TimeInterval = 6 * 60 * 60

    @Published private(set) var phase: UpdatePhase = .idle
    @Published private(set) var autoCheck: Bool
    @Published private(set) var availableVersion: String?
    @Published private(set) var progress: Double = 0
    @Published private(set) var error: String?
    @Published private(set) var notesZH: String?
    @Published private(set) var notesEN: String?
    @Published private(set) var minOS: String?
    @Published private(set) var installResult: UpdateInstallResult?

    let currentVersion: String
    let currentBuild: Int

    private let net: URLSession
    private let supportDir: URL
    private let updatesDir: URL
    private let logURL: URL
    private var started = false
    private var autoTask: Task<Void, Never>?
    private var autoTimer: Timer?
    private var checkTask: Task<Void, Never>?
    private var checkID = UUID()
    private var pending: PendingUpdate?

    private struct PendingUpdate {
        let version: String
        let build: Int
        let sha256: String
        let zipURL: URL
    }

    init() {
        let info = Bundle.main.infoDictionary
        currentVersion = info?["CFBundleShortVersionString"] as? String ?? "0"
        currentBuild = Int(info?["CFBundleVersion"] as? String ?? "") ?? 0
        autoCheck = UserDefaults.standard.object(forKey: "autoCheck") as? Bool ?? true

        supportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WattLite", isDirectory: true)
        updatesDir = supportDir.appendingPathComponent("updates", isDirectory: true)
        logURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/WattLite-update.log")
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 30
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.waitsForConnectivity = false
        net = URLSession(configuration: config)
    }

    /// 启动时读取上次 helper 的结果；联网检查永远从 20 秒后开始。
    func start() {
        guard !started else { return }
        started = true
        readInstallResult()
        cleanupDownloads()
        if autoCheck { scheduleAuto() }
    }

    func setAutoCheck(_ enabled: Bool) {
        guard enabled != autoCheck else { return }
        autoCheck = enabled
        UserDefaults.standard.set(enabled, forKey: "autoCheck")
        if enabled {
            if started { scheduleAuto() }
            return
        }
        autoTask?.cancel()
        autoTask = nil
        autoTimer?.invalidate()
        autoTimer = nil
        // 关闭自动检查后不再有任何后台请求，连正在进行的也一并取消。
        checkTask?.cancel()
        checkTask = nil
        checkID = UUID()
        if phase == .checking || phase == .downloading {
            phase = .idle
            progress = 0
        }
        log("auto check off")
    }

    func checkNow() {
        guard phase != .checking, phase != .downloading, phase != .applying else { return }
        beginCheck(manual: true)
    }

    func stop() {
        autoTask?.cancel()
        autoTask = nil
        autoTimer?.invalidate()
        autoTimer = nil
        checkTask?.cancel()
        checkTask = nil
        checkID = UUID()
        net.invalidateAndCancel()
    }

    func openDownloadPage() {
        NSWorkspace.shared.open(Self.downloadPage)
    }

    var notes: String? {
        if L10n.shared.lang == .en { return notesEN ?? notesZH }
        return notesZH ?? notesEN
    }

    var installResultText: String? {
        guard let result = installResult else { return nil }
        if result.status == "ok" {
            return TF("已更新到 %@。", result.version?.isEmpty == false ? result.version! : T("新版本"))
        }
        return TF("上次更新失败（%@），已恢复旧版本。", resultReason(result.message))
    }

    // MARK: - 定时与检查

    private func scheduleAuto() {
        autoTask?.cancel()
        autoTimer?.invalidate()
        autoTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.firstCheckDelay)
            guard let self, !Task.isCancelled, self.autoCheck else { return }
            self.beginCheck(manual: false)
        }
        let timer = Timer(timeInterval: Self.checkInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.autoCheck else { return }
                self.beginCheck(manual: false)
            }
        }
        timer.tolerance = 300
        RunLoop.main.add(timer, forMode: .common)
        autoTimer = timer
        log("auto check scheduled")
    }

    private func beginCheck(manual: Bool) {
        guard checkTask == nil else { return }
        let id = UUID()
        checkID = id
        checkTask = Task { [weak self] in
            await self?.performCheck(manual: manual, id: id)
        }
    }

    private func performCheck(manual: Bool, id: UUID) async {
        defer { if checkID == id { checkTask = nil } }
        log("check manual=\(manual) current=\(currentVersion) (\(currentBuild))")
        phase = .checking
        error = nil
        progress = 0
        availableVersion = nil
        minOS = nil
        notesZH = nil
        notesEN = nil
        pending = nil

        do {
            guard let manifest = try await fetchManifest() else {
                if checkID == id { fail("检查更新失败，请稍后再试。") }
                return
            }
            try Task.checkCancellation()
            guard checkID == id else { return }

            try validate(manifest)

            let newer: Bool
            if manifest.build != currentBuild {
                newer = manifest.build > currentBuild
            } else {
                switch Self.compareVersions(manifest.version, currentVersion) {
                case .some(let cmp): newer = cmp > 0
                case .none: newer = false
                }
            }
            guard newer else {
                log("up to date remote=\(manifest.version) (\(manifest.build))")
                phase = .upToDate
                return
            }

            log("available \(manifest.version) (\(manifest.build))")
            availableVersion = manifest.version
            minOS = manifest.min_os
            notesZH = manifest.notes_zh
            notesEN = manifest.notes_en
            if let minOS = manifest.min_os, !Self.currentOSMeets(minOS) {
                log("unsupported requires macOS \(minOS)")
                phase = .unsupported
                return
            }
            guard let dir = installDirectory() else {
                log("manual update: bundle location not writable")
                phase = .manual
                return
            }

            let zip = try await download(manifest, id: id)
            try Task.checkCancellation()
            guard checkID == id else { return }
            pending = PendingUpdate(version: manifest.version, build: manifest.build,
                                    sha256: manifest.sha256, zipURL: zip)
            progress = 1
            phase = .ready
            log("ready \(manifest.version) (\(manifest.build)) \(zip.path) dir=\(dir.path)")
        } catch is CancellationError {
            guard checkID == id else { return }
            progress = 0
            if phase == .checking || phase == .downloading { phase = .idle }
            log("check canceled")
        } catch {
            guard checkID == id else { return }
            log("check failed \(error)")
            fail(self.error ?? "检查更新失败，请稍后再试。")
        }
    }

    private func fail(_ message: String) {
        error = message
        progress = 0
        phase = .failed
    }

    // MARK: - 清单

    private struct Manifest: Decodable {
        let version: String
        let build: Int
        let url: String
        let mirror: String?
        let sha256: String
        let min_os: String?
        let published: String?
        let notes_zh: String?
        let notes_en: String?
    }

    private func fetchManifest() async throws -> Manifest? {
        for url in manifestURLs() {
            do {
                try Task.checkCancellation()
                log("manifest \(url.absoluteString)")
                let json = try await fetchData(url, limit: 256 * 1024)
                let sigURL = URL(string: url.absoluteString + ".sig")!
                let sig = try await fetchData(sigURL, limit: 4096)
                guard Self.verifySignature(json, signatureBase64: String(decoding: sig, as: UTF8.self),
                                           publicKeyBase64: publicKeyBase64) else {
                    log("signature invalid \(url.absoluteString)")
                    continue
                }
                return try JSONDecoder().decode(Manifest.self, from: json)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if Task.isCancelled { throw CancellationError() }
                log("manifest failed \(url.absoluteString) \(error)")
            }
        }
        return nil
    }

    private func fetchData(_ url: URL, limit: Int) async throws -> Data {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 20
        request.setValue("WattLite/\(currentVersion) (macOS)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await net.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw UpdateError.http
        }
        guard data.count <= limit else { throw UpdateError.tooLarge }
        return data
    }

    private func validate(_ manifest: Manifest) throws {
        guard Self.parseVersion(manifest.version) != nil, manifest.build >= 0 else {
            throw UpdateError.invalidManifest
        }
        guard let zipURL = allowedURL(manifest.url) else { throw UpdateError.invalidManifest }
        _ = zipURL
        if let mirror = manifest.mirror, allowedURL(mirror) == nil {
            log("ignoring invalid mirror")
        }
        let sha = manifest.sha256.lowercased()
        guard sha.count == 64, sha.allSatisfy({ $0.isHexDigit }) else { throw UpdateError.invalidManifest }
        if let minOS = manifest.min_os, Self.parseVersion(minOS) == nil {
            throw UpdateError.invalidManifest
        }
    }

    private func allowedURL(_ text: String) -> URL? {
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased(), url.host != nil else {
            return nil
        }
        if scheme == "https" { return url }
        if allowHTTP && scheme == "http" { return url }
        return nil
    }

    private var manifestOverride: String? {
        let value = ProcessInfo.processInfo.environment["WATTLITE_UPDATE_MANIFEST"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false ? value : nil
    }

    private var allowHTTP: Bool { manifestOverride != nil }

    private var publicKeyBase64: String {
        if allowHTTP,
           let testKey = ProcessInfo.processInfo.environment["WATTLITE_UPDATE_PUBLIC_KEY"]?
               .trimmingCharacters(in: .whitespacesAndNewlines),
           !testKey.isEmpty {
            return testKey
        }
        return Self.productionPublicKey
    }

    private func manifestURLs() -> [URL] {
        if let override = manifestOverride, let url = URL(string: override) {
            return [url]
        }
        return [Self.primaryManifest, Self.fallbackManifest].compactMap { URL(string: $0) }
    }

    // MARK: - 下载

    private func download(_ manifest: Manifest, id: UUID) async throws -> URL {
        try FileManager.default.createDirectory(at: updatesDir, withIntermediateDirectories: true)
        let safeVersion = manifest.version.map { $0.isLetter || $0.isNumber || ".-_".contains($0) ? $0 : "-" }
        let final = updatesDir.appendingPathComponent("WattLite-\(String(safeVersion))-\(manifest.build).zip")
        let expected = manifest.sha256.lowercased()

        if FileManager.default.fileExists(atPath: final.path) {
            if await Self.hashFile(final) == expected {
                log("using cached download \(final.lastPathComponent)")
                return final
            }
            try? FileManager.default.removeItem(at: final)
        }

        let candidates = [manifest.url, manifest.mirror]
            .compactMap { $0 }
            .compactMap { allowedURL($0) }
            .reduce(into: [URL]()) { result, url in
                if !result.contains(url) { result.append(url) }
            }
        guard !candidates.isEmpty else { throw UpdateError.invalidManifest }

        let part = final.appendingPathExtension("part")
        var last: Error = UpdateError.download
        var sawHashMismatch = false
        for url in candidates {
            try Task.checkCancellation()
            phase = .downloading
            progress = 0
            log("download \(url.absoluteString)")
            do {
                let downloader = StreamingDownloader(destination: part) { [weak self] fraction in
                    Task { @MainActor in
                        guard let self, self.checkID == id, self.phase == .downloading else { return }
                        self.progress = fraction
                    }
                }
                let digest = try await downloader.run(url: url)
                try Task.checkCancellation()
                guard digest == expected else {
                    try? FileManager.default.removeItem(at: part)
                    sawHashMismatch = true
                    log("sha256 mismatch \(url.absoluteString)")
                    continue
                }
                try? FileManager.default.removeItem(at: final)
                try FileManager.default.moveItem(at: part, to: final)
                log("downloaded \(final.lastPathComponent) sha256=\(digest)")
                return final
            } catch is CancellationError {
                try? FileManager.default.removeItem(at: part)
                throw CancellationError()
            } catch {
                try? FileManager.default.removeItem(at: part)
                if Task.isCancelled { throw CancellationError() }
                last = error
                log("download failed \(url.absoluteString) \(error)")
            }
        }
        if sawHashMismatch {
            error = "更新包校验失败，已丢弃。"
            throw UpdateError.hash
        }
        error = "下载更新失败，请稍后再试。"
        throw last
    }

    // MARK: - 安装

    private func installDirectory() -> URL? {
        let app = Bundle.main.bundleURL.standardizedFileURL
        guard app.pathExtension == "app" else { return nil }
        if app.path.contains("/AppTranslocation/") { return nil }
        if app.path.hasPrefix("/Volumes/") { return nil }
        let dir = app.deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: app.path),
              FileManager.default.isWritableFile(atPath: dir.path) else { return nil }
        return dir
    }

    func apply() {
        guard phase == .ready, let pending else { return }
        let zip = pending.zipURL
        phase = .applying
        progress = 1
        Task { [weak self] in
            guard let self else { return }
            let digest = await Self.hashFile(zip)
            guard digest == pending.sha256 else {
                self.phase = .failed
                self.error = "更新包校验失败，已丢弃。"
                try? FileManager.default.removeItem(at: zip)
                self.log("apply rejected: cached zip changed")
                return
            }
            self.launchHelper(zip: zip, expected: pending)
        }
    }

    private func launchHelper(zip: URL, expected: PendingUpdate) {
        let app = Bundle.main.bundleURL.standardizedFileURL
        guard installDirectory() != nil else {
            phase = .manual
            log("apply refused: location not writable")
            return
        }
        do {
            try FileManager.default.createDirectory(at: updatesDir, withIntermediateDirectories: true)
            let scriptURL = updatesDir.appendingPathComponent("apply-update.sh")
            let script = Self.helperScript
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = [scriptURL.path,
                                 String(ProcessInfo.processInfo.processIdentifier),
                                 zip.path,
                                 app.path,
                                 expected.sha256,
                                 String(expected.build)]
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            log("helper started pid=\(process.processIdentifier) version=\(expected.version) (\(expected.build))")
            NSApp.terminate(nil)
        } catch let failure {
            phase = .failed
            error = "无法启动更新，请手动下载安装。"
            log("helper launch failed \(failure)")
        }
    }

    // MARK: - 上次结果

    private func readInstallResult() {
        let url = supportDir.appendingPathComponent("update-result.json")
        guard let data = try? Data(contentsOf: url) else { return }
        defer { try? FileManager.default.removeItem(at: url) }
        guard let result = try? JSONDecoder().decode(UpdateInstallResult.self, from: data) else { return }
        installResult = result
        log("last result status=\(result.status) message=\(result.message ?? "-") version=\(result.version ?? "-")")
    }

    private func resultReason(_ code: String?) -> String {
        switch code {
        case "hash", "unzip", "bundle", "build", "identifier", "codesign", "arguments":
            return T("更新包无效")
        case "readonly", "replace":
            return T("没有写入权限")
        case "open":
            return T("新版本无法启动")
        case "parent-timeout":
            return T("旧版本未能及时退出")
        default:
            return T("未知原因")
        }
    }

    // MARK: - 工具

    private func cleanupDownloads() {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: updatesDir, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        let cutoff = Date().addingTimeInterval(-7 * 24 * 3600)
        for file in files {
            let values = try? file.resourceValues(forKeys: [.contentModificationDateKey])
            let old = (values?.contentModificationDate ?? .distantPast) < cutoff
            if file.pathExtension == "part" || (old && file.pathExtension == "zip") {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    private func log(_ message: String) {
        let stamp = Self.stampFormatter.string(from: Date())
        let line = "\(stamp) \(message)\n"
        try? FileManager.default.createDirectory(at: logURL.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: logURL.path) {
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: logURL) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: Data(line.utf8))
    }

    private static let stampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    nonisolated static func verifySignature(_ data: Data, signatureBase64: String,
                                            publicKeyBase64: String) -> Bool {
        let base64 = signatureBase64.filter { !$0.isWhitespace }
        guard let signatureData = Data(base64Encoded: base64), signatureData.count == 64,
              let keyData = Data(base64Encoded: publicKeyBase64), keyData.count == 65,
              let key = try? P256.Signing.PublicKey(x963Representation: keyData),
              let signature = try? P256.Signing.ECDSASignature(rawRepresentation: signatureData) else {
            return false
        }
        return key.isValidSignature(signature, for: data)
    }

    nonisolated static func parseVersion(_ text: String) -> [Int]? {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard !parts.isEmpty else { return nil }
        var values: [Int] = []
        for part in parts {
            guard !part.isEmpty, let value = Int(part), value >= 0 else { return nil }
            values.append(value)
        }
        return values
    }

    nonisolated static func compareVersions(_ lhs: String, _ rhs: String) -> Int? {
        guard let left = parseVersion(lhs), let right = parseVersion(rhs) else { return nil }
        for index in 0..<max(left.count, right.count) {
            let l = index < left.count ? left[index] : 0
            let r = index < right.count ? right[index] : 0
            if l != r { return l < r ? -1 : 1 }
        }
        return 0
    }

    nonisolated static func currentOSMeets(_ minOS: String) -> Bool {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let current = "\(version.majorVersion).\(version.minorVersion)"
        guard let cmp = compareVersions(current, minOS) else { return false }
        return cmp >= 0
    }

    nonisolated static func hashFile(_ url: URL) async -> String? {
        await Task.detached(priority: .utility) {
            guard let stream = InputStream(url: url) else { return nil }
            stream.open()
            defer { stream.close() }
            var hasher = SHA256()
            var buffer = [UInt8](repeating: 0, count: 1 << 20)
            while true {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count < 0 { return nil }
                if count == 0 { break }
                hasher.update(data: Data(buffer[0..<count]))
            }
            return hasher.finalize().map { String(format: "%02x", $0) }.joined()
        }.value
    }

    private enum UpdateError: Error {
        case http
        case tooLarge
        case invalidManifest
        case hash
        case download
    }

    // MARK: - Helper

    private static let helperScript = #"""
#!/bin/sh
# WattLite one-shot updater. Generated by the app; safe to overwrite.
set -u
PATH=/usr/bin:/bin:/usr/sbin:/sbin
export PATH

PARENT_PID="${1:-}"
ZIP="${2:-}"
APP="${3:-}"
EXPECTED_SHA="${4:-}"
EXPECTED_BUILD="${5:-}"
BUNDLE_ID="local.gabriel.WattLite"

SUPPORT="$HOME/Library/Application Support/WattLite"
LOG="$HOME/Library/Logs/WattLite-update.log"
RESULT="$SUPPORT/update-result.json"
APP_DIR="$(dirname "$APP")"
BACKUP=""
WORK=""
VERSION=""
OPENED_OLD=0

mkdir -p "$SUPPORT" "$HOME/Library/Logs" 2>/dev/null

log() {
    printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG" 2>/dev/null
}

write_result() {
    status="$1"
    message="$2"
    printf '{"status":"%s","message":"%s","version":"%s","build":%s,"at":"%s"}\n' \
        "$status" "$message" "$VERSION" "$EXPECTED_BUILD" "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
        > "$RESULT" 2>/dev/null
}

cleanup() {
    if [ -n "$WORK" ] && [ -d "$WORK" ]; then
        rm -rf "$WORK"
    fi
}
trap cleanup EXIT

restore_old() {
    if [ -n "$BACKUP" ] && [ -d "$BACKUP" ]; then
        rm -rf "$APP"
        mv "$BACKUP" "$APP" || log "rollback move failed"
        BACKUP=""
        open "$APP" >/dev/null 2>&1 || log "open restored app failed"
        OPENED_OLD=1
    fi
}

fail() {
    log "FAIL $1"
    restore_old
    if [ "$OPENED_OLD" -eq 0 ] && [ -d "$APP" ]; then
        open "$APP" >/dev/null 2>&1 || log "open old app failed"
    fi
    write_result failed "$1"
    exit 1
}

case "$PARENT_PID" in ''|*[!0-9]*) log "invalid parent pid"; exit 1;; esac
case "$EXPECTED_BUILD" in ''|*[!0-9]*) log "invalid expected build"; write_result failed "arguments"; exit 1;; esac
case "$EXPECTED_SHA" in *[!0123456789abcdef]*) log "invalid sha"; write_result failed "arguments"; exit 1;; esac
if [ "${#EXPECTED_SHA}" -ne 64 ]; then
    log "invalid sha length"
    write_result failed "arguments"
    exit 1
fi

log "helper start parent=$PARENT_PID build=$EXPECTED_BUILD zip=$ZIP app=$APP"

waited=0
while kill -0 "$PARENT_PID" 2>/dev/null; do
    waited=$((waited + 1))
    if [ "$waited" -ge 120 ]; then
        log "parent still running after 120s"
        write_result failed "parent-timeout"
        exit 1
    fi
    sleep 1
done
log "parent exited"

[ -f "$ZIP" ] || fail "missing-zip"
[ -d "$APP" ] || fail "missing-app"
case "$APP" in *.app) ;; *) fail "not-app";; esac

PROBE="$APP_DIR/.wattlite-update-probe.$$"
if ! touch "$PROBE" 2>/dev/null; then
    fail "readonly"
fi
rm -f "$PROBE"

ACTUAL_SHA="$(shasum -a 256 "$ZIP" 2>/dev/null | awk '{print tolower($1)}')"
[ "$ACTUAL_SHA" = "$EXPECTED_SHA" ] || fail "hash"
log "zip hash ok"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/WattLite-update.XXXXXX")" || fail "temp"
ditto -x -k "$ZIP" "$WORK" || fail "unzip"
NEW="$WORK/WattLite.app"
[ -d "$NEW" ] || fail "bundle"

PLIST="$NEW/Contents/Info.plist"
[ -f "$PLIST" ] || fail "bundle"
NEW_BUILD="$(plutil -extract CFBundleVersion raw -o - "$PLIST" 2>/dev/null)"
case "$NEW_BUILD" in ''|*[!0-9]*) fail "build";; esac
[ "$NEW_BUILD" -ge "$EXPECTED_BUILD" ] || fail "build"
NEW_ID="$(plutil -extract CFBundleIdentifier raw -o - "$PLIST" 2>/dev/null)"
[ "$NEW_ID" = "$BUNDLE_ID" ] || fail "identifier"
VERSION="$(plutil -extract CFBundleShortVersionString raw -o - "$PLIST" 2>/dev/null | tr -cd '0-9A-Za-z._-')"
[ -n "$VERSION" ] || VERSION="unknown"
log "bundle ok version=$VERSION build=$NEW_BUILD"

codesign --verify --strict "$NEW" >/dev/null 2>&1 || fail "codesign"
log "codesign ok"

BASE="$(basename "$APP")"
BACKUP="$APP_DIR/$BASE.backup-$(date '+%Y%m%d%H%M%S')-$$"
[ ! -e "$BACKUP" ] || fail "backup"
mv "$APP" "$BACKUP" || fail "replace"
ditto "$NEW" "$APP" || fail "replace"
xattr -dr com.apple.quarantine "$APP" >/dev/null 2>&1 || true
codesign --verify --strict "$APP" >/dev/null 2>&1 || fail "replace"

write_result ok "installed"
log "replaced app version=$VERSION build=$NEW_BUILD backup=$BACKUP"

if open "$APP" >/dev/null 2>&1; then
    rm -rf "$BACKUP"
    BACKUP=""
    rm -f "$ZIP"
    log "success"
else
    fail "open"
fi
"""#
}

// URLSessionDataDelegate 回调在串行队列里；把响应写盘并同步喂给 SHA-256，避免整包进内存。
private final class StreamingDownloader: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let destination: URL
    private let onProgress: @Sendable (Double) -> Void
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var handle: FileHandle?
    private var hasher = SHA256()
    private var received: Int64 = 0
    private var expected: Int64 = 0
    private var reported: Int64 = 0
    private var continuation: CheckedContinuation<String, Error>?
    private var finished = false

    init(destination: URL, onProgress: @escaping @Sendable (Double) -> Void) {
        self.destination = destination
        self.onProgress = onProgress
    }

    func run(url: URL) async throws -> String {
        try? FileManager.default.removeItem(at: destination)
        guard FileManager.default.createFile(atPath: destination.path, contents: nil) else {
            throw URLError(.cannotCreateFile)
        }
        handle = try FileHandle(forWritingTo: destination)

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 1200
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        self.session = session

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 30

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                let task = session.dataTask(with: request)
                self.task = task
                if Task.isCancelled { task.cancel() }
                task.resume()
            }
        } onCancel: {
            self.task?.cancel()
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            completionHandler(.cancel)
            finish(.failure(URLError(.badServerResponse)))
            return
        }
        expected = http.expectedContentLength
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard !finished else { return }
        do {
            try handle?.write(contentsOf: data)
        } catch {
            finish(.failure(error))
            dataTask.cancel()
            return
        }
        hasher.update(data: data)
        received += Int64(data.count)
        if expected > 0, received - reported >= 256 * 1024 || received >= expected {
            reported = received
            onProgress(min(1, Double(received) / Double(expected)))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            finish(.failure(error))
            return
        }
        if expected > 0, received != expected {
            finish(.failure(URLError(.badServerResponse)))
            return
        }
        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        finish(.success(digest))
    }

    private func finish(_ result: Result<String, Error>) {
        guard !finished else { return }
        finished = true
        try? handle?.close()
        handle = nil
        session?.invalidateAndCancel()
        session = nil
        if case .failure = result { try? FileManager.default.removeItem(at: destination) }
        continuation?.resume(with: result)
        continuation = nil
    }
}
