import Foundation
import Observation
import os
import ServiceManagement

/// Wraps `SMAppService.mainApp` so the panel can show and change launch at login.
@MainActor
@Observable
final class LaunchAtLogin {
    /// Whether the app is registered to open at login.
    private(set) var isEnabled = false
    /// Whether the user must approve the login item in System Settings.
    private(set) var requiresApproval = false
    /// The last error, shown inline in the panel.
    private(set) var errorMessage: String?

    @ObservationIgnored private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Orpheus",
        category: "LaunchAtLogin"
    )

    init() {
        refresh()
    }

    /// Reads the current registration status.
    func refresh() {
        let status = SMAppService.mainApp.status
        isEnabled = status == .enabled || status == .requiresApproval
        requiresApproval = status == .requiresApproval
    }

    /// Registers or unregisters the app as a login item.
    /// - Parameter enabled: `true` to open the app at login.
    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            errorMessage = nil
        } catch {
            logger.error("Launch at login change failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = "Could not change launch at login."
        }
        refresh()
    }

    /// Opens the Login Items pane of System Settings.
    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
