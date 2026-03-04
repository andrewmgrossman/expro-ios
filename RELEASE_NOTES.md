# Release Notes

## 0.1.0 (Initial implementation)

- Added `DevialetCore` Swift package for direct UDP control of Devialet Expert Pro.
- Implemented protocol decode/encode parity with Python reference script.
- Added command reliability flow (4 sends + packet counter + CRC16).
- Added channel mapping parity including slot 1 hardcoded command bytes.
- Added cached IP/status persistence using `UserDefaults`.
- Added SwiftUI app source with:
  - Connection/device header
  - Power and mute controls
  - Volume slider with debounce + safe clamp
  - Dynamic channel grid
  - Diagnostics panel and retry flow
- Added fixture-based unit tests and real-device integration checklist.

## Known limitations in this repo state

- Full iOS build is not executed in this environment because Xcode is not selected (`xcodebuild` unavailable).
- Use Xcode on macOS with a full iOS SDK installation to build/run on device and TestFlight.
