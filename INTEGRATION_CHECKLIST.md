# Real Amplifier Integration Checklist

Run this on iPhone + Devialet Expert Pro on the same local network.

## Pre-checks

- App has Local Network permission enabled in iOS Settings.
- Amplifier is reachable on LAN and broadcasting status packets.
- No firewall blocks UDP ports `45454` and `45455`.

## Discovery and status

- Launch app and confirm device appears within 3 seconds.
- Confirm device name and IP are displayed.
- Confirm connection indicator becomes green.
- Confirm status updates roughly every second.

## Power

- Tap power toggle from standby -> on and confirm status flips to ON.
- Tap power toggle from on -> standby and confirm status flips to STANDBY.
- Verify transitions recover correctly if delayed by amplifier warm-up/cool-down.

## Volume

- Drag slider to `-20.0 dB`; verify amplifier reports approximately `-20.0 dB`.
- Drag slider to `0.0 dB`; verify clamp does not exceed `0.0 dB`.
- Drag slider below `-96.0 dB`; verify clamp remains `-96.0 dB`.
- Confirm rapid slider movement does not flood commands (debounced behavior).

## Mute

- Toggle mute on and verify muted state.
- Toggle mute off and verify unmuted state.
- Repeat quickly to confirm state remains consistent.

## Channel switching

- Switch to each enabled input and confirm amplifier state matches selected slot.
- Explicitly verify slot 1 works (special command bytes path).
- Attempt unavailable slot (if accessible via debug action) and confirm app blocks it.

## Resilience

- Power-cycle Wi-Fi/router while app is open; confirm recovery after network returns.
- Reboot amplifier; confirm rediscovery and control resume.
- Temporarily deny local network permission; verify clear error and retry instructions.

## Pass criteria

- All controls succeed without app crash.
- Status reconciliation occurs within the next broadcast cycle after each command.
- Cached IP path reconnects quickly on app relaunch.
