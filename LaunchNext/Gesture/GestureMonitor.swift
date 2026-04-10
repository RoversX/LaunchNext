import Foundation

final class GestureMonitor {
    typealias Configuration = GestureConfiguration

    private let provider = GestureTouchProvider()
    private let onTrigger: (GestureTriggerAction) -> Void
    private var configuration: Configuration
    private var monitorTask: Task<Void, Never>?

    init(configuration: Configuration, onTrigger: @escaping (GestureTriggerAction) -> Void) {
        self.configuration = configuration
        self.onTrigger = onTrigger
    }

    deinit {
        stop()
    }

    func update(configuration: Configuration) {
        let previousConfiguration = self.configuration
        self.configuration = configuration

        if !configuration.isEnabled {
            stop()
            return
        }

        if monitorTask != nil, previousConfiguration != configuration {
            stop()
        }

        if monitorTask == nil || !provider.isListening {
            start()
        }
    }

    func start() {
        guard configuration.isEnabled else { return }
        guard monitorTask == nil else { return }

        guard provider.startListening(configuration: configuration) else { return }
        let configuration = self.configuration
        monitorTask = Task { [provider, onTrigger] in
            var machines: [String: GestureStateMachine] = [:]
            var lastTriggeredAt: TimeInterval = 0
            for await frame in provider.touchDataStream {
                if Task.isCancelled { break }
                var machine = machines[frame.deviceID] ?? GestureStateMachine(configuration: configuration)
                if let action = machine.consume(samples: frame.samples) {
                    let now = ProcessInfo.processInfo.systemUptime
                    guard now - lastTriggeredAt >= configuration.cooldownDuration else {
                        machines[frame.deviceID] = machine
                        continue
                    }
                    lastTriggeredAt = now
                    await MainActor.run {
                        onTrigger(action)
                    }
                }
                machines[frame.deviceID] = machine
            }
        }
    }

    func restart() {
        stop()
        start()
    }

    func stop() {
        monitorTask?.cancel()
        monitorTask = nil
        _ = provider.stopListening()
    }
}
