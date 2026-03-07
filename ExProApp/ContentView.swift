import DevialetCore
import SwiftUI

struct ContentView: View {
    @StateObject private var store = AppStateStore()
    @State private var sliderValue: Double = VolumeSettings.defaults.presetDb
    @State private var showingInputPicker = false
    @State private var showingSettings = false

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
        .sheet(isPresented: $showingSettings) {
            SettingsView(currentSettings: store.volumeSettings) { updated in
                store.saveVolumeSettings(updated)
            }
        }
        .onAppear {
            store.loadVolumeSettings()
            store.start()
            sliderValue = store.volumeSettings.clampToSliderRange(sliderValue)
        }
        .onDisappear {
            store.stop()
        }
        .onChange(of: store.status?.volumeDb) { _, newValue in
            if let newValue {
                let clamped = store.volumeSettings.clampToSliderRange(newValue)
                withAnimation(.easeOut(duration: 0.18)) {
                    sliderValue = clamped
                }
            }
        }
        .onChange(of: store.volumeSettings) { _, newSettings in
            sliderValue = newSettings.clampToSliderRange(sliderValue)
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

            Button {
                showingSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: Circle())
            }
            .buttonStyle(.plain)
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

            ArcVolumeControl(
                value: $sliderValue,
                range: store.volumeSettings.sliderMinDb...store.volumeSettings.sliderMaxDb,
                referenceValue: store.volumeSettings.presetDb,
                accent: .blue
            ) { newValue in
                store.setVolumeDebounced(newValue)
            }
            .frame(height: 332)

