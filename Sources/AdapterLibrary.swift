import AppKit
import Combine

extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

// 用户自定义适配器资料：JSON 存 Application Support，图片复用 adapters/ 落盘目录，
// 与内置 knownAdapters 同键规则（VID:PID 优先），用户条目覆盖内置条目。
@MainActor
final class AdapterLibrary: ObservableObject {
    static let shared = AdapterLibrary()

    struct Entry: Codable, Equatable {
        var name: String = ""
        var model: String = ""
        var protocols: String = ""
    }

    @Published private(set) var entries: [String: Entry] = [:]

    private static var directory: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("WattLite/adapters", isDirectory: true)
    }
    private static var storeURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("WattLite/adapters.json")
    }

    private init() {
        guard let url = Self.storeURL,
              let data = try? Data(contentsOf: url),
              let loaded = try? JSONDecoder().decode([String: Entry].self, from: data) else { return }
        entries = loaded
    }

    func entry(for key: String?) -> Entry? {
        key.flatMap { entries[$0] }
    }

    func save(_ entry: Entry, key: String, image: NSImage?) {
        entries[key] = entry
        persist()
        if let image { writeImage(image, key: key) }
    }

    func remove(key: String) {
        entries.removeValue(forKey: key)
        persist()
        if let url = Self.directory?.appendingPathComponent("\(key).png") {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func persist() {
        guard let url = Self.storeURL else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(entries) {
            try? data.write(to: url, options: .atomic)
        }
    }

    private func writeImage(_ image: NSImage, key: String) {
        guard let directory = Self.directory else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: directory.appendingPathComponent("\(key).png"), options: .atomic)
    }
}
