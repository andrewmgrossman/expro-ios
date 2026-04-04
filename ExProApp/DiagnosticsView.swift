import SwiftUI
import DevialetCore

struct DiagnosticsView: View {
    let status: AmpStatus?
    let controllerDiagnostics: AmpControllerDiagnostics
    let diagnostics: [String]
    let errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section("Connection") {
                    LabeledContent("Listener") {
                        Text(controllerDiagnostics.listenerActive ? "Active" : "Inactive")
                    }
                    LabeledContent("Last Packet") {
                        Text(lastPacketText)
                    }
                    LabeledContent("Stream Health") {
                        Text(streamHealthText)
                    }
                    LabeledContent("Listener Restarts") {
                        Text("\(controllerDiagnostics.listenerRestartCount)")
                    }
                    if let ip = controllerDiagnostics.lastKnownIPAddress {
                        LabeledContent("Amp IP") {
                            Text(ip)
                                .monospaced()
                        }
                    }
                }

                Section("Current Source") {
                    LabeledContent("Slot") {
                        Text(status.map { "\($0.currentChannel)" } ?? "Unknown")
                    }
                    LabeledContent("Name") {
                        Text(currentSourceName)
                    }
                }

                if let lastCommand = controllerDiagnostics.lastCommand {
                    Section("Last Command") {
                        LabeledContent("Summary") {
                            Text(lastCommand.summary)
                        }
                        LabeledContent("State") {
                            Text(lastCommand.state.rawValue.capitalized)
                        }
                        if let confirmedAt = lastCommand.confirmedAt {
                            LabeledContent("Confirmed") {
                                Text(confirmedAt.formatted(date: .omitted, time: .standard))
                            }
                        }
                    }
                }

                if let errorMessage {
                    Section("Current Error") {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }

                Section("Troubleshooting") {
                    Text("1. Confirm iPhone and amplifier are on the same LAN.")
                    Text("2. Allow Local Network access when prompted.")
                    Text("3. Ensure UDP ports 45454 and 45455 are not blocked.")
                    Text("4. If discovery fails, power-cycle network equipment.")
                }

                Section("Recent Events") {
                    if diagnostics.isEmpty {
                        Text("No logs yet")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(diagnostics, id: \.self) { item in
                            Text(item)
                                .font(.footnote.monospaced())
                        }
                    }
                }
            }
            .navigationTitle("Diagnostics")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var currentSourceName: String {
        guard let status else { return "Unknown" }
        return status.channels.first(where: { $0.slot == status.currentChannel })?.name ?? "Unknown"
    }

    private var lastPacketText: String {
        guard let lastPacketAt = controllerDiagnostics.lastRealPacketAt else { return "No packet yet" }
        let age = max(0, Date().timeIntervalSince(lastPacketAt))
        return "\(lastPacketAt.formatted(date: .omitted, time: .standard)) (\(String(format: "%.1fs", age)) ago)"
    }

    private var streamHealthText: String {
        guard let lastPacketAt = controllerDiagnostics.lastRealPacketAt else { return "Stale" }
        return Date().timeIntervalSince(lastPacketAt) <= 3.0 ? "Healthy" : "Stale"
    }
}

#Preview {
    DiagnosticsView(
        status: nil,
        controllerDiagnostics: AmpControllerDiagnostics(),
        diagnostics: ["[12:00:00] Status stream started"],
        errorMessage: nil
    )
}
