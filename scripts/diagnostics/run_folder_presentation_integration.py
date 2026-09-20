#!/usr/bin/env python3
"""Check real folder presentation views in an isolated, visible macOS window."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix='launchnext-folder-presentation-') as temporary:
    work = Path(temporary)
    for name in ['LaunchNext', 'LaunchNext.xcodeproj']:
        shutil.copytree(root / name, work / name)
    for item in root.iterdir():
        if item.name.startswith('.') or item.name in ['LaunchNext', 'LaunchNext.xcodeproj', 'build', 'Archive']:
            continue
        (work / item.name).symlink_to(item, target_is_directory=item.is_dir())

    entry = work / 'LaunchNext/LaunchpadApp.swift'
    source = entry.read_text()
    marker = '@main\nstruct LaunchpadApp'
    if source.count(marker) != 1:
        raise RuntimeError('App entry point changed; update this verifier.')
    entry.write_text(source.replace(marker, 'struct LaunchpadApp', 1))

    # Keep production observable properties and methods, but skip scanning,
    # layout persistence, input devices and startup observers. The isolated
    # bundle identifier also keeps property defaults out of the user's domain.
    store = work / 'LaunchNext/AppStore.swift'
    source = store.read_text()
    start = source.index('    init() {', source.index('final class AppStore'))
    end = source.index('{', start) + 1
    depth = 1
    while depth:
        if source[end] == '{':
            depth += 1
        elif source[end] == '}':
            depth -= 1
        end += 1
    fixture = '''    init() {
        customIconFileURL = URL(fileURLWithPath: "/tmp/launchnext-opening-fixture-icon.png")
        defaultAppIcon = NSImage(size: NSSize(width: 32, height: 32))
        currentAppIcon = defaultAppIcon
        hasCustomAppIcon = false
        scrollSensitivity = 1
        gridColumnsPerPage = 7
        gridRowsPerPage = 5
        iconColumnSpacing = 0
        iconRowSpacing = 0
    }'''
    store.write_text(source[:start] + fixture + source[end:])

    # Observe private state only in the temporary target; no shipped test hooks.
    host = work / 'LaunchNext/CAFolderPresentation.swift'
    host.write_text(host.read_text() + '''
extension CAFolderPresentationHost {
    var probePhase: String { String(describing: phase) }
    var probeDuration: TimeInterval { duration }
    var probeInitialVelocity: CGFloat { motion?.initialVelocity ?? 0 }
    var probeGlassAnimation: CAKeyframeAnimation? { glassContainer?.layer?.animation(forKey: "folderPresentation.glass") as? CAKeyframeAnimation }
    var probeGrid: CAFolderGridView? { state?.grid }
    var probePlate: CGRect? { presentedGlassFrame }
    var probePanel: CGRect { panelRect }
    var probeClipped: Bool { hosting?.layer?.masksToBounds == true }
    var probeIcons: [CALayer] { animationStage?.layer?.sublayers ?? [] }
    var probeMask: CGPath? { glassMask?.presentation()?.path ?? glassMask?.path }
    var probeGlassProgress: CGFloat {
        guard let source else { return 0 }
        let ratio = (presentedGlassFrame.width - source.plateRectInWindow.width) / (panelRect.width - source.plateRectInWindow.width)
        return phase == .closing ? 1 - ratio : ratio
    }
    // Rasterize a solid plate using the production presentation transform and
    // clipping path. This checks visible coverage, not just matching progress.
    var probePlateCoverage: Double {
        guard let container = glassContainer?.layer, let glass,
              let mask = glassMask, bounds.width > 0, bounds.height > 0 else { return 0 }
        let visual = container.presentation() ?? container
        let rect = presentedGlassFrame
        let root = CALayer()
        root.frame = bounds
        let transformed = CALayer()
        transformed.bounds = visual.bounds
        transformed.anchorPoint = visual.anchorPoint
        transformed.position = visual.position
        transformed.sublayerTransform = visual.sublayerTransform
        root.addSublayer(transformed)
        let plate = CALayer()
        plate.frame = glass.frame
        plate.backgroundColor = NSColor.red.cgColor
        transformed.addSublayer(plate)
        let clipping = CAShapeLayer()
        clipping.frame = bounds
        clipping.path = mask.presentation()?.path ?? mask.path
        root.mask = clipping
        let width = Int(bounds.width), height = Int(bounds.height)
        let context = CGContext(data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        root.render(in: context)
        let bytes = context.data!.assumingMemoryBound(to: UInt8.self)
        var pixels = 0
        for index in 0..<(width * height) where bytes[index * 4 + 3] > 0 { pixels += 1 }
        return Double(pixels) / max(1, rect.width * rect.height)
    }
    var probeChromeOpacity: Float {
        guard let layer = hosting?.layer else { return 0 }
        return (layer.presentation() ?? layer).opacity
    }

}
''')
    grid = work / 'LaunchNext/CAFolderGridView.swift'
    grid.write_text(grid.read_text() + '''
extension CAFolderGridView {
    func probeCheckPendingIconLabel() {
        for scale: CGFloat in [1, 2] {
            let image = Self.renderIcon(NSWorkspace.shared.icon(forFile: "/System/Applications/Notes.app"), side: 72, scale: scale)!
            precondition(image.width == Int(72 * scale) && image.height == Int(72 * scale), "backing scale must be applied exactly once")
            precondition(image.bitsPerComponent == 16)
        }
        let cell = appLayers[0]
        let icon = cell.sublayers!.first(where: { $0.name == "icon" })!
        let label = cell.sublayers!.first(where: { $0.name == "label" })!
        let bitmap = icon.contents
        icon.contents = nil
        finishFolderPresentation()
        precondition(label.opacity == 0, "an overdue bitmap must not leave an orphan label")
        icon.contents = bitmap
        finishFolderPresentation()
        precondition(label.opacity == 1)
    }
    var probeOpeningEndpointDrift: CGFloat {
        guard let root = layer else { return 0 }
        var delta: CGFloat = 0
        for cell in appLayers {
            guard let icon = cell.sublayers?.first(where: { $0.name == "icon" }),
                  let proxy = presentationIcons[ObjectIdentifier(icon)],
                  let stage = proxy.superlayer?.delegate as? NSView else { continue }
            let expected = convert(icon.convert(icon.bounds, to: root), to: stage)
            delta = max(delta, abs(expected.midX - proxy.frame.midX), abs(expected.midY - proxy.frame.midY),
                        abs(expected.width - proxy.frame.width), abs(expected.height - proxy.frame.height))
        }
        return delta
    }
    var probeVisibleLabels: [CALayer] {
        appLayers.enumerated().filter { itemFrames.indices.contains($0.offset) && itemFrames[$0.offset].intersects(bounds) }
            .compactMap { $0.element.sublayers?.first(where: { $0.name == "label" }) }
    }
}
''')
    shutil.copy2(root / 'scripts/diagnostics/FolderPresentationIntegration.swift', work / 'LaunchNext/')
    derived = work / 'DerivedData'
    log = Path('/tmp/launchnext-folder-presentation-build.log')
    with log.open('w') as output:
        subprocess.run(['xcodebuild', 'build', '-project', str(work / 'LaunchNext.xcodeproj'),
                        '-scheme', 'LaunchNext', '-configuration', 'Debug',
                        '-derivedDataPath', str(derived), '-destination', 'platform=macOS',
                        'CODE_SIGNING_ALLOWED=NO',
                        'PRODUCT_BUNDLE_IDENTIFIER=local.launchnext.folderpresentationprobe'],
                       check=True, stdout=output, stderr=subprocess.STDOUT)
    binary = derived / 'Build/Products/Debug/LaunchNext.app/Contents/MacOS/LaunchNext'
    subprocess.run([str(binary)], check=True, timeout=60, cwd=work,
                   env=dict(os.environ, LLVM_PROFILE_FILE=str(work / 'presentation-%p.profraw')))
