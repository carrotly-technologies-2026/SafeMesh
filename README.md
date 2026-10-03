# SafeMesh

**Signed warnings. Offline protective-point maps. A path from one phone to the next.**

SafeMesh is a native HarmonyOS hackathon prototype for a civilian problem: losing mobile service should not also mean losing the warning you received or the map that helps you understand where protective places are located.

The app combines on-device signature verification, a bundled central Kraków map, local storage and a store-and-forward relay design. It includes a real public NearLink API adapter and a clearly labeled three-phone simulation for the available emulator.

**Demo only:** SafeMesh is not connected to RCB or an official warning issuer. All bundled alerts are signed exercises. Mapped PSP protective points are reference records; current access, condition and protection are not verified by the app.

The [readiness and HarmonyOS UX audit](artifacts/READINESS_AUDIT.md) lists current design, accessibility, mesh and submission gaps. Passing the recorded tests is not a claim of complete product readiness or Huawei certification.

## What you can demonstrate

| Screen | Working prototype behavior |
| --- | --- |
| Home | Receive a signed exercise, verify it with native ECDSA P-256/SHA-256, retain accepted content locally and show its expiry. |
| Map | Explore bundled OSM vector geometry and 40 PSP protective points in central Kraków; select and save a point. The blue dot is a labeled demo origin at Rynek, not live GPS. |
| Relay | Run A → B → C through three independent relay engines. Each verifies the same issuer signature; the demo also rejects a duplicate, a modified alert and an expired alert. |
| NearLink panel | Check actual capability. On compatible hardware, request permission, advertise, discover a named peer, connect and send accepted messages. On the emulator, report that the radio is unavailable and show zero physical peers. |
| Guide | Read a short offline preparedness reminder and see what the prototype's verification claim means. |

The starter map is inside the HAP, so it is available on first launch without an installation-time download. Map refresh is currently a preparation script, not an end-user download flow. Distances are straight-line distances from the demo origin; SafeMesh does not compute evacuation routes.

## Run on Windows

Prerequisites: DevEco Studio with the HarmonyOS 6.1.1 / API 24 SDK, DevEco CLI, Node.js 24, and a running compatible emulator. This workspace used DevEco CLI 1.3.4 and an API 24 phone emulator. Minimum app API is 20; compile/target SDK is 24. Native NearLink support detection needs API 23 or later and compatible physical hardware.

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

The convenience script builds, checks the exit code, copies the exact unsigned HAP to `dist/SafeMesh-demo.hap`, writes `dist/SHA256SUMS.txt`, and deploys it:

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
2. Open **Map**. Zoom, tap a marker, read the source's availability category and save a point. Explain that the map and records are bundled and availability is not confirmed live.
3. Open **Relay** and select **Run the signed relay drill**. Show A → B → C, followed by duplicate suppression, forged-text rejection and expiry rejection. The expected result is **6 / 6 checks passed on this device**.
4. Select **Check hardware**. On the emulator, explain the explicit unsupported-radio result. The simulation exercises native cryptography and relay policy; it does not claim to transmit radio packets.

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
node --test tests/protocol.test.mjs tests/nearlink.test.mjs tests/map.test.mjs tests/integration.test.mjs tests/storage.test.mjs
devecocli.cmd check arkts --project .
devecocli.cmd check lint --format json .
```

| Suite | Coverage |
| --- | --- |
| `tests/protocol.test.mjs` | Genuine signatures, signed-field mutation, trust scope, expiry, replay, concurrent arrivals, bounded parsing/cache, restore and revision policy. |
| `tests/nearlink.test.mjs` | Capability gate, exact-name discovery, confirmed connections, MTU framing, split/coalesced reads, invalid input and cleanup. |
| `tests/map.test.mjs` | Dataset preservation, attribution, geometry, coordinate projection, selection, distances, clipping and Canvas submission bounds. |
| `tests/integration.test.mjs` | ViewModel persistence/restore, rejected-input handling, forwarding, concurrency, errors and expiry. |
| `tests/storage.test.mjs` | Native string-size limits, chunked snapshots, generation commits, interrupted writes, initialization and concurrent access. |

Tests discover the TypeScript compiler inside DevEco Studio through `DEVECO_CLI_STUDIO_PATH`; see [NearLink evidence](artifacts/research/nearlink.md) for fallback locations. Protocol/integration/storage tests also accept `ARKTS_TYPESCRIPT_PATH`. The map suite uses Node 24's type-erasure support. Host fixture time is controlled inside the relevant tests; the native app uses the actual device clock.

Final host run: **40 passed, 0 failed** across all five suites. Recorded native checkpoints on emulator `127.0.0.1:5555`:

- Full HAP build succeeded and DevEco CLI install/launch reported **Smoke: PASS**.
- Integrated ArkTS check passed; Code Linter reported zero errors and zero warnings.
- The native relay drill displayed **6 / 6** successful checks.
- NearLink correctly reported unsupported radio with **0 connected** physical peers.
- Relaunch restored the accepted alert and showed **Saved signatures re-verified**. The saved map point also survived relaunch.

See [final build/run log](artifacts/logs/final-build-run.log), [host tests](artifacts/logs/host-tests-final.log), [lint output](artifacts/logs/lint-final.log), [relay accessibility evidence](artifacts/screenshots/relay-release-layout.json), [validation record](artifacts/VALIDATION.md) and [screenshots](artifacts/screenshots/). The separate ArkTS checker retains permission/exception advisories; the manifest declares NearLink permission and the adapter requests it at runtime. An emulator smoke check alone is not proof of every feature.

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

NearLink provides device-to-device links, not a ready-made mesh router. The public adapter uses `@kit.NearLinkKit`, `ohos.permission.ACCESS_NEARLINK`, custom application UUIDs and reliable byte transfer. Its bounded framing allows a message to span the negotiated MTU. A successful write reports local transport success, not a recipient acknowledgement.

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
  model/LocalStore.ets            Private local preferences
  model/DemoAlerts.ets            Signed exercise fixtures
  model/DemoTrust.ets             Exercise public key only
  model/OfflineMapData.ets        Bundled reference data
  transport/NearLinkTransport.ets Public native radio adapter
scripts/                         Build/package helper, map refresh, exercise generation
tests/                           Host tests of application sources
artifacts/research/              Primary-source evidence and limitations
artifacts/logs/                   Build and validation records
artifacts/screenshots/            Native emulator captures
dist/SafeMesh-demo.hap            Submission emulator artifact
```

## Next validation gate

Three supported physical phones are needed for a credible store-and-forward demonstration: A sends to B, A disappears, and B later delivers to C without internet. Measure behavior with a locked screen, interrupted connection, unavailable radio, permission denial and packet bursts before making reliability or battery claims.

A deployable warning service also needs an authorized issuer, audited key custody/rotation/revocation, a trusted-time policy, fresh protective-point access information and operational review. Signatures cannot prevent jamming, message dropping or compromised authority keys. No range, guaranteed delivery or certified shelter safety is claimed by this hackathon build.

AI-assisted development is disclosed in [AI_WORKFLOW.md](AI_WORKFLOW.md). The application itself does not use an AI inference service.
