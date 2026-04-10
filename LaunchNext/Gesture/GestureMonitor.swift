import Foundation

enum GestureMonitorEvent {
    case preview(GesturePreviewState)
    case clearPreview
    case gestureEnded
    case trigger(GestureTriggerAction)
}

final class GestureMonitor {
    typealias Configuration = GestureConfiguration

    private let provider = GestureTouchProvider()
    private let onEvent: (GestureMonitorEvent) -> Void
    private var configuration: Configuration
    private var monitorTask: Task<Void, Never>?

    init(configuration: Configuration, onEvent: @escaping (GestureMonitorEvent) -> Void) {
        self.configuration = configuration
        self.onEvent = onEvent
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

        guard provider.startListening() else { return }
        let configuration = self.configuration
        monitorTask = Task { [provider, onEvent] in
            var machine = GestureStateMachine(configuration: configuration)
            var lastPreview: GesturePreviewState?
            for await samples in provider.touchDataStream {
                if Task.isCancelled { break }
                if let action = machine.consume(samples: samples) {
                    lastPreview = nil
                    await MainActor.run {
                        onEvent(.trigger(action))
                    }
                    continue
                }

                let preview = machine.previewState
                guard preview != lastPreview else { continue }
                lastPreview = preview
                await MainActor.run {
                    if let preview {
                        onEvent(.preview(preview))
                    } else {
                        onEvent(.clearPreview)
                        if samples.isEmpty {
                            onEvent(.gestureEnded)
                        }
                    }
                }
            }

            if lastPreview != nil {
                await MainActor.run {
                    onEvent(.clearPreview)
                    onEvent(.gestureEnded)
                }
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
