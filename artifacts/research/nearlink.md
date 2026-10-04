# NearLink implementation evidence

Researched on 2026-10-03 against the installed HarmonyOS SDK 6.1.1 / API 24 and Huawei's documentation. The runnable app uses ArkTS and ArkUI. This document covers transport, not operational approval as a public warning service.

## What is feasible

NearLink provides short-range device discovery, advertising and point-to-point data transfer. A device can send and receive. An application can build a store-and-forward relay above those links: validate an authority signature, retain the alert, deduplicate it, then send it to the next encountered peer. That application-layer relay is our architecture; the documented APIs do **not** provide a turnkey flood/mesh-routing function.

The emulator cannot test NearLink discovery, connections or radio data transfer. It can test the interface, signed message validation, local persistence and a clearly labeled simulated relay. Successful simulator propagation is not evidence that the physical radio works. Huawei documents both restrictions in [NearLink Kit introduction](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/nearlink-introduction) and [emulator versus device differences](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ide-emulator-specification). The introduction was read through `devecocli docs read` because the web documentation uses a JavaScript shell.

## Exact SDK and API evidence

Authoritative local declarations:

- `C:/Users/user/DevEcoStudio/sdk/default/hms/ets/kits/@kit.NearLinkKit.d.ts`
- `C:/Users/user/DevEcoStudio/sdk/default/hms/ets/api/@hms.nearlink.manager.d.ts`
- `C:/Users/user/DevEcoStudio/sdk/default/hms/ets/api/@hms.nearlink.scan.d.ts`
- `C:/Users/user/DevEcoStudio/sdk/default/hms/ets/api/@hms.nearlink.advertising.d.ts`
- `C:/Users/user/DevEcoStudio/sdk/default/hms/ets/api/@hms.nearlink.dataTransfer.d.ts`
- `C:/Users/user/DevEcoStudio/sdk/default/openharmony/toolchains/lib/PermissionDefinitions.json`

| Capability | Installed public API | Minimum version |
| --- | --- | --- |
| Capability detection | `canIUse('SystemCapability.Communication.NearLink.Core')`, plus `manager.isNearLinkSupported()` from API 23 | syscap; API 23 |
| Radio state | `manager.getState()` | API 13 |
| Advertising | `advertising.startAdvertising(params)` | API 13 |
| Filtered discovery | `scan.startScan(filters, options)` and `scan.on('deviceFound', callback)` | API 13 |
| Register app port | `dataTransfer.createPort(uuid)` | API 18 |
| Connect port | `dataTransfer.connect({ address, uuid, mtu, transferMode })` | API 18 |
| Receive channel status | `dataTransfer.on('connectionStateChanged', callback)` | API 18 |
| Transfer bytes | `dataTransfer.writeData({ address, uuid, data })` | API 18 |
| Receive bytes | `dataTransfer.on('readData', callback)` | API 18 |

The implementation uses `@kit.NearLinkKit`, matching the installed API 24 SDK. Current web pages also describe `@ohos.nearlink.*` in Connectivity Kit starting in API 26. Those newer imports and `onReadData()` function names must not be copied into this implementation. The app's minimum is API 20, and its target SDK and emulator are API 24. The native NearLink adapter needs API 23 or later for its support query; it checks capabilities and dynamically loads the Kit, reporting unsupported status where unavailable. [Huawei data-transfer API](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/nearlink-data-transfer-api).

## Permission and trust boundary

Only `ohos.permission.ACCESS_NEARLINK` is requested. The installed permission definition says `user_grant`, `availableLevel: normal`, `availableType: NORMAL`, `provisionEnable: false`. The app must declare it with a reason resource and request it at runtime. It does not require system-app identity, a privileged SDK or `MANAGE_NEARLINK`.

The adapter never silently changes the radio switch. The user enables NearLink in device settings. It accepts discovered randomized peer addresses as connection handles; these are not stable identities or trusted senders.

NearLink transport is not automatically encrypted. Huawei says pairing is needed for link encryption. Public warning content can travel without confidentiality, but each alert must carry an authority signature verified against a separately trusted key. A transport address, successful connection, advertised name or UUID is not an authority credential. Private distress messages and live locations would need a separate confidentiality design. [Huawei data-transfer guide](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/nearlink-start-data-transfer).

## Discovery constraint that matters for this hackathon

In the installed API 24, `ScanFilters` supports address, exact device name and manufacturer fields. It does **not** support `serviceUuid`, and all-empty filters are rejected. Unfiltered scanning with `null` first appears in API 26. Advertising can include our custom 128-bit service UUID, but that does not create a matching scan filter on API 24.

Our adapter therefore offers exact-name discovery for controlled physical-device tests. It does not fabricate a vendor/manufacturer ID, infer a nearby population or promise anonymous automatic discovery. For a future deployment, evaluate API 26's unfiltered scanning with careful application filtering, an officially assigned manufacturer advertisement, or BLE discovery. [Huawei scan API](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/nearlink-scan).

## Adapter usage contract

Source: `entry/src/harmonyos/transport/NearLinkTransport.ets` (moved from `entry/src/main/ets/transport/` in v1.5.0, when the OpenHarmony / Oniro product got its own stub).

Create `new NearLinkTransport(callbacks)`, where callbacks implement:

