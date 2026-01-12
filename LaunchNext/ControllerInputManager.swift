import Foundation
import Combine
import GameController

enum ControllerCommand {
    enum Direction {
        case left
        case right
        case up
        case down
    }

    case move(Direction)
    case moveRepeat(Direction)
    case stop(Direction)
    case select
    case cancel
    case menu
}

final class ControllerInputManager: ObservableObject {
    static let shared = ControllerInputManager()

    private struct DirectionState {
        var horizontal: Int = 0
        var vertical: Int = 0
        var repeatTimers: [ControllerCommand.Direction: DispatchSourceTimer] = [:]
    }

    private let axisThreshold: Float = 0.6
    private let commandSubject = PassthroughSubject<ControllerCommand, Never>()

    private var observers: [NSObjectProtocol] = []
    private var directionStates: [ObjectIdentifier: DirectionState] = [:]
    private var isRunning = false

    var isActive: Bool { isRunning }

    @Published private(set) var connectedControllerNames: [String] = []

    var commands: AnyPublisher<ControllerCommand, Never> {
        commandSubject.eraseToAnyPublisher()
    }

    private init() {}

    func start() {
        guard !isRunning else { return }
        isRunning = true

        registerNotificationObservers()
        GCController.controllers().forEach { attachHandlers(to: $0) }
        refreshConnectedControllerNames()
        GCController.startWirelessControllerDiscovery(completionHandler: nil)
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false

        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()

        GCController.controllers().forEach { detachHandlers(from: $0) }
        for (_, state) in directionStates {
            for (_, timer) in state.repeatTimers {
                timer.cancel()
            }
        }
        directionStates.removeAll()
        refreshConnectedControllerNames()
        GCController.stopWirelessControllerDiscovery()
    }

    // MARK: - Notifications

