import DevialetCore
import Darwin
import Foundation

@main
struct DevialetTools {
    static func main() async {
        do {
            try await run()
        } catch {
            fputs("error: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    private static func run() async throws {
        var arguments = Array(CommandLine.arguments.dropFirst())
        guard let command = arguments.first else {
            printUsage()
            return
        }
        arguments.removeFirst()

        let controller = DevialetExpertControllerIOS()

        switch command {
        case "watch-status":
            try await watchStatus(arguments: arguments, controller: controller)
        case "send-command":
            try await sendCommand(arguments: arguments, controller: controller)
        case "input-matrix":
            try await inputMatrix(arguments: arguments, controller: controller)
        default:
            printUsage()
        }
    }

    private static func watchStatus(arguments: [String], controller: DevialetExpertControllerIOS) async throws {
        let count = intValue(for: "--count", in: arguments)
        let timeout = doubleValue(for: "--timeout", in: arguments) ?? 5.0
        let stream = controller.startStatusStream()
        _ = try await controller.discover(timeout: timeout)

        var previous: AmpStatus?
        var received = 0

        for await status in stream {
            let event = StatusWatchEvent(
                observedAt: Date(),
                deviceName: status.deviceName,
                ipAddress: status.ipAddress,
                powerOn: status.powerOn,
                muted: status.muted,
                channel: status.currentChannel,
                channelName: status.channels.first(where: { $0.slot == status.currentChannel })?.name,
                volumeDb: status.volumeDb,
                changedFields: changedFields(previous: previous, current: status),
                diagnostics: controller.currentDiagnostics()
            )

            printJSONLine(event)
            previous = status
            received += 1

            if let count, received >= count {
                break
            }
        }
    }

    private static func sendCommand(arguments: [String], controller: DevialetExpertControllerIOS) async throws {
        guard let command = parseCommand(arguments: arguments) else {
            printSendCommandUsage()
            return
        }

        let timeout = doubleValue(for: "--confirm-timeout", in: arguments) ?? 5.0
        _ = try await controller.discover(timeout: timeout)
        try await controller.send(command)

        let outcome = try await waitForConfirmation(
            controller: controller,
            command: command,
            timeout: timeout
        )

        printJSONLine(outcome)
    }

    private static func inputMatrix(arguments: [String], controller: DevialetExpertControllerIOS) async throws {
        let timeout = doubleValue(for: "--timeout", in: arguments) ?? 5.0
        let deltaDb = doubleValue(for: "--delta-db", in: arguments) ?? 0.5
        let discovered = try await controller.discover(timeout: timeout)

        var results: [InputMatrixResult] = []
        for channel in discovered.channels.sorted(by: { $0.slot < $1.slot }) {
            let channelOutcome = try await sendAndConfirm(
                controller: controller,
                command: .setChannel(channel.slot),
                timeout: timeout
            )

            let baseline = channelOutcome.status?.volumeDb ?? discovered.volumeDb
            let targetVolume = probeVolume(from: baseline, deltaDb: deltaDb)

            var volumeOutcome: CommandOutcome?
            if abs(targetVolume - baseline) > 0.001 {
                volumeOutcome = try await sendAndConfirm(
                    controller: controller,
                    command: .setVolume(targetVolume),
                    timeout: timeout
                )

                _ = try? await sendAndConfirm(
                    controller: controller,
                    command: .setVolume(baseline),
                    timeout: timeout
                )
            }

            let result = InputMatrixResult(
                slot: channel.slot,
                name: channel.name,
                channelSwitch: channelOutcome,
                volumeProbeTargetDb: volumeOutcome == nil ? nil : targetVolume,
                volumeProbe: volumeOutcome
            )
            results.append(result)
            printJSONLine(result)
        }

        let summary = InputMatrixSummary(
            observedAt: Date(),
            totalInputs: results.count,
            confirmedChannelSwitches: results.filter { $0.channelSwitch.confirmed }.count,
            confirmedVolumeProbes: results.filter { $0.volumeProbe?.confirmed == true }.count,
            results: results
        )
        printJSON(summary)
    }

    private static func sendAndConfirm(
        controller: DevialetExpertControllerIOS,
        command: AmpCommand,
        timeout: TimeInterval
    ) async throws -> CommandOutcome {
        try await controller.send(command)
        return try await waitForConfirmation(controller: controller, command: command, timeout: timeout)
    }

    private static func waitForConfirmation(
        controller: DevialetExpertControllerIOS,
        command: AmpCommand,
        timeout: TimeInterval
    ) async throws -> CommandOutcome {
        let deadline = Date().addingTimeInterval(timeout)
        var latestStatus: AmpStatus?

        while Date() < deadline {
            do {
                let status = try await controller.getCurrentStatus(timeout: min(1.0, timeout), requireLiveData: true)
                latestStatus = status
                if command.matches(status: status) {
                    return CommandOutcome(
                        command: commandSummary(command),
                        confirmed: true,
                        observedAt: Date(),
                        status: status,
                        diagnostics: controller.currentDiagnostics()
                    )
                }
            } catch {
                // Keep polling until the overall timeout expires.
            }
        }

        return CommandOutcome(
            command: commandSummary(command),
            confirmed: false,
            observedAt: Date(),
            status: latestStatus,
            diagnostics: controller.currentDiagnostics()
        )
    }

    private static func commandSummary(_ command: AmpCommand) -> String {
        switch command {
        case .powerOn:
            return "power-on"
        case .powerOff:
            return "power-off"
        case .togglePower:
            return "toggle-power"
        case .setVolume(let value):
            return String(format: "volume %.1f", value)
        case .mute:
            return "mute"
        case .unmute:
            return "unmute"
        case .toggleMute:
            return "toggle-mute"
        case .setChannel(let slot):
            return "channel \(slot)"
        }
    }

    private static func parseCommand(arguments: [String]) -> AmpCommand? {
        guard let first = arguments.first else { return nil }

        switch first {
        case "power-on":
            return .powerOn
        case "power-off":
            return .powerOff
        case "toggle-power":
            return .togglePower
        case "mute":
            return .mute
        case "unmute":
            return .unmute
        case "toggle-mute":
            return .toggleMute
        case "volume":
            guard arguments.count >= 2, let value = Double(arguments[1]) else { return nil }
            return .setVolume(value)
        case "channel":
            guard arguments.count >= 2, let slot = Int(arguments[1]) else { return nil }
            return .setChannel(slot)
        default:
            return nil
        }
    }

    private static func changedFields(previous: AmpStatus?, current: AmpStatus) -> [String] {
        guard let previous else {
            return ["initial"]
        }

        var fields: [String] = []
        if previous.powerOn != current.powerOn { fields.append("powerOn") }
        if previous.muted != current.muted { fields.append("muted") }
        if previous.currentChannel != current.currentChannel { fields.append("currentChannel") }
        if abs(previous.volumeDb - current.volumeDb) > 0.001 { fields.append("volumeDb") }
        if previous.channels != current.channels { fields.append("channels") }
        return fields
    }

    private static func probeVolume(from current: Double, deltaDb: Double) -> Double {
        let increased = min(0.0, current + deltaDb)
        if abs(increased - current) > 0.001 {
            return SafetyPolicy.normalizeToHalfDbStep(increased)
        }

        return SafetyPolicy.normalizeToHalfDbStep(max(SafetyPolicy.minVolumeDb, current - deltaDb))
    }

    private static func intValue(for flag: String, in arguments: [String]) -> Int? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
        return Int(arguments[index + 1])
    }

    private static func doubleValue(for flag: String, in arguments: [String]) -> Double? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
        return Double(arguments[index + 1])
    }

