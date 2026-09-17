"""Compile current production methods with small model/host fixtures.

This checks dispatch and content equality, not real window rendering or CPU/RSS.
All generated Swift and binaries live in a temporary directory.
"""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
input_source = (root / 'LaunchNext/CAGridView+Input.swift').read_text()
layout = (root / 'LaunchNext/CAGridView+Layout.swift').read_text()
glass = (root / 'LaunchNext/CAGridView+FolderGlass.swift').read_text()


def section(text, start, end):
    begin = text.index(start)
    return text[begin:text.index(end, begin)]


content = section(layout, 'extension LaunchpadItem {', '\nextension CAGridView {')
scale = section(input_source, '    func applyScaleForIndex(', '    func updateSelection(')
animate = section(glass, '    func animateFolderGlass(', '    func syncFolderGlass(')
fixtures = '''import AppKit
import QuartzCore
struct AppInfo { let url: URL; let name: String; let icon: NSImage }
struct FolderInfo { let id: String; let name: String; let pinnedAppPaths: [String]; let apps: [AppInfo] }
struct MissingAppPlaceholder: Equatable {
 let bundlePath: String; let displayName: String; let removableSource: String?
}
enum LaunchpadItem {
 case app(AppInfo), folder(FolderInfo), empty(String), missingApp(MissingAppPlaceholder)
}
@MainActor final class CAGridView {
 let itemsPerPage = 2
 var iconLayers = [[CALayer(), CALayer()]]
 var pressedIndex: Int?, selectedIndex: Int?, hoveredIndex: Int?, dropTargetIndex: Int?
 var activePressEffectEnabled = true
 var activePressScale = 0.9
 var hoverMagnificationEnabled = true
 var hoverMagnificationScale = 1.2
 var usesLiquidGlassFolders = true
 var folderGlassAnimationDeadline: Double = 0
 var syncCalls = 0
 func syncFolderGlass() { syncCalls += 1 }
'''
checks = '''
@main struct Probe {
 @MainActor static func main() {
  let grid = CAGridView()
  for container in grid.iconLayers[0] {
   let icon = CALayer(); icon.name = "icon"; container.addSublayer(icon)
  }
  let backplate = CALayer(); backplate.name = "glass"
  grid.iconLayers[0][1].addSublayer(backplate)
  let appIcon = grid.iconLayers[0][0].sublayers![0]
  grid.hoveredIndex = 0
  grid.applyScaleForIndex(0, animated: true)
  precondition(appIcon.transform.m11 == 1.2 && grid.syncCalls == 0)
  grid.pressedIndex = 0
  grid.applyScaleForIndex(0, animated: true)
  precondition(grid.iconLayers[0][0].transform.m11 == 0.9 && grid.syncCalls == 0)
  precondition(grid.folderGlassAnimationDeadline == 0)
  grid.hoveredIndex = 1
  grid.applyScaleForIndex(1, animated: true)
  precondition(backplate.transform.m11 == 1.2 && grid.syncCalls == 1)
  let deadline = grid.folderGlassAnimationDeadline
  grid.applyScaleForIndex(1, animated: true)
  precondition(grid.syncCalls == 1 && grid.folderGlassAnimationDeadline == deadline,
               "an unchanged folder transform must not extend sampling")
  grid.applyScaleForIndex(0, animated: true)
  precondition(grid.syncCalls == 1 && grid.folderGlassAnimationDeadline == deadline,
               "ordinary app must not alter an active folder animation deadline")
  grid.hoveredIndex = nil
  grid.applyScaleForIndex(1, animated: false)
  precondition(backplate.transform.m11 == 1 && grid.syncCalls == 2)
  grid.usesLiquidGlassFolders = false; grid.hoveredIndex = 1
  grid.applyScaleForIndex(1, animated: true)
  precondition(backplate.transform.m11 == 1.2 && grid.syncCalls == 2)

  let creationGrid = CAGridView()
  let targetIcon = CALayer(); targetIcon.name = "icon"
  let creationPlate = CALayer(); creationPlate.name = "creationGlass"
  creationGrid.iconLayers[0][0].addSublayer(targetIcon)
  creationGrid.iconLayers[0][0].addSublayer(creationPlate)
  creationGrid.dropTargetIndex = 0
  creationGrid.applyScaleForIndex(0, animated: true)
  precondition(CATransform3DIsIdentity(targetIcon.transform),
               "folder creation must keep the target app at its normal size")
  let folderIcon = CALayer(); folderIcon.name = "icon"
  let folderPlate = CALayer(); folderPlate.name = "glass"
  creationGrid.iconLayers[0][1].addSublayer(folderIcon)
  creationGrid.iconLayers[0][1].addSublayer(folderPlate)
  creationGrid.dropTargetIndex = 1
  creationGrid.applyScaleForIndex(1, animated: true)
  precondition(folderIcon.transform.m11 == 1.1 && folderPlate.transform.m11 == 1.1,
               "dropping into an existing folder must retain its existing feedback")

  let missing = LaunchpadItem.missingApp(MissingAppPlaceholder(bundlePath:"/missing.app", displayName:"Missing", removableSource:nil))
  precondition(missing.hasSameGridContent(as: missing))
  let renamed = LaunchpadItem.missingApp(MissingAppPlaceholder(bundlePath:"/missing.app", displayName:"Renamed", removableSource:nil))
  precondition(!missing.hasSameGridContent(as: renamed))
  let relocated = LaunchpadItem.missingApp(MissingAppPlaceholder(bundlePath:"/other.app", displayName:"Missing", removableSource:nil))
  precondition(!missing.hasSameGridContent(as: relocated))
  let removable = LaunchpadItem.missingApp(MissingAppPlaceholder(bundlePath:"/missing.app", displayName:"Missing", removableSource:"disk"))
  precondition(!missing.hasSameGridContent(as: removable))
  let image = NSImage(size:NSSize(width:16,height:16))
  let app = LaunchpadItem.app(AppInfo(url:URL(fileURLWithPath:"/missing.app"),name:"Missing",icon:image))
  precondition(!missing.hasSameGridContent(as: app))
  let changedImage = LaunchpadItem.app(AppInfo(url:URL(fileURLWithPath:"/missing.app"),name:"Missing",icon:NSImage(size:image.size)))
  precondition(app.hasSameGridContent(as: app) && !app.hasSameGridContent(as: changedImage))
  print("PASS: app hover/press skips glass sync, folder scaling syncs, unchanged transforms preserve deadline, classic style; missing-placeholder reuse and content invalidation")
 }
}
'''
with tempfile.TemporaryDirectory(prefix='launchnext-visual-policy-') as folder:
    path = Path(folder)
    source = path / 'Probe.swift'
    source.write_text(fixtures + scale + animate + '\n}\n' + content + checks)
    binary = path / 'probe'
    subprocess.run(['xcrun', 'swiftc', '-parse-as-library', '-module-cache-path',
                    '/tmp/launchnext-glass-module-cache', str(source), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