```typescript
interface NearLinkCallbacks {
  onStatus: (status: NearLinkStatus) => void;
  onPeer: (peer: NearLinkPeer) => void;
  onMessage: (address: string, packet: string) => void;
  onError: (operation: string, code: number, message: string) => void;
}
```

`NearLinkStatus` has `state`, `message`, `supported`, `connectedPeers`. `NearLinkPeer` has `address`, `name`, `rssi`, `connectable`, `connected`, `mtu`. RSSI `127` represents unavailable, not an estimated distance.

1. `probe()` returns `Promise<NearLinkStatus>` and reports unsupported hardware explicitly. NearLink Kit is dynamically imported only after the system-capability gate so a missing Huawei runtime does not crash the app at startup.
2. `start(context)` requests permission, registers the application port, subscribes to callbacks and starts connectable advertisements. Returns `Promise<boolean>`.
3. `discover(peerDeviceName)` starts filtered scanning and reports actual results. Returns `Promise<boolean>`. Discovery alone does not connect.
4. A user chooses a returned peer; `connect(address)` requests a port connection. Only the SDK's connected callback marks a peer connected.
5. `send(address, packet)` sends a string over a confirmed channel, returning local-write success as `Promise<boolean>`. `broadcast(packet, excludeAddress)` visits connected peers and returns the number of successful local writes. Neither method is an application-level delivery acknowledgement.
6. Route `onMessage` through the strict alert parser and signature/replay/expiry checks **before** storing, displaying or forwarding it. When `onPeer` reports a new connection, the root relay engine can send its bounded queue of still-valid accepted alerts.
7. Call `stop()` when leaving the active relay session. It releases advertising, discovery, callback and port resources. Background/locked-screen survival is not implemented or claimed.

State strings: `unsupported`, `off`, `available`, `ready`, `permission-denied`, `error`, `discovering`, `stopped`. `isSupported()` and `connectedCount()` are synchronous getters. Operational errors go to `onError`; normal operational failure returns `false`.

## Wire framing and limits

This app defines a framing protocol, independent of Huawei's radio protocol: big-endian 32-bit magic `0x534D0100`, big-endian 32-bit payload byte length, then UTF-8 packet bytes. The sender serializes writes, requests reliable transfer and chunks a frame to `min(negotiated MTU, 1024)` bytes. Reads are reassembled by peer, so an OS callback boundary is not assumed to be a whole alert. Complete payloads use strict UTF-8 decoding.

Limits: 16 KiB payload, eight tracked peers, 15-second stale partial reset, maximum two full frames in a combined receive buffer. Oversized lengths, invalid framing and malformed UTF-8 are rejected. Chunk writes are paced 10 ms, following [Huawei's congestion FAQ](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/nearlink-faq). No packet repair or end-to-end acknowledgement is implemented. Frame truncation/link interruption requires reconnecting or allowing the partial to expire before retry. Reliable radio ordering and negotiated MTU handling still require device verification.

## Alternatives and next physical test

The installed SDK exposes ordinary-app BLE GATT and advertising through `@kit.ConnectivityKit`; Wi-Fi P2P `createGroup`, `p2pConnect`, `startDiscoverDevices` are also public APIs, subject to their own permissions and support checks. `@kit.DistributedServiceKit` also exposes `linkEnhance` from API 20 for Bluetooth-based connections/data using `DISTRIBUTED_DATASYNC`. None is automatically a mesh router, and none makes NearLink radio simulation possible. See [BLE API](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-bluetooth-ble), [Wi-Fi manager API](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-wifiManager), and [linkEnhance API](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-link-enhance).

Next validation needs three compatible physical Huawei devices: A originates a demo-signed alert, B receives and retains it, A disappears, C later receives it from B without internet. Separately test tampered payload, unknown signer, expiry, repeated packet, relaunch persistence, a message larger than MTU, disconnect during a frame, permissions denied, radio switched off and locked-screen suspension. Do not claim range, delivery guarantees, anti-jamming or background availability until measured. A cryptographic signature prevents accepted forgery under its trust assumptions; it cannot prevent dropping or jamming messages.

Validation so far: the integrated ArkTS check reports zero errors. The adapter's initial isolated lint reported zero defects. Seven host tests run against the actual `.ets` adapter transpiled with the local SDK compiler and mocked platform calls: unsupported capability avoids loading the Kit; discovery requires a valid name; connected count waits for the real callback; a UTF-8 packet survives 127-byte MTU writes and arbitrary 7-byte reads; coalesced frames decode separately; oversized/malformed/invalid-UTF-8 input is rejected; stop clears channels and prevents sends. These mocks validate adapter logic, not physical NearLink behavior. Runtime NearLink radio exchange remains untested because only the emulator is available. Integrating UI/build/emulator evidence is recorded separately by the root task.

Run the persisted tests from the project root:

```powershell
$env:DEVECO_CLI_STUDIO_PATH = 'C:\Users\user\DevEcoStudio'
node --test tests/nearlink.test.mjs
```

The test looks for the bundled TypeScript compiler beneath `DEVECO_CLI_STUDIO_PATH`, then falls back to `<user-home>/DevEcoStudio`, `C:/Program Files/Huawei/DevEco Studio` and `/Applications/DevEco-Studio.app/Contents`. It fails with a setup message if no compiler is found. Node supplies the host test runner; no radio hardware, network, npm installation or generated source copy is required.
