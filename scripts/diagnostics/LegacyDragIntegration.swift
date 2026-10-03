import AppKit
import SwiftUI
import SwiftData

@MainActor enum LegacyDragProbe {
    struct State {
        let draggingID: String?
        let preview: CGPoint
        let pointerOffset: CGPoint
        let gridOrigin: CGPoint
        let gridSize: CGSize
        let columnWidth: CGFloat
        let iconSize: CGFloat
        let refreshID: UUID
        let monitoring: Bool
        let pendingIndex: Int?
    }
    static var state: (() -> State)?
    static var iconPoint: ((Int) -> CGPoint)?
    static var finishAgain: (() -> Void)?
    static var finalizeCount = 0
}

@main struct LegacyDragIntegration {
    @MainActor static func main() {
        setbuf(stdout, nil)
        NSApplication.shared.setActivationPolicy(.accessory)
        let store = AppStore()
        store.useCAGridRenderer = false
        store.isFullscreenMode = false
        store.gridColumnsPerPage = 4
        store.gridRowsPerPage = 3
        store.iconColumnSpacing = 0
        store.iconRowSpacing = 0
        store.enableAnimations = false
        store.backgroundImageEnabled = false
        store.shouldShowOnboarding = false
        store.enableDropPrediction = true
        // Leave a clear insertion region beside each icon, distinct from the folder drop zone.
        store.iconScale = 0.65
        let container = try! ModelContainer(for: TopItemData.self, PageEntryData.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        store.modelContext = container.mainContext
        let apps = (0..<24).map { index in
            AppInfo(name: "Drag fixture \(index)", icon: NSImage(size: NSSize(width: 64, height: 64)),
                    url: URL(fileURLWithPath: "/Synthetic/DragFixture\(index).app"))
        }
        store.apps = apps
        store.items = apps.map { .app($0) }
        let window = BorderlessWindow(contentRect: CGRect(x: 100, y: 100, width: 1000, height: 700),
                                      styleMask: [.borderless, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "LaunchNext Legacy drag verification"
        window.contentView = NSHostingView(rootView: LaunchpadView(appStore: store))
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        func pause(_ seconds: Double = 0.08) async throws {
            try await Task.sleep(for: .seconds(seconds))
        }
        func state() -> LegacyDragProbe.State { LegacyDragProbe.state!() }
        func windowPoint(_ gridPoint: CGPoint) -> CGPoint {
            let origin = state().gridOrigin
            return CGPoint(x: gridPoint.x + origin.x,
                           y: window.contentView!.bounds.height - gridPoint.y - origin.y)
        }
        func post(_ type: NSEvent.EventType, _ point: CGPoint, in target: NSWindow? = nil) {
            let target = target ?? window
            let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: target.windowNumber,
                context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1)!
            // Go through the app's event queue, including local monitors and SwiftUI gestures.
            NSApp.postEvent(event, atStart: false)
        }
        func begin(_ index: Int = 0) async throws {
            let point = LegacyDragProbe.iconPoint!(index)
            post(.leftMouseDown, windowPoint(point))
            try await pause()
            post(.leftMouseDragged, windowPoint(CGPoint(x: point.x + 6, y: point.y)))
            try await pause()
            precondition(state().draggingID != nil, "The real SwiftUI gesture must start a drag")
        }
        func move(_ point: CGPoint) async throws {
            post(.leftMouseDragged, windowPoint(point))
            try await pause(0.15)
        }
        func release(_ point: CGPoint) async throws {
            post(.leftMouseUp, windowPoint(point))
            try await pause(0.4)
        }
        func insertionPoint(_ index: Int) -> CGPoint {
            let center = LegacyDragProbe.iconPoint!(index)
            return CGPoint(x: center.x - state().columnWidth * 0.4, y: center.y)
        }
        func checkFinished() {
            precondition(state().draggingID == nil && !state().monitoring, "Release must clear preview and monitor")
            precondition(LegacyDragProbe.finalizeCount == 1, "Each drag must finalize exactly once")
        }
        func reset() async throws {
            store.searchText = ""
            store.isLayoutLocked = false
            store.useCAGridRenderer = false
            store.openFolder = nil
            store.folders = []
            store.items = apps.map { .app($0) }
            store.currentPage = 0
            store.triggerGridRefresh()
            try await pause(0.25)
            LegacyDragProbe.finalizeCount = 0
        }
        func checkMembership() {
            let flattened = store.items.flatMap { item -> [String] in
                switch item {
                case .app(let app): return [app.id]
                case .folder(let folder): return folder.apps.map(\.id)
                default: return []
                }
            }
            precondition(flattened.sorted() == apps.map(\.id).sorted(), "No apps may be lost or duplicated")
        }
        func descendants(_ view: NSView) -> [NSView] {
            [view] + view.subviews.flatMap(descendants)
        }

        Task { @MainActor in
            do {
                try await pause(0.6)
                precondition(LegacyDragProbe.state != nil && state().gridSize.width > 0)
                let expectStuck = CommandLine.arguments.contains("--expect-stuck")
                try await begin()
                let refreshBefore = state().refreshID
                store.triggerGridRefresh()
                try await pause(0.15)
                if !expectStuck {
                    precondition(state().refreshID == refreshBefore, "Grid rebuild must wait until drag ends")
                }
                let target = insertionPoint(2)
                try await move(target)
                if !expectStuck {
                    let expected = CGPoint(x: target.x - state().pointerOffset.x, y: target.y - state().pointerOffset.y)
                    precondition(hypot(state().preview.x - expected.x, state().preview.y - expected.y) < 2,
                                 "Preview must keep following after the tile disappears")
                }
                try await release(target)
                if expectStuck {
                    precondition(state().draggingID != nil && LegacyDragProbe.finalizeCount == 0,
                                 "Baseline must reproduce the missing drag completion")
                    print("PASS baseline reproduced: refresh during a real SwiftUI drag leaves the preview stuck")
                    exit(0)
                }
                checkFinished()
                precondition(state().refreshID == store.gridRefreshTrigger)
                precondition(store.items[2] == .app(apps[0]), "Same-page drop must move to the requested slot")
                checkMembership()
                print("PASS refresh during drag: preview follows, drop completes once, pending refresh applies")

                try await reset()
                try await begin()
                store.items.swapAt(0, 1) // A real model change destroys the original tile identity.
                try await pause(0.15)
                try await move(insertionPoint(3))
                try await release(insertionPoint(3))
                checkFinished()
                checkMembership()
                print("PASS tile replacement during drag: fallback completes without losing apps")

                try await reset()
                try await begin()
                let destination = insertionPoint(2)
                post(.leftMouseUp, windowPoint(destination)) // No final mouseDragged callback.
                try await pause(0.04)
                LegacyDragProbe.finishAgain?() // Late duplicate gesture completion.
                try await pause(0.35)
                checkFinished()
                precondition(store.items[2] == .app(apps[0]))
                checkMembership()
                print("PASS mouse-up uses the final pointer position and ignores duplicate completion")

                try await reset()
                try await begin()
                try await move(CGPoint(x: state().gridSize.width - 2, y: state().preview.y))
                precondition(store.currentPage == 1, "Dragging to the edge must turn the page")
                try await move(insertionPoint(14))
                try await release(insertionPoint(14))
                checkFinished()
                precondition(store.items.firstIndex(of: .app(apps[0]))! >= 12)
                checkMembership()
                print("PASS cross-page drop retains all apps")

                try await reset()
                try await begin()
                try await move(LegacyDragProbe.iconPoint!(2))
                try await release(LegacyDragProbe.iconPoint!(2))
                checkFinished()
                precondition(store.folders.count == 1 && store.folders[0].apps.count == 2)
                checkMembership()
                print("PASS folder creation completes once")

                try await reset()
                let folder = FolderInfo(name: "Fixture folder", apps: [apps[2], apps[3]])
                store.folders = [folder]
                store.items = [.app(apps[0]), .app(apps[1]), .folder(folder)] + apps.dropFirst(4).map { .app($0) }
                try await pause(0.2)
                try await begin()
                try await move(LegacyDragProbe.iconPoint!(2))
                try await release(LegacyDragProbe.iconPoint!(2))
                checkFinished()
                precondition(store.folders[0].apps.contains(apps[0]))
                checkMembership()
                print("PASS drop into existing folder")

                try await reset()
                try await begin()
                try await release(CGPoint(x: -40, y: -30))
                checkFinished()
                checkMembership()
                print("PASS mouse-up outside the grid clears the drag")

                try await reset()
                try await begin()
                let other = NSWindow(contentRect: CGRect(x: 50, y: 50, width: 200, height: 120),
                                     styleMask: [.titled], backing: .buffered, defer: false)
                let beforeOtherEvent = state().preview
                post(.leftMouseDragged, CGPoint(x: 10, y: 10), in: other)
                post(.leftMouseUp, CGPoint(x: 10, y: 10), in: other)
                try await pause(0.15)
                precondition(state().monitoring && state().preview == beforeOtherEvent
                             && LegacyDragProbe.finalizeCount == 0, "Other windows must not control this drag")
                try await release(insertionPoint(2))
                checkFinished()
                print("PASS unrelated window events do not move or finish the Legacy drag")

                try await reset()
                try await begin()
                post(.leftMouseUp, windowPoint(insertionPoint(2)))
                try await pause(0.03)
                NotificationCenter.default.post(name: .launchpadWindowHidden, object: nil)
                try await pause(0.02)
                try await begin(1)
                try await pause(0.12) // Let the previous drag's delayed cleanup fire.
                precondition(state().draggingID != nil && state().monitoring,
                             "Old cleanup must not cancel a newer drag")
                try await release(insertionPoint(3))
                precondition(state().draggingID == nil && !state().monitoring && LegacyDragProbe.finalizeCount == 2)
                checkMembership()
                print("PASS cancelled landing cleanup cannot clear a subsequent drag")

                for reason in ["lock", "hide", "search", "engine", "deactivate"] {
                    try await reset()
                    let before = store.items.map(\.id)
                    try await begin()
                    switch reason {
                    case "lock": store.isLayoutLocked = true
                    case "hide": NotificationCenter.default.post(name: .launchpadWindowHidden, object: nil)
                    case "search": store.searchText = "Fixture"
                    case "engine": store.useCAGridRenderer = true
                    default: NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: nil)
                    }
                    try await pause(0.1)
                    post(.leftMouseUp, windowPoint(CGPoint(x: 10, y: 10)))
                    try await pause(0.3)
                    precondition(state().draggingID == nil && !state().monitoring)
                    precondition(LegacyDragProbe.finalizeCount == 0 && store.items.map(\.id) == before,
                                 "Cancellation must not place or reorder the dragged app")
                    print("PASS \(reason) cancels the Legacy drag and removes its monitor")
                }

                // Exercise the existing folder-to-grid handoff on each renderer.
                for useCA in [false, true] {
                    try await reset()
                    store.useCAGridRenderer = useCA
                    let sourceFolder = FolderInfo(name: "Handoff folder", apps: Array(apps.prefix(3)))
                    store.folders = [sourceFolder]
                    store.items = [.folder(sourceFolder)] + apps.dropFirst(3).map { .app($0) }
                    try await pause(0.25)
                    store.handoffDragScreenLocation = window.convertPoint(toScreen: windowPoint(insertionPoint(2)))
                    store.handoffDraggingApp = apps[0]
                    store.removeAppFromFolder(apps[0], folder: sourceFolder)
                    try await pause(0.2)
                    precondition(state().draggingID == LaunchpadItem.app(apps[0]).id && !state().monitoring,
                                 "Folder handoff must use its existing monitor")
                    try await release(insertionPoint(2))
                    checkFinished()
                    checkMembership()
                    print("PASS folder handoff in \(useCA ? "Next" : "Legacy") retains its existing path")
                }

                try await reset()
                store.useCAGridRenderer = true
                try await pause(0.3)
                guard let grid = descendants(window.contentView!).compactMap({ $0 as? CAGridView }).first else {
                    preconditionFailure("Next grid missing")
                }
                let sourcePoint = grid.iconCenter(for: 0)!
                post(.leftMouseDown, grid.convert(sourcePoint, to: nil))
                try await pause()
                post(.leftMouseDragged, grid.convert(CGPoint(x: sourcePoint.x + 16, y: sourcePoint.y), to: nil))
                try await pause(0.15)
                precondition(grid.isDraggingItem && !state().monitoring && state().draggingID == nil,
                             "Next must keep owning its native drag")
                let destinationCenter = grid.iconCenter(for: 2)!
                let nextDestination = CGPoint(x: destinationCenter.x - state().columnWidth * 0.4, y: destinationCenter.y)
                post(.leftMouseDragged, grid.convert(nextDestination, to: nil))
                try await pause(0.15)
                post(.leftMouseUp, grid.convert(nextDestination, to: nil))
                try await pause(0.4)
                precondition(!grid.isDraggingItem && LegacyDragProbe.finalizeCount == 0)
                checkMembership()
                print("PASS Next native drag completes without using Legacy monitoring or finalization")
                window.orderOut(nil)
                print("PASS Legacy drag integration")
                exit(0)
            } catch { fatalError("\(error)") }
        }
        NSApp.run()
    }
}
