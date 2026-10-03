# SafeMesh 1.1

**Signed warnings. Offline protective-point maps. A path from one phone to the next.**

SafeMesh is a native HarmonyOS hackathon prototype for a civilian problem: losing mobile service should not also mean losing the warning you received or the map that helps you understand where protective places are located.

The app combines on-device signature verification, a bundled central Kraków map, private local storage and a store-and-forward relay with peer acknowledgements and bounded retries. It includes a real public NearLink API adapter and a clearly labeled three-phone simulation for the available emulator. Version **1.1.0** adds optional device location, durable point saving, searchable access to all 40 bundled points, and a **Settings / Ustawienia** screen opened by the header gear for persisted Polish/English language and Light/Dark/System appearance choices.

**Demo only:** SafeMesh is not connected to RCB or an official warning issuer. All bundled alerts are signed exercises. Mapped PSP protective points are reference records; current access, condition and protection are not verified by the app.

The [readiness and HarmonyOS UX audit](artifacts/READINESS_AUDIT.md) lists current design, accessibility, mesh and submission gaps. Passing the recorded tests is not a claim of complete product readiness or Huawei certification.

## What you can demonstrate

| Screen | Working prototype behavior |
| --- | --- |
| Home | Receive a signed exercise, verify it with native ECDSA P-256/SHA-256, retain accepted content locally and show its expiry. |
| Map | Explore bundled OSM vector geometry and all 40 PSP protective points in central Kraków. Search addresses, select a point and save it locally. The initial marker is a labeled demo origin at Rynek; an explicit location request can replace it with a suitable device fix. |
| Relay | Run A → B → C through three independent relay engines. Each verifies the same issuer signature; the demo also rejects a duplicate, a modified alert and an expired alert. |
| NearLink panel | Check actual capability. On compatible hardware, request permission, advertise, discover a named peer and synchronize every valid cached alert. Track queued messages, peer acknowledgements, retries and exhausted attempts. The emulator reports unavailable radio and zero physical peers. |
| Guide | Read a short offline preparedness reminder and see what the prototype's verification claim means. |
| Settings / Ustawienia | Choose **PL / EN** and **Light / Dark / System** (**Jasny / Ciemny / Systemowy**). Choices are saved locally; System follows the device's appearance automatically. Signed alert text remains unchanged when changing interface language. |

The starter map is inside the HAP, so it is available on first launch without an installation-time download. Map refresh is currently a preparation script. Distances are straight-line distances from the currently labeled origin; the app does not calculate an evacuation route or confirm that an approach is safe.

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

The convenience script builds, checks the exit code, copies the exact unsigned HAP to `dist/SafeMesh-demo.hap`, writes `dist/SHA256SUMS.txt`, and deploys it. A local rerun replaces the checksum manifest with the new HAP entry only; the packaged submission manifest additionally lists its source ZIP and video:

```powershell
.\scripts\run-demo.ps1
```

Use `-Device <serial>` for another target or `-NoRun` to build/package only. If `DEVECO_CLI_STUDIO_PATH` is unset, the helper tries `<user-profile>\DevEcoStudio`; DevEco CLI must already be on `PATH`.

### Install the packaged demo

The submission artifact is `dist/SafeMesh-demo.hap`. It is the debug **unsigned emulator package**, copied from `entry/build/default/outputs/default/entry-default-unsigned.hap`. The configured emulator accepts this HAP; that is not a phone-signing guarantee.

For an existing packaged artifact, install and launch using the SDK's HDC tool:

```powershell
$hdc = Join-Path $env:DEVECO_CLI_STUDIO_PATH 'sdk\default\openharmony\toolchains\hdc.exe'
& $hdc -t 127.0.0.1:5555 install -r '.\dist\SafeMesh-demo.hap'
& $hdc -t 127.0.0.1:5555 shell aa start -b org.safemesh.alerts -a EntryAbility
```

