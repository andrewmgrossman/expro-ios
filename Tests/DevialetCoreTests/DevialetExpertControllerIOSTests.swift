import XCTest
@testable import DevialetCore

final class DevialetExpertControllerIOSTests: XCTestCase {
    func testDiscoverReturnsStatusFromListenerPacket() async throws {
        let transport = MockTransport()
        let defaults = makeEphemeralDefaults()
        let controller = DevialetExpertControllerIOS(transport: transport, userDefaults: defaults)
        let fixture = try fixtureData(named: "status_fixture_1", ext: "bin")

        Task {
            try? await Task.sleep(nanoseconds: 100_000_000)
            transport.emitStatus(packet: fixture, ipAddress: "192.168.1.60")
        }

        let status = try await controller.discover(timeout: 1.0)
        XCTAssertEqual(status.ipAddress, "192.168.1.60")
        XCTAssertEqual(status.deviceName, "Expert 440 Pro")
    }

    func testSendMuteSendsFourPacketsWithIncrementingCounters() async throws {
        let transport = MockTransport()
        let defaults = makeEphemeralDefaults()
        let controller = DevialetExpertControllerIOS(transport: transport, userDefaults: defaults)
        let fixture = try fixtureData(named: "status_fixture_1", ext: "bin")

        Task {
            try? await Task.sleep(nanoseconds: 100_000_000)
            transport.emitStatus(packet: fixture, ipAddress: "192.168.1.61")
        }

        _ = try await controller.discover(timeout: 1.0)
        try await controller.send(.mute)

        let sent = transport.sentPackets
        XCTAssertEqual(sent.count, 4)

        XCTAssertEqual(sent[0].ipAddress, "192.168.1.61")
        XCTAssertEqual(sent[0].packet[7], 0x07)
        XCTAssertEqual(sent[0].packet[6], 0x01)

        XCTAssertEqual(sent[0].packet[3], 0)
        XCTAssertEqual(sent[1].packet[3], 1)
        XCTAssertEqual(sent[2].packet[3], 2)
        XCTAssertEqual(sent[3].packet[3], 3)
    }

    func testStatusStreamYieldsUpdates() async throws {
        let transport = MockTransport()
        let defaults = makeEphemeralDefaults()
        let controller = DevialetExpertControllerIOS(transport: transport, userDefaults: defaults)
        let fixture = try fixtureData(named: "status_fixture_1", ext: "bin")

        let stream = controller.startStatusStream()

        let task = Task { () -> AmpStatus? in
            var iterator = stream.makeAsyncIterator()
            return await iterator.next()
        }

        Task {
            try? await Task.sleep(nanoseconds: 100_000_000)
            transport.emitStatus(packet: fixture, ipAddress: "192.168.1.62")
        }

        let update = await task.value
        XCTAssertEqual(update?.ipAddress, "192.168.1.62")
    }

    func testForcedLiveRefreshWaitsForFreshPacketInsteadOfReturningCachedStatus() async throws {
        let defaults = makeEphemeralDefaults()
        let cachedStatus = AmpStatus(
            deviceName: "Cached Expert",
            ipAddress: "192.168.1.70",
            powerOn: true,
            muted: false,
            currentChannel: 2,
            volumeDb: -35.0,
            channels: [AmpChannel(slot: 2, name: "UPnP")]
        )

        defaults.set("192.168.1.70", forKey: "devialet.cached.ip")
        defaults.set(try JSONEncoder().encode(cachedStatus), forKey: "devialet.cached.status")

        let transport = MockTransport()
        let controller = DevialetExpertControllerIOS(transport: transport, userDefaults: defaults)
        let packet = try statusPacket(volumeDb: -18.0, channel: 4, channelName: "AirPlay")

        Task {
            try? await Task.sleep(nanoseconds: 100_000_000)
            transport.emitStatus(packet: packet, ipAddress: "192.168.1.70")
        }

        let live = try await controller.getCurrentStatus(timeout: 1.0, requireLiveData: true)
        XCTAssertEqual(live.volumeDb, -18.0, accuracy: 0.01)
        XCTAssertEqual(live.currentChannel, 4)
    }

