import DevialetCore
import SwiftUI

struct ContentView: View {
    @StateObject private var store = AppStateStore()
    @State private var sliderValue: Double = -20.0
    @State private var showingInputPicker = false

    private let volumeMinDb: Double = -60.0
    private let volumeMaxDb: Double = 0.0
    private let referenceVolumeDb: Double = -20.0
    private let cardRadius: CGFloat = 20
    private let innerControlRadius: CGFloat = 14

    var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground)
                .ignoresSafeArea()

            VStack(spacing: 10) {
                statusCard

                if let status = store.status {
                    let controlsEnabled = status.powerOn
                    VStack(spacing: 0) {
                        powerMuteCard(status: status, controlsEnabled: controlsEnabled)

                        Spacer(minLength: 22)

                        volumeCard(isEnabled: controlsEnabled)

                        Spacer(minLength: 22)

                        inputCard(status: status, isEnabled: controlsEnabled)
                    }
                    .frame(maxHeight: .infinity)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                } else {
                    Spacer()
                    placeholderCard
                    Spacer()
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
        .sheet(isPresented: $showingInputPicker) {
            if let status = store.status {
                inputPickerSheet(status: status)
            }
        }
        .onAppear {
            store.start()
        }
        .onDisappear {
            store.stop()
        }
        .onChange(of: store.status?.volumeDb) { _, newValue in
            if let newValue {
                let clamped = max(volumeMinDb, min(volumeMaxDb, newValue))
                withAnimation(.easeOut(duration: 0.18)) {
                    sliderValue = clamped
                }
            }
        }
        .onChange(of: store.status?.powerOn) { _, powerOn in
            if powerOn == false {
                showingInputPicker = false
            }
        }
        .alert("Network Error", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { _ in store.dismissError() }
        )) {
            Button("Retry") {
                Task { await store.refreshStatus(timeout: 3.0) }
            }
            Button("Dismiss", role: .cancel) {
                store.dismissError()
            }
        } message: {
            Text(store.errorMessage ?? "Unknown error")
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: store.status?.powerOn)
        .animation(.spring(response: 0.24, dampingFraction: 0.9), value: store.status?.muted)
        .animation(.easeInOut(duration: 0.2), value: store.status?.currentChannel)
    }

    private var statusCard: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(store.isConnected ? Color.green : Color.red)
                .frame(width: 9, height: 9)

            Text(store.status?.deviceName ?? "Searching for amplifier")
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .lineLimit(1)

            Spacer()
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func powerMuteCard(status: AmpStatus, controlsEnabled: Bool) -> some View {
        HStack(spacing: 12) {
            controlIconButton(
                systemName: "power",
                foreground: .white,
                background: status.powerOn ? .green : .red
            ) {
                store.powerToggle()
            }

            controlIconButton(
                systemName: status.muted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                foreground: .white,
                background: status.muted ? .orange : .blue,
                enabled: controlsEnabled
            ) {
                store.muteToggle()
            }
        }
    }

    private func volumeCard(isEnabled: Bool) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Volume")
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(.secondary)

            Text(String(format: "%.1f dB", sliderValue))
                .font(.system(size: 38, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(.primary)

            ZStack(alignment: .leading) {
                Slider(value: $sliderValue, in: volumeMinDb...volumeMaxDb, step: 0.5)
                    .tint(.blue)
                    .onChange(of: sliderValue) { _, newValue in
                        store.setVolumeDebounced(newValue)
                    }

                GeometryReader { geo in
                    let xPosition = tickXPosition(for: referenceVolumeDb, in: geo.size.width)
                    Capsule()
                        .fill(Color.secondary.opacity(0.75))
                        .frame(width: 2, height: 15)
                        .offset(x: xPosition - 1)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                }
                .allowsHitTesting(false)
            }
            .frame(height: 22)

            HStack(spacing: 10) {
                volumeArrowButton(systemName: "arrow.left") {
                    let target = max(volumeMinDb, sliderValue - 1.0)
                    sliderValue = target
                    store.setVolumeImmediate(target, min: volumeMinDb, max: volumeMaxDb)
                }

                Button("-20") {
                    sliderValue = referenceVolumeDb
                    store.setVolumeImmediate(referenceVolumeDb, min: volumeMinDb, max: volumeMaxDb)
                }
                .font(.system(.headline, design: .rounded).weight(.semibold))
                .frame(width: 74)
                .padding(.vertical, 12)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: innerControlRadius, style: .continuous))
                .buttonStyle(PressableControlStyle())

                volumeArrowButton(systemName: "arrow.right") {
                    let target = min(volumeMaxDb, sliderValue + 1.0)
                    sliderValue = target
                    store.setVolumeImmediate(target, min: volumeMinDb, max: volumeMaxDb)
                }
            }
        }
        .padding(18)
        .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: cardRadius, style: .continuous))
        .shadow(color: Color.black.opacity(0.03), radius: 10, y: 3)
        .opacity(isEnabled ? 1.0 : 0.42)
        .saturation(isEnabled ? 1.0 : 0.1)
        .disabled(!isEnabled)
    }

    private func inputCard(status: AmpStatus, isEnabled: Bool) -> some View {
        Button {
            showingInputPicker = true
        } label: {
            HStack {
                Text(currentInputName(status: status))
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.primary)
            .padding(.vertical, 13)
            .padding(.horizontal, 12)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: innerControlRadius, style: .continuous))
        }
        .buttonStyle(PressableControlStyle())
        .padding(18)
        .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: cardRadius, style: .continuous))
        .shadow(color: Color.black.opacity(0.03), radius: 10, y: 3)
        .opacity(isEnabled ? 1.0 : 0.42)
        .saturation(isEnabled ? 1.0 : 0.1)
        .disabled(!isEnabled)
    }

    private var placeholderCard: some View {
        VStack(spacing: 8) {
            ProgressView()
            Text("Waiting for amplifier")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func controlIconButton(
        systemName: String,
        foreground: Color,
        background: Color,
        enabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .foregroundStyle(enabled ? foreground : Color(uiColor: .systemGray2))
                .background(
                    enabled ? background : Color(uiColor: .systemGray5),
                    in: RoundedRectangle(cornerRadius: innerControlRadius, style: .continuous)
                )
        }
        .buttonStyle(PressableControlStyle())
        .disabled(!enabled)
    }

    private func volumeArrowButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.headline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: innerControlRadius, style: .continuous))
        }
        .buttonStyle(PressableControlStyle())
    }

    private func tickXPosition(for value: Double, in width: CGFloat) -> CGFloat {
        let clamped = max(volumeMinDb, min(volumeMaxDb, value))
        let fraction = (clamped - volumeMinDb) / (volumeMaxDb - volumeMinDb)
        return width * fraction
    }

    private func currentInputName(status: AmpStatus) -> String {
        status.channels.first(where: { $0.slot == status.currentChannel })?.name ?? "Unknown"
    }

    private func inputPickerSheet(status: AmpStatus) -> some View {
        NavigationStack {
            List(status.channels) { channel in
                Button {
                    store.selectChannel(channel.slot)
                    showingInputPicker = false
                } label: {
                    HStack {
                        Text(channel.name)
                            .foregroundStyle(.primary)
                        Spacer()
                        if channel.slot == status.currentChannel {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.blue)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Choose Input")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }
}

private struct PressableControlStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.975 : 1.0)
            .opacity(configuration.isPressed ? 0.92 : 1.0)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

#Preview {
    ContentView()
}
