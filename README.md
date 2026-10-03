# SafeMesh 1.3

**Signed warnings. Offline protective-point maps. A path from one phone to the next.**

SafeMesh is a native HarmonyOS hackathon prototype for a civilian problem: losing mobile service should not also mean losing the warning you received or the map that helps you understand where protective places are located.

The app combines on-device signature verification, a bundled central Kraków map, private local storage and a store-and-forward relay with peer acknowledgements and bounded retries. Version **1.3** separates everyday screens from exercise tools, adds **signed Polish and English alert content**, and handles expiry and foreground relay recovery. Home shows the current alert, saved place and connection; the interactive map lives in Map, while exercise loading lives in Tests and diagnostics.

Three separate HarmonyOS emulator apps exchange packets through an explicitly labelled local WebSocket transport mock. The **v1.3 native run** demonstrated A → B with ACK loss/retry, then B → C after B restarted and A disconnected, plus rejection of a forged translation and an expired packet. Physical NearLink remains unverified.

**Demo only:** SafeMesh is not connected to RCB or an official warning issuer. All bundled alerts are signed exercises. Mapped PSP protective points are reference records; current access, condition and protection are not verified by the app.

The [v1.3 validation report](artifacts/research/ui-v13-validation.md) contains current screenshots, language/theme/large-text checks, native packet evidence and recording details. The [multi-emulator lab report](artifacts/research/mesh-lab.md) preserves v1.2 evidence; the [readiness audit](artifacts/READINESS_AUDIT.md) records earlier checkpoints.

## What you can demonstrate

| Screen | Working prototype behavior |
| --- | --- |
| Home / Start | Read the current verified alert and validity time, open the saved protective point, and see connection status. With no current message, **Connect devices / Połącz urządzenia** opens Relay. Home does not load exercise messages or embed a map. |
| Map / Mapa | Switch between Map and List; search all 40 central Kraków PSP addresses, including searches without Polish diacritics. Select a marker or row to open point details, save it, or show it on the map. Back returns to the originating screen. |
| Relay / Łączność | Choose emulator A/B/C, connect to the local test link, inspect neighbors and ACK/retry counters, and send verified cached messages. Open diagnostics for exercise controls. |
| Guide | Read a short offline preparedness reminder and see what the prototype's verification claim means. |
| Settings / Ustawienia | Open the header gear to choose saved **PL / EN** and **Light / Dark / System** preferences. System follows the device appearance. A language switch selects the matching issuer-signed alert variant. |
| Tests and diagnostics / Testy i diagnostyka | Enter from Settings or Relay. Load an exercise, run the six-check local verification test, inspect delivery diagnostics or check NearLink capability. Back returns to the screen that opened diagnostics. |

The starter map is inside the HAP, so it is available on first launch without an installation-time download. Its initial origin is explicitly labelled as a demo point at Rynek. Map refresh is a preparation script. Distances are straight-line distances from the labelled origin; the app does not calculate an evacuation route or confirm that an approach is safe.

**Use my location** performs one foreground request after a permission prompt, with a ten-second fix timeout. A usable fix must be inside the bundled area and report accuracy of 250 metres or better. Permission denial, disabled location, timeout, poor accuracy or a position outside the pack preserve the previous origin and show an explanation. The demo origin remains explicit until a fix is accepted, and can be restored manually. Device coordinates are neither saved to disk nor relayed to peers.

A point's saved badge appears only after the native local write completes. Failed saves retain the previous saved point and show an error; valid saved points restore after relaunch. Map search covers all **40 / 40** reference records in this pack.

## Run on Windows

Prerequisites: DevEco Studio with the HarmonyOS 6.1.1 / API 24 SDK, DevEco CLI, Node.js 24, and a running compatible emulator. This workspace used DevEco CLI 1.3.4 and an API 24 phone emulator. Minimum app API is 20; compile/target SDK is 24. Native NearLink support detection needs API 23 or later and compatible physical hardware.

For a fresh Windows machine, follow the organizers' [DevEco installation and emulator setup](https://github.com/onirodeveloper/hackyeah2026-challenge/blob/main/quickstart-guide.md). Install the Huawei HarmonyOS SDK, including its HMS kits; a plain OpenHarmony SDK alone does not contain NearLink Kit. The tested toolchain uses Node **24.21.0** and npm **11.19.0**. Keep Node24 on `PATH`; the Studio-bundled Node18 does not satisfy this CLI's requirements.

