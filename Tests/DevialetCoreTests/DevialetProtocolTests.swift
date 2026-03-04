import XCTest
@testable import DevialetCore

final class DevialetProtocolTests: XCTestCase {
    private let codec = DevialetProtocol()

    func testCRC16KnownVector() throws {
        var bytes = Data(repeating: 0, count: 12)
        bytes[0] = 0x44
        bytes[1] = 0x72
        bytes[3] = 0x01
        bytes[5] = 0x00
        bytes[6] = 0x01
        bytes[7] = 0x01

        let crc = codec.crc16(bytes: bytes)
        XCTAssertEqual(crc, 0x4B9E)
    }

    func testDecodeStatusFixture() throws {
        let packet = try fixtureData(named: "status_fixture_1", ext: "bin")
        let status = try codec.decodeStatus(packet: packet, ipAddress: "192.168.1.50")

        XCTAssertEqual(status.deviceName, "Expert 440 Pro")
        XCTAssertEqual(status.ipAddress, "192.168.1.50")
        XCTAssertTrue(status.powerOn)
        XCTAssertFalse(status.muted)
        XCTAssertEqual(status.currentChannel, 3)
        XCTAssertEqual(status.volumeDb, -20.0, accuracy: 0.01)
        XCTAssertEqual(status.channels.count, 5)
        XCTAssertEqual(status.channelMap[0], "Optical 1")
        XCTAssertEqual(status.channelMap[1], "Phono")
        XCTAssertEqual(status.channelMap[2], "UPnP")
        XCTAssertEqual(status.channelMap[3], "Airplay")
        XCTAssertEqual(status.channelMap[5], "USB")
    }

    func testVolumeEncodingParity() throws {
        XCTAssertEqual(codec.encodeVolume(db: -96.0), 0xC2C0)
        XCTAssertEqual(codec.encodeVolume(db: -50.0), 0xC248)
        XCTAssertEqual(codec.encodeVolume(db: -20.0), 0xC1A0)
        XCTAssertEqual(codec.encodeVolume(db: -0.5), 0xBF00)
        XCTAssertEqual(codec.encodeVolume(db: 0.0), 0x0000)
    }

    func testChannelEncodingParity() throws {
        let status = AmpStatus(
            deviceName: "Expert",
            ipAddress: "192.168.1.40",
            powerOn: true,
            muted: false,
            currentChannel: 0,
            volumeDb: -20,
            channels: (0...14).map { AmpChannel(slot: $0, name: "Slot \($0)", isEnabled: true) }
        )

        try assertChannel(slot: 0, expectedByte8: 0xFF, expectedByte9: 0xE0, status: status)
        try assertChannel(slot: 1, expectedByte8: 0x3F, expectedByte9: 0x80, status: status)
        try assertChannel(slot: 2, expectedByte8: 0x40, expectedByte9: 0x00, status: status)
        try assertChannel(slot: 3, expectedByte8: 0x40, expectedByte9: 0x40, status: status)
        try assertChannel(slot: 4, expectedByte8: 0x40, expectedByte9: 0x80, status: status)
        try assertChannel(slot: 8, expectedByte8: 0x41, expectedByte9: 0x00, status: status)
        try assertChannel(slot: 14, expectedByte8: 0x41, expectedByte9: 0x60, status: status)
    }

    func testCommandPacketCounterAndCRCFields() throws {
        let base = try codec.makeCommandPacket(for: .powerOn, status: nil)
        let withCounter = codec.applyPacketCounterAndCRC(to: base, packetCounter: 1)

        XCTAssertEqual(withCounter.count, DevialetProtocol.commandPacketLength)
        XCTAssertEqual(withCounter[3], 0x01)
        XCTAssertEqual(withCounter[5], 0x00)
        XCTAssertEqual(withCounter[12], 0x4B)
        XCTAssertEqual(withCounter[13], 0x9E)
    }

    func testChannelFlagParsesNonOneDigitAsEnabled() throws {
        var packet = Data(repeating: 0, count: 598)
        packet[19] = UInt8(ascii: "E")
        packet[20] = UInt8(ascii: "x")
        packet[21] = UInt8(ascii: "p")

        let slot = 1
        let base = 52 + (slot * 17)
        packet[base] = UInt8(ascii: "2")

        let name = Array("Phono".utf8)
        for (index, value) in name.enumerated() {
            packet[base + 1 + index] = value
        }

        packet[562] = 0x80
        packet[563] = UInt8(slot << 2)
        packet[565] = 155

        let status = try codec.decodeStatus(packet: packet, ipAddress: "192.168.1.99")
        XCTAssertEqual(status.channelMap[1], "Phono")
    }

    private func assertChannel(
        slot: Int,
        expectedByte8: UInt8,
        expectedByte9: UInt8,
        status: AmpStatus
    ) throws {
        let packet = try codec.makeCommandPacket(for: .setChannel(slot), status: status)
        XCTAssertEqual(packet[7], 0x05)
        XCTAssertEqual(packet[8], expectedByte8)
        XCTAssertEqual(packet[9], expectedByte9)
    }

    private func fixtureData(named: String, ext: String) throws -> Data {
        guard let url = Bundle.module.url(forResource: named, withExtension: ext) else {
            XCTFail("Fixture \(named).\(ext) not found")
            return Data()
        }
        return try Data(contentsOf: url)
    }
}
