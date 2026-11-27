import CoreAudio
import Foundation
import Observation
import os

/// The observable per-app audio state: running apps, their volume, boost and mute.
///
/// An app is tapped only while it needs processing (volume other than 100 % or muted).
/// At 100 % its audio is left untouched, so audio-capture consent is requested only when
/// the user first changes an app's volume.
@MainActor
@Observable
final class AppAudioModel {
    /// What the panel shows for one app.
    struct AppState: Identifiable, Equatable {
        let app: AudioApp
        /// The volume, where 1 means 100 % and up to ``GainProcessor/maxBoost``.
        var volume: Float
        var isMuted: Bool
        /// Whether a Process Tap is currently processing this app.
        var isProcessed: Bool

        var id: String { app.id }
        /// Whether the app needs a Process Tap.
        var needsProcessing: Bool { isMuted || volume != 1 }
        /// Whether the app is boosted above 100 %.
        var isBoosted: Bool { !isMuted && volume > 1 }
        /// The linear gain applied to the app.
        var gain: Float { isMuted ? 0 : GainProcessor.gain(forVolume: volume) }
    }

    /// Apps that play audio or have custom settings, then the others.
    private(set) var apps: [AppState] = []
    /// The last error, shown inline in the panel.
    private(set) var errorMessage: String?
    /// Set when a processed app plays but no audio reaches the tap, which means audio-capture
    /// permission was refused.
    private(set) var needsCapturePermission = false

