import Foundation

struct GestureConfiguration: Equatable {
    var isEnabled: Bool
    var closeOnPinchOutEnabled: Bool = false
    var tapEnabled: Bool = false
    var tapTogglesWindow: Bool = false
    var requiredFingerCount: Int = 4
    var stableContactDuration: TimeInterval = 0.03
    var openTriggerScaleRatio: Double = 0.84
    var closeTriggerScaleRatio: Double = 1.06
    var openPerFingerRadiusRatio: Double = 0.96
    var closeLeadingFingerRadiusRatio: Double = 1.12
    var minimumOpenParticipatingFingerCount: Int = 3
    var minimumCloseLeadingGap: Double = 0.06
    var maximumCloseSupportingSpread: Double = 0.22
    var requiredConsecutiveMatches: Int = 2
    var cooldownDuration: TimeInterval = 0.85
    var maximumCentroidDriftRatio: Double = 0.55
    var minimumBaselineScale: Double = 0.10
    var tapMaxDuration: TimeInterval = 0.20
    var tapMaxFingerMovement: Double = 0.045
    var tapMaxScaleDeviation: Double = 0.10
}
