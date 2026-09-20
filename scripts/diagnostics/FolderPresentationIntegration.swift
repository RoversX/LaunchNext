// Runs real production views in a temporary app target with an isolated AppStore initializer.
// No user layout is loaded and no screen capture permission is requested.

import AppKit
import QuartzCore
import SwiftUI

@main struct FolderPresentationIntegration {
    @MainActor static func main() {
        setbuf(stdout, nil)
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let window = NSWindow(
            contentRect: CGRect(x: 160, y: 180, width: 960, height: 720), styleMask: [.titled, .resizable],
            backing: .buffered, defer: false)
        window.title = "LaunchNext · CA folder opening verification"
        let root = NSView(frame: CGRect(x: 0, y: 0, width: 960, height: 720))
        root.wantsLayer = true
        let gradient = CAGradientLayer()
        gradient.frame = root.bounds
        gradient.colors = [NSColor.systemIndigo.cgColor, NSColor.systemTeal.cgColor]
        root.layer!.addSublayer(gradient)
        window.contentView = root
        let grid = CAGridView(frame: root.bounds)
        grid.columns = 5
        grid.rows = 3
        grid.iconSize = 90
        grid.contentInsets = NSEdgeInsets(top: 70, left: 50, bottom: 40, right: 50)
        let backdrop = CAFolderBackdropView(grid: grid)
        root.addSubview(backdrop)
        let controller = CAFolderPresentationController()
        controller.grid = grid
        controller.backdrop = backdrop
        let host = CAFolderPresentationHost(frame: root.bounds)
        host.controller = controller
        controller.host = host
        root.addSubview(host)
        let store = AppStore()
        store.useCAGridRenderer = true
        store.enableAnimations = true
        store.animationDuration = 0.3
        let paths = [
            "Calculator", "Maps", "Notes", "Calendar", "Contacts", "Reminders", "Preview", "Shortcuts", "Music",
            "Safari", "Photos", "FaceTime",
        ]
        let apps = paths.map { name in
            let url = URL(fileURLWithPath: "/System/Applications/\(name).app")
            return AppInfo(name: name, icon: NSWorkspace.shared.icon(forFile: url.path), url: url)
        }
        let folder = FolderInfo(name: "Opening", apps: apps)
        store.folders = [folder]
        _ = folder.icon(of: 90, scale: 2)
        grid.items =
            Array(repeating: LaunchpadItem.app(apps[0]), count: 7) + [.folder(folder)]
            + Array(repeating: LaunchpadItem.app(apps[1]), count: 7)
        window.makeKeyAndOrderFront(nil)
        func update() {
            host.update(appStore: store, iconSize: 72, onClose: { store.openFolder = nil }, onLaunchApp: { _ in })
            root.layoutSubtreeIfNeeded()
        }
        Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(200))
                let pivot = backdrop.convert(CGPoint(x: 140, y: 580), to: nil)
                backdrop.setFolderDepth(true, duration: 0, pivotInWindow: pivot)
                let rootLayer = backdrop.layer!
                let marker = CALayer()
                marker.frame = CGRect(x: 140, y: 580, width: 1, height: 1)
                rootLayer.addSublayer(marker)
                let mapped = marker.convert(CGPoint.zero, to: rootLayer)
                precondition(abs(mapped.x - 140) < 0.01 && abs(mapped.y - 580) < 0.01,
                             "the selected folder pivot must remain fixed")
                marker.removeFromSuperlayer()
                backdrop.setFolderDepth(false, duration: 0)
                print("PASS selected-folder depth pivot")
                for glass in [false, true] {
                    grid.usesLiquidGlassFolders = glass
                    for fullscreen in [false, true] {
                        store.isFullscreenMode = fullscreen
                        store.openFolder = folder
                        update()
                        // Start timing at the transition, independently of cold image preparation.
                        for _ in 0..<50 where host.probePhase == "preparing" {
                            try await Task.sleep(for: .milliseconds(10))
                        }
                        precondition(host.probePhase == "opening", "prepared folder must start its animation")
                        precondition(abs(host.probeDuration - 0.24) < 0.001)
                        precondition(host.probeGrid!.isPresentationLayoutReady)
                        for _ in 0..<3 {
                            try await Task.sleep(for: .milliseconds(30))
                            print("SAMPLE", host.probePhase, host.probePlate as Any)
                            if host.probePhase == "opening", host.probeIcons.first?.presentation() != nil {
                                checkSynchronizedProgress(host)
                                precondition(host.probeGrid!.probeOpeningEndpointDrift < 0.01,
                                             "opening proxies must land on the final grid after page-indicator layout")
                            }
                        }
                        print("INTERMEDIATE", glass, fullscreen, host.probePhase, host.probePlate as Any)
                        precondition(
                            host.probePlate!.width > 90 && host.probePlate!.width < host.probePanel.width,
                            "glass must interpolate before completion")
                        precondition(host.probePhase == "opening", "expected real layout to start opening")
                        precondition(grid.presentedFolderID == folder.id)
                        let depth = (backdrop.layer!.presentation() ?? backdrop.layer!).sublayerTransform.m11
                        precondition(depth < 1 && depth >= 0.97, "background must recede with opening")
                        let icons = host.probeIcons
                        precondition(icons.count > 9 && icons.allSatisfy { $0.contents != nil },
                                     "visible icons must be prepared and outside the clipped panel")
                        let extra = icons[9]
                        let initial = (extra.animation(forKey: "folderPresentation.position") as! CAKeyframeAnimation).values!.first as! NSValue
                        precondition(hypot(initial.pointValue.x - extra.position.x, initial.pointValue.y - extra.position.y) > 30,
                                     "icons outside the thumbnail must travel out of the folder")
                        precondition(host.probeChromeOpacity < 0.01,
                                     "labels must not appear ahead of moving icons")
                        checkPlateCoverage(host)
                        let mask = host.probeMask!
                        let maskBounds = mask.boundingBoxOfPath
                        precondition(!mask.contains(CGPoint(x: maskBounds.minX + 0.5, y: maskBounds.minY + 0.5)),
                                     "the growing backplate must keep a rounded silhouette")
                        try await Task.sleep(for: .milliseconds(350))
                        precondition(host.probePhase == "open" && host.probeGrid != nil)
                        precondition(backdrop.contentFilters.isEmpty && backdrop.layer!.filters?.isEmpty != false,
                                     "folder presentation must not install a background blur")
                        precondition(host.probePlate!.equalTo(host.probePanel))
                        precondition(host.probeIcons.isEmpty && host.probeMask == nil,
                                     "temporary layers and mask must be removed after opening")
                        host.probeGrid!.probeCheckPendingIconLabel()
                        weak var releasedGrid = host.probeGrid
                        store.openFolder = nil
                        update()
                        try await Task.sleep(for: .milliseconds(90))
                        precondition(host.probePhase == "closing")
                        checkSynchronizedProgress(host)
                        checkPlateCoverage(host)
                        try await Task.sleep(for: .milliseconds(350))
                        precondition(
                            host.probePhase == "closed" && grid.presentedFolderID == nil && host.probeGrid == nil)
                        // AppKit/SwiftUI may retire their view graph on a later run-loop turn.
                        for _ in 0..<30 where releasedGrid != nil {
                            try await Task.sleep(for: .milliseconds(10))
                        }
                        precondition(releasedGrid == nil, "folder grid retained after closing")
                        precondition(CATransform3DIsIdentity(backdrop.layer!.sublayerTransform), "closing must restore background geometry")
                        precondition(backdrop.contentFilters.isEmpty && backdrop.layer!.animation(forKey: "folderPresentation.blur") == nil,
                                     "closing must remove the filter and its animation")
                        print("PASS open/close, final geometry and release", glass, fullscreen)
                    }
                }
                for mode: AppStore.FolderLayoutMode in [.paged, .vertical] {
                    store.folderLayoutMode = mode
                    let manyApps = (0..<60).map { i in
                        AppInfo(
                            name: "App \(i)", icon: apps[i % apps.count].icon,
                            url: URL(fileURLWithPath: "/tmp/opening-fixture-app-\(i).app"))
                    }
                    let largeFolder = FolderInfo(name: "Large", apps: manyApps)
                    store.folders = [largeFolder]
                    grid.items = [.folder(largeFolder)]
                    store.openFolder = largeFolder
                    update()
                    var checkedOpening = false
                    for _ in 0..<40 {
                        try await Task.sleep(for: .milliseconds(10))
                        if host.probePhase == "opening" {
                            checkedOpening = true
                            precondition(!host.probeIcons.isEmpty)
                            precondition(host.probeGrid!.probeOpeningEndpointDrift < 0.01,
                                         "multi-page layout must not shift after capturing animation endpoints")
                        }
                    }
                    precondition(checkedOpening, "the large-folder check must sample a real opening transition")
                    precondition(host.probePhase == "open" && host.probeClipped)
                    if mode == .paged {
                        precondition(host.probeGrid!.displayedPageCount > 1)
                        host.probeGrid!.setDisplayedPage(1, animated: false)
                    }
                    store.openFolder = nil
                    update()
                    try await Task.sleep(for: .milliseconds(400))
                    precondition(host.probePhase == "closed" && grid.presentedFolderID == nil)
                    print("PASS larger folder and off-page cleanup", mode)
                }
                store.folderLayoutMode = .paged
                store.folders = [folder]
                grid.items = [.folder(folder)]
                store.openFolder = folder
                update()
                try await Task.sleep(for: .milliseconds(100))
                store.openFolder = nil
                update()
                try await Task.sleep(for: .milliseconds(60))
                store.openFolder = folder
                update()
                try await Task.sleep(for: .milliseconds(450))
                precondition(host.probePhase == "open")
                store.openFolder = nil
                update()
                try await Task.sleep(for: .milliseconds(400))
                precondition(host.probePhase == "closed" && grid.presentedFolderID == nil)
                print("PASS rapid reversal and cleanup")
                // Exercise actual mouse dispatch, not just model-driven reversal.
                var openedByClick = 0
                grid.onItemClicked = { item, _ in
                    if case let .folder(value) = item {
                        openedByClick += 1
                        store.openFolder = value
                    }
                }
                store.animationDuration = 1.5 // Folder motion must not inherit paging speed.
                store.openFolder = folder
                update()
                try await Task.sleep(for: .milliseconds(350))
                precondition(abs(host.probeDuration - 0.24) < 0.001)
                let target = grid.folderOpeningSource(id: folder.id, atRest: true)!.plateRectInWindow
                let targetPoint = CGPoint(x: target.midX, y: target.midY)
                store.openFolder = nil
                update()
                precondition(abs(host.probeDuration - 0.28) < 0.001)
                try await Task.sleep(for: .milliseconds(30))
                weak var existingGrid = host.probeGrid
                let previousIcon = host.probeIcons.first!
                let previousPosition = (previousIcon.presentation() ?? previousIcon).position
                sendClick(window, at: targetPoint)
                precondition(store.openFolder?.id == folder.id && host.probeGrid === existingGrid,
                             "reopening must retain the same content without completing dismissal")
                precondition(openedByClick == 0, "same-folder reversal must not dispatch a fresh grid open")
                precondition(host.probeInitialVelocity < 0, "reopening must inherit closing velocity")
                let retargeted = host.probeIcons.first!.animation(forKey: "folderPresentation.position") as! CAKeyframeAnimation
                let firstPosition = (retargeted.values!.first as! NSValue).pointValue
                precondition(hypot(firstPosition.x - previousPosition.x, firstPosition.y - previousPosition.y) < 0.1,
                             "reversal must start at the currently displayed icon position")
                let glassAnimation = host.probeGlassAnimation!
                precondition(retargeted.keyTimes == glassAnimation.keyTimes && retargeted.beginTime == glassAnimation.beginTime,
                             "icons and material must share the trajectory and clock")
                update()
                try await Task.sleep(for: .milliseconds(350))
                precondition(host.probePhase == "open")
                store.openFolder = nil
                update()
                try await Task.sleep(for: .milliseconds(350))
                sendClick(window, at: targetPoint, clickCount: 2)
                precondition(openedByClick == 1, "rapid reopening must accept AppKit double-click classification")
                update()
                for _ in 0..<50 where host.probePhase == "preparing" {
                    try await Task.sleep(for: .milliseconds(10))
                }
                try await Task.sleep(for: .milliseconds(40))
                sendClick(window, at: CGPoint(x: 40, y: 360))
                precondition(store.openFolder == nil, "outside click must interrupt opening")
                update()
                precondition(host.probeDuration < 0.28, "reversal should use remaining travel")
                try await Task.sleep(for: .milliseconds(350))
                precondition(host.probePhase == "closed")
                print("PASS mouse interruption, retained-view reversal, velocity continuity, double click and independent timing")
                let otherFolder = FolderInfo(name: "Other", apps: Array(apps.prefix(3)))
                _ = otherFolder.icon(of: 90, scale: 2)
                store.folders = [folder, otherFolder]
                grid.items = [.folder(folder), .folder(otherFolder)]
                store.openFolder = folder
                update()
                try await Task.sleep(for: .milliseconds(350))
                store.openFolder = nil
                update()
                try await Task.sleep(for: .milliseconds(30))
                let otherTarget = grid.folderOpeningSource(id: otherFolder.id, atRest: true)!.plateRectInWindow
                sendClick(window, at: CGPoint(x: otherTarget.midX, y: otherTarget.midY))
                precondition(store.openFolder?.id == otherFolder.id, "a different folder must still receive the first click")
                update()
                try await Task.sleep(for: .milliseconds(350))
                precondition(host.probePhase == "open")
                store.openFolder = nil
                update()
                try await Task.sleep(for: .milliseconds(350))
                store.folders = [folder]
                grid.items = [.folder(folder)]
                print("PASS different-folder click during closing")
                grid.onItemClicked = nil
                store.enableAnimations = false
                store.openFolder = folder
                update()
                try await Task.sleep(for: .milliseconds(100))
                precondition(host.probePhase == "open")
                store.openFolder = nil
                update()
                precondition(host.probePhase == "closed")
                print("PASS disabled animations")
                store.enableAnimations = true
                store.openFolder = folder
                update()
                try await Task.sleep(for: .milliseconds(80))
                host.dismissImmediately()
                precondition(host.probePhase == "closed" && grid.presentedFolderID == nil)
                precondition(backdrop.contentFilters.isEmpty)
                print("PASS immediate teardown")
                store.openFolder = nil
                update()
                store.openFolder = folder
                update()
                try await Task.sleep(for: .milliseconds(400))
                store.handoffDraggingApp = apps[0]
                store.openFolder = nil
                update()
                precondition(host.probePhase == "closed", "drag handoff must not wait for closing")
                store.handoffDraggingApp = nil
                print("PASS drag handoff")
                store.openFolder = folder
                update()
                try await Task.sleep(for: .milliseconds(80))
                host.frame.size = CGSize(width: 800, height: 600)
                host.layoutSubtreeIfNeeded()
                precondition(host.probePhase == "open", "resize completes the opening")
                store.openFolder = nil
                update()
                try await Task.sleep(for: .milliseconds(400))
                precondition(host.probePhase == "closed")
                print("PASS resize during opening")
                host.dismissImmediately()
                grid.removeFromSuperview()
                store.openFolder = nil
                let swiftUIRoot = NSHostingView(rootView: PresentationProbeRoot(store: store, controller: controller, grid: grid))
                swiftUIRoot.frame = root.bounds
                window.contentView = swiftUIRoot
                try await Task.sleep(for: .milliseconds(200))
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { store.openFolder = folder }
                try await Task.sleep(for: .milliseconds(150))
                let hosted = controller.host!
                checkSynchronizedProgress(hosted)
                checkPlateCoverage(hosted)
                print("PASS SwiftUI opening synchronization")
                try await Task.sleep(for: .milliseconds(350))
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { store.openFolder = nil }
                try await Task.sleep(for: .milliseconds(100))
                checkSynchronizedProgress(hosted)
                checkPlateCoverage(hosted)
                print("PASS SwiftUI closing synchronization")
                let reopeningTarget = grid.folderOpeningSource(id: folder.id, atRest: true)!.plateRectInWindow
                grid.onItemClicked = { item, _ in
                    if case let .folder(value) = item { store.openFolder = value }
                }
                sendClick(window, at: CGPoint(x: reopeningTarget.midX, y: reopeningTarget.midY))
                precondition(store.openFolder != nil, "SwiftUI overlays must not consume the reopening click")
                try await Task.sleep(for: .milliseconds(350))
                precondition(hosted.probePhase == "open")
                store.openFolder = nil
                try await Task.sleep(for: .milliseconds(300))
                precondition(hosted.probePhase == "closed")
                print("PASS SwiftUI first-click reopening")
            } catch {
                print("FAILED", error)
                exit(1)
            }
            app.terminate(nil)
        }
        app.run()
    }

    @MainActor static func sendClick(_ window: NSWindow, at point: CGPoint, clickCount: Int = 1) {
        for type: NSEvent.EventType in [.leftMouseDown, .leftMouseUp] {
            let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, eventNumber: 0, clickCount: clickCount, pressure: 1)!
            window.sendEvent(event)
        }
    }

    @MainActor static func checkPlateCoverage(_ host: CAFolderPresentationHost) {
        let coverage = host.probePlateCoverage
        print("COVERAGE", coverage)
        precondition(coverage > 0.8, "the clipping mask must preserve the shrinking material plate")
    }

    @MainActor static func checkSynchronizedProgress(_ host: CAFolderPresentationHost) {
        let icons = iconProgress(host)
        let glass = host.probeGlassProgress
        print("TIMING glass/icon", glass, icons)
        precondition(abs(glass - icons) < 0.02, "icons and glass must advance together in the same frame")
        let plate = host.probePlate!.insetBy(dx: -2, dy: -2)
        for (index, icon) in host.probeIcons.enumerated() {
            let visual = icon.presentation() ?? icon
            precondition(plate.contains(visual.frame),
                "icon \(index) escapes plate: \(visual.frame), plate: \(plate)")
        }
    }

    @MainActor static func iconProgress(_ host: CAFolderPresentationHost) -> CGFloat {
        guard let icon = host.probeIcons.first,
              let animation = icon.animation(forKey: "folderPresentation.position") as? CAKeyframeAnimation,
              let from = (animation.values?.first as? NSValue)?.pointValue,
              let to = (animation.values?.last as? NSValue)?.pointValue else { return -1 }
        let current = (icon.presentation() ?? icon).position
        let dx = to.x - from.x, dy = to.y - from.y
        return ((current.x - from.x) * dx + (current.y - from.y) * dy) / max(1, dx * dx + dy * dy)
    }
}

private struct PresentationProbeRoot: View {
    @ObservedObject var store: AppStore
    let controller: CAFolderPresentationController
    let grid: CAGridView
    var body: some View {
        ZStack {
            LinearGradient(colors: [.indigo, .teal], startPoint: .top, endPoint: .bottom)
            PresentationProbeGrid(grid: grid, controller: controller)
                .opacity(store.openFolder == nil ? 1 : 0.1)
                .allowsHitTesting(store.openFolder == nil)
            if store.openFolder != nil { Color.black.opacity(0.1).transition(.opacity).allowsHitTesting(false) }
            CAFolderPresentation(appStore: store, controller: controller, iconSize: 72,
                                 onClose: { store.openFolder = nil }, onLaunchApp: { _ in })
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct PresentationProbeGrid: NSViewRepresentable {
    let grid: CAGridView
    let controller: CAFolderPresentationController
    func makeNSView(context: Context) -> CAFolderBackdropView {
        let backdrop = CAFolderBackdropView(grid: grid)
        controller.backdrop = backdrop
        return backdrop
    }
    func updateNSView(_ view: CAFolderBackdropView, context: Context) {}
}
