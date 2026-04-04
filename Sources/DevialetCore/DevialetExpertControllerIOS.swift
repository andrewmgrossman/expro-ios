import Foundation

public final class DevialetExpertControllerIOS: AmpControlling, @unchecked Sendable {
    private enum DefaultsKey {
        static let cachedIP = "devialet.cached.ip"
        static let cachedStatus = "devialet.cached.status"
    }

    private let transport: DevialetTransporting
    private let protocolCodec: DevialetProtocol
    private let userDefaults: UserDefaults
    private let lock = NSLock()
    private let confirmationTimeout: TimeInterval = 3.0

    private var packetCounter: UInt8 = 0
    private var currentStatus: AmpStatus?
    private var knownIPAddress: String?
    private var listenerStarted = false
    private var lastPacketReceivedAt: Date?
    private var listenerRestartCount = 0
    private var lastTransportError: String?
    private var lastCommandDiagnostics: AmpCommandDiagnostics?
    private var pendingCommand: PendingCommand?
    private var streamContinuations: [UUID: AsyncStream<AmpStatus>.Continuation] = [:]
    private var pendingStatusWaiters: [UUID: CheckedContinuation<AmpStatus, Error>] = [:]

    private struct PendingCommand {
        let command: AmpCommand
        let diagnostics: AmpCommandDiagnostics
    }

    public init(
        transport: DevialetTransporting = DevialetTransport(),
        protocolCodec: DevialetProtocol = DevialetProtocol(),
        userDefaults: UserDefaults = .standard
    ) {
        self.transport = transport
        self.protocolCodec = protocolCodec
        self.userDefaults = userDefaults

        if let ip = userDefaults.string(forKey: DefaultsKey.cachedIP), !ip.isEmpty {
            knownIPAddress = ip
        }

        if let data = userDefaults.data(forKey: DefaultsKey.cachedStatus),
           let status = try? JSONDecoder().decode(AmpStatus.self, from: data) {
            currentStatus = status
        }
    }

    deinit {
        transport.stopStatusListener()
    }

