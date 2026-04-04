import Foundation

public struct AmpChannel: Codable, Hashable, Identifiable, Sendable {
    public let slot: Int
    public let name: String
    public let isEnabled: Bool

    public var id: Int { slot }

    public init(slot: Int, name: String, isEnabled: Bool = true) {
        self.slot = slot
        self.name = name
        self.isEnabled = isEnabled
    }
}

public struct AmpStatus: Codable, Equatable, Sendable {
    public var deviceName: String
    public var ipAddress: String
    public var powerOn: Bool
    public var muted: Bool
    public var currentChannel: Int
    public var volumeDb: Double
    public var channels: [AmpChannel]
    public var lastUpdated: Date

    public init(
        deviceName: String,
        ipAddress: String,
        powerOn: Bool,
        muted: Bool,
        currentChannel: Int,
        volumeDb: Double,
        channels: [AmpChannel],
        lastUpdated: Date = Date()
    ) {
        self.deviceName = deviceName
        self.ipAddress = ipAddress
        self.powerOn = powerOn
        self.muted = muted
        self.currentChannel = currentChannel
        self.volumeDb = volumeDb
        self.channels = channels.sorted(by: { $0.slot < $1.slot })
        self.lastUpdated = lastUpdated
    }

    public var channelMap: [Int: String] {
        Dictionary(uniqueKeysWithValues: channels.map { ($0.slot, $0.name) })
    }
}

public enum AmpCommand: Sendable, Equatable {
    case powerOn
    case powerOff
    case togglePower
    case setVolume(Double)
    case mute
    case unmute
    case toggleMute
    case setChannel(Int)
}

public protocol AmpControlling: AnyObject, Sendable {
    func discover(timeout: TimeInterval) async throws -> AmpStatus
    func getCurrentStatus(timeout: TimeInterval, requireLiveData: Bool) async throws -> AmpStatus
    func startStatusStream() -> AsyncStream<AmpStatus>
    func send(_ command: AmpCommand) async throws
    func currentDiagnostics() -> AmpControllerDiagnostics
}

public extension AmpControlling {
    func getCurrentStatus(timeout: TimeInterval = 2.0) async throws -> AmpStatus {
        try await getCurrentStatus(timeout: timeout, requireLiveData: false)
    }
}
