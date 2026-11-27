# Orpheus — macOS audio controller

Instructions for coding agents working on this project. Read this file before making any change.

## Project context

Orpheus is a native macOS menu-bar utility for fine-grained control of system audio. From a single menu-bar item, the user can:

- choose the system output device, input device and sound-effects device, and adjust their volume;
- route each running application to a specific output device;
- set a per-application volume and apply a boost beyond the normal maximum;
- have the app start automatically at login and keep working in the background.

Key decisions:

- **Minimum macOS version: 14.2.** Per-application audio relies on CoreAudio Process Taps (`AudioHardwareCreateProcessTap`, `CATapDescription`), which were introduced in macOS 14.2.
- **Distribution: outside the Mac App Store**, signed with Developer ID, hardened runtime enabled, and notarized. The app is **not sandboxed**, but it must never require administrator privileges, `sudo`, a privileged helper, or a custom audio driver/kernel extension.
- **Build system: an Xcode project** (`Orpheus.xcodeproj`). Swift Package Manager is used only to add third-party packages to the project, if ever needed.
- macOS only. Linux, Windows, iOS and other platforms are out of scope.

Specialized skills or domain notes, if any, live in `.agents/skills/`. Consult them before working on audio routing or Process Tap code.

## Goals

- Run exclusively from the menu bar: no Dock icon and no main window (`LSUIElement = YES`).
- Provide one unified panel to select and adjust system output, system input and system sound effects.
- Let the user assign an output device and an independent volume level to each running application.
- Offer a per-application boost that raises output above 100 % while protecting against clipping.
- Start automatically at login and react in real time to device and application changes.

## Tech stack

- **Swift** (latest stable version supported by the current Xcode) for all code.
- **SwiftUI** for the UI, hosted in a `MenuBarExtra` with the `.window` style.
- **AppKit** only where SwiftUI falls short (for example `NSAlert`, `NSWorkspace`, `NSRunningApplication`).
- **CoreAudio (`AudioObject` / `AudioHardware` APIs)** for device enumeration, default device selection, volume, and change notifications.
- **CoreAudio Process Taps** plus a private aggregate device and an IOProc to capture, re-route and amplify per-application audio.
- **ServiceManagement (`SMAppService.mainApp`)** for launch at login.
- **`os.Logger`** for logging.
- **Swift Testing** (preferred) or **XCTest** for tests.

Do not use AVFoundation session APIs to control devices: `AVAudioSession` is iOS-only and has no effect on macOS device routing.

## Repository structure

There is one single source layout. Keep to it.

```text
.
├── AGENTS.md
├── README.md
├── .gitignore
├── .swiftformat                 # formatting rules (if present)
├── Orpheus.xcodeproj
├── Orpheus
│   ├── App
│   │   ├── OrpheusApp.swift              # @main, MenuBarExtra
│   │   └── LaunchAtLogin.swift           # SMAppService wrapper
│   ├── Audio
│   │   ├── AudioDevice.swift             # model of an AudioObjectID device
│   │   ├── AudioDeviceService.swift      # enumeration, defaults, volume, listeners
│   │   ├── AudioProcess.swift            # model of an audio-producing app
│   │   ├── ProcessTapController.swift    # tap + aggregate device + IOProc per app
│   │   └── GainProcessor.swift           # volume / boost / limiter (pure DSP)
│   ├── Settings
│   │   └── SettingsStore.swift           # persisted per-app and device preferences
│   ├── Theme
│   │   └── Theme.swift                   # colour and font tokens (see UI guidelines)
│   ├── Views
│   │   ├── MenuContentView.swift
│   │   ├── DeviceSectionView.swift
│   │   └── AppRowView.swift
│   ├── Resources
│   │   ├── Assets.xcassets               # includes Theme/ colour sets
│   │   └── Fonts                         # bundled display font + licence
│   ├── Info.plist
│   └── Orpheus.entitlements
├── OrpheusTests
│   ├── GainProcessorTests.swift
│   ├── SettingsStoreTests.swift
│   └── Mocks
│       └── MockAudioDeviceService.swift
└── docs
    └── ARCHITECTURE.md
```

