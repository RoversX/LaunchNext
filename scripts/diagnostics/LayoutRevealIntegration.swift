// Uses real LaunchpadView, AppStore methods and CA views in the isolated diagnostic target.
import AppKit
import SwiftUI

@main struct LayoutRevealIntegration {
    @MainActor static func main() {
        setbuf(stdout, nil)
        NSApplication.shared.setActivationPolicy(.accessory)
        let store = AppStore()
        store.useCAGridRenderer = true
        store.enableAnimations = true
        store.backgroundImageEnabled = false
        store.shouldShowOnboarding = false
        store.isInitialLoading = false
        store.searchDebounceMilliseconds = 200
        let apps = (0..<125).map { index in
            AppInfo(name: "Test \(index)", icon: NSImage(size: NSSize(width: 64, height: 64)),
                    url: URL(fileURLWithPath: "/Applications/RevealFixture\(index).app"))
        }
        let folder = FolderInfo(name: "Reveal folder", apps: Array(apps[10...80]))
        store.folders = [folder]
        // The folder is on page four; intermediate pages have real icons too.
        let folderIndex = 105
        let appIndex = 106
        store.items = Array(apps.prefix(5)).map { .app($0) }
            + (0..<30).map { _ in .empty(UUID().uuidString) }
        store.items += Array(apps[81...90]).map { .app($0) }
            + (0..<25).map { _ in .empty(UUID().uuidString) }
        store.items += Array(apps[91...100]).map { .app($0) }
            + (0..<25).map { _ in .empty(UUID().uuidString) }
        store.items += [.folder(folder), .app(apps[124])]
        let window = NSWindow(contentRect: CGRect(x: 100, y: 100, width: 1100, height: 800),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = NSHostingView(rootView: LaunchpadView(appStore: store))
        window.makeKeyAndOrderFront(nil)
        func descendants(_ view: NSView) -> [NSView] {
            [view] + view.subviews.flatMap(descendants)
        }
        func outerGrid() -> CAGridView? {
            descendants(window.contentView!).compactMap { $0 as? CAGridView }.first
        }
        func folderGrid() -> CAFolderGridView? {
            descendants(window.contentView!).compactMap { $0 as? CAFolderGridView }.first
        }
        func outerFeedback(at index: Int) -> CAKeyframeAnimation? {
            outerGrid()?.presentationContainer(at: index)?.animation(forKey: LayoutRevealFeedback.animationKey) as? CAKeyframeAnimation
        }
        func waitFor(_ description: String, timeout: TimeInterval = 2.5, _ ready: () -> Bool) async throws {
            let deadline = CACurrentMediaTime() + timeout
            while !ready(), CACurrentMediaTime() < deadline { try await Task.sleep(for: .milliseconds(10)) }
            precondition(ready(), description)
        }
        func checkFeedback(_ animation: CAKeyframeAnimation?) {
            guard let animation, let values = animation.values as? [NSNumber] else {
                preconditionFailure("Missing press feedback")
            }
            precondition(values.count == 3 && values[0].doubleValue == 1 && values[2].doubleValue == 1)
            precondition(values[1].doubleValue < 1, "Feedback must shrink, not magnify")
            precondition(animation.duration == LayoutRevealFeedback.duration)
        }
        Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(350))
                // A normal pending search must not overwrite the requested destination.
                store.searchText = "Test 124"
                try await Task.sleep(for: .milliseconds(300))
                store.searchText = "Test 8"
                outerGrid()?.clearIconCache()
                precondition(store.requestShowInLayout(apps[124]))
                precondition(store.searchText.isEmpty && store.searchQuery.isEmpty, "Show must clear search immediately")
                try await waitFor("The full layout must be restored") { outerGrid()?.items.count == store.items.count }
                try await Task.sleep(for: .milliseconds(100))
                precondition(store.currentPage == 0, "Keep page one visible while icons are loading")
                precondition(outerGrid()?.revealIconsAreReady(from: 0, through: 3) == false)
                try await waitFor("Start guided paging once icons are ready") { outerGrid()?.layoutRevealPageMotion != nil }
                guard let pagingGrid = outerGrid() else { preconditionFailure("Missing main grid") }
                precondition(pagingGrid.revealIconsAreReady(from: 0, through: 3))
                let motion = pagingGrid.layoutRevealPageMotion!
                precondition(motion.duration >= 0.6)
                // A normal SwiftUI layout during paging must preserve the animation.
                pagingGrid.needsLayout = true
                pagingGrid.layoutSubtreeIfNeeded()
                precondition(pagingGrid.layoutRevealPageMotion?.id == motion.id)
                try await Task.sleep(for: .milliseconds(180))
                precondition(pagingGrid.isScrollAnimating)
                precondition(pagingGrid.scrollOffset < motion.from && pagingGrid.scrollOffset > motion.to)
                precondition(store.openFolder == nil)
                try await waitFor("Acknowledge the destination after paging") { outerFeedback(at: appIndex) != nil }
                checkFeedback(outerFeedback(at: appIndex))
                try await Task.sleep(for: .milliseconds(650))
                precondition(store.searchText.isEmpty && store.searchQuery.isEmpty)
                precondition(store.currentPage == appIndex / (store.gridColumnsPerPage * store.gridRowsPerPage))
                precondition(outerGrid()?.selectedIndex == nil, "Navigation must not magnify the target")
                precondition(store.openFolder == nil && store.layoutRevealRequest == nil)
                print("PASS cold icons finish before page-one-to-four motion; layout preserves intermediate frames")
                for mode: AppStore.FolderLayoutMode in [.paged, .vertical] {
                    store.folderLayoutMode = mode
                    store.searchText = "Test 79"
                    try await Task.sleep(for: .milliseconds(300))
                    precondition(store.requestShowInLayout(apps[79]))
                    let requestedAt = CACurrentMediaTime()
                    try await waitFor("The containing folder must acknowledge navigation", timeout: 2.5) { outerFeedback(at: folderIndex) != nil }
                    checkFeedback(outerFeedback(at: folderIndex))
                    precondition(store.openFolder == nil, "Press the containing folder before opening it")
                    precondition(outerGrid()?.selectedIndex == nil, "The containing folder must not magnify during the pause")
                    precondition(store.layoutRevealRequest != nil)
                    try await waitFor("Open promptly after the press", timeout: 0.5) { store.openFolder?.id == folder.id }
                    precondition(CACurrentMediaTime() - requestedAt >= 0.85, "Show the page route before opening")
                    try await waitFor("The nested app must acknowledge the final step") { folderGrid()?.probeRevealFeedback != nil }
                    checkFeedback(folderGrid()?.probeRevealFeedback)
                    try await Task.sleep(for: .milliseconds(300))
                    precondition(store.currentPage == folderIndex / (store.gridColumnsPerPage * store.gridRowsPerPage))
                    guard let grid = folderGrid() else { preconditionFailure("Folder grid not created") }
                    precondition(grid.probeSelectedIndex == 69, "Nested app must be selected")
                    precondition(grid.probeSelectionVisible, "Nested app must be visible")
                    precondition(grid.probeSelectedIconScale == 1, "Revealing the nested app must not magnify it")
                    if mode == .paged { precondition(grid.displayedPage > 0) }
                    // Ordinary keyboard selection must still use its existing enlargement.
                    grid.updateSelection(69, animated: false)
                    precondition(abs(grid.probeSelectedIconScale - 1.16) < 0.001)
                    print("PASS nested reveal in \(mode): guided paging then folder/app press feedback, visible destination and normal selection")
                    store.openFolder = nil
                    try await Task.sleep(for: .milliseconds(400))
                    store.openFolder = folder
                    try await Task.sleep(for: .milliseconds(500))
                    precondition(folderGrid()?.probeSelectedIndex == nil, "Ordinary reopen must not reuse old reveal")
                    store.openFolder = nil
                    try await Task.sleep(for: .milliseconds(400))
                }
                store.searchText = "Test 79"
                try await Task.sleep(for: .milliseconds(300))
                precondition(store.requestShowInLayout(apps[79]))
                try await Task.sleep(for: .milliseconds(100))
                store.searchText = "Test 124"
                try await Task.sleep(for: .milliseconds(700))
                precondition(store.openFolder == nil && store.layoutRevealRequest == nil)
                precondition(store.searchQuery == "Test 124")
                print("PASS new input during icon loading cancels guided navigation")
                // A new search and a newer reveal both cancel the pending folder opening.
                precondition(store.requestShowInLayout(apps[79]))
                try await waitFor("Pending folder feedback") { outerFeedback(at: folderIndex) != nil }
                store.searchText = "Test 124"
                try await Task.sleep(for: .milliseconds(1100))
                precondition(store.openFolder == nil && store.layoutRevealRequest == nil)
                precondition(store.searchQuery == "Test 124")
                precondition(store.requestShowInLayout(apps[79]))
                try await waitFor("Pending folder feedback") { outerFeedback(at: folderIndex) != nil }
                precondition(store.requestShowInLayout(apps[124]))
                try await Task.sleep(for: .milliseconds(1100))
                precondition(store.openFolder == nil && outerGrid()?.selectedIndex == nil)
                print("PASS folder reveal pause is cancelled by new search or newer navigation")

                // Send an ordinary click outside the grid through AppKit's event route.
                precondition(store.requestShowInLayout(apps[79]))
                try await waitFor("Pending folder feedback") { outerFeedback(at: folderIndex) != nil }
                let click = NSEvent.mouseEvent(with: .rightMouseDown, location: NSPoint(x: 2, y: 2),
                    modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
                NSApp.sendEvent(click)
                try await Task.sleep(for: .milliseconds(1100))
                precondition(store.openFolder == nil && store.layoutRevealRequest == nil)
                precondition(store.requestShowInLayout(apps[79]))
                try await waitFor("Pending folder feedback") { outerFeedback(at: folderIndex) != nil }
                NotificationCenter.default.post(name: .launchpadWindowHidden, object: nil)
                try await Task.sleep(for: .milliseconds(1100))
                precondition(store.openFolder == nil && store.layoutRevealRequest == nil)
                print("PASS user input and window hiding cancel pending navigation")
                let absent = AppInfo(name: "Gone", icon: NSImage(size: .zero), url: URL(fileURLWithPath: "/Applications/Absent.app"))
                let before = store.items.map(\.id)
                precondition(!store.requestShowInLayout(absent))
                precondition(store.items.map(\.id) == before)
                print("PASS missing targets are ignored; layout order is unchanged")
                window.orderOut(nil)
                exit(0)
            } catch { fatalError("\(error)") }
        }
        NSApplication.shared.run()
    }
}
