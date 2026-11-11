#!/usr/bin/env python3
"""Exercise production hit testing and mouse handlers in an isolated NSView.

Models, animation, app launching and item drag effects are stubbed. This checks
click/page-drag routing, not real window event delivery or visual animation.
"""
import argparse
from pathlib import Path
import runpy
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
declaration = runpy.run_path(str(root / 'scripts/test-application-reconciliation.py'))['declaration']
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--input-source', type=Path, default=root / 'LaunchNext/CAGridView+Input.swift')
args = parser.parse_args()
source = args.input_source.read_text()
methods = '\n'.join(declaration(source, marker) for marker in (
    '    override func mouseDown(', '    override func mouseDragged(',
    '    override func mouseUp(', '    func itemAt(', '    func gridPositionAt(',
    '    func rubberBand(',
))
callback = declaration((root / 'LaunchNext/CAGridViewRepresentable.swift').read_text(),
                       '        view.onItemClicked = ')
host = '''import AppKit
import QuartzCore
struct AppInfo { var url = URL(fileURLWithPath: "/fixture.app") }
enum LaunchpadItem { case app(AppInfo), folder(String), missingApp(String), empty(String) }
extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
final class ProbeGrid: NSView {
    var items: [LaunchpadItem] = []
    var columns = 4, rows = 1
    var itemsPerPage: Int { columns * rows }
    var pageCount: Int { max(1, (items.count + itemsPerPage - 1) / itemsPerPage) }
    var pageSpacing: CGFloat = 0, columnSpacing: CGFloat = 20, rowSpacing: CGFloat = 20
    var scrollOffset: CGFloat = 0, iconSize: CGFloat = 60, labelFontSize: CGFloat = 12
    var showLabels = true
    var contentInsets = NSEdgeInsetsZero
    var externalAppDragSessionActive = false, isPageDragging = false, isDraggingItem = false
    var isBatchSelectionMode = false, isLayoutLocked = false
    var pressedIndex: Int?, currentPage = 0
    var pageDragStartX: CGFloat = 0, pageDragStartOffset: CGFloat = 0
    var dragStartPoint = CGPoint.zero, dragCurrentPoint = CGPoint.zero
    var longPressTimer: Timer?, longPressDuration = 0.5
    var onEmptyAreaClicked: (() -> Void)?
    var onItemClicked: ((LaunchpadItem, Int) -> Void)?
    var pageContainerLayer = CALayer()
    var itemDragStarts = 0
    func finishFolderDissolve() {}
    func finishDragLanding() {}
    func setPressedIndex(_ index: Int?) { pressedIndex = index }
    func startDragging(item: LaunchpadItem, index: Int, at: CGPoint) { itemDragStarts += 1 }
    func endDragging(at: CGPoint) {}
    func navigateToPage(_ page: Int, animated: Bool) {
        currentPage = page
        scrollOffset = -CGFloat(page) * (bounds.width + pageSpacing)
    }
    func toggleBatchSelection(forAppPath: String) {}
    func syncFolderGlass(geometryChanged: Bool) {}
    func externalDockDragCandidate() -> AppInfo? { nil }
    func shouldStartExternalDockDrag(localPoint: CGPoint, windowPoint: CGPoint, dragDelta: CGPoint) -> Bool { false }
    func startExternalDockDrag(for app: AppInfo, event: NSEvent, at: CGPoint) {}
    func updateDragging(at: CGPoint) {}
'''
checks = '''
func event(_ type: NSEvent.EventType, _ x: CGFloat) -> NSEvent {
    NSEvent.mouseEvent(with: type, location: CGPoint(x: x, y: 60), modifierFlags: [],
        timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 0)!
}
func drainClick() {
    let end = Date().addingTimeInterval(0.1)
    while Date() < end { _ = RunLoop.main.run(mode: .default, before: end) }
}
let view = ProbeGrid(frame: NSRect(x: 0, y: 0, width: 460, height: 120))
var closed = 0, launched = 0, folderOpened = 0
let launchApp: (AppInfo) -> Void = { _ in launched += 1 }
let onOpenFolder: ((String) -> Void)? = { _ in folderOpened += 1 }
// INSERT_CLICK_CALLBACK
view.onEmptyAreaClicked = { closed += 1 }
view.items = [.app(AppInfo()), .empty("slot"), .folder("folder"), .missingApp("missing")]
for (name, x, close, launch, folder) in [
    ("empty slot center", CGFloat(170), 1, 0, 0),
    ("empty slot margin", CGFloat(125), 1, 0, 0),
    ("cell gap", CGFloat(110), 1, 0, 0),
    ("application", CGFloat(50), 0, 1, 0),
    ("folder", CGFloat(290), 0, 0, 1),
    ("missing application", CGFloat(410), 0, 0, 0)
] {
    closed = 0; launched = 0; folderOpened = 0
    view.mouseDown(with: event(.leftMouseDown, x))
    view.mouseUp(with: event(.leftMouseUp, x))
    drainClick()
    precondition(closed == close && launched == launch && folderOpened == folder, name)
    print("PASS " + name)
}
view.items.removeLast()
closed = 0
view.mouseDown(with: event(.leftMouseDown, 410))
view.mouseUp(with: event(.leftMouseUp, 410))
precondition(closed == 1, "unallocated cell must close")
print("PASS unallocated cell")

view.items = [.app(AppInfo()), .empty("first"), .app(AppInfo()), .app(AppInfo()),
              .app(AppInfo()), .empty("second"), .app(AppInfo()), .app(AppInfo())]
for (startPage, endX, expectedPage) in [(0, CGFloat(20), 1), (1, CGFloat(320), 0)] {
    view.navigateToPage(startPage, animated: false)
    closed = 0
    precondition(view.gridPositionAt(CGPoint(x: 170, y: 60)) == startPage * 4 + 1,
                 "empty slot must remain a valid drop destination")
    view.mouseDown(with: event(.leftMouseDown, 170))
    precondition(view.isPageDragging && view.pressedIndex == nil && view.longPressTimer == nil,
                 "empty slot must start a page gesture without an item long press")
    view.mouseDragged(with: event(.leftMouseDragged, endX))
    view.mouseUp(with: event(.leftMouseUp, endX))
    precondition(view.currentPage == expectedPage && closed == 0 && view.itemDragStarts == 0,
                 "empty-slot drag must page without closing or dragging an item")
    print("PASS page drag from empty slot on page " + String(startPage))
}
'''.replace('// INSERT_CLICK_CALLBACK', callback)

with tempfile.TemporaryDirectory(prefix='launchnext-empty-input-') as folder:
    work = Path(folder)
    swift = work / 'main.swift'
    swift.write_text(host + methods + '\n}\n' + checks)
    binary = work / 'probe'
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', '-module-cache-path',
                    str(work / 'module-cache'), str(swift), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