- `Audio/` contains all CoreAudio code. Nothing outside this folder calls CoreAudio C APIs directly.
- `Views/` contains SwiftUI views only. Views never talk to CoreAudio; they go through observable models/services.
- Tests live in `OrpheusTests/`, mirroring the source names.
- Add a `CHANGELOG.md` at the root once the first release is tagged.

## Commands: build, test, lint

All commands run from the repository root.

```sh
# Build (Debug)
xcodebuild -project Orpheus.xcodeproj -scheme Orpheus \
  -configuration Debug -destination 'platform=macOS' build

# Run all tests
xcodebuild -project Orpheus.xcodeproj -scheme Orpheus \
  -destination 'platform=macOS' test

# Run a single test class or test
xcodebuild -project Orpheus.xcodeproj -scheme Orpheus \
  -destination 'platform=macOS' test \
  -only-testing:OrpheusTests/GainProcessorTests

# Format (if .swiftformat is present)
swiftformat .

# Lint (if .swiftlint.yml is present)
swiftlint
```

Before considering a task done, the agent must:

1. build with `xcodebuild … build` without errors or new warnings;
2. run `xcodebuild … test` and have all tests pass;
3. run `swiftformat` / `swiftlint` if they are configured, and fix what they report.

Release builds are archived, signed with Developer ID, and notarized with `xcrun notarytool`. Agents do not sign or notarize; they never handle signing credentials.

## Coding conventions

### Naming and formatting

- Follow the [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/).
- File names match the main type they contain, in `PascalCase` (e.g. `AudioDeviceService.swift`).
- Types, protocols and enum names use `PascalCase`; enum cases, properties, functions and constants use `camelCase` (e.g. `static let maxBoost: Float = 4.0`). Do not use `k` prefixes or leading underscores.
- Use access control (`private`, `fileprivate`, `internal`) instead of naming tricks. Default to the narrowest access level.
- Imports at the top of the file, sorted alphabetically, followed by one blank line.
- Use trailing closure syntax when the last argument is a closure.
- Avoid magic numbers: define named constants.

### Swift practices

- Prefer `struct` and `enum`; use `class` only for reference semantics or identity (services, controllers owning CoreAudio resources).
- Prefer `let` over `var`.
- Use `guard` for early exits; prefer `if let` / `guard let` over force unwrapping. Force unwraps are allowed only for programmer errors that cannot happen at runtime, with a comment.
- Use `switch` for exhaustive matching on enums.
- Use `throws` and `do`/`catch` for recoverable errors. Wrap `OSStatus` results in a dedicated `AudioError` type that keeps the status code and the failing operation.
- Use `try?` only when ignoring the error is intentional and safe.
- Use Swift concurrency (`async`/`await`, `Task`, actors) for non-real-time asynchronous work. UI state is `@MainActor`; update it with `await MainActor.run` or from `@MainActor` code, not `DispatchQueue.main.async`.
- Use `@Observable` (Observation framework) for models observed by SwiftUI.
- Use `#if DEBUG` for debug-only code.

### CoreAudio rules

- Access devices through `AudioObjectGetPropertyData` / `AudioObjectSetPropertyData` on `kAudioObjectSystemObject` and device `AudioObjectID`s:
  - devices: `kAudioHardwarePropertyDevices`;
  - defaults: `kAudioHardwarePropertyDefaultOutputDevice`, `kAudioHardwarePropertyDefaultInputDevice`, `kAudioHardwarePropertyDefaultSystemOutputDevice` (sound effects);
  - volume: `kAudioDevicePropertyVolumeScalar` on the main element, or the virtual main volume when the device has no main control; mute: `kAudioDevicePropertyMute`.
