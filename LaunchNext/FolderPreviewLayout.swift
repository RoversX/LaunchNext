import Foundation
import CoreGraphics

/// Shared by the bitmap renderer and merge animation (bottom-left coordinates).
enum FolderPreviewLayout {
    static func iconRect(at index: Int, side: CGFloat) -> CGRect? {
        guard (0..<9).contains(index), side > 0 else { return nil }
        let content = CGRect(x: 0, y: 0, width: side, height: side)
            .insetBy(dx: round(side * 0.12), dy: round(side * 0.12))
        let inner = content.insetBy(dx: round(content.width * 0.08), dy: round(content.width * 0.08))
        let spacing = max(1, round(inner.width * 0.02))
        let tile = floor((inner.width - 2 * spacing) / 3)
        let inset = (inner.width - (3 * tile + 2 * spacing)) / 2
        return CGRect(x: inner.minX + inset + CGFloat(index % 3) * (tile + spacing),
                      y: inner.maxY - inset - CGFloat(index / 3 + 1) * tile - CGFloat(index / 3) * spacing,
                      width: tile, height: tile)
    }
}
