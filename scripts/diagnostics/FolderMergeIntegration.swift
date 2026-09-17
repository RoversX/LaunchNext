// Compiled in a temporary copy of the app target, replacing only its @main.
// Uses the real CAGridView, input/landing/layout code, FolderInfo and renderer.
// Model callbacks are in-memory fixtures: no AppStore, user layout or persistence.
import AppKit
import QuartzCore
import ScreenCaptureKit
import AVFoundation

final class MergeRecordingObserver: NSObject, SCRecordingOutputDelegate {
    func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) { print("Recording finished") }
    func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) { print("Recording failed: \(error)") }
}

@main
struct FolderMergeIntegration {
    @MainActor static func main() {
        setbuf(stdout, nil)
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let window = NSWindow(contentRect: CGRect(x: 150, y: 200, width: 780, height: 310),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.title = "LaunchNext · production grid merge check"
        let grid = CAGridView(frame: CGRect(x: 0, y: 0, width: 780, height: 310))
        grid.columns = 3; grid.rows = 1; grid.iconSize = 120
        grid.contentInsets = NSEdgeInsets(top: 40, left: 30, bottom: 30, right: 30)
        let background = CAGradientLayer(); background.frame = grid.bounds
        background.colors = [NSColor.systemIndigo.cgColor, NSColor.systemTeal.cgColor]
        grid.layer!.insertSublayer(background, at: 0)
        window.contentView = grid
        window.makeKeyAndOrderFront(nil)
        let paths = ["/System/Applications/Calculator.app", "/System/Applications/Maps.app",
                     "/System/Applications/Notes.app"]
        let apps = paths.map { AppInfo(name: URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent,
                                      icon: NSWorkspace.shared.icon(forFile: $0), url: URL(fileURLWithPath: $0)) }
        grid.onCreateFolder = { source, target, _ in
            DispatchQueue.main.async {
                // Simulate work before model publication, longer than several frames.
                Thread.sleep(forTimeInterval: 0.12)
                let folder = FolderInfo(name: "Untitled", apps: [source, target])
                grid.items = [.folder(folder), .app(apps[2])]
            }
        }
        grid.onMoveToFolder = { source, folder in
            DispatchQueue.main.async {
                var updated = folder; updated.apps.append(source)
                grid.items = [.folder(updated)]
            }
        }
        Task { @MainActor in
            if CommandLine.arguments.contains("--guardrails-only") {
                checkPreferenceMigration()
                checkDissolveTiles(apps: apps)
                for glass in [false, true] {
                    grid.usesLiquidGlassFolders = glass
                    await checkDissolveHandoff(grid, apps: apps)
                    await checkMergeGuardrails(grid, apps: apps)
                    print("PASS merge guardrails glass=\(glass): zero dimensions and orphan cleanup")
                }
                app.terminate(nil)
                return
            }
            var stream: SCStream?
            let observer = MergeRecordingObserver()
            if CommandLine.arguments.contains("--record") {
                do {
                    let share = try await SCShareableContent.currentProcess
                    let own = share.windows.first { $0.windowID == CGWindowID(window.windowNumber) }!
                    let config = SCStreamConfiguration()
                    config.width = 1560; config.height = 664; config.showsCursor = false
                    config.capturesAudio = false
                    config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
                    let capture = SCStream(filter: SCContentFilter(desktopIndependentWindow: own), configuration: config, delegate: nil)
                    let recording = SCRecordingOutputConfiguration()
                    recording.outputURL = URL(fileURLWithPath: "/tmp/launchnext-merge-integration.mp4")
                    try? FileManager.default.removeItem(at: recording.outputURL)
                    try capture.addRecordingOutput(SCRecordingOutput(configuration: recording, delegate: observer))
                    try await capture.startCapture()
                    stream = capture
                    try? await Task.sleep(for: .milliseconds(200))
                } catch { print("Recording unavailable: \(error)") }
            }
            for glass in [false, true] {
                grid.usesLiquidGlassFolders = glass
                grid.items = apps.map { .app($0) }
                try? await Task.sleep(for: .milliseconds(180))
                let hoverPoint = iconCenter(grid, index: 1)
                grid.startDragging(item: grid.items[0], index: 0, at: hoverPoint)
                let hover = GridDropPreview.merge(targetID: grid.items[1].id)
                grid.showDropPreview(hover)
                try? await Task.sleep(for: .milliseconds(80))
                // Deterministic state check even if this host receives no display-link ticks.
                grid.updateFolderCreationHighlight(at: CACurrentMediaTime())
                let previousHighlight = grid.folderCreationHighlight!
                precondition(previousHighlight.scale > 0.15)
                grid.items = Array(grid.items)
                grid.showDropPreview(hover)
                precondition(grid.folderCreationHighlight != nil, "same preview must survive layer rebuild")
                precondition(grid.folderCreationHighlight?.startedAt == previousHighlight.startedAt,
                             "rebuild must not restart the entrance animation")
                precondition(grid.folderCreationHighlight!.scale >= previousHighlight.scale)
                grid.items = [.app(apps[0]), .app(apps[2]), .app(apps[1])]
                precondition(grid.dropTargetIndex == 2,
                             "restore target by identity, not its previous index")
                precondition(grid.folderCreationHighlight?.container === grid.iconLayers[0][2])
                grid.items = [.app(apps[0]), .app(apps[2])]
                precondition(grid.dragDropPreview == .none && grid.dropTargetIndex == nil
                             && grid.folderCreationHighlight == nil, "removed target cancels its preview")
                grid.cancelDragging()

                let hoverFolder = FolderInfo(apps: [apps[1], apps[2]])
                grid.items = [.app(apps[0]), .folder(hoverFolder)]
                try? await Task.sleep(for: .milliseconds(180))
                grid.startDragging(item: grid.items[0], index: 0, at: iconCenter(grid, index: 1))
                grid.showDropPreview(.merge(targetID: grid.items[1].id))
                grid.items = Array(grid.items)
                let folderIcon = grid.iconLayers[0][1].sublayers!.first { $0.name == "icon" }!
                precondition(folderIcon.transform.m11 == 1.1, "existing-folder feedback must also survive rebuild")
                grid.cancelDragging()
                print("PASS hover rebuild glass=\(glass): same preview, progress, moved/removed target, existing folder")
                if CommandLine.arguments.contains("--hover-rebuild-only") { continue }
                grid.items = apps.map { .app($0) }
                try? await Task.sleep(for: .milliseconds(300))
                let point = iconCenter(grid, index: 1)
                grid.startDragging(item: grid.items[0], index: 0, at: point)
                grid.showDropPreview(.merge(targetID: grid.items[1].id))
                try? await Task.sleep(for: .milliseconds(220))
                release(grid, at: point)
                precondition(grid.folderMergeLanding != nil)
                precondition(grid.folderMergeLanding?.startedAt == nil, "wait for model before consuming animation time")
                // Yield through the deliberately slow model callback and first frame.
                let modelDeadline = CACurrentMediaTime() + 2
                while grid.folderMergeLanding?.startedAt == nil {
                    try? await Task.sleep(for: .milliseconds(5))
                    precondition(grid.folderMergeLanding != nil, "model update must retain merge")
                    precondition(CACurrentMediaTime() < modelDeadline,
                                 "visible-window display link did not start the merge within two seconds")
                }
                precondition(grid.iconLayers[0][1].animation(forKey: "mergeNeighborPosition") != nil,
                             "neighbor compaction during creation must animate")
                let neighborBeforeRefresh = grid.iconLayers[0][1]
                grid.items = Array(grid.items)
                precondition(grid.iconLayers[0][1] === neighborBeforeRefresh)
                precondition(neighborBeforeRefresh.animation(forKey: "mergeNeighborPosition") != nil,
                             "duplicate publication must keep neighbor motion")
                let merge = grid.folderMergeLanding!
                let drag = grid.draggingLayer!
                precondition(merge.icon.contents != nil && drag.opacity == 1)
                precondition(grid.iconLayers[0][0].opacity == 0, "no duplicate final folder preview")
                precondition(merge.icon.animation(forKey: "mergeTransform") != nil)
                precondition(drag.animation(forKey: "mergeTransform") != nil)
                let start = merge.startedAt!
                try? await Task.sleep(for: .milliseconds(80))
                let presentationScale = drag.presentation()?.transform.m11 ?? 0
                precondition(presentationScale > drag.transform.m11 && presentationScale < 1.1,
                             "real production grid must render intermediate scale")
                print("INTERMEDIATE glass=\(glass) elapsed=\(CACurrentMediaTime()-start) scale=\(presentationScale)")
                try? await Task.sleep(for: .milliseconds(350))
                precondition(grid.folderMergeLanding == nil && grid.draggingLayer == nil)
                precondition(grid.iconLayers[0][0].opacity == 1)
                precondition(merge.container.superlayer == nil, "temporary layers must be removed")
                // Existing folder: visible third slot, then overflow beyond nine slots.
                for count in [2, 9] {
                    let members = (0..<count).map { n in
                        AppInfo(name: "Fixture \(n)", icon: apps[1].icon,
                                url: URL(fileURLWithPath: "/tmp/folder-member-\(n).app"))
                    }
                    grid.items = [.folder(FolderInfo(apps: members)), .app(apps[0])]
                    try? await Task.sleep(for: .milliseconds(160))
                    let targetPoint = iconCenter(grid, index: 0)
                    grid.startDragging(item: grid.items[1], index: 1, at: targetPoint)
                    grid.showDropPreview(.merge(targetID: grid.items[0].id))
                    release(grid, at: targetPoint)
                    try? await Task.sleep(for: .milliseconds(60))
                    precondition(grid.folderMergeLanding?.targetPath == nil)
                    precondition((grid.draggingLayer?.animation(forKey: "mergeOpacity") != nil) == (count == 9))
                    if count == 2 {
                        // A second real rebuild must preserve the visual and hidden destination.
                        let visual = grid.folderMergeLanding!.container
                        grid.items = Array(grid.items)
                        precondition(grid.folderMergeLanding?.container === visual)
                        precondition(grid.iconLayers[0][0].opacity == 0)
                    }
                    try? await Task.sleep(for: .milliseconds(350))
                    precondition(grid.folderMergeLanding == nil && grid.iconLayers[0][0].opacity == 1)
                }
                // Rejected callback and explicit cancellation restore both originals.
                let callback = grid.onCreateFolder
                grid.onCreateFolder = { _, _, _ in }
                for cancel in [false, true] {
                    grid.items = apps.map { .app($0) }
                    try? await Task.sleep(for: .milliseconds(100))
                    let target = iconCenter(grid, index: 1)
                    grid.startDragging(item: grid.items[0], index: 0, at: target)
                    grid.showDropPreview(.merge(targetID: grid.items[1].id))
                    release(grid, at: target)
                    if cancel { grid.cancelDragging() }
                    try? await Task.sleep(for: .milliseconds(360))
                    precondition(grid.folderMergeLanding == nil && grid.draggingLayer == nil)
                    precondition(grid.iconLayers[0][0].opacity == 1 && grid.iconLayers[0][1].opacity == 1)
                }
                grid.onCreateFolder = callback
                // Dissolution uses the real notification hook and real grid layers.
                grid.columns = 6; grid.rows = 2; grid.iconSize = 72
                for count in [2, 10] {
                    let members = (0..<count).map { n in
                        n < 2 ? apps[n] : AppInfo(name: "Member \(n)", icon: apps[0].icon,
                                                 url: URL(fileURLWithPath: "/tmp/dissolve-member-\(n).app"))
                    }
                    let folder = FolderInfo(apps: members)
                    grid.items = [.folder(folder), .app(apps[2])]
                    try? await Task.sleep(for: .milliseconds(180))
                    NotificationCenter.default.post(name: .launchpadFolderWillDissolve, object: folder)
                    precondition(grid.folderDissolveTransition != nil)
                    grid.items = members.map { .app($0) } + [.app(apps[2])]
                    let transition = grid.folderDissolveTransition!
                    precondition(transition.startedAt != nil)
                    if glass {
                        let plates = nativeGlass(grid).filter { !$0.isHidden }
                        precondition(plates.count == 1 && abs(plates[0].frame.width - 72 * 0.8) < 0.01,
                                     "first native frame must retain the full-size plate")
                    }
                    let first = grid.iconLayers[0][0]
                    let firstIcon = first.sublayers!.first { $0.name == "icon" }!
                    precondition(firstIcon.animation(forKey: "dissolveScale") != nil)
                    let neighbor = grid.iconLayers[0][count]
                    precondition(neighbor.animation(forKey: "dissolvePosition") != nil)
                    if count == 10 {
                        let overflow = grid.iconLayers[0][9].sublayers!.first { $0.name == "icon" }!
                        precondition(overflow.animation(forKey: "dissolveOpacity") != nil)
                    }
                    grid.items = Array(grid.items)
                    precondition(grid.iconLayers[0][0] === first, "duplicate publication must preserve dissolve layers")
                    try? await Task.sleep(for: .milliseconds(80))
                    let scale = firstIcon.presentation()?.transform.m11 ?? 0
                    precondition(scale > 0.2 && scale < 1, "dissolve must display intermediate growth")
                    print("DISSOLVE glass=\(glass) count=\(count) scale=\(scale)")
                    try? await Task.sleep(for: .milliseconds(250))
                    precondition(grid.folderDissolveTransition == nil && transition.plate.superlayer == nil)
                    precondition(grid.containerLayer.zPosition == 0, "restore grid compositing order")
                }
                // A no-op notification and teardown must not leave a plate or raised grid.
                let rejected = FolderInfo(apps: [apps[0], apps[1]])
                grid.items = [.folder(rejected)]
                try? await Task.sleep(for: .milliseconds(100))
                NotificationCenter.default.post(name: .launchpadFolderWillDissolve, object: rejected)
                grid.updateFolderDissolve(at: CACurrentMediaTime() + 1)
                precondition(grid.folderDissolveTransition == nil)
                NotificationCenter.default.post(name: .launchpadFolderWillDissolve, object: rejected)
                grid.items = [.app(apps[0]), .app(apps[1])]
                grid.launchpadWindowDidHide(Notification(name: .launchpadWindowHidden))
                precondition(grid.folderDissolveTransition == nil && grid.containerLayer.zPosition == 0)
                grid.animationsEnabled = false
                grid.items = [.folder(rejected)]
                NotificationCenter.default.post(name: .launchpadFolderWillDissolve, object: rejected)
                precondition(grid.folderDissolveTransition == nil, "respect disabled animations")
                grid.animationsEnabled = true
                grid.columns = 3; grid.rows = 1; grid.iconSize = 120
                print("PASS dissolve glass=\(glass): visible growth, neighbors, overflow, duplicate publication, no-op, teardown, animation setting")
                print("PASS glass=\(glass): production input, delayed model, intermediate presentation, creation, existing/overflow folder, rebuild, rejection, cancellation, cleanup")
            }
            if let stream {
                try? await stream.stopCapture()
                try? await Task.sleep(for: .milliseconds(500))
                print("/tmp/launchnext-merge-integration.mp4")
            }
            withExtendedLifetime(observer) {}
            app.terminate(nil)
        }
        app.run()
    }

    @MainActor static func nativeGlass(_ view: NSView) -> [NSGlassEffectView] {
        (view as? NSGlassEffectView).map { [$0] } ?? view.subviews.flatMap { nativeGlass($0) }
    }

    @MainActor static func checkPreferenceMigration() {
        let suite = "LaunchNext.GuardrailProbe.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        precondition(AppStore.loadFolderLiquidGlassEnabled(from: defaults))
        precondition(defaults.persistentDomain(forName: suite)?.isEmpty != false,
                     "reading defaults must not perform migration")
        defaults.set(false, forKey: AppStore.folderLiquidGlassKey)
        precondition(!AppStore.loadFolderLiquidGlassEnabled(from: defaults))
        precondition(!defaults.bool(forKey: "folderLiquidGlassDefaultEnabledV1"))
        AppStore.migrateFolderLiquidGlassDefaultIfNeeded(from: defaults)
        precondition(AppStore.loadFolderLiquidGlassEnabled(from: defaults), "preserve the one-time opt-in policy")
        defaults.set(false, forKey: AppStore.folderLiquidGlassKey)
        AppStore.migrateFolderLiquidGlassDefaultIfNeeded(from: defaults)
        precondition(!AppStore.loadFolderLiquidGlassEnabled(from: defaults), "preserve subsequent opt-outs")
        print("PASS preferences: read-only load, explicit migration, subsequent opt-out")
    }

    @MainActor static func checkDissolveTiles(apps: [AppInfo]) {
        let context = CGContext(data: nil, width: 144, height: 144, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        for slot in 0..<9 {
            let rect = FolderPreviewLayout.iconRect(at: slot, side: 72)!
            context.setFillColor(CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                                         components: [CGFloat(slot + 1) / 10, 0, 0, 1])!)
            context.fill(CGRect(x: rect.minX * 2, y: rect.minY * 2, width: rect.width * 2, height: rect.height * 2))
        }
        let transition = FolderDissolveTransition(folder: FolderInfo(apps: apps),
            iconRect: CGRect(x: 0, y: 0, width: 86.4, height: 86.4), oldPositions: [:],
            previewImage: context.makeImage(), previewSide: 72)
        let start = CACurrentMediaTime()
        let tiles = (0..<9).map { transition.previewTile(at: $0)! }
        let elapsed = (CACurrentMediaTime() - start) * 1000
        for (slot, tile) in tiles.enumerated() {
            let bitmap = NSBitmapImageRep(cgImage: tile)
            // Compare encoded fixture channels, not a second display-profile conversion.
            let red = bitmap.colorAt(x: tile.width / 2, y: tile.height / 2)!.redComponent
            let expected = CGFloat(slot + 1) / 10
            precondition(abs(red - expected) < 0.01, "crop must preserve row order and logical preview scale")
        }
        precondition(transition.previewTile(at: 9) == nil)
        print("PASS dissolve: nine existing-bitmap tiles, correct rows at scaled display size; crop ms=\(elapsed)")
    }

    @MainActor static func checkMergeGuardrails(_ grid: CAGridView, apps: [AppInfo]) async {
        for fault in ["preview", "glass", "icon", "orphan"] {
            grid.items = apps.map { .app($0) }
            try? await Task.sleep(for: .milliseconds(180))
            let sourceID = grid.items[0].id, targetID = grid.items[1].id
            grid.startDragging(item: grid.items[0], index: 0, at: iconCenter(grid, index: 1))
            grid.showDropPreview(.merge(targetID: targetID))
            precondition(grid.beginFolderMergeLanding(itemID: sourceID, targetID: targetID))
            let merge = grid.folderMergeLanding!
            if fault == "orphan" {
                // Deliberately inject a split state; this is not a normal user path.
                grid.dragLanding = nil
            } else {
                grid.items = [.folder(FolderInfo(apps: [apps[1], apps[0]])), .app(apps[2])]
                switch fault {
                case "preview": grid.draggingLayer!.bounds.size.width = 0
                case "glass": merge.glass.bounds.size.width = 0
                default: merge.icon.bounds.size.width = 0
                }
            }
            grid.updateDragLanding(at: CACurrentMediaTime())
            precondition(grid.dragLanding == nil && grid.folderMergeLanding == nil && grid.draggingLayer == nil)
            precondition(merge.container.superlayer == nil)
            precondition(grid.iconLayers.flatMap { $0 }.allSatisfy { $0.opacity == 1 }, "restore all affected cells")
            grid.cancelDragging()
        }
    }

    @MainActor static func checkDissolveHandoff(_ grid: CAGridView, apps: [AppInfo]) async {
        let folder = FolderInfo(apps: apps)
        grid.items = [.folder(folder)]
        try? await Task.sleep(for: .milliseconds(250))
        grid.clearIconCache()
        grid.beginFolderDissolve(folder)
        weak var transition = grid.folderDissolveTransition
        precondition(transition?.previewImage != nil)
        grid.items = apps.map { .app($0) }
        let icon = grid.iconLayers[0][0].sublayers!.first { $0.name == "icon" }!
        precondition(icon.contents != nil, "cold grid must immediately show its existing preview tile")
        let deadline = CACurrentMediaTime() + 3
        while grid.getCachedIcon(for: apps[0].url.path) == nil && CACurrentMediaTime() < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        try? await Task.sleep(for: .milliseconds(50))
        let loaded = grid.getCachedIcon(for: apps[0].url.path)!
        precondition(icon.contents as AnyObject? === loaded, "normal async loading must replace the temporary tile")
        grid.finishFolderDissolve()
        precondition(transition == nil, "cleanup must release the temporary state and borrowed preview")
        print("PASS dissolve handoff: cold grid has pixels, async replacement, state released")
    }
    @MainActor static func iconCenter(_ grid: CAGridView, index: Int) -> CGPoint {
        let icon = grid.iconLayers[index / grid.itemsPerPage][index % grid.itemsPerPage]
            .sublayers!.first { $0.name == "icon" }!
        let rect = icon.convert(icon.bounds, to: grid.layer!)
        return CGPoint(x: rect.midX, y: rect.midY)
    }
    @MainActor static func release(_ grid: CAGridView, at point: CGPoint) {
        let event = NSEvent.mouseEvent(with: .leftMouseUp, location: grid.convert(point, to: nil),
                                      modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                      windowNumber: grid.window!.windowNumber, context: nil,
                                      eventNumber: 0, clickCount: 1, pressure: 0)!
        grid.mouseUp(with: event)
    }
}
