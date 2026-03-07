import DevialetCore
import Foundation

struct VolumeSettings: Codable, Equatable {
    static let allowedStepValues: [Double] = [0.5, 1.0, 2.0]

    static let defaults = VolumeSettings(
        sliderMinDb: -60.0,
        sliderMaxDb: 0.0,
        presetDb: -20.0,
        volumeStepDb: 1.0
    )

    var sliderMinDb: Double
    var sliderMaxDb: Double
    var presetDb: Double
    var volumeStepDb: Double

    init(
        sliderMinDb: Double,
        sliderMaxDb: Double,
        presetDb: Double,
        volumeStepDb: Double = 1.0
    ) {
        self.sliderMinDb = sliderMinDb
        self.sliderMaxDb = sliderMaxDb
        self.presetDb = presetDb
        self.volumeStepDb = volumeStepDb
    }

    func normalized() -> VolumeSettings {
        var normalizedMin = min(max(sliderMinDb, SafetyPolicy.minVolumeDb), SafetyPolicy.maxVolumeDb)
        var normalizedMax = min(max(sliderMaxDb, SafetyPolicy.minVolumeDb), SafetyPolicy.maxVolumeDb)

        if normalizedMin >= normalizedMax {
            normalizedMax = min(SafetyPolicy.maxVolumeDb, normalizedMin + 0.5)
            if normalizedMin >= normalizedMax {
                normalizedMin = max(SafetyPolicy.minVolumeDb, normalizedMax - 0.5)
            }
        }

        let normalizedPreset = min(max(presetDb, normalizedMin), normalizedMax)
        let normalizedStep = Self.nearestStep(to: volumeStepDb)

        return VolumeSettings(
            sliderMinDb: SafetyPolicy.normalizeToHalfDbStep(normalizedMin),
            sliderMaxDb: SafetyPolicy.normalizeToHalfDbStep(normalizedMax),
            presetDb: SafetyPolicy.normalizeToHalfDbStep(normalizedPreset),
            volumeStepDb: normalizedStep
        )
    }

    func clampToSliderRange(_ value: Double) -> Double {
        min(max(value, sliderMinDb), sliderMaxDb)
    }

    private static func nearestStep(to value: Double) -> Double {
        allowedStepValues.min(by: { abs($0 - value) < abs($1 - value) }) ?? 1.0
    }

    private enum CodingKeys: String, CodingKey {
        case sliderMinDb
        case sliderMaxDb
        case presetDb
        case volumeStepDb
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sliderMinDb = try container.decode(Double.self, forKey: .sliderMinDb)
        sliderMaxDb = try container.decode(Double.self, forKey: .sliderMaxDb)
        presetDb = try container.decode(Double.self, forKey: .presetDb)
        volumeStepDb = try container.decodeIfPresent(Double.self, forKey: .volumeStepDb) ?? 1.0
    }
}
