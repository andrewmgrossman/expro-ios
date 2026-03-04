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
}

private final class MockTransport: DevialetTransporting, @unchecked Sendable {
    private let lock = NSLock()

    private var onPacket: (@Sendable (Data, String?) -> Void)?
    private var onError: (@Sendable (Error) -> Void)?
    private(set) var sentPackets: [(packet: Data, ipAddress: String)] = []

    func startStatusListener(
        onPacket: @escaping @Sendable (Data, String?) -> Void,
        onError: @escaping @Sendable (Error) -> Void
    ) throws {
        lock.withLock {
            self.onPacket = onPacket
            self.onError = onError
        }
    }

    func stopStatusListener() {
        lock.withLock {
            onPacket = nil
            onError = nil
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
}

private extension NSLock {
    @discardableResult
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