Install the pinned CLI and its organizer-supplied patches from the complete tools checkout:

```powershell
git clone https://github.com/onirodeveloper/hackyeah2026-challenge C:\src\hackyeah-tools
npm.cmd install -g @deveco/deveco-cli@1.3.4
node C:\src\hackyeah-tools\scripts\apply-devecocli-patches.mjs
node --version
devecocli.cmd -V
```

The patch script and its adjacent patch definitions must stay together. The patches correct lint reporting and disable a problematic CLI memory sampler. These are development-tool changes, not application dependencies or extra app privileges. Python3 is needed only for map refresh and Windows demo recording; Node and the SDK suffice for building the supplied map pack.

Open PowerShell in the project folder. Adjust the Studio directory if installed elsewhere:

```powershell
Set-Location C:\Users\user\SafeMesh
$env:DEVECO_CLI_STUDIO_PATH = 'C:\Users\user\DevEcoStudio'
$env:Path += ';' + (Join-Path $env:APPDATA 'npm')
devecocli.cmd device list --format json
devecocli.cmd build
if ($LASTEXITCODE -ne 0) { throw 'SafeMesh build failed' }
devecocli.cmd run --skip-build --module entry --device 127.0.0.1:5555
```

Use the actual device name or serial reported by `device list`. To start the already configured local emulator, use `devecocli.cmd emulator start HackYeahPhone`. A fresh computer needs a phone instance and system image configured first.

`devecocli run --skip-build` installs the existing build and launches `org.safemesh.alerts/EntryAbility`; it can also be rerun to relaunch the demo without rebuilding.

For a single-emulator rebuild, the helper reads `versionName` from `AppScope/app.json5`, builds, writes `dist/SafeMesh-1.3.0.hap` and its HAP-only SHA-256 manifest, and deploys it. Historical v1.1/v1.2 packages are preserved. The lab launcher below uses the build output directly:

```powershell
.\scripts\run-demo.ps1
```

Use `-Device <serial>` for another target or `-NoRun` to build/package only. If `DEVECO_CLI_STUDIO_PATH` is unset, the helper tries `<user-profile>\DevEcoStudio`; DevEco CLI must already be on `PATH`.

### Install the packaged demo

The v1.3 release files are [HAP](dist/SafeMesh-1.3.0.hap), [source ZIP](dist/SafeMesh-1.3.0-source.zip), [demo video](dist/SafeMesh-1.3.0-demo.mp4) and [SHA-256 manifest](dist/SafeMesh-1.3.0.sha256.txt). The HAP is a debug **unsigned emulator package**, copied from `entry/build/default/outputs/default/entry-default-unsigned.hap`.

Historical packages remain separate: [v1.2 HAP](dist/SafeMesh-mesh-lab-1.2.0.hap) and [checksum](dist/SafeMesh-mesh-lab-1.2.0.sha256.txt); `SafeMesh-demo.hap`, video and source ZIP preserve v1.1. Neither historical package contains the v1.3 screens or bilingual fixture.

Install and launch the packaged artifact using the SDK's HDC tool:

```powershell
$hdc = Join-Path $env:DEVECO_CLI_STUDIO_PATH 'sdk\default\openharmony\toolchains\hdc.exe'
& $hdc -t 127.0.0.1:5555 install -r '.\dist\SafeMesh-1.3.0.hap'
& $hdc -t 127.0.0.1:5555 shell aa start -b org.safemesh.alerts -a EntryAbility
```

The second command alone launches an installed app. This project's executable validation target is the emulator. No production certificate or private issuer key is included.

## Three-emulator packet demo

Configure three existing API 24 phone emulators named `HackYeahPhone`, `SafeMeshB` and `SafeMeshC`, then run:

```powershell
$env:DEVECO_CLI_STUDIO_PATH = 'C:\Users\user\DevEcoStudio'
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/start-mesh-lab.ps1
```

The helper builds once, starts the named instances, discovers their actual device serials, verifies or starts the loopback hub, checks HDC reverse ports and installs/launches the same HAP on all three. Use `-SkipBuild` for an existing build; use `-EmulatorA`, `-EmulatorB` and `-EmulatorC` for other instance names. It does not create/download emulators, accept licences, uninstall apps or erase their data. Logs and a newly started hub's PID are kept in ignored `.cache/mesh-lab/`.

