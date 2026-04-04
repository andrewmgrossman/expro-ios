import Foundation

public enum AmpCommandConfirmationState: String, Codable, Equatable, Sendable {
    case pending
    case confirmed
    case unconfirmed
}

public struct AmpCommandDiagnostics: Codable, Equatable, Sendable {
    public var summary: String
    public var sentAt: Date
    public var state: AmpCommandConfirmationState
    public var confirmedAt: Date?

    public init(
        summary: String,
        sentAt: Date,
        state: AmpCommandConfirmationState,
        confirmedAt: Date? = nil
    ) {
        self.summary = summary
        self.sentAt = sentAt
        self.state = state
        self.confirmedAt = confirmedAt
    }
}

public struct AmpControllerDiagnostics: Codable, Equatable, Sendable {
    public var listenerActive: Bool
    public var lastRealPacketAt: Date?
    public var listenerRestartCount: Int
    public var lastTransportError: String?
    public var lastKnownIPAddress: String?
    public var lastCommand: AmpCommandDiagnostics?

    public init(
        listenerActive: Bool = false,
        lastRealPacketAt: Date? = nil,
        listenerRestartCount: Int = 0,
        lastTransportError: String? = nil,
        lastKnownIPAddress: String? = nil,
        lastCommand: AmpCommandDiagnostics? = nil
    ) {
        self.listenerActive = listenerActive
        self.lastRealPacketAt = lastRealPacketAt
        self.listenerRestartCount = listenerRestartCount
        self.lastTransportError = lastTransportError
        self.lastKnownIPAddress = lastKnownIPAddress
        self.lastCommand = lastCommand
    }
}
