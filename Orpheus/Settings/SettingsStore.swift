import Foundation

/// The `UserDefaults` keys used by Orpheus.
enum SettingsKey: String, CaseIterable {
    /// Per-app volume, `[bundleID: Double]`; 1 means 100 %.
    case appVolumes = "app.volumes"
    /// Muted apps, `[bundleID: Bool]`.
    case appMutes = "app.mutes"
    /// The selected panel theme, a ``ThemeID`` raw value. Read and written with `@AppStorage`.
    case themeID = "theme.id"
}

/// Persists user preferences. Per-app settings are keyed by bundle identifier.
///
/// Default values (100 %, not muted) are not stored, so an app returns to the normal
/// system behaviour once reset.
final class SettingsStore {
    private let defaults: UserDefaults

    /// Creates a store.
    /// - Parameter defaults: The defaults database; tests pass an isolated suite.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The saved volume of an app.
    /// - Parameter appID: The app's bundle identifier.
    /// - Returns: The volume, where 1 means 100 %, or `nil` when none is saved.
    func appVolume(for appID: String) -> Float? {
        (dictionary(.appVolumes) as? [String: Double])?[appID].map(Float.init)
    }

    /// Saves the volume of an app; 100 % removes the entry.
    /// - Parameters:
    ///   - volume: The volume, where 1 means 100 %.
    ///   - appID: The app's bundle identifier.
    func setAppVolume(_ volume: Float, for appID: String) {
        var values = (dictionary(.appVolumes) as? [String: Double]) ?? [:]
        values[appID] = volume == 1 ? nil : Double(volume)
        defaults.set(values, forKey: SettingsKey.appVolumes.rawValue)
    }

    /// Whether an app is saved as muted.
    /// - Parameter appID: The app's bundle identifier.
    /// - Returns: `true` if muted.
    func isAppMuted(_ appID: String) -> Bool {
        (dictionary(.appMutes) as? [String: Bool])?[appID] ?? false
    }

    /// Saves the mute state of an app; unmuted removes the entry.
    /// - Parameters:
    ///   - muted: The mute state.
    ///   - appID: The app's bundle identifier.
    func setAppMuted(_ muted: Bool, for appID: String) {
        var values = (dictionary(.appMutes) as? [String: Bool]) ?? [:]
        values[appID] = muted ? true : nil
        defaults.set(values, forKey: SettingsKey.appMutes.rawValue)
    }

    private func dictionary(_ key: SettingsKey) -> [String: Any]? {
        defaults.dictionary(forKey: key.rawValue)
    }
}