    private func registerNotificationObservers() {
        let center = NotificationCenter.default

        let connect = center.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] notification in
            guard let controller = notification.object as? GCController else { return }
            self?.attachHandlers(to: controller)
            self?.refreshConnectedControllerNames()
        }

        let disconnect = center.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { [weak self] notification in
            guard let controller = notification.object as? GCController else { return }
            self?.detachHandlers(from: controller)
            self?.refreshConnectedControllerNames()
        }

        observers.append(contentsOf: [connect, disconnect])
    }

    // MARK: - Controller Handling

    private func attachHandlers(to controller: GCController) {
        let identifier = ObjectIdentifier(controller)
        directionStates[identifier] = DirectionState()

        controller.controllerPausedHandler = { [weak self] _ in
            self?.emit(.cancel)
        }

        if let extended = controller.extendedGamepad {
            configure(gamepad: extended, controller: controller)
        }

        if let micro = controller.microGamepad {
            configure(microGamepad: micro, controller: controller)
        }
    }

    private func detachHandlers(from controller: GCController) {
        let identifier = ObjectIdentifier(controller)
        if let state = directionStates.removeValue(forKey: identifier) {
            for (direction, timer) in state.repeatTimers {
                timer.cancel()
                emit(.stop(direction))
            }
        }

        controller.controllerPausedHandler = nil

        if let extended = controller.extendedGamepad {
            extended.dpad.valueChangedHandler = nil
            extended.leftThumbstick.valueChangedHandler = nil
            extended.buttonA.valueChangedHandler = nil
            extended.buttonB.valueChangedHandler = nil
            if #available(macOS 11.3, *) {
                extended.buttonMenu.valueChangedHandler = nil
            }
        }

        if let micro = controller.microGamepad {
            micro.dpad.valueChangedHandler = nil
            micro.buttonA.valueChangedHandler = nil
            if #available(macOS 11.3, *) {
                micro.buttonMenu.valueChangedHandler = nil
            }
        }
    }

    private func configure(gamepad: GCExtendedGamepad, controller: GCController) {
        gamepad.dpad.valueChangedHandler = { [weak self, weak controller] _, xValue, yValue in
            guard let controller else { return }
            self?.handleDirectionalInput(from: controller, horizontal: xValue, vertical: yValue)
        }

        gamepad.leftThumbstick.valueChangedHandler = { [weak self, weak controller] _, xValue, yValue in
            guard let controller else { return }
            self?.handleDirectionalInput(from: controller, horizontal: xValue, vertical: yValue)
        }

        gamepad.buttonA.valueChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            self?.emit(.select)
        }

        gamepad.buttonB.valueChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            self?.emit(.cancel)
        }

        if #available(macOS 11.3, *) {
            gamepad.buttonMenu.valueChangedHandler = { [weak self] _, _, pressed in
                guard pressed else { return }
                self?.emit(.menu)
            }
        }
    }

    private func configure(microGamepad: GCMicroGamepad, controller: GCController) {
        microGamepad.allowsRotation = true

        microGamepad.dpad.valueChangedHandler = { [weak self, weak controller] _, xValue, yValue in
            guard let controller else { return }
            self?.handleDirectionalInput(from: controller, horizontal: xValue, vertical: yValue)
        }

        microGamepad.buttonA.valueChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            self?.emit(.select)
        }

        if #available(macOS 11.3, *) {
            microGamepad.buttonMenu.valueChangedHandler = { [weak self] _, _, pressed in
                guard pressed else { return }
                self?.emit(.menu)
            }
        }
    }

    private func handleDirectionalInput(from controller: GCController, horizontal: Float?, vertical: Float?) {
        let identifier = ObjectIdentifier(controller)
        var state = directionStates[identifier] ?? DirectionState()

        if let horizontal {
            let direction = discreteDirection(from: horizontal)
            state = updateState(state,
                                for: identifier,
                                axis: .horizontal,
                                newValue: direction)
        }

        if let vertical {
            let direction = discreteDirection(from: vertical)
            state = updateState(state,
                                for: identifier,
                                axis: .vertical,
                                newValue: direction)
        }

        directionStates[identifier] = state
    }

    private enum Axis {
        case horizontal
        case vertical
    }

    private func discreteDirection(from value: Float) -> Int {
        if value >= axisThreshold { return 1 }
        if value <= -axisThreshold { return -1 }
        return 0
    }

    private func direction(for axis: Axis, value: Int) -> ControllerCommand.Direction? {
        guard value != 0 else { return nil }
        switch axis {
        case .horizontal:
            return value == -1 ? .left : .right
        case .vertical:
            return value == 1 ? .up : .down
        }
    }

    private func updateState(_ state: DirectionState,
                             for identifier: ObjectIdentifier,
                             axis: Axis,
                             newValue: Int) -> DirectionState {
        var updated = state

        let oldValue: Int
        switch axis {
        case .horizontal:
            oldValue = state.horizontal
            updated.horizontal = newValue
        case .vertical:
            oldValue = state.vertical
            updated.vertical = newValue
        }

        if oldValue == newValue { return updated }

        if let oldDirection = direction(for: axis, value: oldValue) {
            cancelRepeat(state: &updated, direction: oldDirection)
            emit(.stop(oldDirection))
        }

        if let newDirection = direction(for: axis, value: newValue) {
            emit(.move(newDirection))
            startRepeat(state: &updated, direction: newDirection)
        }

        return updated
    }

    private func startRepeat(state: inout DirectionState, direction: ControllerCommand.Direction) {
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
        timer.schedule(deadline: .now() + 0.25, repeating: 0.14)
        timer.setEventHandler { [weak self] in
            self?.emit(.moveRepeat(direction))
        }
        state.repeatTimers[direction] = timer
        timer.resume()
    }

    private func cancelRepeat(state: inout DirectionState, direction: ControllerCommand.Direction) {
        if let timer = state.repeatTimers.removeValue(forKey: direction) {
            timer.cancel()
        }
    }

    private func emit(_ command: ControllerCommand) {
        DispatchQueue.main.async { [weak self] in
            self?.commandSubject.send(command)
        }
    }

    private func refreshConnectedControllerNames() {
        let controllers = GCController.controllers()
        let names = controllers.enumerated().map { index, controller -> String in
            let trimmed = controller.vendorName?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let trimmed, !trimmed.isEmpty {
                return trimmed
            }
            return String(format: "Controller %d", index + 1)
        }

        DispatchQueue.main.async { [weak self] in
            self?.connectedControllerNames = names
        }
    }
}
