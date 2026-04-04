import DevialetCore
import Foundation
import SwiftUI

@MainActor
final class AppStateStore: ObservableObject {
    private enum DefaultsKey {
        static let volumeSettings = "expro.volume.settings"
    }

    @Published var status: AmpStatus?
    @Published var isConnected = false
    @Published var isSyncing = false
    @Published var errorMessage: String?
    @Published var diagnostics: [String] = []
    @Published var controllerDiagnostics = AmpControllerDiagnostics()
    @Published var volumeSettings: VolumeSettings

    private let controller: AmpControlling
    private let userDefaults: UserDefaults
    private var streamTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var volumeTask: Task<Void, Never>?
    private var lastStreamUpdate: Date = .distantPast
    private var lastLoggedCommandFingerprint: String?
    private var lastLoggedTransportError: String?
    private let healthyPacketThreshold: TimeInterval = 3.0

    init(
        controller: AmpControlling = DevialetExpertControllerIOS(),
        userDefaults: UserDefaults = .standard
    ) {
        self.controller = controller
        self.userDefaults = userDefaults
        self.volumeSettings = Self.loadSettings(from: userDefaults)
    }

    func start() {
        guard streamTask == nil else { return }

        let stream = controller.startStatusStream()

        streamTask = Task { [weak self] in
            guard let self else { return }
            for await update in stream {
                lastStreamUpdate = Date()
                status = update
                clampVolumeToSettingsIfNeeded(sendCommandIfChanged: false)
                if errorMessage != nil {
                    errorMessage = nil
                }
                syncDiagnostics(logEvents: true)
            }
        }

        refreshTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await refreshStatus(timeout: 2.0)
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }

