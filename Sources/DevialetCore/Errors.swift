import Foundation

public enum AmpControlError: Error, LocalizedError, Sendable {
    case invalidStatusPacket(length: Int)
    case decodeFailed(reason: String)
    case discoveryTimeout(seconds: TimeInterval)
    case statusTimeout(seconds: TimeInterval)
    case missingAmplifierIPAddress
    case invalidVolume(Double)
    case invalidChannel(Int)
    case noKnownStatus
    case listenerStartupFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidStatusPacket(let length):
            return "Invalid status packet length: \(length). Expected at least 566 bytes."
        case .decodeFailed(let reason):
            return "Status decode failed: \(reason)"
        case .discoveryTimeout(let seconds):
            return "No Devialet amplifier discovered after \(seconds)s"
        case .statusTimeout(let seconds):
            return "Timed out waiting for status update after \(seconds)s"
        case .missingAmplifierIPAddress:
            return "No amplifier IP address available. Discover amplifier first."
        case .invalidVolume(let db):
            return "Invalid volume \(db). Expected between -96.0 and 30.0 dB."
        case .invalidChannel(let channel):
            return "Invalid or unavailable channel \(channel)."
        case .noKnownStatus:
            return "No known amplifier status."
        case .listenerStartupFailed(let message):
            return "Failed to start UDP status listener: \(message)"
        }
    }
}
