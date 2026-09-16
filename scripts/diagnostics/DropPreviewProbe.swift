import AppKit

// Minimal model/host for the production preview and commit extension. Pointer
// hit testing remains a main-app acceptance check; these checks verify that
// the displayed operation is the one actually dispatched to the owner.
struct AppInfo { let id: String }
struct FolderInfo { let id: String }
enum LaunchpadItem {
    case app(AppInfo), folder(FolderInfo), empty(String), missingApp(String)
    var id: String {
        switch self {
        case .app(let value): return value.id
        case .folder(let value): return value.id
        case .empty(let value), .missingApp(let value): return value
        }
    }
}

@MainActor final class CAGridView {
    var items: [LaunchpadItem] = []
    var dragDropPreview: GridDropPreview = .none
    var pendingDropPreview: GridDropPreview?
    var isDraggingItem = true
    let hoverUpdateDelay: TimeInterval = 0.15
    var hoverUpdateTimer: Timer?
    var pendingHoverIndex: Int?
    var currentHoverIndex: Int?
    var dropTargetIndex: Int?
    var onReorderItems: ((Int, Int) -> Void)?
    var onCreateFolder: ((AppInfo, AppInfo, Int) -> Void)?
    var onMoveToFolder: ((AppInfo, FolderInfo) -> Void)?
    func clearDropTargetHighlight() { dropTargetIndex = nil }
    func highlightDropTarget(at index: Int) { dropTargetIndex = index }
    func applyIconPositionUpdate() { currentHoverIndex = pendingHoverIndex }
}

