# Orpheus architecture

## Layers

```text
OrpheusApp (MenuBarExtra, .window style)
  └─ MenuContentView ── DeviceSectionView ── VolumeBar / QuestComponents   (Views/, SwiftUI only)
        │ reads and calls
        ▼
  SystemAudioModel  (@MainActor @Observable)                              (Audio/, no C calls)
        │ AudioDeviceProviding protocol
        ▼
  AudioDeviceService (CoreAudio AudioObject APIs, listeners)               (Audio/)
```

- **Views** never call CoreAudio. They read `SystemAudioModel` and call its methods.
- **`SystemAudioModel`** holds the state for the three system roles (output, input,
  sound effects): candidate devices, selected device and volume. It reports failures as
  inline error messages and produces toasts when a device connects or disconnects.
- **`AudioDeviceProviding`** abstracts the hardware so the model is tested with
  `MockAudioDeviceService`, without real audio devices.
- **`AudioDeviceService`** is the only type that calls CoreAudio. It:
  - lists devices (`kAudioHardwarePropertyDevices`) with name, UID, transport type,
    channel counts (stream configuration) and nominal sample rate;
  - reads and writes the default output, input and system-output devices;
  - reads and writes volume (`kAudioDevicePropertyVolumeScalar` on the main element, or
    `kAudioHardwareServiceDeviceProperty_VirtualMainVolume` when there is no main control)
    and mute, after checking `AudioObjectHasProperty` / `AudioObjectIsPropertySettable`;
  - wraps every failing `OSStatus` in `AudioError` (operation + status).

## Change notifications

`AudioDeviceService.startObserving` adds listener blocks on the main queue for the device
list and the three default devices, plus volume and mute listeners on the current default
output and input devices. These device listeners are rebuilt whenever a default device or
the device list changes. `stopObserving` (also called from `deinit`) removes every listener.

`SystemAudioModel` coalesces bursts of notifications into a single refresh.

## Sound effects volume

macOS has no public API for the alert volume, so the sound-effects row only selects the
device.

## Theme

`Theme` exposes the colour tokens from `Resources/Assets.xcassets/Theme/` (the default
"Néon" theme), layout metrics, the display font (Space Grotesk Bold, registered with
`ATSApplicationFontsPath`) and the motion curve, which falls back to a fade with Reduce
Motion. Views get the theme from the environment (`\.theme`).

## Per-app volume and boost

```text
AppAudioModel (@MainActor @Observable)
  ├─ AudioProcessProviding → AudioProcessService (kAudioHardwarePropertyProcessObjectList)
  ├─ AppGrouping + RunningAppResolving (helpers → owning app)
  ├─ SettingsStore (volume / mute per bundle ID)
  └─ ProcessTapMaking → ProcessTapController, one per processed app:

     app processes ──CATapDescription (stereo mixdown, mutedWhenTapped)──▶ Process Tap
        Process Tap ──▶ private aggregate device (main sub-device = system output)
        aggregate IOProc ──GainProcessor (gain ramp + soft limiter)──▶ output device
```

- **Grouping.** Apps often play from helper processes. `AppGrouping` attaches each
  process to a regular app by walking parent PIDs, then by bundle-ID prefix
  (`com.google.Chrome.helper` → `com.google.Chrome`), then WebKit → Safari. Processes with no
  owning app, and Orpheus itself, are hidden.
- **Only when needed.** An app is tapped only while its volume is not 100 % or it is muted.
  At 100 % its audio is untouched and the tap is destroyed. The audio-capture consent prompt
  therefore appears the first time the user changes an app's volume.
- **Gain.** `GainProcessor.gain(forVolume:)` is quadratic up to 100 % and linear above it, up
  to `GainProcessor.maxBoost` (300 %). The IOProc ramps from the previous gain to the new one
  across each buffer and passes every sample through a soft limiter (transparent below 0.9,
  never reaching ±1).
- **Real-time safety.** The IOProc block captures only an `AtomicFloat` (target gain,
  lock-free via the `OrpheusAtomics` C module in `Modules/`), a pointer holding the last
  ramp gain, and constants. It does not allocate, lock or log.
- **Buffers.** The aggregate lists the output device's own input streams first, then the
  tap's mixdown stream, so the IOProc reads the last input buffer. Tap and output formats
  must be 32-bit float, checked before starting.
- **Output changes.** `SystemAudioModel.onOutputDeviceChange` tells `AppAudioModel`, which
  rebuilds every tap on the new device. Taps are also rebuilt when an app's set of processes
  changes, and released when it quits.
- **Permission refused.** If a processed app plays but its tap never receives audio for a
  few seconds, the panel explains how to allow Orpheus in Privacy & Security, or to reset the
  app to 100 %.
- Orpheus's aggregate devices use the UID prefix `ProcessTapController.aggregateUIDPrefix`
  and are filtered out of device lists.

## Menu-bar and app icons

The menu-bar icon is a monochrome lyre at full size with no background, drawn by
`MenuBarIcon` with a lazy `NSImage` drawing handler: white on a dark menu bar, black on a
light one (like a template image). It is not a template so its strings can show the state:
yellow when an app is boosted, pink when the output is muted. `LyreGeometry` and the PNGs in
`AppIcon.appiconset` share the same geometry.

## Planned

- Choosing a different output device per app (the aggregate's main sub-device).
