import Foundation

public enum SafetyPolicy {
    public static let minVolumeDb: Double = -96.0
    public static let maxVolumeDb: Double = 0.0
    public static let volumeDebounceInterval: TimeInterval = 0.25

    public static func clampVolume(_ value: Double) -> Double {
        min(max(value, minVolumeDb), maxVolumeDb)
    }

    public static func normalizeToHalfDbStep(_ value: Double) -> Double {
        let clamped = clampVolume(value)
        return (clamped * 2.0).rounded() / 2.0
    }
}
