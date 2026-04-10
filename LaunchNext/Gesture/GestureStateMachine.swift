import Foundation
import CoreGraphics

enum GestureTriggerAction {
    case open
    case close
    case toggle
}

struct GesturePreviewState: Equatable {
    let action: GestureTriggerAction
    let progress: CGFloat
}

struct GestureStateMachine {
    private struct TapMetrics {
        let initialPoints: [Int32: CGPoint]
        let baselineScale: Double
        let startedAt: TimeInterval
        var maxFingerMovement: Double
        var maxScaleDeviation: Double
    }

    private enum State {
        case idle
        case arming(ids: Set<Int32>, startedAt: TimeInterval, scales: [Double], centroids: [CGPoint], tapMetrics: TapMetrics)
        case tracking(
            ids: Set<Int32>,
            baselineScale: Double,
            baselineCentroid: CGPoint,
            baselineRadii: [Int32: Double],
            filteredScale: Double,
            candidateAction: GestureTriggerAction?,
            consecutiveMatches: Int,
            tapMetrics: TapMetrics
        )
        case cooldown(until: TimeInterval)
    }

    private var state: State = .idle
    private(set) var previewState: GesturePreviewState?
    private let configuration: GestureConfiguration
    private let smoothingAlpha = 0.7

    init(configuration: GestureConfiguration) {
        self.configuration = configuration
    }

    private func debugLog(_ message: String) {
        #if DEBUG
        print("[Gesture] \(message)")
        #endif
    }

