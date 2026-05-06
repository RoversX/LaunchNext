import Foundation

enum GestureDeviceSelectionMode: String, CaseIterable, Codable, Identifiable {
    case automatic
    case selected

    var id: String { rawValue }
}

struct GestureInputDevice: Identifiable, Hashable {
    let id: String
    let name: String
    let isBuiltIn: Bool
    let kind: GestureInputDeviceKind
    let familyID: Int
    let sensorSurfaceWidth: Int
    let sensorSurfaceHeight: Int
    let isRecommended: Bool
}

enum GestureInputDeviceKind: String, Hashable {
    case trackpad
    case mouse
    case touchBar
    case unknown
}

extension OMSDeviceInfo {
    var isGestureTrackpadCandidate: Bool {
        isTrackpad || deviceName.localizedCaseInsensitiveContains("Trackpad")
    }

    var isRecommendedGestureDevice: Bool {
        isGestureTrackpadCandidate && gestureInputDeviceKind == .trackpad
    }

    var gestureInputDeviceKind: GestureInputDeviceKind {
        if deviceName.localizedCaseInsensitiveContains("Touch Bar") {
            return .touchBar
        }
        if deviceName.localizedCaseInsensitiveContains("Mouse") {
            return .mouse
        }
        if isGestureTrackpadCandidate {
            return .trackpad
        }
        return .unknown
    }
}
