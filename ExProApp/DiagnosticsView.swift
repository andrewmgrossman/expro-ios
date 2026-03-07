import SwiftUI

struct DiagnosticsView: View {
    let diagnostics: [String]
    let errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
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
}

#Preview {
    DiagnosticsView(diagnostics: ["[12:00:00] Status stream started"], errorMessage: nil)
}
