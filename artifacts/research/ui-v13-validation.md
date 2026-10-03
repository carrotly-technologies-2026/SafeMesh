# SafeMesh 1.3 validation

Validated on the API 24 HarmonyOS emulators HackYeahPhone (A, 5555), SafeMeshB (B, 5557), and SafeMeshC (C, 5559). Host date: 2026-10-03; emulator logs use UTC+8 and therefore display 2026-10-04. Application source commit: `247323e`.

## Build and package

- [Final checks](../logs/ui-v13-final-checks-build.log): 130 host tests passed, 19 ArkTS source files with zero errors, zero Code Linter issues, successful debug HAP build. The 34 ArkTS advisories concern permission declarations, exception handling and the supported but deprecated `intl.DateTimeFormat` API; they are not counted as linter errors.
- HAP SHA-256: `539865c2b4717f2f936d953e36945a0d2a5c198563637dc008dacc0165a284b7`.
- The package is an unsigned emulator HAP. It does not establish phone-signing or Huawei certification.
- All three emulators passed the [initial integrated deployment](../logs/ui-v13-deploy-three.log). The final window-color and metric-alignment changes received a subsequent build and deployment; see the `ui-v13-final-run-*` logs.

## Interface and language

Start contains an alert, saved-place row and connection row. The interactive Canvas appears only on Map. With no alert, the action opens Relay; exercise loading and protocol tests live in Tests and diagnostics. Map provides address search, map/list selection and a separate point detail with source availability, save and show-on-map actions. Guide sections expand individually. Appearance and language are grouped in Settings, opened with the native gear symbol.

- [Polish Home](../screenshots/ui-v13-final-home-pl.png): authenticated Polish title and body, localized validity date with explicit UTC, saved place and connection. No duplicated map.
- [Empty receiver Home](../screenshots/ui-v13-c-empty-home.png): no current alert and an action to connect devices.
- [English Home](../screenshots/ui-v13-b-home-en.png): language changed without reloading the signed exercise. The alternate title/body are authenticated by the same v2 signature. V1 canonical bytes remain compatible; a missing signed translation displays the original with a language notice.
- [Huge text](../screenshots/ui-v13-b-huge-home.png): the native Huge preset was measured at **fontSizeScale=1.45** in the [configuration log](../logs/ui-v13-b-runtime-huge.log). Home, Map/list, Settings and navigation were inspected at that scale. This is not a claim of testing every scale up to the app's configured 2.0 cap.
- [Final dark Map](../screenshots/ui-v13-final-dark-map.png): native symbols, dark Canvas colors and readable status-bar content. Earlier dark screenshots predate the explicit window-system-bar update.
- [Search after returning from details](../screenshots/ui-v13-b-search-preserved-pl.png): `glowny` returns five of forty records, including Rynek Główny, with localized availability. Source place names remain Polish proper names in either interface language. The earlier B search captures include initial system-keyboard onboarding and are not search-success evidence.
- [Storage after process restart](../screenshots/ui-v13-b-restart-home.png): the saved Rynek Główny 1 record, verified exercise and PL/Light preferences returned. [Full B validation log](../logs/ui-v13-b-validation.log).
- [Guide](../screenshots/ui-v13-c-guide.png): expanding the second section replaces the first section's body.
- [Native diagnostics](../logs/ui-v13-a-runtime.log): all six signature/relay checks passed using the device crypto implementation. Their [visible result](../screenshots/ui-v13-a-diagnostics.png) is localized. Back returns to the screen that opened Diagnostics.
- [NearLink capability](../logs/ui-v13-a-nearlink-layout.json): the emulator reports NearLink unavailable without crashing while importing the public lazy Kit bindings.

The initial UI captures precede the final metric alignment and system-bar color changes. These presentation-only changes did not modify payloads, storage, navigation, timers or transport. Final release captures are identified by `ui-v13-final-*`.

## Foreground lifecycle

