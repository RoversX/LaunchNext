import SwiftUI

enum LNAnimations {
    // MARK: - Springs - 优化性能的动画配置
    static var springFast: Animation {
        guard AnimationPreferences.isEnabled else { return .linear(duration: 0.0001) }
        return .spring(response: AnimationPreferences.springResponse, dampingFraction: 0.8)
    }

    /// The response of springFast. With its damping, the motion has settled by then.
    static var springFastResponse: TimeInterval { AnimationPreferences.springResponse }
    
    // MARK: - 性能优化的动画
    static var dragPreview: Animation {
        guard AnimationPreferences.isEnabled else { return .linear(duration: 0.0001) }
        return .easeOut(duration: AnimationPreferences.baseDuration)
    }
    static var gridUpdate: Animation {
        guard AnimationPreferences.isEnabled else { return .linear(duration: 0.0001) }
        return .easeInOut(duration: AnimationPreferences.baseDuration)
    }
    
    // MARK: - Transitions
    static var folderOpenTransition: AnyTransition {
        if AnimationPreferences.isEnabled {
            return AnyTransition.scale(scale: 0.95).combined(with: .opacity)
        } else {
            return AnyTransition.opacity
        }
    }
}

private enum AnimationPreferences {
    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: "enableAnimations") as? Bool ?? true
    }

    static var baseDuration: Double {
        let stored = UserDefaults.standard.double(forKey: "animationDuration")
        let value = stored == 0 ? 0.3 : stored
        return max(0.05, min(value, 1.5))
    }

    static var springResponse: Double {
        max(0.15, baseDuration)
    }
}