        syncDiagnostics(logEvents: false)
        log("Status stream started")
    }

    func stop() {
        streamTask?.cancel()
        refreshTask?.cancel()
        volumeTask?.cancel()

        streamTask = nil
        refreshTask = nil
        volumeTask = nil

        syncDiagnostics(logEvents: false)
        log("Status stream stopped")
    }

    func refreshStatus(timeout: TimeInterval = 2.0, requireLiveData: Bool? = nil) async {
        guard !isSyncing else { return }

        isSyncing = true
        defer { isSyncing = false }

        do {
            let forceLiveRefresh = requireLiveData ?? shouldRequireLiveStatusRefresh()
            let fresh = try await controller.getCurrentStatus(timeout: timeout, requireLiveData: forceLiveRefresh)
            status = fresh
            clampVolumeToSettingsIfNeeded(sendCommandIfChanged: false)
            syncDiagnostics(logEvents: true)
        } catch {
            syncDiagnostics(logEvents: true)
            isConnected = false
            errorMessage = error.localizedDescription
            log("Refresh failed: \(error.localizedDescription)")
        }
    }

    func powerToggle() {
        if let currentStatus = status {
            let command: AmpCommand = currentStatus.powerOn ? .powerOff : .powerOn
            let optimisticText = currentStatus.powerOn ? "Power off sent" : "Power on sent"
            runCommand(command, optimisticText: optimisticText)
        } else {
            runCommand(.togglePower, optimisticText: "Power toggle sent")
        }
    }

    func muteToggle() {
        if let currentStatus = status {
            let command: AmpCommand = currentStatus.muted ? .unmute : .mute
            let optimisticText = currentStatus.muted ? "Unmute sent" : "Mute sent"
            runCommand(command, optimisticText: optimisticText)
        } else {
            runCommand(.toggleMute, optimisticText: "Mute toggle sent")
        }
    }

    func selectChannel(_ slot: Int) {
        runCommand(.setChannel(slot), optimisticText: "Switched to channel \(slot)")
    }

    func setVolumeDebounced(_ value: Double) {
        let clamped = volumeSettings.clampToSliderRange(value)
        let normalized = SafetyPolicy.normalizeToHalfDbStep(clamped)

        updateLocalVolume(normalized)

        volumeTask?.cancel()
        volumeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(SafetyPolicy.volumeDebounceInterval * 1_000_000_000))
            guard !Task.isCancelled else { return }
            let optimisticText = String(format: "Volume set to %.1f dB", normalized)
            await self?.runCommandAsync(.setVolume(normalized), optimisticText: optimisticText)
        }
    }

    func setVolumeImmediate(_ value: Double, min minValue: Double, max maxValue: Double) {
        volumeTask?.cancel()
        let boundsClamped = max(minValue, min(maxValue, value))
        let clamped = volumeSettings.clampToSliderRange(boundsClamped)
        let normalized = SafetyPolicy.normalizeToHalfDbStep(clamped)
        updateLocalVolume(normalized)

        let optimisticText = String(format: "Volume set to %.1f dB", normalized)
        runCommand(.setVolume(normalized), optimisticText: optimisticText)
    }

    func loadVolumeSettings() {
        volumeSettings = Self.loadSettings(from: userDefaults)
        clampVolumeToSettingsIfNeeded(sendCommandIfChanged: false)
    }

    func saveVolumeSettings(_ settings: VolumeSettings) {
        let normalized = settings.normalized()
        volumeSettings = normalized

        if let encoded = try? JSONEncoder().encode(normalized) {
            userDefaults.set(encoded, forKey: DefaultsKey.volumeSettings)
        }

        clampVolumeToSettingsIfNeeded(sendCommandIfChanged: true)
    }

    private func runCommand(_ command: AmpCommand, optimisticText: String) {
        Task {
            await runCommandAsync(command, optimisticText: optimisticText)
        }
    }

    private func runCommandAsync(_ command: AmpCommand, optimisticText: String) async {
        do {
            try await controller.send(command)
            syncDiagnostics(logEvents: true)
            await refreshStatus(timeout: 2.5, requireLiveData: true)
            log(optimisticText)
        } catch {
            syncDiagnostics(logEvents: true)
            errorMessage = error.localizedDescription
            log("Command failed: \(error.localizedDescription)")
        }
    }

    func dismissError() {
        errorMessage = nil
    }

    private func log(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        diagnostics.insert("[\(formatter.string(from: Date()))] \(message)", at: 0)
        diagnostics = Array(diagnostics.prefix(40))
    }

    private func updateLocalVolume(_ value: Double) {
        if var current = status {
            current.volumeDb = value
            status = current
        }
    }

    private func clampVolumeToSettingsIfNeeded(sendCommandIfChanged: Bool) {
        guard let currentStatus = status else { return }

        let clamped = volumeSettings.clampToSliderRange(currentStatus.volumeDb)
        let normalized = SafetyPolicy.normalizeToHalfDbStep(clamped)
        guard abs(normalized - currentStatus.volumeDb) > 0.001 else { return }

        updateLocalVolume(normalized)

        guard sendCommandIfChanged, currentStatus.powerOn else { return }
        let optimisticText = String(format: "Volume adjusted to %.1f dB", normalized)
        runCommand(.setVolume(normalized), optimisticText: optimisticText)
    }

    private func shouldRequireLiveStatusRefresh() -> Bool {
        let packetAge = controller.currentDiagnostics().lastRealPacketAt.map { Date().timeIntervalSince($0) } ?? .infinity
        return packetAge > healthyPacketThreshold || Date().timeIntervalSince(lastStreamUpdate) > healthyPacketThreshold
    }

    private func syncDiagnostics(logEvents: Bool) {
        let snapshot = controller.currentDiagnostics()
        controllerDiagnostics = snapshot

        if let lastRealPacketAt = snapshot.lastRealPacketAt {
            isConnected = Date().timeIntervalSince(lastRealPacketAt) <= healthyPacketThreshold
        } else {
            isConnected = false
        }

        if logEvents, let error = snapshot.lastTransportError, error != lastLoggedTransportError {
            lastLoggedTransportError = error
            log("Listener issue: \(error)")
        } else if snapshot.lastTransportError == nil {
            lastLoggedTransportError = nil
        }

        if logEvents, let lastCommand = snapshot.lastCommand {
            let fingerprint = "\(lastCommand.summary)|\(lastCommand.state.rawValue)|\(lastCommand.confirmedAt?.timeIntervalSince1970 ?? 0)"
            if fingerprint != lastLoggedCommandFingerprint {
                lastLoggedCommandFingerprint = fingerprint
                switch lastCommand.state {
                case .pending:
                    log("Awaiting confirmation: \(lastCommand.summary)")
                case .confirmed:
                    log("Confirmed: \(lastCommand.summary)")
                case .unconfirmed:
                    log("Unconfirmed: \(lastCommand.summary)")
                }
            }
        }
    }

    private static func loadSettings(from userDefaults: UserDefaults) -> VolumeSettings {
        guard let data = userDefaults.data(forKey: DefaultsKey.volumeSettings),
              let decoded = try? JSONDecoder().decode(VolumeSettings.self, from: data) else {
            return VolumeSettings.defaults
        }

        return decoded.normalized()
    }
}
