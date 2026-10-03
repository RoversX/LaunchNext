#!/usr/bin/env python3
"""Exercise Legacy drag events in an isolated copy of the real app target."""
import argparse
import fcntl
import os
import platform
from pathlib import Path
import shutil
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--baseline-ref', help='Reproduce the stuck drag using LaunchpadView from this Git ref')
parser.add_argument('--work-dir', type=Path, help='Keep/reuse build artifacts in this directory')
args = parser.parse_args()
root = Path(__file__).resolve().parents[2]
work = (args.work_dir or Path(tempfile.mkdtemp(prefix='launchnext-legacy-drag-'))).resolve()
if work == root or root in work.parents:
    raise ValueError('The diagnostic work directory must be outside the repository.')
work.mkdir(parents=True, exist_ok=True)
for name in ['LaunchNext', 'LaunchNext.xcodeproj']:
    shutil.copytree(root / name, work / name, dirs_exist_ok=True)
for name in ['Config', 'LaunchNextContextMenuCore', 'LaunchNextWallpaperCore', 'LaunchNextTests', 'UpdaterScripts'] + [p.name for p in root.glob('*.lproj')]:
    target = work / name
    if not target.exists():
        target.symlink_to(root / name, target_is_directory=True)

entry = work / 'LaunchNext/LaunchpadApp.swift'
source = entry.read_text()
marker = '@main\nstruct LaunchpadApp'
assert source.count(marker) == 1
entry.write_text(source.replace(marker, 'struct LaunchpadApp', 1))

# Keep production model operations; skip real scans, hotkeys, persistence and startup observers.
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
store.write_text(source[:start] + '''    init() {
        customIconFileURL = URL(fileURLWithPath: "/tmp/launchnext-legacy-drag-icon.png")
        defaultAppIcon = NSImage(size: NSSize(width: 32, height: 32))
        currentAppIcon = defaultAppIcon
        hasCustomAppIcon = false
        scrollSensitivity = 1
        gridColumnsPerPage = 4
        gridRowsPerPage = 3
        iconColumnSpacing = 0
        iconRowSpacing = 0
        hasPerformedInitialScan = true
        isInitialLoading = false
    }''' + source[end:])

view = work / 'LaunchNext/LaunchpadView.swift'
source = (subprocess.check_output(['git', 'show', f'{args.baseline_ref}:LaunchNext/LaunchpadView.swift'], cwd=root, text=True)
          if args.baseline_ref else view.read_text())
# No wallpaper/cache writes and no real app scans in the test window.
begin = source.index('    private func refreshBackgroundImage(')
end = source.index('    private func setupWindowShownObserver()', begin)
source = source[:begin] + '    private func refreshBackgroundImage(reason: BackgroundImageController.RefreshReason) {}\n\n' + source[end:]
source = source.replace('                  checkCacheStatus()', '')
source = source.replace('            backgroundImageController.clear()', '')
source = source.replace('              setupInitialSelection()', '              setupInitialSelection()\n              installLegacyDragProbe()')
marker = '    private func finalizeDragOperation(containerSize: CGSize, columnWidth: CGFloat, appHeight: CGFloat, iconSize: CGFloat) {'
assert source.count(marker) == 1
source = source.replace(marker, marker + '\n        LegacyDragProbe.finalizeCount += 1')
source += '''
extension LaunchpadView {
    private func installLegacyDragProbe() {
        LegacyDragProbe.state = {
            LegacyDragProbe.State(draggingID: draggingItem?.id, preview: dragPreviewPosition,
                pointerOffset: dragPointerOffset, gridOrigin: gridOriginInWindow,
                gridSize: currentContainerSize, columnWidth: currentColumnWidth,
                iconSize: currentIconSize, refreshID: REFRESH_ID, monitoring: MONITORING, pendingIndex: pendingDropIndex)
        }
        LegacyDragProbe.iconPoint = { index in
            iconCenter(for: index, geoSize: currentContainerSize, columnWidth: currentColumnWidth,
                       appHeight: currentAppHeight, iconSize: currentIconSize)
        }
        FINISH_HOOK
    }
}
'''.replace('REFRESH_ID', 'appStore.gridRefreshTrigger' if args.baseline_ref else 'displayedGridRefreshID').replace(
    'MONITORING', 'false' if args.baseline_ref else 'legacyItemDragSession?.eventMonitor != nil').replace(
    'FINISH_HOOK', '' if args.baseline_ref else 'LegacyDragProbe.finishAgain = { endLegacyItemDrag() }')
view.write_text(source)
shutil.copy2(root / 'scripts/diagnostics/LegacyDragIntegration.swift', work / 'LaunchNext/')
log = work / 'build.log'
print(f'Artifacts: {work}', flush=True)
with log.open('w') as output:
    result = subprocess.run(['xcodebuild', 'build', '-project', str(work / 'LaunchNext.xcodeproj'),
                             '-scheme', 'LaunchNext', '-configuration', 'Debug',
                             '-derivedDataPath', str(work / 'DerivedData'), '-destination', f'platform=macOS,arch={platform.machine()}',
                             'CODE_SIGNING_ALLOWED=NO', 'PRODUCT_BUNDLE_IDENTIFIER=local.launchnext.legacydragprobe'],
                            stdout=output, stderr=subprocess.STDOUT)
if result.returncode:
    raise RuntimeError(f'Build failed: {log}')
binary = work / 'DerivedData/Build/Products/Debug/LaunchNext.app/Contents/MacOS/LaunchNext'
with Path('/tmp/launchnext-legacy-drag-probe.lock').open('w') as lock:
    # Visible test windows must not steal focus from a concurrent baseline run.
    fcntl.flock(lock, fcntl.LOCK_EX)
    subprocess.run([str(binary)] + (['--expect-stuck'] if args.baseline_ref else []), check=True, timeout=90,
                   cwd=work, env=dict(os.environ, LLVM_PROFILE_FILE=str(work / 'drag-%p.profraw')))