@main struct DropPreviewProbe {
    @MainActor static func main() {
        precondition(GridDropPreview.insertion(index: 9, sourceIndex: 4, itemCount: 5, itemsPerPage: 12) == .none,
                     "last item dropped in trailing empty cells must stay in its actual slot")
        precondition(GridDropPreview.insertion(index: 9, sourceIndex: 1, itemCount: 5, itemsPerPage: 12) == .insert(index: 4))
        precondition(GridDropPreview.insertion(index: 19, sourceIndex: 1, itemCount: 15, itemsPerPage: 12) == .insert(index: 15))
        precondition(GridDropPreview.insertion(index: 8, sourceIndex: 1, itemCount: 20, itemsPerPage: 12) == .insert(index: 8))
        let grid = CAGridView()
        let source = LaunchpadItem.app(AppInfo(id: "source"))
        let target = LaunchpadItem.app(AppInfo(id: "target"))
        let folder = LaunchpadItem.folder(FolderInfo(id: "folder"))
        grid.items = [source, target, folder]
        var actions: [String] = []
        grid.onCreateFolder = { actions.append("create:\($0.id):\($1.id):\($2)") }
        grid.onMoveToFolder = { actions.append("add:\($0.id):\($1.id)") }
        grid.onReorderItems = { actions.append("insert:\($0):\($1)") }

        grid.requestDropPreview(.insert(index: 1))
        let pendingTimer = grid.hoverUpdateTimer!
        precondition(grid.dragDropPreview == .none && grid.currentHoverIndex == nil)
        // A non-repeating Timer reports a zero repeat interval.
        precondition(abs(pendingTimer.fireDate.timeIntervalSinceNow - 0.15) < 0.03)
        grid.requestDropPreview(.insert(index: 1))
        precondition(grid.hoverUpdateTimer === pendingTimer, "same candidate must not postpone dwell")
        _ = grid.commitDropPreview(grid.dragDropPreview, draggedItem: source)
        precondition(actions.isEmpty, "unseen insertion must not be committed")
        pendingTimer.fire()
        precondition(grid.dragDropPreview == .insert(index: 1) && grid.currentHoverIndex == 1)
        grid.requestDropPreview(.insert(index: 2))
        let staleTimer = grid.hoverUpdateTimer!
        grid.requestDropPreview(.merge(targetID: "target"))
        precondition(!staleTimer.isValid && grid.dragDropPreview == .merge(targetID: "target"))
        grid.requestDropPreview(.insert(index: 2))
        precondition(grid.dropTargetIndex == nil && grid.dragDropPreview == .none,
                     "leaving merge clears its feedback before insertion dwell")
        let cancelledTimer = grid.hoverUpdateTimer!
        grid.showDropPreview(.none)
        precondition(!cancelledTimer.isValid && grid.pendingDropPreview == nil,
                     "cancel/page change must clear pending work even with no displayed preview")

        grid.pendingHoverIndex = 2
        grid.currentHoverIndex = 2
        let timer = Timer(timeInterval: 0.15, repeats: false) { _ in preconditionFailure("stale insertion") }
        RunLoop.main.add(timer, forMode: .common)
        grid.hoverUpdateTimer = timer
        grid.showDropPreview(.merge(targetID: "target"))
        precondition(!timer.isValid && grid.hoverUpdateTimer == nil)
        precondition(grid.dropTargetIndex == 1 && grid.currentHoverIndex == nil)
        _ = grid.commitDropPreview(grid.dragDropPreview, draggedItem: source)
        precondition(actions == ["create:source:target:1"])

        // Immediate release after switching from a merge to an insertion.
        grid.showDropPreview(.insert(index: 2))
        precondition(grid.dropTargetIndex == nil && grid.currentHoverIndex == 2)
        _ = grid.commitDropPreview(grid.dragDropPreview, draggedItem: source)
        precondition(actions.last == "insert:0:2")
        grid.showDropPreview(.merge(targetID: "folder"))
        precondition(grid.dropTargetIndex == 2 && grid.currentHoverIndex == nil)
        _ = grid.commitDropPreview(grid.dragDropPreview, draggedItem: source)
        precondition(actions.last == "add:source:folder")

        // Another model publication moves the target and source before release.
        grid.showDropPreview(.merge(targetID: "target"))
        grid.items = [target, folder, source]
        _ = grid.commitDropPreview(grid.dragDropPreview, draggedItem: source)
        precondition(actions.last == "create:source:target:0")
        let count = actions.count
        grid.items = [folder, source]
        precondition(grid.commitDropPreview(grid.dragDropPreview, draggedItem: source) == .none)
        precondition(actions.count == count, "missing merge target must not become insertion")
        grid.showDropPreview(.none)
        precondition(grid.dropTargetIndex == nil && grid.currentHoverIndex == nil)
        _ = grid.commitDropPreview(grid.dragDropPreview, draggedItem: source)
        _ = grid.commitDropPreview(.merge(targetID: "source"), draggedItem: source)
        _ = grid.commitDropPreview(.insert(index: 1), draggedItem: source)
        precondition(actions.count == count)
        grid.items = [folder]
        _ = grid.commitDropPreview(.insert(index: 1), draggedItem: source)
        precondition(actions.count == count, "removed source must cancel")

        let layer = CALayer()
        layer.position = CGPoint(x: 10, y: 20)
        let visible = CGPoint(x: 30, y: 40)
        let destination = CGPoint(x: 200, y: 20)
        GridLayerMotion.move(layer, to: destination, from: visible)
        let animation = layer.animation(forKey: "position") as! CABasicAnimation
        precondition((animation.fromValue as! NSValue).pointValue == visible)
        precondition((animation.toValue as! NSValue).pointValue == destination)
        precondition(layer.position == destination && animation.duration == 0.18)
        GridLayerMotion.move(layer, to: destination)
        let unchanged = layer.animation(forKey: "position") as! CABasicAnimation
        precondition((unchanged.fromValue as! NSValue).pointValue == visible,
                     "duplicate publication must not restart motion")
        GridLayerMotion.move(layer, to: CGPoint(x: 350, y: 20), from: CGPoint(x: 90, y: 20))
        let redirected = layer.animation(forKey: "position") as! CABasicAnimation
        precondition((redirected.fromValue as! NSValue).pointValue == CGPoint(x: 90, y: 20))
        GridLayerMotion.move(layer, to: CGPoint(x: 400, y: 20), duringHover: true)
        precondition(layer.animation(forKey: "position")!.duration == 0.45,
                     "hover movement must retain the original timing, separate from landing")
        print("PASS: insertion dwell, no unseen drop, merge/insert/none feedback and dispatch, immediate release, stale timer cancellation, stable target identity, missing target/source, separate hover/landing timing, duplicate update and mid-motion retarget")
    }
}