    mutating func consume(samples: [GestureTouchSample], at time: TimeInterval = ProcessInfo.processInfo.systemUptime) -> GestureTriggerAction? {
        let touches = normalized(samples)

        switch state {
        case .idle:
            previewState = nil
            guard touches.count == configuration.requiredFingerCount else { return nil }
            let ids = Set(touches.map(\.id))
            let scale = scale(for: touches)
            let centroid = centroid(for: touches)
            state = .arming(
                ids: ids,
                startedAt: time,
                scales: [scale],
                centroids: [centroid],
                tapMetrics: TapMetrics(
                    initialPoints: Dictionary(uniqueKeysWithValues: touches.map { ($0.id, $0.point) }),
                    baselineScale: scale,
                    startedAt: time,
                    maxFingerMovement: 0,
                    maxScaleDeviation: 0
                )
            )
            debugLog("arming started scale=\(String(format: "%.3f", scale)) ids=\(ids.sorted().map(String.init).joined(separator: ","))")
            return nil

        case let .arming(ids, startedAt, scales, centroids, tapMetrics):
            if touches.isEmpty {
                previewState = nil
                if let action = tapAction(for: tapMetrics, endedAt: time) {
                    debugLog("tap recognized action=\(String(describing: action)) duration=\(String(format: "%.3f", time - tapMetrics.startedAt)) movement=\(String(format: "%.3f", tapMetrics.maxFingerMovement)) scaleDeviation=\(String(format: "%.3f", tapMetrics.maxScaleDeviation))")
                    state = .idle
                    return action
                }
                state = .idle
                return nil
            }

            guard touches.count == configuration.requiredFingerCount else {
                previewState = nil
                if touches.count < configuration.requiredFingerCount,
                   let action = tapAction(for: tapMetrics, endedAt: time) {
                    debugLog("tap recognized action=\(String(describing: action)) on finger release")
                    state = .idle
                    return action
                }
                state = .idle
                return nil
            }

            let currentIDs = Set(touches.map(\.id))
            guard currentIDs == ids else {
                previewState = nil
                let scale = scale(for: touches)
                let centroid = centroid(for: touches)
                state = .arming(
                    ids: currentIDs,
                    startedAt: time,
                    scales: [scale],
                    centroids: [centroid],
                    tapMetrics: TapMetrics(
                        initialPoints: Dictionary(uniqueKeysWithValues: touches.map { ($0.id, $0.point) }),
                        baselineScale: scale,
                        startedAt: time,
                        maxFingerMovement: 0,
                        maxScaleDeviation: 0
                    )
                )
                return nil
            }

            let updatedScales = appended(scales, value: scale(for: touches))
            let updatedCentroids = appended(centroids, value: centroid(for: touches))
            let updatedTapMetrics = updatedTapMetrics(from: tapMetrics, touches: touches)

            guard time - startedAt >= configuration.stableContactDuration else {
                previewState = nil
                state = .arming(
                    ids: ids,
                    startedAt: startedAt,
                    scales: updatedScales,
                    centroids: updatedCentroids,
                    tapMetrics: updatedTapMetrics
                )
                return nil
            }

            let baselineWindow = max(1, min(updatedScales.count, 2))
            let baselineScale = median(Array(updatedScales.prefix(baselineWindow)))
            guard baselineScale >= configuration.minimumBaselineScale else {
                previewState = nil
                state = .idle
                return nil
            }

            let baselineCentroid = average(Array(updatedCentroids.prefix(baselineWindow)))
            let baselineRadii = radii(for: touches, around: baselineCentroid)

            state = .tracking(
                ids: ids,
                baselineScale: baselineScale,
                baselineCentroid: baselineCentroid,
                baselineRadii: baselineRadii,
                filteredScale: baselineScale,
                candidateAction: nil,
                consecutiveMatches: 0,
                tapMetrics: updatedTapMetrics
            )
            debugLog("tracking baseline=\(String(format: "%.3f", baselineScale)) centroid=(\(String(format: "%.3f", baselineCentroid.x)),\(String(format: "%.3f", baselineCentroid.y)))")
            previewState = nil
            return nil

        case let .tracking(ids, baselineScale, baselineCentroid, baselineRadii, filteredScale, candidateAction, consecutiveMatches, tapMetrics):
            if touches.isEmpty {
                let lastPreview = previewState
                previewState = nil
                if let action = tapAction(for: tapMetrics, endedAt: time) {
                    state = .idle
                    return action
                }
                if let action = pinchActionOnRelease(lastPreview: lastPreview,
                                                    candidateAction: candidateAction,
                                                    consecutiveMatches: consecutiveMatches) {
                    debugLog("release action=\(String(describing: action))")
                    state = .idle
                    return action
                }
                state = .idle
                return nil
            }

            guard touches.count == configuration.requiredFingerCount else {
                let lastPreview = previewState
                previewState = nil
                if touches.count < configuration.requiredFingerCount,
                   let action = tapAction(for: tapMetrics, endedAt: time) {
                    debugLog("tap recognized action=\(String(describing: action)) on finger release")
                    state = .idle
                    return action
                }
                if touches.count < configuration.requiredFingerCount,
                   let action = pinchActionOnRelease(lastPreview: lastPreview,
                                                    candidateAction: candidateAction,
                                                    consecutiveMatches: consecutiveMatches) {
                    debugLog("release action=\(String(describing: action)) on finger release")
                    state = .idle
                    return action
                }
                state = .idle
                return nil
            }

            let currentIDs = Set(touches.map(\.id))
            guard currentIDs == ids else {
                previewState = nil
                let scale = scale(for: touches)
                let centroid = centroid(for: touches)
                state = .arming(
                    ids: currentIDs,
                    startedAt: time,
                    scales: [scale],
                    centroids: [centroid],
                    tapMetrics: TapMetrics(
                        initialPoints: Dictionary(uniqueKeysWithValues: touches.map { ($0.id, $0.point) }),
                        baselineScale: scale,
                        startedAt: time,
                        maxFingerMovement: 0,
                        maxScaleDeviation: 0
                    )
                )
                return nil
            }

            let currentScale = scale(for: touches)
            let smoothedScale = (filteredScale * smoothingAlpha) + (currentScale * (1 - smoothingAlpha))
            let scaleRatio = smoothedScale / baselineScale
            let currentCentroid = centroid(for: touches)
            let centroidDrift = distance(from: baselineCentroid, to: currentCentroid)
            let maxDrift = max(baselineScale * configuration.maximumCentroidDriftRatio, 0.04)
            let currentRadii = radii(for: touches, around: currentCentroid)
            let radialRatios = perFingerRadialRatios(currentRadii: currentRadii, baselineRadii: baselineRadii)
            let inwardFingerCount = radialRatios.filter { $0 <= configuration.openPerFingerRadiusRatio }.count
            let updatedTapMetrics = updatedTapMetrics(from: tapMetrics, touches: touches)
            let preview = makePreviewState(scaleRatio: scaleRatio,
                                           centroidDrift: centroidDrift,
                                           maxDrift: maxDrift,
                                           inwardFingerCount: inwardFingerCount)

            let nextAction: GestureTriggerAction?
            if centroidDrift <= maxDrift,
               scaleRatio <= configuration.openTriggerScaleRatio,
               inwardFingerCount >= configuration.minimumOpenParticipatingFingerCount {
                nextAction = .open
            } else if configuration.closeOnPinchOutEnabled,
                      centroidDrift <= maxDrift,
                      scaleRatio >= configuration.closeTriggerScaleRatio {
                nextAction = .close
            } else {
                nextAction = nil
            }

            let nextMatches: Int
            if let nextAction {
                nextMatches = nextAction == candidateAction ? (consecutiveMatches + 1) : 1
                if nextMatches >= configuration.requiredConsecutiveMatches {
                    debugLog("candidate action=\(String(describing: nextAction)) scaleRatio=\(String(format: "%.3f", scaleRatio)) centroidDrift=\(String(format: "%.3f", centroidDrift)) inwardCount=\(inwardFingerCount) matches=\(nextMatches)")
                }
            } else {
                nextMatches = 0
            }

            previewState = preview
            state = .tracking(
                ids: ids,
                baselineScale: baselineScale,
                baselineCentroid: baselineCentroid,
                baselineRadii: baselineRadii,
                filteredScale: smoothedScale,
                candidateAction: nextAction,
                consecutiveMatches: nextMatches,
                tapMetrics: updatedTapMetrics
            )
            return nil

        case let .cooldown(until):
            previewState = nil
            guard time >= until else { return nil }
            state = .idle
            if touches.isEmpty {
                return nil
            }
            return consume(samples: touches, at: time)
        }
    }

