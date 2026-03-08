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
    private var activeHotCornerID: String?
    private var cooldownUntil: Date?
    private let cooldown: TimeInterval = 1.0
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
        let wasEnabled = self.configuration.isEnabled
        self.configuration = configuration

        if !configuration.isEnabled {
            stop()
            return
        }

        if !wasEnabled || localMonitor == nil || globalMonitor == nil {
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
        activeHotCornerID = nil
    }

    private func handlePointerActivity() {
        guard configuration.isEnabled else { return }

        let mouseLocation = NSEvent.mouseLocation
        guard let hotCornerID = hotCornerIdentifier(at: mouseLocation) else {
            activeHotCornerID = nil
            cancelPendingTrigger()
            return
        }

        guard hotCornerID != activeHotCornerID else { return }

        activeHotCornerID = hotCornerID
        cancelPendingTrigger()

        if let cooldownUntil, cooldownUntil > Date() {
            return
        }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.configuration.isEnabled else { return }
            guard self.activeHotCornerID == hotCornerID else { return }
            self.cooldownUntil = Date().addingTimeInterval(self.cooldown)
            self.onTrigger()
        }
        pendingTrigger = workItem

        if configuration.triggerDelay <= 0 {
            DispatchQueue.main.async(execute: workItem)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + configuration.triggerDelay, execute: workItem)
        }
    }

    private func cancelPendingTrigger() {
        pendingTrigger?.cancel()
        pendingTrigger = nil
    }

    private func hotCornerIdentifier(at location: NSPoint) -> String? {
        let size = max(configuration.hitboxSize, 1)
        for (index, screen) in NSScreen.screens.enumerated() {
            let frame = screen.frame
            let hitbox = hitboxRect(in: frame, size: size)
            if hitbox.contains(location) {
                return "\(screenIdentifier(for: screen, fallbackIndex: index)):\(configuration.position.rawValue)"
            }
        }
        return nil
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

    private func screenIdentifier(for screen: NSScreen, fallbackIndex: Int) -> String {
        if let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            return number.stringValue
        }
        return "screen-\(fallbackIndex)"
    }
}
