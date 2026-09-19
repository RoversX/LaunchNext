import Foundation

/// Bounds retained desktop frames, independently of temporary capture/decoding buffers.
public enum WallpaperCacheBudget {
    public static let maximumBytes = 48 * 1024 * 1024

    /// `mostRecentFirst` includes only retained displays. Never evict the frame
    /// currently being displayed, even if that single image exceeds the budget.
    public static func retainedDisplays(
        mostRecentFirst: [UInt32], bytesByDisplay: [UInt32: Int],
        currentDisplay: UInt32, unfiltered: Bool
    ) -> Set<UInt32> {
        let countLimit = unfiltered ? 3 : 8
        var retained: Set<UInt32> = []
        var remaining = maximumBytes
        let ordered = [currentDisplay] + mostRecentFirst.filter { $0 != currentDisplay }
        for display in ordered {
            guard !retained.contains(display), let bytes = bytesByDisplay[display], bytes >= 0 else { continue }
            guard retained.count < countLimit else { break }
            if display == currentDisplay || bytes <= remaining {
                retained.insert(display)
                remaining = max(0, remaining - bytes)
            }
        }
        return retained
    }
}
