import AppKit

/// Byte-budgeted LRU cache for the grid's rendered icon bitmaps.
///
/// The grid renders each app icon into a Retina-sized bitmap before handing it
/// to a `CALayer`. Those bitmaps are large (hundreds of KB each once the grid
/// is wide, e.g. on a 4K display), so a per-path dictionary grows without
/// bound as the user pages through the grid: with ~170 icons the cache alone
/// reached 1.7 GB of resident memory.
///
/// `FolderIconBitmapCache` already solved the same problem for folder
/// previews, so this cache follows the same shape: byte budget, LRU eviction,
/// and a full flush under memory pressure.
final class GridIconBitmapCache {
    private struct Entry {
        let image: CGImage
        let cost: Int
        var lastUse: UInt64
    }

    private let lock = NSLock()
    private let byteLimit: Int
    private var entries: [String: Entry] = [:]
    private var bytes = 0
    private var clock: UInt64 = 0
    private var pressure: DispatchSourceMemoryPressure?

    /// - Parameter byteLimit: hard budget for retained bitmaps. Icons are
    ///   rendered once at display resolution (~0.5 MB each for a 180 pt icon on
    ///   a 2x display), so this holds a few hundred of them: enough for a full
    ///   multi-page grid without evicting what was just shown, while keeping a
    ///   wide display from turning into a gigabyte.
    init(byteLimit: Int = 128 * 1024 * 1024, observesMemoryPressure: Bool = true) {
        self.byteLimit = max(0, byteLimit)
        if observesMemoryPressure {
            let source = DispatchSource.makeMemoryPressureSource(
                eventMask: [.warning, .critical],
                queue: .global(qos: .utility)
            )
            source.setEventHandler { [weak self] in self?.removeAll() }
            pressure = source
            source.resume()
        }
    }

    deinit {
        pressure?.cancel()
    }

    func image(for path: String) -> CGImage? {
        lock.lock()
        defer { lock.unlock() }
        guard var entry = entries[path] else { return nil }
        clock &+= 1
        entry.lastUse = clock
        entries[path] = entry
        return entry.image
    }

    func insert(_ image: CGImage, for path: String) {
        let (cost, overflow) = image.bytesPerRow.multipliedReportingOverflow(by: image.height)
        guard !overflow, cost > 0, cost <= byteLimit else { return }

        lock.lock()
        defer { lock.unlock() }
        if let old = entries.removeValue(forKey: path) {
            bytes -= old.cost
        }
        while bytes > byteLimit - cost,
              let oldest = entries.min(by: { $0.value.lastUse < $1.value.lastUse }) {
            bytes -= oldest.value.cost
            entries.removeValue(forKey: oldest.key)
        }
        clock &+= 1
        entries[path] = Entry(image: image, cost: cost, lastUse: clock)
        bytes += cost
    }

    func removeAll() {
        lock.lock()
        defer { lock.unlock() }
        entries.removeAll()
        bytes = 0
    }

    /// Retained bytes, exposed for diagnostics and tests.
    var currentBytes: Int {
        lock.lock()
        defer { lock.unlock() }
        return bytes
    }
}
