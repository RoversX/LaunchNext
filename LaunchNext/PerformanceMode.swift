import Foundation

enum PerformanceMode: String, CaseIterable, Identifiable {
    case full
    case lean

    var id: String { rawValue }

    static let userDefaultsKey = "performanceMode"

    private static let activeMode: PerformanceMode = {
        if let raw = UserDefaults.standard.string(forKey: userDefaultsKey),
           let mode = PerformanceMode(rawValue: raw) {
            return mode
        }
        return .full
    }()

    static var current: PerformanceMode { activeMode }

    static func persist(_ mode: PerformanceMode) {
        UserDefaults.standard.set(mode.rawValue, forKey: userDefaultsKey)
    }
}