- Always check `AudioObjectHasProperty` and `AudioObjectIsPropertySettable` before reading or writing; not every device exposes volume or mute.
- Detect changes with `AudioObjectAddPropertyListenerBlock` (device list, default devices, volume, process list). Remove every listener you add when the owning object is torn down.
- Identify devices persistently by `kAudioDevicePropertyDeviceUID`, never by `AudioObjectID` (IDs change across reboots and reconnections).
- Enumerate audio-producing apps with `kAudioHardwarePropertyProcessObjectList` and read `kAudioProcessPropertyPID`, `kAudioProcessPropertyBundleID` and `kAudioProcessPropertyIsRunningOutput`. Use `NSRunningApplication` for names and icons.
- Per-app routing, volume and boost: create a `CATapDescription` for the target process with mute behaviour `.mutedWhenTapped`, create the tap with `AudioHardwareCreateProcessTap`, attach it to a private aggregate device whose main sub-device is the chosen output, and process the samples in an IOProc via `GainProcessor`. Destroy the IOProc, aggregate device and tap (`AudioHardwareDestroyProcessTap`) when the app quits or the setting is removed.
- Boost must apply a soft limiter or clipping protection; never write samples outside [-1.0, 1.0].
- **Real-time thread rules (IOProc / render callbacks):** no memory allocation, no locks, no Objective-C/Swift messaging that may allocate, no `async`/`await`, no logging, no file or network I/O. Pass parameters with atomics or lock-free structures.
- Use `NSAlert` for user-facing errors that need attention; otherwise show the state inline in the menu.

### Persistence and logging

- Store preferences in `UserDefaults`, behind `SettingsStore`, with keys defined in a `SettingsKey` enum. Per-app settings are keyed by bundle identifier, device settings by device UID.
- Log with `Logger(subsystem: Bundle.main.bundleIdentifier!, category: "...")`, using `.error`, `.warning` (`.default`), `.info` and `.debug` levels. Never use `print` in production code. Do not log audio content.

### Documentation and comments

- Document public and internal-API types and functions with `///` comments (summary, `- Parameters:`, `- Returns:`, `- Throws:`).
- Write other comments only to explain non-obvious logic, CoreAudio quirks, or planned work.
- Keep `docs/ARCHITECTURE.md` up to date when the audio pipeline changes.

## Testing

- Use Swift Testing (`@Test`, `#expect`, `@Suite`) for new tests; XCTest remains acceptable for existing tests.
- Test files are named `<TypeUnderTest>Tests.swift`. Test functions describe the behaviour in `camelCase` (e.g. `boostIsLimitedToUnitRange()`, or `testBoostIsLimitedToUnitRange()` in XCTest).
- Put CoreAudio behind protocols (e.g. `AudioDeviceProviding`) so logic can be tested with mocks in `OrpheusTests/Mocks`. Unit tests must not depend on the real audio hardware of the machine.
- Cover at least: gain/boost math and limiting, settings persistence, device selection logic, and error paths (device disappears, property not settable, tap creation fails, audio-capture permission denied).
- Every new feature or bug fix comes with tests for its testable logic.

## Quality rules

- Prefer native frameworks. Every third-party dependency must be justified in the PR description (use case and why a native API is not enough).
- The app must handle empty device lists, devices without volume controls, and devices or apps disappearing at any time without crashing.
- Audio processing must not add audible latency or noticeable CPU usage; profile with Instruments when touching the IOProc or `GainProcessor`.
- Accessibility: every control has a meaningful accessibility label (`.accessibilityLabel`), works with VoiceOver and keyboard navigation, and respects Increase Contrast and Reduce Transparency.
- Devices and applications are shown with their native names.
- Do not store anything sensitive in preferences; audio data is never written to disk.

Before handing back, confirm:

- [ ] `xcodebuild build` succeeds with no new warnings.
- [ ] `xcodebuild test` passes.
- [ ] `swiftformat` / `swiftlint` are clean, if configured.
- [ ] New logic is covered by tests, including error paths.
- [ ] Every CoreAudio listener, tap, aggregate device and IOProc created is also released.
- [ ] No allocation, lock or logging was added on the real-time audio thread.
- [ ] UI is usable with VoiceOver and the keyboard.
- [ ] No unjustified dependency was added.

## Permissions and system integration

- `Info.plist` must contain `LSUIElement = YES` and `NSAudioCaptureUsageDescription` (required for Process Taps; macOS shows a system consent prompt). Add `NSMicrophoneUsageDescription` only if the app actually reads input audio.
- Request audio-capture consent only when the user first enables a per-app feature, and handle refusal gracefully (disable per-app controls and explain how to re-enable them in System Settings).
- Launch at login uses `SMAppService.mainApp.register()` / `unregister()`, and the UI reflects `SMAppService.mainApp.status`, including `.requiresApproval`.
- Hardened runtime is enabled; App Sandbox is disabled. Do not add entitlements beyond what a feature strictly needs.

