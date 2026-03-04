import DevialetCore
import Foundation
import SwiftUI

@MainActor
final class AppStateStore: ObservableObject {
    @Published var status: AmpStatus?
    @Published var isConnected = false
    @Published var isSyncing = false
    @Published var errorMessage: String?
    @Published var diagnostics: [String] = []

    private let controller: AmpControlling
    private var streamTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var volumeTask: Task<Void, Never>?

    init(controller: AmpControlling = DevialetExpertControllerIOS()) {
        self.controller = controller
    }

    func start() {
        guard streamTask == nil else { return }

        let stream = controller.startStatusStream()

        streamTask = Task { [weak self] in
            guard let self else { return }
            for await update in stream {
                status = update
                isConnected = true
                if errorMessage != nil {
                    errorMessage = nil
                }
            }
        }

        refreshTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await refreshStatus(timeout: 2.0)
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }

        log("Status stream started")
    }

    func stop() {
        streamTask?.cancel()
        refreshTask?.cancel()
        volumeTask?.cancel()

        streamTask = nil
        refreshTask = nil
        volumeTask = nil

        log("Status stream stopped")
    }

    func refreshStatus(timeout: TimeInterval = 2.0) async {
        guard !isSyncing else { return }

        isSyncing = true
        defer { isSyncing = false }

        do {
            let fresh = try await controller.getCurrentStatus(timeout: timeout)
            status = fresh
            isConnected = true
        } catch {
            isConnected = false
            errorMessage = error.localizedDescription
            log("Refresh failed: \(error.localizedDescription)")
        }
    }

    func powerToggle() {
        runCommand(.togglePower, optimisticText: "Power toggle sent")
    }

    func muteToggle() {
        runCommand(.toggleMute, optimisticText: "Mute toggle sent")
    }

    func selectChannel(_ slot: Int) {
        runCommand(.setChannel(slot), optimisticText: "Switched to channel \(slot)")
    }

    func setVolumeDebounced(_ value: Double) {
        let normalized = SafetyPolicy.normalizeToHalfDbStep(value)

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
        let clamped = max(minValue, min(maxValue, value))
        let normalized = SafetyPolicy.normalizeToHalfDbStep(clamped)
        updateLocalVolume(normalized)

        let optimisticText = String(format: "Volume set to %.1f dB", normalized)
        runCommand(.setVolume(normalized), optimisticText: optimisticText)
    }

    private func runCommand(_ command: AmpCommand, optimisticText: String) {
        Task {
            await runCommandAsync(command, optimisticText: optimisticText)
        }
    }

    private func runCommandAsync(_ command: AmpCommand, optimisticText: String) async {
        do {
            try await controller.send(command)
            await refreshStatus(timeout: 2.5)
            log(optimisticText)
        } catch {
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
            current.lastUpdated = Date()
            status = current
        }
    }
}