With A and C connected, launching native Settings on A removed A from the hub; returning to SafeMesh reconnected A automatically with its original role. No manual Connect action occurred between these snapshots:

1. [A and C connected](../logs/ui-v13-relay-01-ac-isolated.json).
2. [A in background, only C connected](../logs/ui-v13-relay-02-a-background.json).
3. [A resumed, A and C connected again](../logs/ui-v13-relay-03-a-resumed.json).

Host regressions also cover explicit stop defeating a pending resume, late operation cancellation, expired alert replacement, restored-cache verification and forged translation rejection. Foreground recovery is not a background-delivery claim.

## Three-process delivery on the final HAP

B's **demo app data only** was reset after its UI audit so that its first receipt could be distinguished from locally loading the exercise. A already held the valid v2 fixture; C remained empty. All three apps used the final HAP above. Hub topology initially permitted only A–B, while C was connected but isolated.

1. The hub dropped B's first ACK. A sent twice; B accepted the first hop and classified the retry as a verified duplicate. A's UI remained connected and displayed **0 pending / 1 acknowledged / 1 retry**. [Hub counters](../logs/ui-v13-relay-05-retried.json), [B native log](../logs/ui-v13-relay-05-b-runtime.log), [A screenshot](../screenshots/ui-v13-final-a-retry.png).
2. A was explicitly disconnected. B's app process was force-stopped and restarted; its stored alert reappeared before reconnecting. C still had no alert. [B restored](../screenshots/ui-v13-final-b-restored.png), [C empty layout](../logs/ui-v13-relay-06-c-still-empty.json).
3. B reconnected and the topology changed to B–C only. C accepted **hop 2** from B's durable cache while A remained offline. A→C attempts stayed zero. [C native log](../logs/ui-v13-relay-07-c-runtime.log), [hub state](../logs/ui-v13-relay-07-hop-two.json), [C received screen](../screenshots/ui-v13-final-c-received.png).
4. An already-signed v2 packet was modified only in its English translation; its original signature was retained. Injecting it into B produced `invalid`. A genuinely signed expired fixture produced `expired`. Neither received an ACK; the connection stayed usable. A valid duplicate then received an ACK. [Native rejection/duplicate log](../logs/ui-v13-relay-10-b-runtime.log), [no-ACK counters](../logs/ui-v13-relay-09-no-ack.json), [duplicate ACK counters](../logs/ui-v13-relay-10-duplicate-ack.json).

[13/13 assertions over recorded native evidence passed](../logs/ui-v13-native-results.json), separately from the 130 host tests. The local hub passed packets and injected explicitly requested test faults; it did not sign alerts, acknowledge deliveries or keep an alert cache. The phone apps performed verification and forwarding.

## Recording

`dist/SafeMesh-1.3.0-demo.mp4` is a new native-window capture of Home, Map/list/detail, Guide and the PL/EN and light/dark changes. It contains no composited UI or Windows desktop: H.264, 478 × 1030, 15 fps, 90.000 seconds, 1350 frames, zero late frames. Three decoded frames were inspected. [Capture/probe/review record](../logs/newui-v13-video-review.json).

SHA-256: `0dc977d772005e28658ebb9712ca2faa1854ea0e51b82a672a697646a22e9d26`. This video demonstrates the UI; the separate packet logs below establish communication between emulator processes. The v1.1 recording is preserved under its original filename.

## Scope

The local WebSocket hub substitutes for the NearLink transport between three independent app processes. On-device signature verification, persistence, forwarding, ACK matching and retries remain real app code. This does not demonstrate physical NearLink discovery, RF range, interference, battery consumption or delivery while the application is suspended. No physical devices are available for this project.

SafeMesh is an exercise prototype, not connected to RCB or an official issuer. The bundled PSP points are dated reference records; the app does not establish current access, condition or protection. Distances are straight-line estimates. Official integration and production trust-key management remain outside this release.
