# Script Parity Checklist

## Protocol and status decode

- Python `crc16()` ([devialet_expert_control.py](/Users/andrewmg/devialet/devialet_expert_control.py:41))
  - iOS `DevialetProtocol.crc16(bytes:)` ([DevialetProtocol.swift](/Users/andrewmg/devialet/ios/Sources/DevialetCore/DevialetProtocol.swift:163))
- Status decode logic ([devialet_expert_control.py](/Users/andrewmg/devialet/devialet_expert_control.py:166))
  - iOS `decodeStatus(packet:ipAddress:)` ([DevialetProtocol.swift](/Users/andrewmg/devialet/ios/Sources/DevialetCore/DevialetProtocol.swift:12))
- 2048-byte receive buffer requirement ([devialet_expert_control.py](/Users/andrewmg/devialet/devialet_expert_control.py:110))
  - iOS constant `statusPacketPreferredBufferLength` ([DevialetProtocol.swift](/Users/andrewmg/devialet/ios/Sources/DevialetCore/DevialetProtocol.swift:8))

## Discovery and cached IP behavior

- Python cached IP read/write ([devialet_expert_control.py](/Users/andrewmg/devialet/devialet_expert_control.py:80), [devialet_expert_control.py](/Users/andrewmg/devialet/devialet_expert_control.py:89))
  - iOS `UserDefaults` cache (`devialet.cached.ip`, `devialet.cached.status`) ([DevialetExpertControllerIOS.swift](/Users/andrewmg/devialet/ios/Sources/DevialetCore/DevialetExpertControllerIOS.swift:5))
- Python discover/get status flow ([devialet_expert_control.py](/Users/andrewmg/devialet/devialet_expert_control.py:96), [devialet_expert_control.py](/Users/andrewmg/devialet/devialet_expert_control.py:124))
  - iOS `discover(timeout:)` and `getCurrentStatus(timeout:)` ([DevialetExpertControllerIOS.swift](/Users/andrewmg/devialet/ios/Sources/DevialetCore/DevialetExpertControllerIOS.swift:66), [DevialetExpertControllerIOS.swift](/Users/andrewmg/devialet/ios/Sources/DevialetCore/DevialetExpertControllerIOS.swift:81))

## Command packet behavior

- Python `_send_command` 4x packet send and counter/CRC update ([devialet_expert_control.py](/Users/andrewmg/devialet/devialet_expert_control.py:209))
  - iOS `sendReliably(basePacket:ipAddress:)` + `applyPacketCounterAndCRC` ([DevialetExpertControllerIOS.swift](/Users/andrewmg/devialet/ios/Sources/DevialetCore/DevialetExpertControllerIOS.swift:136), [DevialetProtocol.swift](/Users/andrewmg/devialet/ios/Sources/DevialetCore/DevialetProtocol.swift:127))
- Header bytes `0x44 0x72` ([devialet_expert_control.py](/Users/andrewmg/devialet/devialet_expert_control.py:217))
  - iOS `makeCommandPacket` ([DevialetProtocol.swift](/Users/andrewmg/devialet/ios/Sources/DevialetCore/DevialetProtocol.swift:50))

## Control methods

- Power on/off/toggle ([devialet_expert_control.py](/Users/andrewmg/devialet/devialet_expert_control.py:236), [devialet_expert_control.py](/Users/andrewmg/devialet/devialet_expert_control.py:243), [devialet_expert_control.py](/Users/andrewmg/devialet/devialet_expert_control.py:250))
  - iOS `send(.powerOn/.powerOff/.togglePower)` resolution ([DevialetExpertControllerIOS.swift](/Users/andrewmg/devialet/ios/Sources/DevialetCore/DevialetExpertControllerIOS.swift:99))
- Mute/unmute/toggle ([devialet_expert_control.py](/Users/andrewmg/devialet/devialet_expert_control.py:258), [devialet_expert_control.py](/Users/andrewmg/devialet/devialet_expert_control.py:265), [devialet_expert_control.py](/Users/andrewmg/devialet/devialet_expert_control.py:272))
  - iOS `send(.mute/.unmute/.toggleMute)` resolution ([DevialetExpertControllerIOS.swift](/Users/andrewmg/devialet/ios/Sources/DevialetCore/DevialetExpertControllerIOS.swift:104))
- Volume encoding/clamp behavior ([devialet_expert_control.py](/Users/andrewmg/devialet/devialet_expert_control.py:280))
  - iOS `SafetyPolicy` + `encodeVolume(db:)` ([SafetyPolicy.swift](/Users/andrewmg/devialet/ios/Sources/DevialetCore/SafetyPolicy.swift:3), [DevialetProtocol.swift](/Users/andrewmg/devialet/ios/Sources/DevialetCore/DevialetProtocol.swift:142))
- Channel mapping with slot 1 special-case and non-linear slots ([devialet_expert_control.py](/Users/andrewmg/devialet/devialet_expert_control.py:318))
  - iOS `makeCommandPacket(for:.setChannel)` ([DevialetProtocol.swift](/Users/andrewmg/devialet/ios/Sources/DevialetCore/DevialetProtocol.swift:82))

## UX additions beyond parity

- Optimistic updates after send ([DevialetExpertControllerIOS.swift](/Users/andrewmg/devialet/ios/Sources/DevialetCore/DevialetExpertControllerIOS.swift:222))
- Debounced volume updates in UI store ([AppStateStore.swift](/Users/andrewmg/devialet/ios/DevialetExpertControlApp/AppStateStore.swift:79))
- Diagnostics panel and retry flows ([ContentView.swift](/Users/andrewmg/devialet/ios/DevialetExpertControlApp/ContentView.swift:61), [DiagnosticsView.swift](/Users/andrewmg/devialet/ios/DevialetExpertControlApp/DiagnosticsView.swift:3))