The second command alone launches an installed app. Physical Huawei phones require an appropriate development certificate, provisioning profile and registered device, configured through DevEco Studio signing. No production certificate or private issuer key is included.

## A two-minute demo

1. Open **Home** and select **Receive a signed drill**. Point out the exercise label, native signature result and validity period.
2. Open **Map**. Search one of the 40 addresses, zoom, select a marker, read its source availability category and save it. Optionally request location and show the labeled demo fallback if a usable fix is unavailable. Explain that records are bundled and access is not confirmed live.
3. Open **Relay** and select **Run the signed relay drill**. Show A → B → C, followed by duplicate suppression, forged-text rejection and expiry rejection. The expected result is **6 / 6 checks passed on this device**.
4. Select **Check hardware**. On the emulator, explain the explicit unsupported-radio result. The simulation exercises native cryptography and relay policy; it does not claim to transmit radio packets.
5. Open **Settings / Ustawienia** using the gear in the upper-right corner. Choose **PL / EN**, then demonstrate **Light / Dark / System**. Relaunch to check that the selections restore; System automatically follows the device theme. Alert signatures cover the original message text, so changing interface language does not translate a signed alert.

### Record the emulator demo

The Windows recorder captures the visible `Emulator.exe` client window and uses the FFmpeg bundled with DevEco Studio. Keep one emulator window visible, keep its size unchanged, and operate the app while recording:

```powershell
python scripts/record-demo.py --duration 120 --output dist/SafeMesh-demo.mp4
```

Use `--studio <directory>` for a different Studio installation or `--pid <Emulator.exe PID>` when multiple emulator windows are open. Python's standard library is sufficient. The recorder refuses to overwrite an existing output.

The local video artifact is [dist/SafeMesh-demo.mp4](dist/SafeMesh-demo.mp4): a reviewed, silent **90-second** recording of the native emulator, including the map, six relay checks and appearance/language settings. Capture metadata and the final checksum are in the [validation record](artifacts/VALIDATION.md). Recording does not publish or upload anything.

### Refresh an expired exercise

The checked-in fresh fixture expires on **2026-10-06 at 15:19:32 UTC**. Its validity is intentionally limited to 72 hours. The app must reject it after that time.

Before a later presentation, regenerate the exercise fixtures, rebuild, repackage and redeploy with one command:

```powershell
.\scripts\run-demo.ps1 -RefreshDrill
```

The helper invokes `node scripts/generate-demo-alerts.mjs` before building. Generation rotates the pinned **demo** public key and signs new fixtures together. The temporary private key stays in the generator process and is not saved into the app. Previously stored alerts from the old key fail verification; receive the new drill or run the relay demo again.

## Reproducible checks

The host suites execute actual checked-in `.ets` implementation after transpilation/type erasure. Platform radio, preferences and Canvas are mocked where necessary; host cryptography uses Node/OpenSSL. These tests complement native checks.

```powershell
$env:DEVECO_CLI_STUDIO_PATH = 'C:\Users\user\DevEcoStudio'
.\scripts\check.ps1 -Build
```

The helper discovers every `tests/*.test.mjs` suite, runs host tests, ArkTS checking and Code Linter, then builds the entry module when `-Build` is present. It stops on a nonzero exit and reports `CHECKS: PASS` only after the requested checks complete. Omit `-Build` for checks without packaging; use `scripts/run-demo.ps1` afterward to package/deploy the build.

