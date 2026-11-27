import AppKit
import CoreAudio

/// A CoreAudio process object: one process that is a client of the audio system.
struct AudioProcess: Identifiable, Hashable, Sendable {
    /// The CoreAudio process object ID, used to build a Process Tap.
    let id: AudioObjectID
    let pid: pid_t
    /// The bundle identifier reported by CoreAudio, if any.
    let bundleID: String?
    /// Whether the process is currently playing audio.
    let isRunningOutput: Bool
}

/// What the app layer knows about a running process, from `NSRunningApplication` and BSD.
struct RunningAppInfo: Equatable {
    let pid: pid_t
    let parentPID: pid_t?
    let bundleID: String?
    let name: String
    /// Whether it is a regular app that appears in the Dock.
    let isRegular: Bool
}

/// Resolves a PID to app information, so grouping can be tested without real processes.
protocol RunningAppResolving {
    /// Information about a running process.
    /// - Parameter pid: The process ID.
    /// - Returns: The information, or `nil` if the process is gone.
    func info(for pid: pid_t) -> RunningAppInfo?

    /// Regular apps currently running, used to match helper processes by bundle ID.
    func regularApps() -> [RunningAppInfo]
}

/// An application as shown in the panel: one app and all its audio helper processes.
struct AudioApp: Identifiable, Hashable, Sendable {
    /// The bundle identifier, or `"pid:<pid>"` when the app has none. Used as the settings key.
    let id: String
    let name: String
    /// The PID of the app itself, used to look up its icon.
    let pid: pid_t
    /// The CoreAudio process objects that make up this app's audio.
    let processObjectIDs: [AudioObjectID]
    /// Whether any of its processes is playing audio.
    let isPlaying: Bool
}

/// Groups CoreAudio process objects into apps.
///
/// Browsers and many other apps play audio from helper processes
/// (for example "Google Chrome Helper" or WebKit's "WebContent"). Each helper is attached to
/// the regular app that owns it, using, in order: the parent process, the bundle-ID prefix
/// (`com.google.Chrome.helper` → `com.google.Chrome`), and WebKit processes → Safari.
enum AppGrouping {
    private static let webKitPrefix = "com.apple.WebKit."
    private static let safariBundleID = "com.apple.Safari"
    private static let maxParentDepth = 8

    /// Builds the app list.
    /// - Parameters:
    ///   - processes: The CoreAudio process objects.
    ///   - resolver: Looks up running-app information.
    ///   - excludedPID: A process to leave out (Orpheus itself).
    /// - Returns: Apps sorted with playing apps first, then by name.
    static func apps(
        from processes: [AudioProcess],
        resolver: RunningAppResolving,
        excludedPID: pid_t
    ) -> [AudioApp] {
        let regularApps = resolver.regularApps()
        var groups: [String: (owner: RunningAppInfo, objects: [AudioObjectID], isPlaying: Bool)] = [:]

        for process in processes where process.pid != excludedPID {
            guard let owner = owner(of: process, resolver: resolver, regularApps: regularApps),
                  owner.pid != excludedPID
            else {
                continue
            }
            let key = owner.bundleID ?? "pid:\(owner.pid)"
            var group = groups[key] ?? (owner, [], false)
            group.objects.append(process.id)
            group.isPlaying = group.isPlaying || process.isRunningOutput
            groups[key] = group
        }

        return groups
            .map { key, group in
                AudioApp(
                    id: key,
                    name: group.owner.name,
                    pid: group.owner.pid,
                    processObjectIDs: group.objects.sorted(),
                    isPlaying: group.isPlaying
                )
            }
            .sorted { lhs, rhs in
                if lhs.isPlaying != rhs.isPlaying { return lhs.isPlaying }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }

    private static func owner(
        of process: AudioProcess,
        resolver: RunningAppResolving,
        regularApps: [RunningAppInfo]
    ) -> RunningAppInfo? {
        guard let info = resolver.info(for: process.pid) else { return nil }
        if info.isRegular { return info }

        // 1. Walk up the parent processes.
        var parentPID = info.parentPID
        for _ in 0 ..< maxParentDepth {
            guard let pid = parentPID, pid > 1, let parent = resolver.info(for: pid) else { break }
            if parent.isRegular { return parent }
            parentPID = parent.parentPID
        }

        // 2. Match the bundle ID prefix of a regular app.
        let bundleID = info.bundleID ?? process.bundleID
        if let bundleID {
            let match = regularApps
                .filter { app in
                    guard let appID = app.bundleID else { return false }
                    return bundleID.hasPrefix(appID + ".")
                }
                .max { ($0.bundleID?.count ?? 0) < ($1.bundleID?.count ?? 0) }
            if let match { return match }

            // 3. WebKit helpers belong to Safari when it is running.
            if bundleID.hasPrefix(webKitPrefix),
               let safari = regularApps.first(where: { $0.bundleID == safariBundleID }) {
                return safari
            }
        }

        // Background processes without an owning app are not shown.
        return nil
    }
}

/// The `NSRunningApplication` / BSD implementation of ``RunningAppResolving``.
struct SystemRunningAppResolver: RunningAppResolving {
    func info(for pid: pid_t) -> RunningAppInfo? {
        let app = NSRunningApplication(processIdentifier: pid)
        guard app != nil || Self.parentPID(of: pid) != nil else { return nil }
        return RunningAppInfo(
            pid: pid,
            parentPID: Self.parentPID(of: pid),
            bundleID: app?.bundleIdentifier,
            name: app?.localizedName ?? "Process \(pid)",
            isRegular: app?.activationPolicy == .regular
        )
    }

    func regularApps() -> [RunningAppInfo] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .map { app in
                RunningAppInfo(
                    pid: app.processIdentifier,
                    parentPID: nil,
                    bundleID: app.bundleIdentifier,
                    name: app.localizedName ?? app.bundleIdentifier ?? "App",
                    isRegular: true
                )
            }
    }

    /// The parent PID from `sysctl(KERN_PROC_PID)`.
    private static func parentPID(of pid: pid_t) -> pid_t? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0) == 0, size > 0 else { return nil }
        return info.kp_eproc.e_ppid
    }
}
