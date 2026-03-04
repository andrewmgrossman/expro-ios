# Devialet iPhone App Source

This folder contains a native iOS implementation for controlling Devialet Expert Pro amplifiers with direct UDP networking.

## What is implemented

- `Sources/DevialetCore/`: protocol, transport, controller, safety policy, shared models
- `Tests/DevialetCoreTests/`: fixture-based protocol tests and parity checks
- `DevialetExpertControlApp/`: SwiftUI app source (main screen, diagnostics, app state store, `Info.plist`)

## Feature coverage

- Discovery by listening on UDP `45454`
- Status decode parity (device name, power, mute, channel, volume, dynamic inputs)
- Command send on UDP `45455` with 4x send reliability, packet counters, CRC16
- Power on/off/toggle
- Mute/unmute/toggle
- Volume set with clamp to `[-96, 0]` and 0.5 dB steps
- Channel switch with non-linear mapping and slot 1 hardcoded bytes (`0x3F 0x80`)
- Cached amplifier IP and cached status via `UserDefaults`
- Optimistic UI updates and 1s refresh loop while app is active

## Add to Xcode

### Option A: Generate project with XcodeGen

```bash
brew install xcodegen
cd ios
xcodegen generate
open DevialetExpertControl.xcodeproj
```

The generator spec is in `ios/project.yml`.

### Option B: Manual project setup

1. Open Xcode and create a new iOS App project (SwiftUI, iOS 17+).
2. Add `DevialetExpertControlApp/*.swift` files and `DevialetExpertControlApp/Info.plist` to the app target.
3. Add local Swift package dependency pointing to this `ios/` folder.
4. Link the package product `DevialetCore` to your app target.
5. Ensure the target uses the provided local network usage description in `Info.plist`.

## Tests

Run from this folder:

```bash
cd ios
swift test
```

If your environment has Swift/SDK cache permission issues or toolchain mismatch, run tests from a machine with full Xcode selected:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

## Real-device acceptance checklist

Use `INTEGRATION_CHECKLIST.md` in this folder for on-network validation against a real Expert Pro.