In **Relay / Łączność**, choose A/B/C on the corresponding emulator and select **Connect / Połącz**. Keep each app in the foreground. On A, open **Tests and diagnostics / Testy i diagnostyka**, then **Load and send exercise / Wczytaj i wyślij ćwiczenie**. Alternatively, load the exercise there, return to Relay and select **Send message / Wyślij wiadomość**. Home on each receiving app shows its verified signed content.

The visible emulator-transport label distinguishes this mode from NearLink radio. The hub routes only configured A–B/B–C edges, never a direct A–C link, and does not store or acknowledge alerts. Leaving the app foreground pauses its link and timers. Returning resumes only a previously active connection; an explicit Disconnect stays disconnected. After a fresh process launch, use Connect again.

The [v1.3 native report](artifacts/research/ui-v13-validation.md#three-process-delivery-on-the-final-hap) records isolating C, dropping B's first ACK, restarting B with its saved alert, bringing C into range and injecting tampered/expired/duplicate packets. **B accepted hop 1**, **C later accepted hop 2 with A offline**, and rejected packets received no ACK. The separate [v1.2 lab report](artifacts/research/mesh-lab.md) preserves the earlier run.

For a repeat with a new exercise key, rebuild and redeploy **all three apps together**:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/start-mesh-lab.ps1 -RefreshDrill
```

This rotates the demo key and makes old cached exercises fail verification without wiping app data. Do not combine it with `-SkipBuild`, or refresh only one emulator. The fixture/control helpers are `scripts/mesh-lab-fixtures.mjs` and `scripts/mesh-lab-control.mjs`; their commands and effects are documented in the lab report.

## A two-minute single-emulator demo

1. Start on **Home / Start**: the empty state offers **Connect devices / Połącz urządzenia**. Open the header gear, then **Tests and diagnostics / Testy i diagnostyka** → **Load exercise message / Wczytaj wiadomość ćwiczebną** (`diagnosticDrill`). Return to Home to inspect the verified alert and expiry.
2. Open **Map / Mapa**. Search an address with or without Polish diacritics (`searchPoints`), switch Map/List, and open a marker or result. In point details, save the point (`savePoint`), use **Show on map / Pokaż na mapie**, or go Back. Home should show the saved address; the map remains on its own tab.
3. Open **Settings / Ustawienia** and switch **Polski / English** (`languagePl` / `languageEn`). Check that both UI and signed alert content change language. Try Light/Dark/System, then relaunch to check stored preferences and saved content.
4. Open diagnostics from Settings or Relay, then **Run verification test / Uruchom test weryfikacji** (`runRelay`). The intended result is six passing checks: A → B → C, duplicate suppression, forged-content rejection and expiry rejection. This test runs within one app process.
5. In diagnostics, **Check NearLink support / Sprawdź obsługę NearLink** (`checkNearLink`) shows the emulator's unsupported-radio result. Use the three-emulator walkthrough above for actual inter-app packet exchange over the local transport mock.

### Record the emulator demo

The Windows recorder captures the visible `Emulator.exe` client window and uses the FFmpeg bundled with DevEco Studio. Keep one emulator window visible, keep its size unchanged, and operate the app while recording:

```powershell
python scripts/record-demo.py --duration 120 --output dist/SafeMesh-1.3.0-demo.mp4
```

Use `--studio <directory>` for a different Studio installation or `--pid <Emulator.exe PID>` when multiple emulator windows are open. Python's standard library is sufficient. The recorder refuses to overwrite an existing output.

The new [v1.3 demo video](dist/SafeMesh-1.3.0-demo.mp4) is a reviewed, silent **90-second native-window recording** showing the revised Home, offline Map/list/detail, Guide and PL/EN with light/dark settings. It has 1350 frames at 15 fps and zero late capture frames; [capture and review evidence](artifacts/logs/newui-v13-video-review.json). It is a UI demonstration; the packet logs establish the three-emulator exchange separately. The historical `dist/SafeMesh-demo.mp4` and its [v1.1 validation record](artifacts/VALIDATION.md) are preserved. Recording does not publish or upload anything.

### Refresh an expired exercise

The checked-in bilingual fixture expires at **2026-10-06T18:49:45.616Z**. Its validity is intentionally limited to 72 hours. The app rejects it after that time.

Before a later presentation, regenerate the exercise fixtures, rebuild, repackage and redeploy with one command:

```powershell
.\scripts\run-demo.ps1 -RefreshDrill
```

The helper invokes `node scripts/generate-demo-alerts.mjs` before building. Generation rotates the pinned **demo** public key and signs new fixtures together. The temporary private key stays in the generator process and is not saved into the app. Previously stored alerts from the old key fail verification; receive the new drill or run the relay demo again. For the three-emulator lab, use `start-mesh-lab.ps1 -RefreshDrill` instead so all three receive the same new build and key. `mesh-lab-fixtures.mjs` only derives fault-test packets from existing signatures; it does not refresh dates or rotate keys.

## Reproducible checks

The host suites execute actual checked-in `.ets` implementation after transpilation/type erasure. Platform radio, preferences and Canvas are mocked where necessary; host cryptography uses Node/OpenSSL. These tests complement native checks.

```powershell
$env:DEVECO_CLI_STUDIO_PATH = 'C:\Users\user\DevEcoStudio'
.\scripts\check.ps1 -Build
```

The helper discovers every `tests/*.test.mjs` suite, runs host tests, ArkTS checking and Code Linter, then builds the entry module when `-Build` is present. It stops on a nonzero exit and reports `CHECKS: PASS` only after the requested checks complete. Omit `-Build` for checks without packaging; use `scripts/run-demo.ps1` afterward to package/deploy the build.

| Suite | Coverage |
| --- | --- |
| `tests/protocol.test.mjs` | Genuine signatures, signed v2 translations, exact v1 canonical compatibility, malformed/unsigned language rejection, trust scope, expiry, replay, bounded parsing/cache, restore and native empty-encoder regression. |
| `tests/alert-display.test.mjs` | Actual ViewModel with real ECDSA: PL/EN selection, original-language fallback, forged translation rejection, restore, expiry fallback and paused/resumed timers. |
| `tests/nearlink.test.mjs` | Capability gate, exact-name discovery, confirmed connections, MTU framing, split/coalesced reads, invalid input and cleanup. |
| `tests/map.test.mjs` | Dataset preservation, attribution, geometry, coordinate projection, selection, distances, clipping and Canvas submission bounds. |
| `tests/integration.test.mjs` | ViewModel persistence/restore, rejected-input handling, forwarding, concurrency, errors and expiry. |
| `tests/storage.test.mjs` | Native string-size limits, chunked snapshots, generation commits, interrupted writes, initialization and concurrent access. |
| `tests/delivery.test.mjs` | Full-cache synchronization, delayed/reconnected peers, strict ACK matching, loss/retry policy, expiry, deadlines, transport switching, retired callbacks, foreground lifecycle and three independent ViewModels. |
| `tests/location.test.mjs` | Native one-shot location permission/capability handling, usable results and failure paths. |
| `tests/emulator-transport.test.mjs` | Actual ArkTS WebSocket adapter with platform mocks: handshake, peer updates, packet bounds, sender filtering, deadlines, error diagnostics and stop races. |
| `tests/mesh-lab-server.test.mjs` | Actual local sockets and RFC WebSocket framing, topology, injected loss, malformed input, host/origin checks, heartbeat cleanup and public fixture derivation. |

Tests discover the TypeScript compiler inside DevEco Studio through `DEVECO_CLI_STUDIO_PATH`; see [NearLink evidence](artifacts/research/nearlink.md) for fallback locations. Protocol/integration/storage tests also accept `ARKTS_TYPESCRIPT_PATH`. The map suite uses Node 24's type-erasure support. Host fixture time is controlled inside the relevant tests; the native app uses the actual device clock.

**Version 1.3 checks:** **130 host tests passed**, **19 ArkTS files / zero errors** with 34 separate permission, exception and deprecated-API advisories, **zero Code Linter issues**, and a successful HAP build. See the [final check/build log](artifacts/logs/ui-v13-final-checks-build.log). All three emulator deployments passed smoke checks; [13/13 assertions over native evidence](artifacts/logs/ui-v13-native-results.json) passed. UI validation covered PL/EN, light/dark/system appearance, saved-point restoration and the real **1.45× Huge** system text preset.

Historical **v1.2** check/build passed **96 host checks across nine suites**, **19 ArkTS files / zero errors** with 29 separate advisories, **zero lint issues** and **BUILD SUCCESSFUL**. See the [combined log](artifacts/logs/mesh-lab-final-checks-build.log), [8 / 8 native relay-scenario assertions](artifacts/logs/mesh-lab-native-results.json), and [automatic stale-connection removal after B restarted](artifacts/logs/mesh-lab-08-stale-peer-removed.json). The [lab report](artifacts/research/mesh-lab.md) identifies the exact builds used. These are not v1.3 results.

Historical **v1.1** evidence remains available: **61 host checks / seven suites**, **17 ArkTS files / zero errors**, lint/build and **Smoke: PASS** in the [checks log](artifacts/logs/v11-checks.log), [run log](artifacts/logs/v11-run.log) and [validation record](artifacts/VALIDATION.md). Native-icon navigation, gear/back behavior and a [same-host clean-checkout build](artifacts/logs/v11-clean-checkout.log) were verified for that revision only.

Required native checkpoints include a successful HAP build and launch, **6 / 6** signature/relay drill checks, explicit unavailable NearLink radio on the emulator, and restored alerts/saved points after relaunch. Device location, themes and large-text behavior need their own recorded interaction checks. Permission/exception advisories from the ArkTS checker are separate from Code Linter results; the manifest declares the needed permissions and the corresponding native adapters request them at runtime. An emulator smoke check alone is not proof of every feature.

## Transport and signature design

```text
Trusted issuer signs alert
          │
          ▼
Phone A ──► Phone B retains alert ──► Phone C
 verify       verify + dedupe          verify
          signature remains unchanged
```

The relay engine authenticates a bounded, canonical payload before displaying or forwarding it. A pinned exercise public key can authorize exercises only. Accepted messages are copied into a bounded cache, revisions are checked, expired messages are removed and replay history is re-verified when restored. The maximum cooperative hop budget is eight; an unsigned hop counter is not proof of an adversary's path length.

Version 2 signs the source language and every alternate title, body and area under the separate `SafeMesh.Alert.v2` canonical domain. The fixture contains a Polish original and one English alternate. Only `pl` and `en` are accepted; duplicates, malformed alternatives and oversized content are rejected. The complete canonical content remains bounded to 4 KiB. Switching language selects already-verified content and leaves packet bytes and signature unchanged.

Version 1 canonical bytes remain exact. A valid v1 alert displays its original text with an explicit unknown-language fallback; unsigned translation metadata is rejected. A v2 alert missing the requested alternate also shows a labelled original-language fallback. Old-format support does not bypass the pinned key, signature or expiry checks. When the visible alert expires, the app selects the newest still-valid cached alert, or clears the alert if none remain.

NearLink provides device-to-device links; SafeMesh supplies the application relay policy. The public adapter uses `@kit.NearLinkKit`, `ohos.permission.ACCESS_NEARLINK`, a custom application UUID and reliable byte transfer. Its bounded framing allows a message to span the negotiated MTU.

The app synchronizes **all current verified cached alerts** with a delayed or reconnected peer, using the same relay policy over the local emulator link and the optional NearLink adapter. The foreground queue is limited to eight peers and 128 alerts per peer, sends at most four packets per batch, and rechecks cache membership and expiry before sending. Each item gets at most three attempts per connection, with bounded ACK waits and a three-second wait for each native send. Expired items leave the queue. Background suspension stops links and timers; foreground recovery reconnects a previously active link and resynchronizes valid saved content. Explicit Disconnect cancels recovery.

An ACK must match the expected connected peer, a fresh random delivery token, the issuer key ID, alert ID and revision. Receivers ACK only a verified accepted message or a verified duplicate; duplicates are acknowledged again to recover from ACK loss, without being forwarded again. Forged or expired data never gets a success ACK. Local write success alone is not recorded as acknowledged delivery. Legacy raw signed alerts are still accepted on input; ACK-based delivery requires a compatible current peer.

**An acknowledgement is a cooperative receiving-app receipt.** It does not prove a human read the message or that a hostile peer will pass it on. It does not confer authority on message content. Storage errors remain visible separately, and the foreground prototype makes no background-delivery guarantee.

API 24 requires a discovery filter and does not support a service-UUID scan filter. The prototype therefore asks for the other phone's exact NearLink device name. It does not invent a manufacturer identifier to bypass this constraint. The emulator cannot test NearLink scanning, connections or data transfer. Details and official source links: [NearLink research](artifacts/research/nearlink.md) and [security protocol](artifacts/research/security.md).

## Map sources and attribution

The bundled pack contains 40 selected PSP protective points near central Kraków, with original names, addresses and access categories. It is a subset of the published inventory, not a complete city listing. PSP data publication date: **2026-09-28**. OSM geometry snapshot: **2026-10-03**.

**© OpenStreetMap contributors (ODbL) · Komenda Główna PSP (CC BY 4.0).**

- [PSP dataset on dane.gov.pl](https://dane.gov.pl/pl/dataset/28058,punkty-schronienia-w-polsce/resource/1393918)
- [OpenStreetMap copyright and attribution](https://www.openstreetmap.org/copyright)
- [ODbL 1.0](https://opendatacommons.org/licenses/odbl/1-0/)
- [Map provenance, licensing and limitations](artifacts/research/maps.md)

The pack uses vector data from a bounded Overpass query, not bulk downloads from the OSM community raster-tile server. Original metadata, source URLs, dates and hashes are in `entry/src/main/resources/rawfile/map-pack.json`. Retain attribution and the applicable data licences when redistributing the map.

Maintainer refresh, with internet access and Python:

```powershell
python scripts/refresh-map.py
node --test tests/map.test.mjs
devecocli.cmd build
```

This refresh contacts public data services and should be run deliberately during preparation, not automatically for every app launch.

## Project layout

```text
entry/src/main/ets/
  pages/Index.ets                 Native ArkUI app screens
  views/OfflineMap.ets            Canvas vector map
  viewmodel/                     Alert, relay and map state
  model/AlertProtocol.ets         Signature, trust and relay policy
  model/DeliveryProtocol.ets      Bounded data/ACK wire format
  model/DeliveryQueue.ets         Foreground peer synchronization and retries
  model/LocalStore.ets            Private local preferences
  model/DeviceLocation.ets        Optional one-shot native location
  model/DemoAlerts.ets            Signed exercise fixtures
  model/DemoTrust.ets             Exercise public key only
  model/OfflineMapData.ets        Bundled reference data
  transport/NearLinkTransport.ets Public native radio adapter
  transport/RelayTransport.ets    Shared packet-link contract
  transport/EmulatorTransport.ets Local WebSocket link between separate emulator apps
scripts/                         Checks, build/package, map refresh, exercise generation, recorder, mesh lab
tests/                           Host tests of application sources
artifacts/research/              Primary-source evidence and limitations
artifacts/logs/                   Build and validation records
artifacts/screenshots/            Native emulator captures
dist/SafeMesh-1.3.0.hap           v1.3 emulator package
dist/SafeMesh-1.3.0-source.zip    v1.3 source archive
dist/SafeMesh-1.3.0-demo.mp4      v1.3 native UI demonstration
dist/SafeMesh-1.3.0.sha256.txt    v1.3 checksum manifest
dist/SafeMesh-mesh-lab-1.2.0.hap   Historical v1.2 emulator lab package
dist/SafeMesh-demo.hap            Historical v1.1 submission package
dist/SafeMesh-demo.mp4            Historical v1.1 single-emulator demonstration
```

## Validation scope

The current target is API 24 emulators. Native v1.3 checks cover signed A → B → C delivery, ACK loss, B restoration, bilingual display and foreground recovery. The local hub is an intentional transport mock. Physical NearLink, radio range, battery behavior and background delivery are outside the demonstrated scope.

A deployable warning service also needs an authorized issuer, audited key custody/rotation/revocation, a trusted-time policy, fresh protective-point access information and operational review. Signatures cannot prevent jamming, message dropping or compromised authority keys. No range, guaranteed delivery or certified shelter safety is claimed by this hackathon build.

AI-assisted development is disclosed in [AI_WORKFLOW.md](AI_WORKFLOW.md). The application itself does not use an AI inference service.

Paste-ready submission text, cover image and opening instructions are in [SUBMISSION.md](SUBMISSION.md).