| Suite | Coverage |
| --- | --- |
| `tests/protocol.test.mjs` | Genuine signatures, signed-field mutation, trust scope, expiry, replay, concurrent arrivals, bounded parsing/cache, restore and revision policy. |
| `tests/nearlink.test.mjs` | Capability gate, exact-name discovery, confirmed connections, MTU framing, split/coalesced reads, invalid input and cleanup. |
| `tests/map.test.mjs` | Dataset preservation, attribution, geometry, coordinate projection, selection, distances, clipping and Canvas submission bounds. |
| `tests/integration.test.mjs` | ViewModel persistence/restore, rejected-input handling, forwarding, concurrency, errors and expiry. |
| `tests/storage.test.mjs` | Native string-size limits, chunked snapshots, generation commits, interrupted writes, initialization and concurrent access. |
| `tests/delivery.test.mjs` | Full-cache synchronization, delayed/reconnected peers, strict ACK matching, packet/ACK loss, bounded retries, expiry, send deadlines, startup/stop races and queue limits. |
| `tests/location.test.mjs` | Native one-shot location permission/capability handling, usable results and failure paths. |

Tests discover the TypeScript compiler inside DevEco Studio through `DEVECO_CLI_STUDIO_PATH`; see [NearLink evidence](artifacts/research/nearlink.md) for fallback locations. Protocol/integration/storage tests also accept `ARKTS_TYPESCRIPT_PATH`. The map suite uses Node 24's type-erasure support. Host fixture time is controlled inside the relevant tests; the native app uses the actual device clock.

The current v1.1 inventory contains **61 host checks across seven suites**. The recorded v1.1 check run passed all 61, checked 17 ArkTS files with zero errors, and completed lint/build checks; installation and launch reported **Smoke: PASS**. Use the [v1.1 checks log](artifacts/logs/v11-checks.log), [v1.1 install/launch log](artifacts/logs/v11-run.log), [validation record](artifacts/VALIDATION.md) and [screenshots](artifacts/screenshots/) for the evidence and its scope. The final native-icon and gear-navigation revision also passed [ArkTS](artifacts/logs/v11-release-arkts.log), [lint](artifacts/logs/v11-release-lint.log), [build](artifacts/logs/v11-release-build.log) and [emulator smoke](artifacts/logs/v11-release-run.log). Both the header arrow and system Back returned from Settings to the previous Map screen. The source was also checked and built from a [clean local checkout](artifacts/logs/v11-clean-checkout.log) on the same host.

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

NearLink provides device-to-device links; SafeMesh supplies the application relay policy. The public adapter uses `@kit.NearLinkKit`, `ohos.permission.ACCESS_NEARLINK`, a custom application UUID and reliable byte transfer. Its bounded framing allows a message to span the negotiated MTU.

Version 1.1 synchronizes **all current verified cached alerts** with a delayed or reconnected peer. The foreground queue is limited to eight peers and 128 alerts per peer, sends at most four packets per batch, and rechecks authenticity-cache membership and expiry before sending. Each item gets at most three attempts per connection, with bounded ACK waits and a three-second wait for each native send. Expired items leave the queue. Stop clears queue-owned timers and prevents late startup callbacks from reviving the relay.

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
scripts/                         Checks, build/package, map refresh, exercise generation, recorder
tests/                           Host tests of application sources
artifacts/research/              Primary-source evidence and limitations
artifacts/logs/                   Build and validation records
artifacts/screenshots/            Native emulator captures
dist/SafeMesh-demo.hap            Submission emulator artifact
dist/SafeMesh-demo.mp4            Recorded and reviewed native emulator demonstration
```

## Next validation gate

Three supported physical phones are needed for a credible store-and-forward demonstration: A sends to B, A disappears, and B later delivers to C without internet. Measure behavior with a locked screen, interrupted connection, unavailable radio, permission denial and packet bursts before making reliability or battery claims.

A deployable warning service also needs an authorized issuer, audited key custody/rotation/revocation, a trusted-time policy, fresh protective-point access information and operational review. Signatures cannot prevent jamming, message dropping or compromised authority keys. No range, guaranteed delivery or certified shelter safety is claimed by this hackathon build.

AI-assisted development is disclosed in [AI_WORKFLOW.md](AI_WORKFLOW.md). The application itself does not use an AI inference service.

Paste-ready submission text, cover image and opening instructions are in [SUBMISSION.md](SUBMISSION.md).
