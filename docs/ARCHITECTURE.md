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

## Planned

- Per-app audio: `AudioProcess`, `ProcessTapController` (Process Tap + private aggregate
  device + IOProc) and `GainProcessor` (volume, boost, limiter).
- `SettingsStore` for per-app and per-device preferences.