    private func makePreviewState(scaleRatio: Double,
                                  centroidDrift: Double,
                                  maxDrift: Double,
                                  inwardFingerCount: Int) -> GesturePreviewState? {
        let relaxedDriftLimit = maxDrift * 1.35

        if scaleRatio < 1 {
            guard centroidDrift <= relaxedDriftLimit else { return nil }
            let relaxedFingerCount = max(2, configuration.minimumOpenParticipatingFingerCount - 1)
            guard inwardFingerCount >= relaxedFingerCount else { return nil }
            let denominator = max(1 - configuration.openTriggerScaleRatio, 0.0001)
            let rawProgress = (1 - scaleRatio) / denominator
            let progress = easedPreviewProgress(rawProgress)
            guard progress > 0.01 else { return nil }
            return GesturePreviewState(action: .open, progress: progress)
        }

        guard configuration.closeOnPinchOutEnabled else { return nil }
        guard centroidDrift <= relaxedDriftLimit else { return nil }
        let previewStartScaleRatio = 1.002
        let previewTravelMultiplier = 2.0
        let denominator = max((configuration.closeTriggerScaleRatio - previewStartScaleRatio) * previewTravelMultiplier, 0.0001)
        let rawProgress = (scaleRatio - previewStartScaleRatio) / denominator
        guard rawProgress > 0.001 else { return nil }
        let progress = easedPreviewProgress(rawProgress)
        guard progress > 0.01 else { return nil }
        return GesturePreviewState(action: .close, progress: progress)
    }

    private func easedPreviewProgress(_ rawValue: Double) -> CGFloat {
        let clamped = min(max(rawValue, 0), 1)
        let eased = clamped * clamped * (3 - 2 * clamped)
        return CGFloat(eased)
    }

    private func pinchActionOnRelease(lastPreview: GesturePreviewState?,
                                      candidateAction: GestureTriggerAction?,
                                      consecutiveMatches: Int) -> GestureTriggerAction? {
        let releaseMatchThreshold = max(1, configuration.requiredConsecutiveMatches - 1)
        if let candidateAction, consecutiveMatches >= releaseMatchThreshold {
            return candidateAction
        }

        guard let lastPreview else { return nil }
        switch lastPreview.action {
        case .open where lastPreview.progress >= 0.16:
            return .open
        case .close where lastPreview.progress >= 0.14:
            return .close
        default:
            return nil
        }
    }

    private func normalized(_ samples: [GestureTouchSample]) -> [GestureTouchSample] {
        samples.sorted { lhs, rhs in lhs.id < rhs.id }
    }

    private func scale(for touches: [GestureTouchSample]) -> Double {
        guard touches.count > 1 else { return 0 }
        var distances: [Double] = []
        distances.reserveCapacity((touches.count * (touches.count - 1)) / 2)

        for index in touches.indices {
            for otherIndex in touches.indices where otherIndex > index {
                distances.append(distance(from: touches[index].point, to: touches[otherIndex].point))
            }
        }
        return median(distances)
    }

