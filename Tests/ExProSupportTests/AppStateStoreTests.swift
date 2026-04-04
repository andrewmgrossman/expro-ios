import DevialetCore
@testable import ExProSupport
import XCTest

@MainActor
final class AppStateStoreTests: XCTestCase {
    func testExternalVolumeChangesOverrideOptimisticLocalState() async throws {
        let controller = MockController()
        let store = AppStateStore(controller: controller, userDefaults: makeEphemeralDefaults())
        let initial = makeStatus(volumeDb: -20.0, channel: 3, name: "Roon Ready")

        controller.diagnosticsSnapshot = makeDiagnostics(lastRealPacketAt: Date())
        store.start()
        controller.emit(initial)
        await waitUntil { store.status != nil }

        store.setVolumeImmediate(-10.0, min: -96.0, max: 0.0)
        XCTAssertEqual(try XCTUnwrap(store.status).volumeDb, -10.0, accuracy: 0.01)

        let external = makeStatus(volumeDb: -32.0, channel: 3, name: "Roon Ready")
        controller.diagnosticsSnapshot = makeDiagnostics(lastRealPacketAt: Date())
        controller.emit(external)
        await waitUntil { store.status?.volumeDb == -32.0 }

        XCTAssertEqual(try XCTUnwrap(store.status).volumeDb, -32.0, accuracy: 0.01)
        store.stop()
    }

    func testRefreshStatusUsesLiveDataWhenStreamIsStale() async throws {
        let controller = MockController()
        let store = AppStateStore(controller: controller, userDefaults: makeEphemeralDefaults())
        let stalePacketTime = Date().addingTimeInterval(-10.0)
        let fresh = makeStatus(volumeDb: -25.0, channel: 4, name: "AirPlay")

        controller.diagnosticsSnapshot = makeDiagnostics(lastRealPacketAt: stalePacketTime)
        controller.statusHandler = { _, requireLiveData in
            XCTAssertTrue(requireLiveData)
            controller.diagnosticsSnapshot = self.makeDiagnostics(lastRealPacketAt: Date())
            return fresh
        }

        await store.refreshStatus(timeout: 0.1)
        XCTAssertEqual(try XCTUnwrap(store.status).volumeDb, -25.0, accuracy: 0.01)
        XCTAssertTrue(store.isConnected)
    }

    func testConnectionStateDegradesWhenPacketIsStale() async throws {
        let controller = MockController()
        let store = AppStateStore(controller: controller, userDefaults: makeEphemeralDefaults())
        let stale = makeStatus(volumeDb: -20.0, channel: 2, name: "UPnP")

        controller.diagnosticsSnapshot = makeDiagnostics(lastRealPacketAt: Date().addingTimeInterval(-10.0))
        controller.statusHandler = { _, _ in stale }

        await store.refreshStatus(timeout: 0.1, requireLiveData: false)
        XCTAssertFalse(store.isConnected)
        XCTAssertEqual(store.controllerDiagnostics.listenerRestartCount, 0)
    }

    private func makeStatus(volumeDb: Double, channel: Int, name: String) -> AmpStatus {
        AmpStatus(
            deviceName: "Expert 440 Pro",
            ipAddress: "192.168.1.80",
            powerOn: true,
            muted: false,
            currentChannel: channel,
            volumeDb: volumeDb,
            channels: [
                AmpChannel(slot: channel, name: name, isEnabled: true)
            ]
        )
    }

    private func makeDiagnostics(lastRealPacketAt: Date?) -> AmpControllerDiagnostics {
        AmpControllerDiagnostics(
            listenerActive: true,
            lastRealPacketAt: lastRealPacketAt,
            listenerRestartCount: 0,
            lastTransportError: nil,
            lastKnownIPAddress: "192.168.1.80",
            lastCommand: nil
        )
    }

    private func makeEphemeralDefaults() -> UserDefaults {
        let suiteName = "ExProSupportTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func waitUntil(
        timeoutNanoseconds: UInt64 = 1_000_000_000,
        condition: @escaping @MainActor () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(TimeInterval(timeoutNanoseconds) / 1_000_000_000)
        while Date() < deadline {
            if condition() {
                return
            }

            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }
}

private final class MockController: AmpControlling, @unchecked Sendable {
    var diagnosticsSnapshot = AmpControllerDiagnostics()
    var statusHandler: ((TimeInterval, Bool) async throws -> AmpStatus)?
    private var continuation: AsyncStream<AmpStatus>.Continuation?

    func discover(timeout: TimeInterval) async throws -> AmpStatus {
        try await getCurrentStatus(timeout: timeout, requireLiveData: true)
    }

    func getCurrentStatus(timeout: TimeInterval, requireLiveData: Bool) async throws -> AmpStatus {
        if let statusHandler {
            return try await statusHandler(timeout, requireLiveData)
        }
        throw AmpControlError.noKnownStatus
    }

    func startStatusStream() -> AsyncStream<AmpStatus> {
        AsyncStream { continuation in
            self.continuation = continuation
        }
    }

    func send(_ command: AmpCommand) async throws {}

    func currentDiagnostics() -> AmpControllerDiagnostics {
        diagnosticsSnapshot
    }

    func emit(_ status: AmpStatus) {
        statusHandler = { _, _ in status }
        continuation?.yield(status)
    }
}
