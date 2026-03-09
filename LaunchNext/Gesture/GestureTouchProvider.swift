import Foundation
import CoreGraphics

struct GestureTouchSample: Sendable {
    let id: Int32
    let point: CGPoint
}

final class GestureTouchProvider {
    private let manager = OMSManager.shared

    var isListening: Bool {
        manager.isListening
    }

    @discardableResult
    func startListening() -> Bool {
        selectPreferredDeviceIfNeeded()
        return manager.startListening() || manager.isListening
    }

    @discardableResult
    func stopListening() -> Bool {
        manager.stopListening() || !manager.isListening
    }

    var touchDataStream: AsyncStream<[GestureTouchSample]> {
        AsyncStream { continuation in
            let task = Task {
                for await touches in manager.touchDataStream {
                    if Task.isCancelled { break }
                    continuation.yield(Self.activeSamples(from: touches))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private func selectPreferredDeviceIfNeeded() {
        if let current = manager.currentDevice, current.isBuiltIn {
            return
        }
        if let builtIn = manager.availableDevices.first(where: \.isBuiltIn) {
            _ = manager.selectDevice(builtIn)
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

    private static let activeStates: Set<OMSState> = [
        .starting,
        .making,
        .touching,
        .breaking,
        .lingering
    ]
}
