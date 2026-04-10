import Foundation
import CoreGraphics

struct GestureTouchSample: Sendable {
    let id: Int32
    let point: CGPoint
}

struct GestureTouchFrame: Sendable {
    let deviceID: String
    let samples: [GestureTouchSample]
}

final class GestureTouchProvider {
    private let manager = OMSManager.shared
    private let activeDeviceLock = NSLock()
    private var activeDeviceID: String?

    var isListening: Bool {
        manager.isListening
    }

    var availableDevices: [GestureInputDevice] {
        manager.availableDevices
            .filter(\.isGestureTrackpadCandidate)
            .map { GestureInputDevice(id: $0.deviceID, name: $0.deviceName, isBuiltIn: $0.isBuiltIn) }
    }

    func refreshDevices() {
        manager.refreshDevices()
    }

    func configureDevices(mode: GestureDeviceSelectionMode, selectedDeviceIDs: [String]) {
        let availableTrackpads = manager.availableDevices.filter(\.isGestureTrackpadCandidate)

        switch mode {
        case .automatic:
            _ = manager.selectDevices(availableTrackpads)
        case .selected:
            let selected = availableTrackpads.filter { selectedDeviceIDs.contains($0.deviceID) }
            _ = manager.selectDevices(selected)
        }
    }

    @discardableResult
    func startListening(configuration: GestureConfiguration) -> Bool {
        refreshDevices()
        configureDevices(mode: configuration.deviceSelectionMode, selectedDeviceIDs: configuration.selectedDeviceIDs)
        guard !manager.selectedDevices.filter(\.isGestureTrackpadCandidate).isEmpty else { return false }
        resetActiveDevice()
        return manager.startListening() || manager.isListening
    }

    @discardableResult
    func stopListening() -> Bool {
        resetActiveDevice()
        return manager.stopListening() || !manager.isListening
    }

    var touchDataStream: AsyncStream<GestureTouchFrame> {
        AsyncStream { continuation in
            let task = Task { [weak self] in
                guard let self else {
                    continuation.finish()
                    return
                }
                for await frame in manager.touchDataStream {
                    if Task.isCancelled { break }
                    guard let routedSamples = self.route(frame) else { continue }
                    continuation.yield(
                        GestureTouchFrame(
                            deviceID: frame.deviceID,
                            samples: routedSamples
                        )
                    )
                }
                continuation.finish()
            }
            continuation.onTermination = { [weak self] _ in
                task.cancel()
                Task { @MainActor [weak self] in
                    self?.resetActiveDevice()
                }
            }
        }
    }

    private func route(_ frame: OMSTouchFrame) -> [GestureTouchSample]? {
        let samples = Self.activeSamples(from: frame.touches)
        return withActiveDeviceLock {
            if samples.isEmpty {
                guard activeDeviceID == frame.deviceID else { return nil }
                activeDeviceID = nil
                return []
            }
            if let activeDeviceID, activeDeviceID != frame.deviceID {
                return nil
            }
            activeDeviceID = frame.deviceID
            return samples
        }
    }

    private static func activeSamples(from touches: [OMSTouchData]) -> [GestureTouchSample] {
        touches.compactMap { touch in
            guard activeStates.contains(touch.state) else { return nil }
            return GestureTouchSample(
                id: touch.id,
                point: CGPoint(x: Double(touch.position.x), y: Double(touch.position.y))
            )
        }
    }

    private func resetActiveDevice() {
        withActiveDeviceLock {
            activeDeviceID = nil
        }
    }

    private func withActiveDeviceLock<T>(_ body: () -> T) -> T {
        activeDeviceLock.lock()
        defer { activeDeviceLock.unlock() }
        return body()
    }

    private static let activeStates: Set<OMSState> = [
        .starting,
        .making,
        .touching,
        .breaking,
        .lingering
    ]
}