## Prohibitions

### Standard prohibitions

- Do not edit generated files or vendored dependencies.
- Do not commit secrets, certificates, provisioning profiles or notarization credentials.
- Do not disable tests or lint rules to make CI pass.
- Do not rewrite shared Git history.

### Project-specific prohibitions

- Do not require administrator privileges: no `sudo`, no privileged helper tools, no `SMJobBless`, no installer scripts that write to system locations.
- Do not install audio drivers, HAL plug-ins or kernel/system extensions; per-app audio must use Process Taps only.
- Do not use private or undocumented Apple APIs.
- Do not hardcode absolute paths that differ across macOS versions or machines.
- Do not capture or process an application's audio before the user has granted audio-capture consent.
- Do not assume a device supports volume, mute or a given format; check first.
- Do not open a main window or show a Dock icon; the menu bar is the only entry point.
- Do not use iOS-only APIs (`AVAudioSession`, `UIKit`, `UIAlertController`).

## Git workflow

- `main` holds production-ready code. Never commit directly to `main`.
- Branch from `main`: `feature/<short-description>`, `bugfix/<short-description>`, `chore/<short-description>`.
- Follow Conventional Commits for commit messages; PR titles use `type(scope): subject`.
- Keep commits small and atomic: one logical change per commit.
- CI must pass before merging; at least one maintainer approval is required.
- Merge with squash and merge to keep a linear history on `main`.
- Once `CHANGELOG.md` exists, update it in any PR that adds a feature or a breaking change.

## UI guidelines

Orpheus has a **gamified look inspired by Today Quest**: a dark, playful, "game HUD" interface with bold type, chunky rounded cards and bright neon accents. It is a visual style only: there is **no XP, level, streak, reward or progression system**. Every number shown is a real audio value (volume, boost, device count).

### Overall layout

- A single menu-bar item: a template SF Symbol (e.g. `speaker.wave.2.fill`) in the menu bar itself, so it stays native there. The game style applies to the panel it opens.
- The panel is a `MenuBarExtra` with the `.window` style, about 340-380 pt wide, on a dark background. Do not use system vibrancy as the main background; the panel has its own colours.
- Layout, top to bottom:
  1. **Header**: app name "ORPHEUS" in the display font, a "badge" tile showing the current output device icon, and a settings button.
  2. **System card**: Output, Input and Sound effects rows, each with a device picker and a volume bar.
  3. **Apps card**: one row per application currently playing audio.
  4. **Collapsed sections** (e.g. "OTHER APPS" with a count pill) for long lists, expanded on click.
  5. **Footer**: launch-at-login toggle and Quit.

### Colour tokens

Define colours once, as named tokens in the asset catalog (`Resources/Assets.xcassets/Theme/`) exposed through a `Theme` type. Never hardcode hex values in views.

| Token | Hex | Use |
|---|---|---|
| `background` | `#0D0A1F` | panel background |
| `surface` | `#1B1538` | main cards |
| `surfaceMuted` | `#161131` | secondary cards, collapsed sections, icon buttons |
| `textPrimary` | `#FFFFFF` | titles, app and device names |
| `textSecondary` | `#C0B7ED` | subtitles, captions |
| `textDisabled` | `#5F5A7E` | inactive rows, muted apps |
| `accentPrimary` | `#A88BFF` | default accent: badges, checkboxes, selected pickers, links |
| `accentBoost` | `#FFC53D` | volume bars and anything boost-related |
| `boostChipBackground` | `#3A2E10` | background of yellow value chips (e.g. "+150 %") |
| `accentAction` | `#FF3D86` | main action button, mute state, recording/live indicator |
| `accentSuccess` | `#3EE6A0` | active / connected / "in use" states, segment progress |
| `accentInfo` | `#53E7FF` | device and hardware information (sample rate, transport type) |
| `infoSurface` | `#0F2B38` | background of info cards (e.g. current default device) |