    func testOptimisticUpdatesDoNotAdvanceLastRealPacketTimestamp() async throws {
        let transport = MockTransport()
        let defaults = makeEphemeralDefaults()
        let controller = DevialetExpertControllerIOS(transport: transport, userDefaults: defaults)
        let initialPacket = try statusPacket(volumeDb: -20.0, channel: 3, channelName: "Roon Ready")

        Task {
            try? await Task.sleep(nanoseconds: 100_000_000)
            transport.emitStatus(packet: initialPacket, ipAddress: "192.168.1.71")
        }

        _ = try await controller.discover(timeout: 1.0)
        let packetTime = try XCTUnwrap(controller.currentDiagnostics().lastRealPacketAt)

        try await controller.send(.setVolume(-10.0))
        let diagnosticsAfterSend = controller.currentDiagnostics()
        XCTAssertEqual(diagnosticsAfterSend.lastRealPacketAt, packetTime)
        XCTAssertEqual(diagnosticsAfterSend.lastCommand?.state, .pending)

        let externalPacket = try statusPacket(volumeDb: -32.0, channel: 3, channelName: "Roon Ready")
        Task {
            try? await Task.sleep(nanoseconds: 100_000_000)
            transport.emitStatus(packet: externalPacket, ipAddress: "192.168.1.71")
        }

        let refreshed = try await controller.getCurrentStatus(timeout: 1.0, requireLiveData: true)
        XCTAssertEqual(refreshed.volumeDb, -32.0, accuracy: 0.01)
    }

    func testListenerRestartsAfterTransportError() async throws {
        let transport = MockTransport()
        let defaults = makeEphemeralDefaults()
        let controller = DevialetExpertControllerIOS(transport: transport, userDefaults: defaults)
        let packet = try fixtureData(named: "status_fixture_1", ext: "bin")

        Task {
            try? await Task.sleep(nanoseconds: 100_000_000)
            transport.emitStatus(packet: packet, ipAddress: "192.168.1.72")
        }

        _ = try await controller.discover(timeout: 1.0)
        transport.emitError(AmpControlError.decodeFailed(reason: "listener failed"))

        Task {
            try? await Task.sleep(nanoseconds: 100_000_000)
            transport.emitStatus(packet: packet, ipAddress: "192.168.1.72")
        }

        _ = try await controller.getCurrentStatus(timeout: 1.0, requireLiveData: true)
        let diagnostics = controller.currentDiagnostics()
        XCTAssertEqual(diagnostics.listenerRestartCount, 1)
        XCTAssertEqual(transport.startCount, 2)
        XCTAssertGreaterThanOrEqual(transport.stopCount, 1)
    }

    private func fixtureData(named: String, ext: String) throws -> Data {
        guard let url = Bundle.module.url(forResource: named, withExtension: ext) else {
            XCTFail("Fixture \(named).\(ext) not found")
            return Data()
        }
        return try Data(contentsOf: url)
    }

    private func makeEphemeralDefaults() -> UserDefaults {
        let suiteName = "DevialetCoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func statusPacket(volumeDb: Double, channel: Int, channelName: String) throws -> Data {
        var packet = try fixtureData(named: "status_fixture_1", ext: "bin")
        packet[563] = UInt8((channel << 2) & 0xFC)
        packet[565] = UInt8((volumeDb + 97.5) * 2.0)

        for slot in 0..<15 {
            let base = 52 + (slot * 17)
            packet[base] = 0
            for index in 1..<17 {
                packet[base + index] = 0
            }
        }

        let base = 52 + (channel * 17)
        packet[base] = UInt8(ascii: "1")
        for (index, value) in channelName.utf8.prefix(16).enumerated() {
            packet[base + 1 + index] = value
        }
        return packet
    }
}

private final class MockTransport: DevialetTransporting, @unchecked Sendable {
    private let lock = NSLock()

    private var onPacket: (@Sendable (Data, String?) -> Void)?
    private var onError: (@Sendable (Error) -> Void)?
    private(set) var sentPackets: [(packet: Data, ipAddress: String)] = []
    private(set) var startCount = 0
    private(set) var stopCount = 0

    func startStatusListener(
        onPacket: @escaping @Sendable (Data, String?) -> Void,
        onError: @escaping @Sendable (Error) -> Void
    ) throws {
        lock.withLock {
            self.onPacket = onPacket
            self.onError = onError
            startCount += 1
        }
    }

    func stopStatusListener() {
        lock.withLock {
            onPacket = nil
            onError = nil
            stopCount += 1
        }
    }

    func send(packet: Data, to ipAddress: String) async throws {
        lock.withLock {
            sentPackets.append((packet: packet, ipAddress: ipAddress))
        }
    }

    func emitStatus(packet: Data, ipAddress: String) {
        let callback = lock.withLock { onPacket }
        callback?(packet, ipAddress)
    }

    func emitError(_ error: Error) {
        let callback = lock.withLock { onError }
        callback?(error)
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