    private static func printJSONLine<T: Encodable>(_ value: T) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(value), let text = String(data: data, encoding: .utf8) {
            print(text)
        }
    }

    private static func printJSON<T: Encodable>(_ value: T) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(value), let text = String(data: data, encoding: .utf8) {
            print(text)
        }
    }

    private static func printUsage() {
        print(
            """
            Usage:
              swift run DevialetTools watch-status [--count N] [--timeout seconds]
              swift run DevialetTools send-command <power-on|power-off|toggle-power|mute|unmute|toggle-mute|volume DB|channel SLOT> [--confirm-timeout seconds]
              swift run DevialetTools input-matrix [--timeout seconds] [--delta-db 0.5]
            """
        )
    }

    private static func printSendCommandUsage() {
        print("send-command expects one of: power-on, power-off, toggle-power, mute, unmute, toggle-mute, volume <db>, channel <slot>")
    }
}

private extension AmpCommand {
    func matches(status: AmpStatus) -> Bool {
        switch self {
        case .powerOn:
            return status.powerOn
        case .powerOff:
            return !status.powerOn
        case .togglePower:
            return false
        case .setVolume(let value):
            return abs(status.volumeDb - SafetyPolicy.normalizeToHalfDbStep(value)) < 0.001
        case .mute:
            return status.muted
        case .unmute:
            return !status.muted
        case .toggleMute:
            return false
        case .setChannel(let slot):
            return status.currentChannel == slot
        }
    }
}

private struct StatusWatchEvent: Encodable {
    let observedAt: Date
    let deviceName: String
    let ipAddress: String
    let powerOn: Bool
    let muted: Bool
    let channel: Int
    let channelName: String?
    let volumeDb: Double
    let changedFields: [String]
    let diagnostics: AmpControllerDiagnostics
}

private struct CommandOutcome: Encodable {
    let command: String
    let confirmed: Bool
    let observedAt: Date
    let status: AmpStatus?
    let diagnostics: AmpControllerDiagnostics
}

private struct InputMatrixResult: Encodable {
    let slot: Int
    let name: String
    let channelSwitch: CommandOutcome
    let volumeProbeTargetDb: Double?
    let volumeProbe: CommandOutcome?
}

private struct InputMatrixSummary: Encodable {
    let observedAt: Date
    let totalInputs: Int
    let confirmedChannelSwitches: Int
    let confirmedVolumeProbes: Int
    let results: [InputMatrixResult]
}
