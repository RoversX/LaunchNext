import AppKit

extension CAGridView {
    /// Retain the original insertion dwell while keeping merge feedback
    /// immediate. Only a displayed preview is eligible for mouse-up.
    func requestDropPreview(_ preview: GridDropPreview) {
        guard case .insert = preview, preview != dragDropPreview else {
            showDropPreview(preview)
            return
        }
        guard pendingDropPreview != preview else { return }
        // Leaving a merge zone must immediately clear its highlight, even
        // while waiting for the next insertion preview to become stable.
        if case .merge = dragDropPreview { showDropPreview(.none) }
        hoverUpdateTimer?.invalidate()
        pendingDropPreview = preview
        let timer = Timer(timeInterval: hoverUpdateDelay, repeats: false) { [weak self] _ in
            // Installed exclusively on RunLoop.main below.
            MainActor.assumeIsolated {
                guard let self, self.isDraggingItem, self.pendingDropPreview == preview else { return }
                self.showDropPreview(preview)
            }
        }
        hoverUpdateTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    /// Commit the operation and its feedback together. Single-item previews
    /// cannot leave a delayed insertion timer racing a merge highlight.
    func showDropPreview(_ preview: GridDropPreview) {
        hoverUpdateTimer?.invalidate()
        hoverUpdateTimer = nil
        pendingDropPreview = nil
        guard preview != dragDropPreview else { return }
        dragDropPreview = preview
        clearDropTargetHighlight()
        switch preview {
        case .none:
            pendingHoverIndex = nil
        case .insert(let index):
            pendingHoverIndex = index
        case .merge(let targetID):
            pendingHoverIndex = nil
            if let index = items.firstIndex(where: { $0.id == targetID }) {
                highlightDropTarget(at: index)
            }
        }
        applyIconPositionUpdate()
    }

    /// Execute exactly the preview that was displayed. This deliberately takes
    /// no pointer location: mouse-up must not use a second hit-testing rule.
    func commitDropPreview(_ preview: GridDropPreview, draggedItem: LaunchpadItem) -> GridDropPreview {
        guard let sourceIndex = items.firstIndex(where: { $0.id == draggedItem.id }) else { return .none }
        switch preview {
        case .none:
            return .none
        case .insert(let index):
            guard index >= 0, index != sourceIndex else { return .none }
            onReorderItems?(sourceIndex, index)
            return preview
        case .merge(let targetID):
            if case .app(let app) = draggedItem, targetID != draggedItem.id,
               let index = items.firstIndex(where: { $0.id == targetID }) {
                switch items[index] {
                case .app(let target):
                    guard let onCreateFolder else { return .none }
                    onCreateFolder(app, target, index)
                    return preview
                case .folder(let folder):
                    guard let onMoveToFolder else { return .none }
                    onMoveToFolder(app, folder)
                    return preview
                case .empty, .missingApp:
                    break
                }
            }
            // A missing highlighted target cancels the merge; it cannot become
            // an insertion just because the target changed before mouse-up.
            return .none
        }
    }
}