    @ObservationIgnored private let processProvider: AudioProcessProviding
    @ObservationIgnored private let resolver: RunningAppResolving
    @ObservationIgnored private let tapFactory: ProcessTapMaking
    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let excludedPID: pid_t
    @ObservationIgnored private let permissionCheckDelay: Duration
    @ObservationIgnored private var taps: [String: ProcessTapControlling] = [:]
    @ObservationIgnored private var outputDeviceUID: String?
    @ObservationIgnored private var refreshScheduled = false
    @ObservationIgnored private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Orpheus",
        category: "AppAudioModel"
    )

    /// Creates a model.
    /// - Parameters:
    ///   - processProvider: The source of audio processes.
    ///   - resolver: Maps processes to apps.
    ///   - tapFactory: Creates per-app pipelines.
    ///   - settings: Where per-app settings are saved.
    ///   - excludedPID: A process never shown or tapped (Orpheus itself).
    ///   - permissionCheckDelay: How long a processed app may play silence before the
    ///     panel suggests checking the audio-capture permission.
    init(
        processProvider: AudioProcessProviding,
        resolver: RunningAppResolving,
        tapFactory: ProcessTapMaking,
        settings: SettingsStore,
        excludedPID: pid_t = ProcessInfo.processInfo.processIdentifier,
        permissionCheckDelay: Duration = .seconds(4)
    ) {
        self.processProvider = processProvider
        self.resolver = resolver
        self.tapFactory = tapFactory
        self.settings = settings
        self.excludedPID = excludedPID
        self.permissionCheckDelay = permissionCheckDelay
    }

    /// Apps currently playing audio, or with custom settings.
    var activeApps: [AppState] {
        apps.filter { $0.app.isPlaying || $0.needsProcessing }
    }

    /// The other running audio apps.
    var otherApps: [AppState] {
        apps.filter { !$0.app.isPlaying && !$0.needsProcessing }
    }

    /// Whether any app is boosted above 100 %.
    var hasBoostedApp: Bool {
        apps.contains { $0.isBoosted }
    }

    /// Reads the app list and starts following changes.
    func start() {
        processProvider.startObserving { [weak self] in
            Task { @MainActor in self?.scheduleRefresh() }
        }
        refresh()
    }

    /// Stops following changes and releases every tap, giving apps their normal audio back.
    func stop() {
        processProvider.stopObserving()
        taps.values.forEach { $0.invalidate() }
        taps = [:]
    }

    /// Re-reads the app list and updates the taps.
    func refresh() {
        let processes: [AudioProcess]
        do {
            processes = try processProvider.audioProcesses()
        } catch {
            report(error)
            processes = []
        }
        let groups = AppGrouping.apps(from: processes, resolver: resolver, excludedPID: excludedPID)
        apps = groups.map { app in
            AppState(
                app: app,
                volume: settings.appVolume(for: app.id) ?? 1,
                isMuted: settings.isAppMuted(app.id),
                isProcessed: false
            )
        }
        reconcileTaps()
    }

    /// Sets the device that processed apps play on (the system output device).
    /// - Parameter uid: The device UID, or `nil` when there is no output device.
    func setOutputDevice(uid: String?) {
        guard uid != outputDeviceUID else { return }
        outputDeviceUID = uid
        reconcileTaps()
    }

    /// Changes an app's volume.
    /// - Parameters:
    ///   - volume: The new volume; clamped to `0...GainProcessor.maxBoost`.
    ///   - appID: The app.
    func setVolume(_ volume: Float, for appID: String) {
        guard let index = apps.firstIndex(where: { $0.id == appID }) else { return }
        apps[index].volume = min(max(volume, 0), GainProcessor.maxBoost)
        save(apps[index])
        reconcileTaps()
    }

    /// Mutes or unmutes an app.
    /// - Parameter appID: The app.
    func toggleMute(for appID: String) {
        guard let index = apps.firstIndex(where: { $0.id == appID }) else { return }
        apps[index].isMuted.toggle()
        save(apps[index])
        reconcileTaps()
    }

    /// Returns an app to 100 % and unmuted, which stops processing it.
    /// - Parameter appID: The app.
    func reset(_ appID: String) {
        guard let index = apps.firstIndex(where: { $0.id == appID }) else { return }
        apps[index].volume = 1
        apps[index].isMuted = false
        save(apps[index])
        reconcileTaps()
    }

    /// Hides the current error message.
    func dismissError() {
        errorMessage = nil
    }

    // MARK: Private

    private func scheduleRefresh() {
        guard !refreshScheduled else { return }
        refreshScheduled = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            refreshScheduled = false
            refresh()
        }
    }

    private func save(_ state: AppState) {
        // Apps without a bundle identifier are keyed by PID, which is not stable.
        guard !state.id.hasPrefix("pid:") else { return }
        settings.setAppVolume(state.volume, for: state.id)
        settings.setAppMuted(state.isMuted, for: state.id)
    }

    /// Creates, updates or releases taps so they match the app states.
    private func reconcileTaps() {
        let wanted = Dictionary(uniqueKeysWithValues: apps.map { ($0.id, $0) })

        for (appID, tap) in taps where wanted[appID]?.needsProcessing != true {
            tap.invalidate()
            taps[appID] = nil
        }

        for index in apps.indices {
            let state = apps[index]
            guard state.needsProcessing, let outputDeviceUID else {
                if let tap = taps.removeValue(forKey: state.id) { tap.invalidate() }
                apps[index].isProcessed = false
                continue
            }

            if let tap = taps[state.id],
               tap.processObjectIDs == state.app.processObjectIDs,
               tap.outputDeviceUID == outputDeviceUID {
                tap.setGain(state.gain)
                apps[index].isProcessed = true
                continue
            }

            taps.removeValue(forKey: state.id)?.invalidate()
            do {
                let tap = try tapFactory.makeTap(
                    processObjectIDs: state.app.processObjectIDs,
                    outputDeviceUID: outputDeviceUID,
                    gain: state.gain
                )
                taps[state.id] = tap
                apps[index].isProcessed = true
                errorMessage = nil
                schedulePermissionCheck(for: state.id)
            } catch {
                apps[index].isProcessed = false
                report(error)
            }
        }
    }

    /// A tap on a playing app that never receives audio means capture permission was refused.
    private func schedulePermissionCheck(for appID: String) {
        let delay = permissionCheckDelay
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard let self,
                  let tap = taps[appID],
                  let state = apps.first(where: { $0.id == appID }),
                  state.app.isPlaying
            else {
                return
            }
            needsCapturePermission = !tap.hasReceivedAudio
        }
    }

    private func report(_ error: Error) {
        logger.error("\(error.localizedDescription, privacy: .public)")
        errorMessage = error.localizedDescription
    }
}