            HStack(spacing: 10) {
                volumeArrowButton(systemName: "arrow.left") {
                    let target = max(store.volumeSettings.sliderMinDb, sliderValue - store.volumeSettings.volumeStepDb)
                    sliderValue = target
                    store.setVolumeImmediate(target, min: store.volumeSettings.sliderMinDb, max: store.volumeSettings.sliderMaxDb)
                }

                Button(dbButtonLabel(store.volumeSettings.presetDb)) {
                    sliderValue = store.volumeSettings.presetDb
                    store.setVolumeImmediate(store.volumeSettings.presetDb, min: store.volumeSettings.sliderMinDb, max: store.volumeSettings.sliderMaxDb)
                }
                .font(.system(.headline, design: .rounded).weight(.semibold))
                .frame(width: 74)
                .padding(.vertical, 12)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: innerControlRadius, style: .continuous))
                .buttonStyle(PressableControlStyle())

                volumeArrowButton(systemName: "arrow.right") {
                    let target = min(store.volumeSettings.sliderMaxDb, sliderValue + store.volumeSettings.volumeStepDb)
                    sliderValue = target
                    store.setVolumeImmediate(target, min: store.volumeSettings.sliderMinDb, max: store.volumeSettings.sliderMaxDb)
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

    private func currentInputName(status: AmpStatus) -> String {
        status.channels.first(where: { $0.slot == status.currentChannel })?.name ?? "Unknown"
    }

    private func dbButtonLabel(_ value: Double) -> String {
        if abs(value.rounded() - value) < 0.001 {
            return String(format: "%.0f", value)
        }
        return String(format: "%.1f", value)
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

private struct ArcVolumeControl: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let referenceValue: Double
    let accent: Color
    let onChange: (Double) -> Void

    private let startDegrees: Double = 190
    private let endDegrees: Double = 350
    private let majorTickCount: Int = 6
    private let trackWidth: CGFloat = 12

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let radius = max(120, (width / 2.0) - 16)
            let center = CGPoint(x: width / 2.0, y: radius + 20)

            let currentDegrees = degrees(for: value)
            let referenceDegrees = degrees(for: referenceValue)

            ZStack {
                arcPath(center: center, radius: radius, start: startDegrees, end: endDegrees)
                    .stroke(Color.secondary.opacity(0.20), style: StrokeStyle(lineWidth: trackWidth, lineCap: .round))

                arcPath(center: center, radius: radius, start: startDegrees, end: currentDegrees)
                    .stroke(accent, style: StrokeStyle(lineWidth: trackWidth, lineCap: .round))

                // Subtle highlight to make the active segment feel polished.
                arcPath(center: center, radius: radius - 1, start: startDegrees, end: currentDegrees)
                    .stroke(Color.white.opacity(0.45), style: StrokeStyle(lineWidth: 2, lineCap: .round))

                // Major ticks only, intentionally thin.
                ForEach(0...majorTickCount, id: \.self) { index in
                    let t = Double(index) / Double(majorTickCount)
                    let degrees = startDegrees + ((endDegrees - startDegrees) * t)
                    let start = point(center: center, radius: radius - 17, degrees: degrees)
                    let end = point(center: center, radius: radius + 9, degrees: degrees)
                    Path { path in
                        path.move(to: start)
                        path.addLine(to: end)
                    }
                    .stroke(Color.secondary.opacity(0.58), style: StrokeStyle(lineWidth: 1, lineCap: .round))
                }

                // Reference marker for the preset button level.
                let referenceStart = point(center: center, radius: radius - 18, degrees: referenceDegrees)
                let referenceEnd = point(center: center, radius: radius + 11, degrees: referenceDegrees)
                Path { path in
                    path.move(to: referenceStart)
                    path.addLine(to: referenceEnd)
                }
                .stroke(Color.secondary.opacity(0.78), style: StrokeStyle(lineWidth: 2, lineCap: .round))

                let thumb = point(center: center, radius: radius, degrees: currentDegrees)
                Circle()
                    .fill(Color(uiColor: .systemBackground))
                    .frame(width: 24, height: 24)
                    .overlay(
                        Circle()
                            .stroke(accent, lineWidth: 3)
                    )
                    .overlay(
                        Circle()
                            .fill(accent)
                            .frame(width: 8, height: 8)
                    )
                    .position(thumb)
                    .shadow(color: Color.black.opacity(0.16), radius: 6, y: 2)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let mapped = value(for: drag.location, center: center)
                        value = mapped
                        onChange(mapped)
                    }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .clipped()
        }
    }

    private func arcPath(center: CGPoint, radius: CGFloat, start: Double, end: Double) -> Path {
        var path = Path()
        let steps = 120
        for step in 0...steps {
            let t = Double(step) / Double(steps)
            let degrees = start + ((end - start) * t)
            let pt = point(center: center, radius: radius, degrees: degrees)
            if step == 0 {
                path.move(to: pt)
            } else {
                path.addLine(to: pt)
            }
        }
        return path
    }

    private func point(center: CGPoint, radius: CGFloat, degrees: Double) -> CGPoint {
        let radians = degrees * .pi / 180.0
        return CGPoint(
            x: center.x + (CGFloat(Foundation.cos(radians)) * radius),
            y: center.y + (CGFloat(Foundation.sin(radians)) * radius)
        )
    }

    private func degrees(for value: Double) -> Double {
        let clamped = min(max(value, range.lowerBound), range.upperBound)
        let fraction = (clamped - range.lowerBound) / (range.upperBound - range.lowerBound)
        return startDegrees + ((endDegrees - startDegrees) * fraction)
    }

    private func value(for location: CGPoint, center: CGPoint) -> Double {
        let radians = Foundation.atan2(
            Double(location.y - center.y),
            Double(location.x - center.x)
        )
        var degrees = radians * 180.0 / .pi
        if degrees < 0 {
            degrees += 360
        }

        let clampedDegrees = min(max(degrees, startDegrees), endDegrees)
        let fraction = (clampedDegrees - startDegrees) / (endDegrees - startDegrees)
        let raw = range.lowerBound + (fraction * (range.upperBound - range.lowerBound))
        return (raw * 2.0).rounded() / 2.0
    }
}
