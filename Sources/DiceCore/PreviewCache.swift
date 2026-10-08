import Foundation
import CoreGraphics

/// A deterministic memory budget; only decoded previews live here, never original files.
public final class PreviewCache: @unchecked Sendable {
    private struct Entry { let image: CGImage; let cost: Int; var access: UInt64 }
    private var entries: [String: Entry] = [:]
    private var clock: UInt64 = 0
    private var bytes = 0
    private var hits = 0
    private var misses = 0
    private let lock = NSLock()
    public let limit: Int
    public init(limit: Int = 32 * 1024 * 1024) { self.limit = max(0, limit) }
    public static func key(_ url: URL, page: Int = 1) -> String { url.path + "|page:" + String(page) }
    public func image(for key: String) -> CGImage? {
        lock.lock(); defer { lock.unlock() }
        guard var entry = entries[key] else { misses += 1; return nil }
        clock &+= 1; entry.access = clock; entries[key] = entry; hits += 1
        return entry.image
    }
    public func insert(_ image: CGImage, for key: String) {
        let cost = image.bytesPerRow * image.height
        lock.lock(); defer { lock.unlock() }
        if let old = entries.removeValue(forKey: key) { bytes -= old.cost }
        guard cost <= limit else { return }
        while bytes + cost > limit, let oldest = entries.min(by: { $0.value.access < $1.value.access }) {
            bytes -= oldest.value.cost; entries.removeValue(forKey: oldest.key)
        }
        clock &+= 1; entries[key] = Entry(image: image, cost: cost, access: clock); bytes += cost
    }
    public func remove(_ key: String) {
        lock.lock(); defer { lock.unlock() }
        if let old = entries.removeValue(forKey: key) { bytes -= old.cost }
    }
    public func clear() { lock.lock(); defer { lock.unlock() }; entries.removeAll(); bytes = 0 }
    public var statistics: (bytes: Int, count: Int, hits: Int, misses: Int) {
        lock.lock(); defer { lock.unlock() }; return (bytes, entries.count, hits, misses)
    }
}
