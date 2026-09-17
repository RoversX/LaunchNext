// Compile with LaunchNext/FolderGlassOverlay.swift; see scripts/diagnostics/README.md.
import AppKit
import QuartzCore
import Darwin
import ScreenCaptureKit
import ImageIO
import UniformTypeIdentifiers

@MainActor
final class GlassProbe: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    let canvas = NSView(frame: NSRect(x: 0, y: 0, width: 980, height: 680))
    let page = CALayer()
    var folders: [CALayer] = []
    var overlay: FolderGlassOverlay?
    var timer: Timer?
    var start: CFTimeInterval = 0
    var cpuStart: Double = 0
    var previous: CFTimeInterval = 0
    var intervals: [Double] = []
    var peakViews = 0
    var peakFootprint = 0.0
    let args = CommandLine.arguments
    var glass: Bool { args.contains("--glass") }
    var count: Int { args.contains("--sparse") ? 6 : 35 }
    var pageCount: Int { args.contains("--start-late") ? 6 : 2 }
    var pageStride: Int { args.contains("--start-late") ? 1060 : 980 }
    var output: String { args.contains("--glass") ? "glass" : "classic" }

    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(contentRect: canvas.bounds, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "LaunchNext folder glass probe · \(output) · \(count) folders"
        window.isReleasedWhenClosed = false
        window.contentView = canvas
        canvas.wantsLayer = true
        let background = CAGradientLayer()
        background.frame = canvas.bounds
        background.colors = [NSColor.systemIndigo.cgColor, NSColor.systemTeal.cgColor, NSColor.systemOrange.cgColor]
        background.startPoint = CGPoint(x: 0, y: 1)
        background.endPoint = CGPoint(x: 1, y: 0)
        canvas.layer!.addSublayer(background)
        page.frame = CGRect(x: 0, y: 0, width: pageCount * pageStride - (pageStride - 980), height: 680)
        canvas.layer!.addSublayer(page)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let image = previewImage()
        for p in 0..<pageCount {
            for i in 0..<count {
                let container = CALayer()
                container.frame = CGRect(x: p * pageStride + 50 + (i % 7) * 132, y: 535 - (i / 7) * 116, width: 96, height: 96)
                let back = CALayer()
                back.name = "glass"
                back.frame = CGRect(x: 8, y: 8, width: 80, height: 80)
                back.cornerRadius = 20
                back.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
                back.borderColor = NSColor.white.withAlphaComponent(0.2).cgColor
                back.borderWidth = 0.5
                back.shadowOpacity = 0.15
                back.shadowRadius = 3
                back.shadowOffset = CGSize(width: 0, height: -1)
                container.addSublayer(back)
                let icon = CALayer()
                icon.name = "icon"
                icon.frame = container.bounds
                icon.contents = image
                container.addSublayer(icon)
                page.addSublayer(container)
                folders.append(container)
            }
        }
        CATransaction.commit()
        window.center()
        if args.contains("--check") {
            runChecks()
            return
        }
        window.makeKeyAndOrderFront(nil)
        if args.contains("--start-late") {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            page.transform = CATransform3DMakeTranslation(-CGFloat(3 * pageStride), 0, 0)
            CATransaction.commit()
        }
        let delayedImage = args.contains("--late-preview") ? folders[0].sublayers![1].contents : nil
        if args.contains("--late-preview") { folders[0].sublayers![1].contents = nil }
        if glass { enableGlass() }
        print("PROBE window=\(window.windowNumber) pid=\(getpid()) mode=\(output)")
        fflush(stdout)
        if args.contains("--screenshot") {
            Task {
                do {
                    try await Task.sleep(for: .seconds(1))
                    if args.contains("--late-preview") {
                        let icon = folders[0].sublayers![1]
                        icon.contents = delayedImage
                        overlay?.updatePreviewContents(for: icon)
                        // No geometry sync or animation after the late image arrives.
                        try await Task.sleep(for: .milliseconds(100))
                    }
                    if args.contains("--toggle") {
                        for _ in 0..<3 {
                            overlay?.reset()
                            overlay?.removeFromSuperview()
                            overlay = nil
                            try await Task.sleep(for: .milliseconds(50))
                            enableGlass()
                            try await Task.sleep(for: .milliseconds(100))
                        }
                    }
                    if args.contains("--shift") {
                        CATransaction.begin()
                        CATransaction.setDisableActions(true)
                        page.transform = CATransform3DMakeTranslation(-490, 0, 0)
                        sync(geometryChanged: false)
                        CATransaction.commit()
                        try await Task.sleep(for: .seconds(1))
                    }
                    if args.contains("--drag") || args.contains("--drop") || args.contains("--drag-start") {
                        CATransaction.begin()
                        CATransaction.setDisableActions(!args.contains("--legacy-start"))
                        let dragged = CALayer()
                        dragged.bounds = folders[0].bounds
                        dragged.position = (args.contains("--drop") || args.contains("--drag-start"))
                            ? CGPoint(x: folders[0].position.x + 18, y: folders[0].position.y - 12)
                            : CGPoint(x: 490, y: 345)
                        dragged.transform = CATransform3DMakeScale(1.2, 1.2, 1)
                        dragged.zPosition = 1000
                        for original in folders[0].sublayers! {
                            let copy = CALayer()
                            copy.name = original.name
                            copy.frame = original.frame
                            copy.contents = original.contents
                            copy.cornerRadius = original.cornerRadius
                            copy.backgroundColor = original.backgroundColor
                            dragged.addSublayer(copy)
                        }
                        if !args.contains("--legacy-start") { folders[0].removeAnimation(forKey: "opacity") }
                        folders[0].opacity = 0
                        canvas.layer!.addSublayer(dragged)
                        folders.append(dragged)
                        sync()
                        CATransaction.commit()
                        try await Task.sleep(for: .milliseconds(args.contains("--drag-start") ? 20 : 1000))
                        if args.contains("--drag-start") {
                            let opacity = folders[0].presentation()?.opacity ?? folders[0].opacity
                            print("DRAG START source model opacity=\(folders[0].opacity) presented opacity=\(opacity) animation=\(folders[0].animation(forKey: "opacity") != nil)")
                            if !args.contains("--legacy-start") {
                                precondition(opacity == 0 && folders[0].animation(forKey: "opacity") == nil,
                                             "source must disappear immediately when drag glass appears")
                            }
                        }
                        if args.contains("--drop") {
                            CATransaction.begin()
                            CATransaction.setDisableActions(true)
                            overlay?.removeDraggingGlass(for: dragged)
                            dragged.removeFromSuperlayer()
                            folders.removeLast()
                            folders[0].opacity = 1
                            sync()
                            CATransaction.commit()
                            try await Task.sleep(for: .milliseconds(20))
                        }
                    }
                    if let overlay {
                        let actual = nativeViews(overlay).filter { !$0.isHidden }.map { nativeRect($0) }
                        let expected = folders.filter { $0.opacity > 0 }.map {
                            let back = $0.sublayers![0]
                            return back.convert(back.bounds, to: canvas.layer!)
                        }
                        let mismatches = actual.filter { rect in
                            !expected.contains { abs($0.minX - rect.minX) < 0.1 && abs($0.minY - rect.minY) < 0.1 }
                        }.count
                        print("POST-LAYOUT geometry mismatches=\(mismatches) / \(actual.count)")
                        precondition(mismatches == 0, "native layout changed the requested page offset")
                    }
                    // Only this probe's synthetic window; no desktop enumeration.
                    let content = try await SCShareableContent.currentProcess
                    guard let own = content.windows.first(where: { $0.windowID == CGWindowID(window.windowNumber) }) else {
                        throw NSError(domain: "ProbeWindowUnavailable", code: 1)
                    }
                    let filter = SCContentFilter(desktopIndependentWindow: own)
                    let configuration = SCStreamConfiguration()
                    configuration.width = Int(own.frame.width * 2)
                    configuration.height = Int(own.frame.height * 2)
                    configuration.showsCursor = false
                    let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
                    let url = URL(fileURLWithPath: "/tmp/launchnext-folder-\(output)\(args.contains("--start-late") ? "-late" : "")\(args.contains("--shift") ? "-shift" : "")\(args.contains("--drag") ? "-drag" : "")\(args.contains("--drop") ? "-drop" : "")\(args.contains("--drag-start") ? "-start" : "")\(args.contains("--legacy-start") ? "-before" : "")\(args.contains("--late-preview") ? "-late-preview" : "").png")
                    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
                    CGImageDestinationAddImage(destination, image, nil)
                    precondition(CGImageDestinationFinalize(destination))
                    print("SCREENSHOT \(url.path)")
                } catch {
                    print("SCREENSHOT FAILED \(error)")
                    fflush(stdout)
                    exit(1)
                }
                fflush(stdout)
                NSApp.terminate(nil)
            }
            return
        }
        if args.contains("--still") { return }
        // Same workload and timer in both modes. This measures process CPU and
        // callback scheduling, NOT compositor/GPU frame delivery.
        start = CACurrentMediaTime()
        cpuStart = cpuSeconds()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 120, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    func enableGlass() {
        let view = FolderGlassOverlay(frame: canvas.bounds)
        canvas.addSubview(view)
        overlay = view
        sync()
    }

    func sync(geometryChanged: Bool = true) {
        overlay?.sync(containers: folders, root: canvas.layer!, page: page, viewport: canvas.bounds, geometryChanged: geometryChanged)
        peakViews = max(peakViews, overlay?.activeGlassCount ?? 0)
    }

    func tick() {
        let now = CACurrentMediaTime()
        let elapsed = now - start
        // A locked/hidden window changes compositor work and invalidates this
        // comparison. Allow the initial window-ordering transaction to settle.
        if elapsed > 1, !window.occlusionState.contains(.visible) {
            print("INVALID: probe window is not visible; unlock the display and rerun")
            fflush(stdout)
            exit(2)
        }
        if previous > 0 { intervals.append((now - previous) * 1000) }
        previous = now
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        page.transform = CATransform3DMakeTranslation(-490 * (1 - cos(elapsed * .pi)), 0, 0)
        if args.contains("--split-scroll-commit") {
            CATransaction.commit()
            sync(geometryChanged: false)
        } else {
            sync(geometryChanged: false)
            CATransaction.commit()
        }
        if intervals.count % 60 == 0 { peakFootprint = max(peakFootprint, footprintMiB()) }
        if elapsed >= 12 {
            timer?.invalidate()
            let sorted = intervals.sorted()
            let p95 = sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))]
            print(String(format: "RESULT mode=%@ folders=%d duration=%.3f process_cpu_seconds=%.4f callback_p95_ms=%.3f peak_glass_views=%d sampled_peak_footprint_mib=%.2f", output, count, elapsed, cpuSeconds() - cpuStart, p95, peakViews, peakFootprint))
            fflush(stdout)
            overlay?.reset()
            NSApp.terminate(nil)
        }
    }

    func nativeViews(_ view: NSView) -> [NSGlassEffectView] {
        view.subviews.flatMap { child in
            if let glass = child as? NSGlassEffectView { return [glass] }
            return nativeViews(child)
        }
    }

    func nativeRect(_ native: NSGlassEffectView) -> CGRect {
        // AppKit view conversion alone ignores the material subtree's CA
        // translation. Use actual layer coordinates after native layout; before
        // backing exists, apply the group's transform explicitly.
        if let layer = native.layer { return layer.convert(layer.bounds, to: canvas.layer!) }
        var ancestor = native.superview
        while let view = ancestor {
            if view is NSGlassEffectContainerView, let group = view.layer {
                let rect = native.convert(native.bounds, to: view)
                let transformed = rect.applying(CATransform3DGetAffineTransform(group.sublayerTransform))
                return group.convert(transformed, to: canvas.layer!)
            }
            ancestor = view.superview
        }
        preconditionFailure("missing native effect group")
    }

    func runChecks() {
        enableGlass()
        precondition(overlay!.activeGlassCount == count * 2, "nearby pages should stay prepared")
        precondition(overlay!.hitTest(CGPoint(x: 80, y: 80)) == nil, "glass must not steal grid input")
        let source = folders[0].sublayers![0]
        let icon = folders[0].sublayers![1]
        precondition(source.isHidden && icon.isHidden)
        let native = nativeViews(overlay!).first!
        precondition(native.style == .clear)
        precondition(nativeRect(native) == source.convert(source.bounds, to: canvas.layer!))
        precondition((native.contentView!.layer!.sublayers!.first!.contents as AnyObject?) === (icon.contents as AnyObject?))
        // Simulate a cache miss completing after the initial glass sync, while
        // no pointer/display-link animation triggers a subsequent geometry sync.
        let loadedImage = icon.contents
        let preview = native.contentView!.layer!.sublayers!.first!
        icon.contents = nil
        overlay!.updatePreviewContents(for: icon)
        precondition(preview.contents == nil)
        icon.contents = loadedImage
        icon.contentsScale = 2
        overlay!.updatePreviewContents(for: icon)
        precondition((preview.contents as AnyObject?) === (loadedImage as AnyObject?),
                     "async image arrival must update idle glass without another sync")
        precondition(preview.contentsScale == 2)
        precondition(nativeViews(overlay!).contains { $0 === native }, "bitmap completion must reuse native glass")
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        page.transform = CATransform3DMakeTranslation(-980, 0, 0)
        sync(geometryChanged: false)
        precondition(overlay!.activeGlassCount == count * 2)
        precondition(source.isHidden && icon.isHidden, "nearby pages must not churn while paging")
        precondition(nativeViews(overlay!).contains { $0 === native }, "paging must reuse native views")
        precondition(nativeRect(native) == source.convert(source.bounds, to: canvas.layer!))

        // Crossing the bounded effect surface must invalidate the pure-scroll
        // fast path even when the supplied layer identities are unchanged.
        page.bounds.size.width = 5880
        page.transform = CATransform3DMakeTranslation(-3920, 0, 0)
        sync(geometryChanged: false)
        precondition(overlay!.activeGlassCount == 0, "distant pages must not keep rendering")
        precondition(!source.isHidden && !icon.isHidden)
        page.bounds.size.width = 1960
        page.transform = CATransform3DMakeTranslation(-980, 0, 0)
        sync(geometryChanged: false)
        precondition(overlay!.activeGlassCount == count * 2)

        // A changed nearby batch must release removed source records even on
        // the pure-scroll path, and a subsequent batch must restore them.
        overlay!.sync(containers: Array(folders.suffix(count)), root: canvas.layer!,
                      page: page, viewport: canvas.bounds, geometryChanged: false)
        precondition(nativeViews(overlay!).count == count)
        precondition(!source.isHidden && !icon.isHidden)
        sync(geometryChanged: false)
        precondition(overlay!.activeGlassCount == count * 2)
        let dragged = folders[count]
        dragged.removeFromSuperlayer()
        canvas.layer!.addSublayer(dragged)
        dragged.position = CGPoint(x: 250, y: 300)
        dragged.transform = CATransform3DMakeScale(1.2, 1.2, 1)
        dragged.zPosition = 1000
        sync()
        let rect = dragged.sublayers![0].convert(dragged.sublayers![0].bounds, to: canvas.layer!)
        precondition(nativeViews(overlay!).contains { $0.convert($0.bounds, to: canvas) == rect }, "drag geometry must follow root coordinates and scale")
        dragged.position = CGPoint(x: 420, y: 280)
        sync(geometryChanged: false)
        let movedRect = dragged.sublayers![0].convert(dragged.sublayers![0].bounds, to: canvas.layer!)
        precondition(nativeViews(overlay!).contains { !$0.isHidden && nativeRect($0) == movedRect },
                     "drag-only sync must follow the pointer without updating page geometry")
        dragged.position.x = -500
        sync(geometryChanged: false)
        precondition(overlay!.activeGlassCount == count * 2 - 1, "offscreen drag must be culled")
        dragged.position = CGPoint(x: 420, y: 280)
        sync(geometryChanged: false)
        precondition(overlay!.activeGlassCount == count * 2, "drag returning onscreen must restore glass")
        dragged.opacity = 0
        sync(geometryChanged: false)
        precondition(overlay!.activeGlassCount == count * 2 - 1, "hidden drag source must not leave glass behind")
        dragged.opacity = 1
        sync()
        precondition(overlay!.activeGlassCount == count * 2)
        overlay!.removeDraggingGlass(for: dragged)
        // No subsequent sync or display-link callback: teardown must be immediate.
        precondition(overlay!.activeGlassCount == count * 2 - 1)
        precondition(!nativeViews(overlay!).contains { !$0.isHidden && nativeRect($0) == movedRect },
                     "released drag must not leave native glass until the next sync")
        precondition(!dragged.sublayers![0].isHidden && !dragged.sublayers![1].isHidden)
        sync()
        precondition(overlay!.activeGlassCount == count * 2, "a subsequent drag must show its group again")
        overlay!.reset()
        precondition(overlay!.activeGlassCount == 0)
        precondition(folders.allSatisfy { !$0.sublayers![0].isHidden && !$0.sublayers![1].isHidden })
        // Folder creation grows only its backplate. The target's shared bitmap
        // must stay outside the small glass view's clipping bounds at full size.
        let savedPageTransform = page.transform
        page.transform = CATransform3DIdentity
        let creation = CALayer()
        creation.frame = CGRect(x: 200, y: 200, width: 96, height: 96)
        page.addSublayer(creation)
        let creationPlate = CALayer()
        creationPlate.name = "creationGlass"
        creationPlate.frame = CGRect(x: 5, y: 5, width: 86, height: 86)
        creationPlate.transform = CATransform3DMakeScale(0.15, 0.15, 1)
        creation.addSublayer(creationPlate)
        let targetIcon = CALayer()
        targetIcon.name = "icon"
        targetIcon.frame = creation.bounds
        targetIcon.contents = loadedImage
        creation.addSublayer(targetIcon)
        overlay!.sync(containers: [creation], root: canvas.layer!, page: page, viewport: canvas.bounds)
        let creationGlass = nativeViews(overlay!).first!
        let previewHost = overlay!.subviews.first { view in
            view.layer?.sublayers?.contains { ($0.contents as AnyObject?) === (loadedImage as AnyObject?) } == true
        }!
        let creationPreview = previewHost.layer!.sublayers!.first {
            ($0.contents as AnyObject?) === (loadedImage as AnyObject?)
        }!
        let fixedIconFrame = creationPreview.frame
        precondition(fixedIconFrame.size == targetIcon.bounds.size)
        precondition(creationGlass.frame.width < fixedIconFrame.width / 2)
        creationPlate.transform = CATransform3DIdentity
        overlay!.sync(containers: [creation], root: canvas.layer!, page: page, viewport: canvas.bounds)
        precondition(creationPreview.frame == fixedIconFrame, "backplate growth must not scale the app")
        precondition(nativeViews(overlay!).first === creationGlass, "growth must reuse one native view")
        page.transform = CATransform3DMakeTranslation(-80, 0, 0)
        overlay!.sync(containers: [creation], root: canvas.layer!, page: page,
                      viewport: canvas.bounds, geometryChanged: false)
        precondition(previewHost.layer!.sublayerTransform.m41 == -80,
                     "pure paging must carry the creation icon along with its glass")
        precondition(creationPreview.frame == fixedIconFrame)
        creationPlate.removeFromSuperlayer()
        overlay!.sync(containers: [creation], root: canvas.layer!, page: page, viewport: canvas.bounds)
        precondition(!targetIcon.isHidden && previewHost.superview == nil)
        precondition(overlay!.activeGlassCount == 0)
        creation.removeFromSuperlayer()
        page.transform = savedPageTransform
        let released = overlay
        overlay!.removeFromSuperview()
        overlay = nil
        CATransaction.commit()
        // AppKit/Core Animation may release detached views after committing the
        // current event. Test lifecycle after that commit, not inside it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak released] in
            precondition(released == nil, "detached effect container retained")
            print("PASS: clear style, bitmap sharing, idle preview completion, hit testing, bounded culling, paging reuse, batch invalidation, drag-only updates, drag scale/position, source hiding, immediate drag teardown, reset and deallocation")
            fflush(stdout)
            NSApp.terminate(nil)
        }
    }

    func previewImage() -> CGImage {
        let context = CGContext(data: nil, width: 96, height: 96, bitsPerComponent: 8, bytesPerRow: 384,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        for i in 0..<9 {
            context.setFillColor([NSColor.systemPink, .systemYellow, .white][i % 3].cgColor)
            context.fill(CGRect(x: 18 + (i % 3) * 21, y: 18 + (i / 3) * 21, width: 17, height: 17))
        }
        return context.makeImage()!
    }

    func footprintMiB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : -1
    }

    func cpuSeconds() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec)
            + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
    }
}

@main struct Main {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = GlassProbe()
        app.setActivationPolicy(.accessory)
        app.delegate = delegate
        app.run()
    }
}
