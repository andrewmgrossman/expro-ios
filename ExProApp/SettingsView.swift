import DevialetCore
import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    let currentSettings: VolumeSettings
    let onSave: (VolumeSettings) -> Void

    @State private var sliderMinDb: Double
    @State private var sliderMaxDb: Double
    @State private var presetDb: Double
    @State private var volumeStepDb: Double

    init(currentSettings: VolumeSettings, onSave: @escaping (VolumeSettings) -> Void) {
        self.currentSettings = currentSettings
        self.onSave = onSave
        _sliderMinDb = State(initialValue: currentSettings.sliderMinDb)
        _sliderMaxDb = State(initialValue: currentSettings.sliderMaxDb)
        _presetDb = State(initialValue: currentSettings.presetDb)
        _volumeStepDb = State(initialValue: currentSettings.volumeStepDb)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Volume Range") {
                    sliderRow(
                        title: "Minimum",
                        value: $sliderMinDb,
                        range: SafetyPolicy.minVolumeDb...(sliderMaxDb - 0.5)
                    ) { updated in
                        sliderMinDb = min(updated, sliderMaxDb - 0.5)
                        presetDb = min(max(presetDb, sliderMinDb), sliderMaxDb)
                    }

                    sliderRow(
                        title: "Maximum",
                        value: $sliderMaxDb,
                        range: (sliderMinDb + 0.5)...SafetyPolicy.maxVolumeDb
                    ) { updated in
                        sliderMaxDb = max(updated, sliderMinDb + 0.5)
                        presetDb = min(max(presetDb, sliderMinDb), sliderMaxDb)
                    }
                }

                Section("Preset Button") {
                    sliderRow(
                        title: "Preset Level",
                        value: $presetDb,
                        range: sliderMinDb...sliderMaxDb
                    ) { updated in
                        presetDb = min(max(updated, sliderMinDb), sliderMaxDb)
                    }
                }

                Section("Arrow Buttons") {
                    Picker("Increment", selection: $volumeStepDb) {
                        Text("0.5 dB").tag(0.5)
                        Text("1 dB").tag(1.0)
                        Text("2 dB").tag(2.0)
                    }
                    .pickerStyle(.segmented)
                }

                Section("License") {
                    Text(licenseText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, 2)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(draftSettings.normalized())
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private var draftSettings: VolumeSettings {
        VolumeSettings(
            sliderMinDb: sliderMinDb,
            sliderMaxDb: sliderMaxDb,
            presetDb: presetDb,
            volumeStepDb: volumeStepDb
        )
    }

    private func sliderRow(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        onUpdate: @escaping (Double) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                Spacer()
                Text(dbText(value.wrappedValue))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Slider(
                value: Binding(
                    get: { value.wrappedValue },
                    set: { newValue in
                        let stepped = SafetyPolicy.normalizeToHalfDbStep(newValue)
                        value.wrappedValue = stepped
                        onUpdate(stepped)
                    }
                ),
                in: range,
                step: 0.5
            )
        }
        .padding(.vertical, 2)
    }

    private func dbText(_ value: Double) -> String {
        if abs(value.rounded() - value) < 0.001 {
            return String(format: "%.0f dB", value)
        }
        return String(format: "%.1f dB", value)
    }

    private var licenseText: String {
        """
        Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the “Software”), to use, copy, modify, publish, distribute, sublicense, and/or sell copies of the Software, for any purpose and without restriction.

        THE SOFTWARE IS PROVIDED “AS IS,” WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY CLAIM, DAMAGES, OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT, OR OTHERWISE, ARISING FROM, OUT OF, OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
        """
    }
}