    private func centroid(for touches: [GestureTouchSample]) -> CGPoint {
        let total = touches.reduce(CGPoint.zero) { partial, touch in
            CGPoint(x: partial.x + touch.point.x, y: partial.y + touch.point.y)
        }
        let divisor = CGFloat(max(touches.count, 1))
        return CGPoint(x: total.x / divisor, y: total.y / divisor)
    }

    private func radii(for touches: [GestureTouchSample], around centroid: CGPoint) -> [Int32: Double] {
        Dictionary(uniqueKeysWithValues: touches.map { touch in
            (touch.id, distance(from: touch.point, to: centroid))
        })
    }

    private func perFingerRadialRatios(currentRadii: [Int32: Double], baselineRadii: [Int32: Double]) -> [Double] {
        currentRadii.compactMap { id, currentRadius in
            guard let baselineRadius = baselineRadii[id] else { return nil }
            return currentRadius / max(baselineRadius, 0.0001)
        }
    }

    private func updatedTapMetrics(from metrics: TapMetrics, touches: [GestureTouchSample]) -> TapMetrics {
        var updated = metrics
        let currentScale = scale(for: touches)
        let scaleDeviation = abs((currentScale / max(metrics.baselineScale, 0.0001)) - 1)
        let maxMovement = touches.reduce(0.0) { partial, touch in
            guard let initialPoint = metrics.initialPoints[touch.id] else { return partial }
            return max(partial, distance(from: touch.point, to: initialPoint))
        }
        updated.maxScaleDeviation = max(metrics.maxScaleDeviation, scaleDeviation)
        updated.maxFingerMovement = max(metrics.maxFingerMovement, maxMovement)
        return updated
    }

    private func tapAction(for metrics: TapMetrics, endedAt time: TimeInterval) -> GestureTriggerAction? {
        guard configuration.tapEnabled else { return nil }
        let duration = time - metrics.startedAt
        guard duration <= configuration.tapMaxDuration else {
            debugLog("tap rejected reason=duration duration=\(String(format: "%.3f", duration)) limit=\(String(format: "%.3f", configuration.tapMaxDuration)) movement=\(String(format: "%.3f", metrics.maxFingerMovement)) scaleDeviation=\(String(format: "%.3f", metrics.maxScaleDeviation))")
            return nil
        }
        guard metrics.maxFingerMovement <= configuration.tapMaxFingerMovement else {
            debugLog("tap rejected reason=movement duration=\(String(format: "%.3f", duration)) movement=\(String(format: "%.3f", metrics.maxFingerMovement)) limit=\(String(format: "%.3f", configuration.tapMaxFingerMovement)) scaleDeviation=\(String(format: "%.3f", metrics.maxScaleDeviation))")
            return nil
        }
        guard metrics.maxScaleDeviation <= configuration.tapMaxScaleDeviation else {
            debugLog("tap rejected reason=scaleDeviation duration=\(String(format: "%.3f", duration)) movement=\(String(format: "%.3f", metrics.maxFingerMovement)) scaleDeviation=\(String(format: "%.3f", metrics.maxScaleDeviation)) limit=\(String(format: "%.3f", configuration.tapMaxScaleDeviation))")
            return nil
        }
        return configuration.tapTogglesWindow ? .toggle : .open
    }

    private func average(_ points: [CGPoint]) -> CGPoint {
        guard !points.isEmpty else { return .zero }
        let total = points.reduce(CGPoint.zero) { partial, point in
            CGPoint(x: partial.x + point.x, y: partial.y + point.y)
        }
        let divisor = CGFloat(points.count)
        return CGPoint(x: total.x / divisor, y: total.y / divisor)
    }

    private func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }

    private func distance(from lhs: CGPoint, to rhs: CGPoint) -> Double {
        let dx = Double(lhs.x - rhs.x)
        let dy = Double(lhs.y - rhs.y)
        return sqrt((dx * dx) + (dy * dy))
    }

    private func appended<T>(_ values: [T], value: T, limit: Int = 6) -> [T] {
        let suffixCount = max(limit - 1, 0)
        return Array(values.suffix(suffixCount)) + [value]
    }
}
