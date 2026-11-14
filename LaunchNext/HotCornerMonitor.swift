import AppKit
import Foundation

final class HotCornerMonitor {
    struct Configuration: Equatable {
        var isEnabled: Bool
        var position: AppStore.HotCornerPosition
        var triggerDelay: TimeInterval
        var hitboxSize: CGFloat
    }

    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var pendingTrigger: DispatchWorkItem?
    private var tracker = HotCornerTracker()
    private let onTrigger: () -> Void
    private var configuration: Configuration

    init(configuration: Configuration, onTrigger: @escaping () -> Void) {
        self.configuration = configuration
        self.onTrigger = onTrigger
    }

    deinit {
        stop()
    }

    func update(configuration: Configuration) {
        let previous = self.configuration
        self.configuration = configuration

        if !configuration.isEnabled {
            stop()
            return
        }

        if configuration.position != previous.position || configuration.hitboxSize != previous.hitboxSize {
            // A visit or pending trigger belongs to the old corner.
            cancelPendingTrigger()
            tracker.reset()
        }

        if !previous.isEnabled || localMonitor == nil || globalMonitor == nil {
            start()
        }
    }

    func start() {
        guard configuration.isEnabled else { return }
        guard localMonitor == nil, globalMonitor == nil else { return }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            self?.handlePointerActivity()
            return event
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            self?.handlePointerActivity()
        }
    }

    func stop() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }

        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }

        cancelPendingTrigger()
        tracker.reset()
    }

    private func handlePointerActivity() {
        guard configuration.isEnabled else { return }

        switch tracker.pointerMoved(to: NSEvent.mouseLocation,
                                    at: ProcessInfo.processInfo.systemUptime,
                                    triggerDelay: configuration.triggerDelay,
                                    corners: corners) {
        case .ignore:
            break
        case .cancel:
            cancelPendingTrigger()
        case .schedule(let visit, let delay):
            scheduleTrigger(forVisit: visit, after: delay)
        }
    }

    private func scheduleTrigger(forVisit visit: Int, after delay: TimeInterval) {
        cancelPendingTrigger()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.configuration.isEnabled else { return }
            guard self.tracker.mayTrigger(visit: visit) else { return }
            self.pendingTrigger = nil
            self.tracker.didTrigger(visit: visit, at: ProcessInfo.processInfo.systemUptime)
            self.onTrigger()
        }
        pendingTrigger = workItem

        if delay <= 0 {
            DispatchQueue.main.async(execute: workItem)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
        }
    }

    private func cancelPendingTrigger() {
        pendingTrigger?.cancel()
        pendingTrigger = nil
    }

    private func corners() -> [HotCornerTracker.Corner] {
        let size = max(configuration.hitboxSize, 1)
        return NSScreen.screens.map { screen in
            HotCornerTracker.Corner(hitbox: hitboxRect(in: screen.frame, size: size), screenFrame: screen.frame)
        }
    }

    private func hitboxRect(in frame: CGRect, size: CGFloat) -> CGRect {
        switch configuration.position {
        case .topLeft:
            return CGRect(x: frame.minX, y: frame.maxY - size, width: size, height: size)
        case .topRight:
            return CGRect(x: frame.maxX - size, y: frame.maxY - size, width: size, height: size)
        case .bottomLeft:
            return CGRect(x: frame.minX, y: frame.minY, width: size, height: size)
        case .bottomRight:
            return CGRect(x: frame.maxX - size, y: frame.minY, width: size, height: size)
        }
    }
}
