# Orpheus

Orpheus is a native macOS menu-bar app for controlling system audio: choose the output,
input and sound-effects devices and adjust their volume from one panel. Per-app routing,
volume and boost (CoreAudio Process Taps) come in later milestones.

- macOS 14.2 or later
- Xcode 16 or later
- Distributed outside the Mac App Store (Developer ID, notarized), never needs admin rights

## Build and test

```sh
xcodebuild -project Orpheus.xcodeproj -scheme Orpheus \
  -configuration Debug -destination 'platform=macOS' build

xcodebuild -project Orpheus.xcodeproj -scheme Orpheus \
  -destination 'platform=macOS' test
```

Orpheus runs only from the menu bar (no Dock icon, no main window).

See [AGENTS.md](AGENTS.md) for conventions and [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the design.

## Credits

The display font is [Space Grotesk](https://github.com/floriankarsten/space-grotesk) by Florian Karsten,
licensed under the SIL Open Font License 1.1 (`Orpheus/Resources/Fonts/SpaceGrotesk-OFL.txt`).