- Use a coloured text on a dark tinted background of the same hue for chips and pills (yellow on `boostChipBackground`, green on dark green, and so on).
- Plan for **themes** like Today Quest's (Néon, Rétro 8-bit, Cosmos…): the table above is the default "Néon" theme. Views read colours only from `Theme`, so another theme is just another set of tokens.
- The panel is always dark by default. A light theme is an optional extra theme, not an automatic Light Mode switch.

### Typography

- **Display font** (titles, section headers, big numbers): a bold geometric typeface with a game feel, bundled in `Resources/Fonts` and registered in `Info.plist` (Today Quest uses this style; pick an open-licence font such as Space Grotesk and keep its licence file in the repo).
- Section titles are **uppercase** in the display font ("SYSTEM", "APPS", "OUTPUT").
- **Body text**: the system font (SF Pro) for names, captions and secondary text.
- Numbers (volume %, boost %) use monospaced digits (`.monospacedDigit()`) so they do not jitter while sliding.
- Support Dynamic Type sizes where SwiftUI allows it; never go below 11 pt.

### Components

- **Cards**: large rounded rectangles (corner radius about 20-24 pt), filled with `surface`, no border, with thin `surfaceMuted` dividers between rows.
- **"Chunky" 3D effect**: buttons, badges and the header tile have a darker bottom edge (a 3-4 pt offset shadow of a darker shade of their colour) to look pressable, like game buttons. When pressed, the button moves down and the edge disappears.
- **Volume bars**: thick (8-10 pt), fully rounded capsule tracks in `surfaceMuted` with a filled part in the accent colour (yellow `accentBoost` by default). Implement them as a custom slider so they look like progress bars while staying fully accessible (`.accessibilityValue`, `.accessibilityAdjustableAction`).
- **Boost**: when the volume goes above 100 %, the part of the bar above 100 % gets a brighter yellow/glow, and a yellow chip shows the value ("+150 %"). Boost has its own distinct, very visible state.
- **Segment indicator**: small capsule segments (green when active) to show compact states, e.g. how many apps are currently playing.
- **App rows**: app icon in a rounded tile, name in `textPrimary`, current device in `textSecondary` with a small SF Symbol, a volume bar, and a value chip on the right. Muted apps are shown dimmed with the name struck through, like completed tasks in Today Quest.
- **Checkboxes and toggles**: rounded squares outlined in `accentPrimary`; checked = filled `accentSuccess` with a dark check mark.
- **Main action button**: a round `accentAction` button with a glow (for example "Mute all" / "Unmute").
- **Icon buttons**: rounded square tiles in `surfaceMuted` with a white SF Symbol.
- **Info cards**: `infoSurface` background with `accentInfo` text, for details about the current device.
- **Toasts**: short, bold, yellow pill-shaped banners with a darker bottom edge for quick feedback ("AirPods connected", "Boost on"). They appear at the top of the panel and disappear after about 2 seconds. Use them instead of alerts for non-critical events.
- **Decoration**: a few soft, rounded coloured squares in a corner of the header, as in Today Quest, kept subtle and never behind text.

### Motion and feedback

- Use short, springy animations (`.spring(response: 0.3, dampingFraction: 0.7)`) for presses, toggles, expanding sections and toasts.
- Bars animate smoothly to their new value when the volume changes outside the app.
- Respect **Reduce Motion**: replace springs and bounces with simple fades.
- No sounds for UI feedback (the app controls audio; it must not add noise).

### Accessibility and native behaviour

- Every custom control has an accessibility label, value and, for bars, adjustable actions; everything is reachable with the keyboard and VoiceOver.
- Text and important icons reach at least a 4.5:1 contrast ratio against their background; check every new token pair.
- With **Increase Contrast**, add 1 pt borders to cards and controls. With **Reduce Transparency**, remove glows.
- Show help text on hover with `.help(...)`.
- Use `NSAlert` only for critical errors (for example audio-capture permission permanently denied); use toasts or inline messages otherwise.

### What not to do

- No XP, levels, streaks, rewards, badges to "earn" or any progression mechanics.
- No hardcoded colours or fonts in views: always go through `Theme`.
- No custom drawing in the menu bar itself; only the panel is styled.