    public func startStatusStream() -> AsyncStream<AmpStatus> {
        do {
            try startListenerIfNeeded()
        } catch {
            return AsyncStream { continuation in
                continuation.finish()
            }
        }

        let id = UUID()
        return AsyncStream { continuation in
            lock.withLock {
                streamContinuations[id] = continuation
                if let currentStatus {
                    continuation.yield(currentStatus)
                }
            }

            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                self.lock.withLock {
                    self.streamContinuations.removeValue(forKey: id)
                }
            }
        }
    }

    public func discover(timeout: TimeInterval = 3.0) async throws -> AmpStatus {
        do {
            return try await getLiveStatus(timeout: timeout)
        } catch {
            throw AmpControlError.discoveryTimeout(seconds: timeout)
        }
    }

    public func getCurrentStatus(timeout: TimeInterval = 2.0, requireLiveData: Bool = false) async throws -> AmpStatus {
        try startListenerIfNeeded()

        if !requireLiveData, isCurrentStatusFresh {
            return lock.withLock { currentStatus! }
        }

        do {
            return try await getLiveStatus(timeout: timeout)
        } catch {
            if !requireLiveData, let cached = lock.withLock({ currentStatus }) {
                expirePendingCommandIfNeeded()
                return cached
            }
            throw AmpControlError.statusTimeout(seconds: timeout)
        }
    }

    public func currentDiagnostics() -> AmpControllerDiagnostics {
        expirePendingCommandIfNeeded()
        return lock.withLock {
            AmpControllerDiagnostics(
                listenerActive: listenerStarted,
                lastRealPacketAt: lastPacketReceivedAt,
                listenerRestartCount: listenerRestartCount,
                lastTransportError: lastTransportError,
                lastKnownIPAddress: knownIPAddress ?? currentStatus?.ipAddress,
                lastCommand: lastCommandDiagnostics
            )
        }
    }

    public func send(_ command: AmpCommand) async throws {
        try startListenerIfNeeded()

        var resolvedCommand = command
        var statusForValidation = lock.withLock { currentStatus }

        switch command {
        case .togglePower:
            let status = try await getCurrentStatus(timeout: 2.0, requireLiveData: true)
            resolvedCommand = status.powerOn ? .powerOff : .powerOn
            statusForValidation = status

        case .toggleMute:
            let status = try await getCurrentStatus(timeout: 2.0, requireLiveData: true)
            resolvedCommand = status.muted ? .unmute : .mute
            statusForValidation = status

        case .setChannel:
            if statusForValidation == nil {
                statusForValidation = try await getCurrentStatus(timeout: 2.0, requireLiveData: true)
            }

        default:
            break
        }

        let targetIP = try await resolveIPAddress(timeout: 3.0)
        let basePacket = try protocolCodec.makeCommandPacket(for: resolvedCommand, status: statusForValidation)
        let sentAt = Date()

        do {
            try await sendReliably(basePacket: basePacket, ipAddress: targetIP)
        } catch {
            clearCachedIP()
            let rediscovered = try await discover(timeout: 3.0)
            try await sendReliably(basePacket: basePacket, ipAddress: rediscovered.ipAddress)
        }

        recordPendingCommand(resolvedCommand, sentAt: sentAt)
        applyOptimisticUpdate(for: resolvedCommand)
    }

    private var isCurrentStatusFresh: Bool {
        lock.withLock {
            guard currentStatus != nil, let lastPacketReceivedAt else { return false }
            return Date().timeIntervalSince(lastPacketReceivedAt) < 1.5
        }
    }

    private func getLiveStatus(timeout: TimeInterval) async throws -> AmpStatus {
        try startListenerIfNeeded()

        do {
            return try await waitForNextStatus(timeout: timeout)
        } catch {
            recoverListener(reason: "Status stream stalled")
            try startListenerIfNeeded()
            return try await waitForNextStatus(timeout: timeout)
        }
    }

    private func sendReliably(basePacket: Data, ipAddress: String) async throws {
        for _ in 0..<4 {
            let counter = lock.withLock { () -> UInt8 in
                defer { packetCounter &+= 1 }
                return packetCounter
            }

            let packet = protocolCodec.applyPacketCounterAndCRC(to: basePacket, packetCounter: counter)
            try await transport.send(packet: packet, to: ipAddress)
        }
    }

    private func waitForNextStatus(timeout: TimeInterval) async throws -> AmpStatus {
        try await withCheckedThrowingContinuation { continuation in
            let id = UUID()
            lock.withLock {
                pendingStatusWaiters[id] = continuation
            }

            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [weak self] in
                guard let self else { return }

                let waiter = self.lock.withLock { self.pendingStatusWaiters.removeValue(forKey: id) }
                waiter?.resume(throwing: AmpControlError.statusTimeout(seconds: timeout))
            }
        }
    }

    private func startListenerIfNeeded() throws {
        let alreadyStarted = lock.withLock { listenerStarted }
        if alreadyStarted { return }

        try transport.startStatusListener { [weak self] packet, packetIP in
            self?.handleStatusPacket(packet: packet, ipAddress: packetIP)
        } onError: { [weak self] error in
            self?.recoverListener(reason: error.localizedDescription)
        }

        lock.withLock {
            listenerStarted = true
            lastTransportError = nil
        }
    }

    private func handleStatusPacket(packet: Data, ipAddress: String?) {
        let fallbackIP = lock.withLock { knownIPAddress } ?? ""
        let sourceIP = ipAddress ?? fallbackIP

        guard !sourceIP.isEmpty,
              let status = try? protocolCodec.decodeStatus(packet: packet, ipAddress: sourceIP) else {
            return
        }

        let receivedAt = Date()
        cache(status: status, receivedAt: receivedAt)
        confirmPendingCommandIfNeeded(with: status, receivedAt: receivedAt)

        let continuations: [AsyncStream<AmpStatus>.Continuation]
        let waiters: [CheckedContinuation<AmpStatus, Error>]

        continuations = lock.withLock {
            Array(streamContinuations.values)
        }

        waiters = lock.withLock {
            let all = Array(pendingStatusWaiters.values)
            pendingStatusWaiters.removeAll()
            return all
        }

        continuations.forEach { $0.yield(status) }
        waiters.forEach { $0.resume(returning: status) }
    }

    private func resolveIPAddress(timeout: TimeInterval) async throws -> String {
        if let ip = lock.withLock({ knownIPAddress }), !ip.isEmpty {
            return ip
        }

        if let status = lock.withLock({ currentStatus }) {
            return status.ipAddress
        }

        let discovered = try await discover(timeout: timeout)
        return discovered.ipAddress
    }

    private func applyOptimisticUpdate(for command: AmpCommand) {
        guard var status = lock.withLock({ currentStatus }) else { return }

        switch command {
        case .powerOn:
            status.powerOn = true
        case .powerOff:
            status.powerOn = false
        case .setVolume(let value):
            status.volumeDb = SafetyPolicy.normalizeToHalfDbStep(value)
        case .mute:
            status.muted = true
        case .unmute:
            status.muted = false
        case .setChannel(let channel):
            status.currentChannel = channel
        case .togglePower, .toggleMute:
            break
        }

        project(status: status)

        let continuations = lock.withLock { Array(streamContinuations.values) }
        continuations.forEach { $0.yield(status) }
    }

    private func project(status: AmpStatus) {
        lock.withLock {
            currentStatus = status
            knownIPAddress = status.ipAddress
        }
    }

    private func cache(status: AmpStatus, receivedAt: Date?) {
        project(status: status)
        lock.withLock {
            if let receivedAt {
                lastPacketReceivedAt = receivedAt
            }
        }

        userDefaults.set(status.ipAddress, forKey: DefaultsKey.cachedIP)

        if let data = try? JSONEncoder().encode(status) {
            userDefaults.set(data, forKey: DefaultsKey.cachedStatus)
        }
    }

    private func clearCachedIP() {
        lock.withLock {
            knownIPAddress = nil
        }
        userDefaults.removeObject(forKey: DefaultsKey.cachedIP)
    }

    private func recoverListener(reason: String) {
        let shouldRestart = lock.withLock { listenerStarted }
        transport.stopStatusListener()

        lock.withLock {
            if shouldRestart {
                listenerRestartCount += 1
            }
            listenerStarted = false
            lastTransportError = reason
        }
    }

    private func recordPendingCommand(_ command: AmpCommand, sentAt: Date) {
        let diagnostics = AmpCommandDiagnostics(
            summary: command.summary,
            sentAt: sentAt,
            state: .pending
        )

        lock.withLock {
            lastCommandDiagnostics = diagnostics
            pendingCommand = PendingCommand(command: command, diagnostics: diagnostics)
        }
    }

    private func confirmPendingCommandIfNeeded(with status: AmpStatus, receivedAt: Date) {
        lock.withLock {
            guard let pendingCommand else { return }

            if pendingCommand.command.matches(status: status) {
                var confirmed = pendingCommand.diagnostics
                confirmed.state = .confirmed
                confirmed.confirmedAt = receivedAt
                lastCommandDiagnostics = confirmed
                self.pendingCommand = nil
            } else if receivedAt.timeIntervalSince(pendingCommand.diagnostics.sentAt) >= confirmationTimeout {
                var unconfirmed = pendingCommand.diagnostics
                unconfirmed.state = .unconfirmed
                lastCommandDiagnostics = unconfirmed
                self.pendingCommand = nil
            }
        }
    }

    private func expirePendingCommandIfNeeded() {
        lock.withLock {
            guard let pendingCommand else { return }
            guard Date().timeIntervalSince(pendingCommand.diagnostics.sentAt) >= confirmationTimeout else { return }

            var unconfirmed = pendingCommand.diagnostics
            unconfirmed.state = .unconfirmed
            lastCommandDiagnostics = unconfirmed
            self.pendingCommand = nil
        }
    }
}

private extension NSLock {
    @discardableResult
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}

private extension AmpCommand {
    var summary: String {
        switch self {
        case .powerOn:
            return "Power on"
        case .powerOff:
            return "Power off"
        case .togglePower:
            return "Toggle power"
        case .setVolume(let value):
            return String(format: "Set volume to %.1f dB", SafetyPolicy.normalizeToHalfDbStep(value))
        case .mute:
            return "Mute"
        case .unmute:
            return "Unmute"
        case .toggleMute:
            return "Toggle mute"
        case .setChannel(let slot):
            return "Switch to input \(slot)"
        }
    }

    func matches(status: AmpStatus) -> Bool {
        switch self {
        case .powerOn:
            return status.powerOn
        case .powerOff:
            return !status.powerOn
        case .setVolume(let value):
            return abs(status.volumeDb - SafetyPolicy.normalizeToHalfDbStep(value)) < 0.001
        case .mute:
            return status.muted
        case .unmute:
            return !status.muted
        case .setChannel(let slot):
            return status.currentChannel == slot
        case .togglePower, .toggleMute:
            return false
        }
    }
}
