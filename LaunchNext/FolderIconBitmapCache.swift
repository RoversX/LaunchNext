import AppKit

/// Small rendered icons shared across folder presentations. The byte limit is
/// enforced explicitly; live icon layers can still retain their own images.
final class FolderIconBitmapCache {
    static let shared = FolderIconBitmapCache()

    struct Key: Hashable {
        let path: String
        let side: CGFloat
        let scale: CGFloat
        let appearance: String
    }
    struct Request {
        let key: Key
        let generation: UInt64
    }
    private struct Entry {
        let image: CGImage
        weak var source: NSImage?
        let cost: Int
        var lastUse: UInt64
    }

    private let lock = NSLock()
    private let byteLimit: Int
    private var entries: [Key: Entry] = [:]
    private var bytes = 0
    private var clock: UInt64 = 0
    private var generation: UInt64 = 0
    private var pressure: DispatchSourceMemoryPressure?

    init(byteLimit: Int = 4 * 1024 * 1024, observesMemoryPressure: Bool = true) {
        self.byteLimit = max(0, byteLimit)
        if observesMemoryPressure {
            let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .global(qos: .utility))
            source.setEventHandler { [weak self] in self?.clear() }
            pressure = source
            source.resume()
        }
    }
    deinit { pressure?.cancel() }

    func request(for key: Key) -> Request {
        lock.lock(); defer { lock.unlock() }
        return Request(key: key, generation: generation)
    }

    func image(for request: Request, source: NSImage) -> CGImage? {
        lock.lock(); defer { lock.unlock() }
        guard request.generation == generation, var entry = entries[request.key] else { return nil }
        guard entry.source === source else {
            bytes -= entry.cost
            entries.removeValue(forKey: request.key)
            return nil
        }
        clock &+= 1
        entry.lastUse = clock
        entries[request.key] = entry
        return entry.image
    }

    func insert(_ image: CGImage, for request: Request, source: NSImage) {
        let (cost, overflow) = image.bytesPerRow.multipliedReportingOverflow(by: image.height)
        guard !overflow, cost > 0, cost <= byteLimit else { return }
        lock.lock(); defer { lock.unlock() }
        // Work started before a refresh must not repopulate the cleared cache.
        guard request.generation == generation else { return }
        if let old = entries.removeValue(forKey: request.key) { bytes -= old.cost }
        while bytes > byteLimit - cost, let oldest = entries.min(by: { $0.value.lastUse < $1.value.lastUse }) {
            bytes -= oldest.value.cost
            entries.removeValue(forKey: oldest.key)
        }
        clock &+= 1
        entries[request.key] = Entry(image: image, source: source, cost: cost, lastUse: clock)
        bytes += cost
    }

    func isCurrent(_ request: Request) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return request.generation == generation
    }

    func clear() {
        lock.lock(); defer { lock.unlock() }
        generation &+= 1
        entries.removeAll()
        bytes = 0
    }
}
