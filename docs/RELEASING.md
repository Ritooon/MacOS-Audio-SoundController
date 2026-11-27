# Releasing Orpheus

`scripts/release.sh` builds `build/release/Orpheus-<version>.dmg` from a Release archive.
Bump `MARKETING_VERSION` (and `CURRENT_PROJECT_VERSION`) in the project before a release.

## Without an Apple Developer account (ad hoc)

```sh
scripts/release.sh --adhoc
```

The app is signed ad hoc with the hardened runtime. It works on any Mac running macOS 14.2+,
but Gatekeeper blocks the first launch because the app is not notarized. Whoever installs it must:

1. drag Orpheus to Applications;
2. try to open it once, then go to **System Settings > Privacy & Security** and click **Open Anyway**
   (on recent macOS versions, right-click > Open is no longer enough);
   or run `xattr -dr com.apple.quarantine /Applications/Orpheus.app`.

## With a paid Apple Developer account (Developer ID + notarization)

One-time setup on the Mac that builds:

1. In Xcode > Settings > Accounts, add the Apple ID, then **Manage Certificates > + > Developer ID Application**.
2. Create an app-specific password at <https://account.apple.com> (Sign-In and Security).
3. Store notarization credentials in the keychain (prompts for the password, nothing goes in the repo):

   ```sh
   xcrun notarytool store-credentials orpheus-notary \
     --apple-id "<apple id>" --team-id "<TEAM_ID>"
   ```

Then each release:

```sh
TEAM_ID=<TEAM_ID> scripts/release.sh
```

The script archives, exports with Developer ID, builds and signs the .dmg, submits it to Apple's
notary service, staples the ticket and checks it with `spctl`. The resulting .dmg opens on any Mac
without a Gatekeeper warning.

## Entitlements and usage strings

- Not sandboxed (distributed outside the Mac App Store).
- Hardened runtime with `com.apple.security.device.audio-input`, needed to read the input streams of
  the Process Tap aggregate devices.
- `NSAudioCaptureUsageDescription` (Process Taps consent) and `NSMicrophoneUsageDescription` in `Info.plist`.
