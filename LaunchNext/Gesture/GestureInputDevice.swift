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
}

extension OMSDeviceInfo {
    var isGestureTrackpadCandidate: Bool {
        deviceName.localizedCaseInsensitiveContains("Trackpad")
    }
}
