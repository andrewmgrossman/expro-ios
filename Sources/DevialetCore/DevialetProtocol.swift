import Foundation

public struct DevialetProtocol: Sendable {
    public static let statusPort: UInt16 = 45454
    public static let commandPort: UInt16 = 45455
    public static let statusPacketMinLength: Int = 566
    public static let statusPacketPreferredBufferLength: Int = 2048
    public static let commandPacketLength: Int = 142

    public init() {}

    public func decodeStatus(packet: Data, ipAddress: String) throws -> AmpStatus {
        guard packet.count >= Self.statusPacketMinLength else {
            throw AmpControlError.invalidStatusPacket(length: packet.count)
        }

        let deviceName = decodeString(in: packet, range: 19..<50)

        var channels: [AmpChannel] = []
        for slot in 0..<15 {
            let base = 52 + (slot * 17)
            guard packet.count >= (base + 17) else { break }

            let enabled = isEnabledChannelFlag(packet[base])
            if enabled {
                let name = decodeString(in: packet, range: (base + 1)..<(base + 17))
                channels.append(AmpChannel(slot: slot, name: name.isEmpty ? "Slot \(slot)" : name, isEnabled: true))
            }
        }

        let powerOn = (packet[562] & 0x80) != 0
        let muted = (packet[563] & 0x02) != 0
        let currentChannel = Int((packet[563] & 0xFC) >> 2)
        let volumeDb = (Double(packet[565]) / 2.0) - 97.5

        return AmpStatus(
            deviceName: deviceName.isEmpty ? "Unknown Devialet" : deviceName,
            ipAddress: ipAddress,
            powerOn: powerOn,
            muted: muted,
            currentChannel: currentChannel,
            volumeDb: volumeDb,
            channels: channels,
            lastUpdated: Date()
        )
    }

    public func makeCommandPacket(for command: AmpCommand, status: AmpStatus?) throws -> Data {
        var packet = Data(repeating: 0, count: Self.commandPacketLength)
        packet[0] = 0x44
        packet[1] = 0x72

        switch command {
        case .powerOn:
            packet[6] = 0x01
            packet[7] = 0x01

        case .powerOff:
            packet[6] = 0x00
            packet[7] = 0x01

        case .setVolume(let requestedDb):
            let db = SafetyPolicy.normalizeToHalfDbStep(requestedDb)
            guard db >= SafetyPolicy.minVolumeDb && db <= SafetyPolicy.maxVolumeDb else {
                throw AmpControlError.invalidVolume(requestedDb)
            }

            let encoded = encodeVolume(db: db)
            packet[6] = 0x00
            packet[7] = 0x04
            packet[8] = UInt8((encoded & 0xFF00) >> 8)
            packet[9] = UInt8(encoded & 0x00FF)

        case .mute:
            packet[6] = 0x01
            packet[7] = 0x07

        case .unmute:
            packet[6] = 0x00
            packet[7] = 0x07

        case .setChannel(let slot):
            guard (0...14).contains(slot) else {
                throw AmpControlError.invalidChannel(slot)
            }

            if let status, !status.channels.contains(where: { $0.slot == slot && $0.isEnabled }) {
                throw AmpControlError.invalidChannel(slot)
            }

            packet[6] = 0x00
            packet[7] = 0x05

            if slot == 1 {
                packet[8] = 0x3F
                packet[9] = 0x80
            } else {
                let cmdValue: Int
                switch slot {
                case 0:
                    cmdValue = -1
                case 2:
                    cmdValue = 0
                case 3:
                    cmdValue = 2
                default:
                    cmdValue = slot
                }

                let rawCmd = UInt32(UInt16(bitPattern: Int16(cmdValue))) << 5
                let outVal = UInt32(0x4000) | rawCmd

                packet[8] = UInt8((outVal & 0xFF00) >> 8)
                if cmdValue > 7 {
                    packet[9] = UInt8((outVal & 0x00FF) >> 1)
                } else {
                    packet[9] = UInt8(outVal & 0x00FF)
                }
            }

        case .togglePower, .toggleMute:
            throw AmpControlError.decodeFailed(reason: "Toggle commands must be resolved to concrete commands before packet encoding")
        }

        return packet
    }

    public func applyPacketCounterAndCRC(to basePacket: Data, packetCounter: UInt8) -> Data {
        var packet = basePacket
        guard packet.count >= 14 else { return packet }

        packet[3] = packetCounter
        packet[5] = packetCounter >> 1

        let crc = crc16(bytes: packet.prefix(12))
        packet[12] = UInt8((crc & 0xFF00) >> 8)
        packet[13] = UInt8(crc & 0x00FF)
        return packet
    }

    public func encodeVolume(db: Double) -> UInt16 {
        let normalized = SafetyPolicy.normalizeToHalfDbStep(db)
        let absolute = abs(normalized)

        func dbConvert(_ value: Double) -> Int {
            if value <= 0.0 { return 0 }
            if abs(value - 0.5) < 0.0001 { return 0x3F00 }

            let exponent = Int(ceil(1.0 + log2(value)))
            let shifted = exponent <= 0 ? 256 : (256 >> exponent)
            let remaining = max(0.0, value - 0.5)
            return shifted + dbConvert(remaining)
        }

        var result = dbConvert(absolute)
        if normalized < 0 {
            result |= 0x8000
        }

        return UInt16(result & 0xFFFF)
    }

    public func crc16<C: Collection>(bytes: C) -> UInt16 where C.Element == UInt8 {
        var crc: UInt16 = 0xFFFF

        for byte in bytes {
            crc ^= UInt16(byte) << 8
            for _ in 0..<8 {
                if (crc & 0x8000) != 0 {
                    crc = (crc << 1) ^ 0x1021
                } else {
                    crc <<= 1
                }
            }
        }

        return crc & 0xFFFF
    }

    private func decodeString(in packet: Data, range: Range<Int>) -> String {
        guard packet.count >= range.upperBound else { return "" }
        let chunk = packet.subdata(in: range)
        let raw = String(data: chunk, encoding: .utf8) ?? ""
        return raw.trimmingCharacters(in: .controlCharacters.union(.whitespacesAndNewlines))
    }

    private func isEnabledChannelFlag(_ byte: UInt8) -> Bool {
        let scalar = UnicodeScalar(byte)
        if let digit = Int(String(scalar)) {
            return digit != 0
        }
        return byte != 0
    }
}
