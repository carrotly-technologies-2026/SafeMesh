# SafeMesh team guide

How to build, run, test, record and release SafeMesh, and where the submission stands. Commands assume Windows PowerShell in the repository root unless marked as Linux. For the jury-facing overview, read [README.md](../README.md).

## 1. "I want to…"

| Goal | Command or place | Time |
| --- | --- | --- |
| Run every automated check and build the HAP | `.\scripts\check.ps1 -Build` | about 1–2 min |
| Run one test suite | `node --test tests\delivery.test.mjs` | seconds |
| Build, install and launch on one emulator | `.\scripts\run-demo.ps1 -Device 127.0.0.1:5555` | about 1 min |
| Start the three-emulator demo (issuer, hub, A/B/C) | `powershell -ExecutionPolicy Bypass -File scripts\start-authority-demo.ps1` | 1–3 min |
| Control the emulator "radio" (ranges, loss, forged packets) | `node scripts\mesh-lab-control.mjs …` (§5.4) | instant |
| Re-check the recorded v1.4 native evidence | `node scripts\validate-authority-evidence.mjs` | seconds |
| Record a demo video | `python scripts\record-mesh-demo.py …` (§6) | — |
| Run on Linux / Oniro (OpenHarmony) | [COMMANDS.md](../COMMANDS.md) | — |
| Test NearLink on physical phones | [docs/PHYSICAL_TESTING.md](PHYSICAL_TESTING.md) | — |
| Refresh the bundled exercise before it expires | `.\scripts\run-demo.ps1 -RefreshDrill` (§8.1) | about 1 min |
| Publish a release | §8.3 | about 5 min |

## 2. Repository map

| Path | What it is |
| --- | --- |
| `entry/src/main/ets/` | Shared app code: `pages/Index.ets` (UI), `viewmodel/`, `model/` (protocol, delivery queue, storage, location, authority client), `transport/` (link contract, emulator link), `views/` (map, copy) |
| `entry/src/harmonyos/transport/NearLinkTransport.ets` | Real NearLink Kit adapter, used by the **`default`** product (HarmonyOS) |
| `entry/src/oniro/transport/NearLinkTransport.ets` | NearLink stub, used by the **`oniro`** product (OpenHarmony / Oniro) |
| `build-profile.json5`, `entry/build-profile.json5`, `hvigorfile.ts` | Two products, two targets (`sourceRoots`), Oniro-only manifest changes |
| `entry/src/main/resources/{base,en,pl}` | UI strings (base = English) and the offline map pack (`rawfile/map-pack.json`) |
| `tests/` | 15 host test suites, 174 tests (§4) |
| `scripts/` | Checks, build/deploy, issuer service, emulator hub, fixtures, recorders, map refresh; `scripts/oniro/` for Linux |
| `artifacts/` | Evidence: `logs/`, `screenshots/`, `research/` (design and validation reports) |
| `docs/` | This guide and the physical NearLink runbook |
| `signatures/` | Public OpenHarmony SDK debug signing inputs for the `oniro` product only |
| `dist/` (git-ignored) | Local packages; published files are in GitHub Releases |
| `.cache/` (git-ignored) | Issuer private key and activation code, hub/issuer logs, recorder FFmpeg. **Never commit or share.** |

Products:

| Product | Runtime | NearLink | Signed | Who builds it |
| --- | --- | --- | --- | --- |
| `default` | HarmonyOS, target API 24, min API 20 | Real adapter | No (emulators); phones are signed locally in DevEco | DevEco Studio / `devecocli` on Windows |
| `oniro` | OpenHarmony API 23, min API 20, device type `default` | Stub ("unsupported") | OpenHarmony public debug key | `oniro-app build --product oniro` on Linux |

Releases: [v1.5.1](https://github.com/carrotly-technologies-2026/SafeMesh/releases/tag/v1.5.1) is current (HAP and SHA-256, plus the demo video). [v1.4.1](https://github.com/carrotly-technologies-2026/SafeMesh/releases/tag/v1.4.1) is where the video was recorded.

## 3. Setup (Windows, HarmonyOS product)

Needed: DevEco Studio 6.1.1 with the **HarmonyOS** SDK API 24 including HMS kits, Node.js 24, DevEco CLI 1.3.4 with the organizers' patches, Python 3 (map refresh and recording only), and API 24 phone emulators. The full steps are in README → *Run on Windows*. Every new PowerShell session needs:

```powershell
$env:DEVECO_CLI_STUDIO_PATH = Join-Path $env:USERPROFILE 'DevEcoStudio'   # adjust if installed elsewhere
$env:Path += ';' + (Join-Path $env:APPDATA 'npm')
devecocli.cmd device list --format json      # running emulators and their serials
```

The three demo emulators on the team laptop:

| Name | Serial | Role |
| --- | --- | --- |
| `HackYeahPhone` | `127.0.0.1:5555` | A (issuer) |
| `SafeMeshB` | `127.0.0.1:5557` | B |
| `SafeMeshC` | `127.0.0.1:5559` | C |

Start a stopped one with `devecocli.cmd emulator start SafeMeshB`. If an emulator screen keeps locking during a demo, run:

```powershell
$hdc = Join-Path $env:DEVECO_CLI_STUDIO_PATH 'sdk\default\openharmony\toolchains\hdc.exe'
foreach ($s in '127.0.0.1:5555','127.0.0.1:5557','127.0.0.1:5559') {
  & $hdc -t $s shell power-shell wakeup
  & $hdc -t $s shell power-shell setmode 602          # keep the screen on
  & $hdc -t $s shell power-shell timeout -o 7200000   # 2 h screen-off timeout
}
```

Linux / Oniro setup is in [COMMANDS.md](../COMMANDS.md).

## 4. Automated checks

### 4.1 `scripts/check.ps1`

```powershell
.\scripts\check.ps1          # tests, ArkTS check, lint
.\scripts\check.ps1 -Build   # the same, plus the HarmonyOS HAP build
```

It runs, in order, and stops at the first failure:

1. **Host tests:** every `tests/*.test.mjs` through `node --test`.
2. **ArkTS check twice, once per product source set** (`harmonyos`, then `oniro`). Each run uses a temporary mirror where that product's NearLink adapter sits in `src/main`. DevEco CLI 1.3.4 cannot resolve the `entry/transport/NearLinkTransport` target import by itself.
3. **Code Linter** over all `.ets` files.
4. **Build** (`-Build` only): `devecocli build --modules entry --build-mode debug` → `entry/build/default/outputs/default/entry-default-unsigned.hap`.

Passing output looks like this:

```text
ℹ tests 174
ℹ pass 174
ℹ fail 0
ArkTS check: harmonyos source set
No errors found in 21 file(s).
ArkTS check: oniro source set
No errors found in 21 file(s).
Summary: Issues: 0 | Errors: 0 | Warnings: 0 | Suggestions: 0 | Files with issues: 0
BUILD SUCCESSFUL
CHECKS: PASS
```

Lines such as `SAFEMESH_RESTORE_ERROR Error: disk unavailable` or `SAFEMESH_TRANSPORT_ERROR … Invalid individual packet` are **expected**: they come from tests that inject failures on purpose. Node prints `ExperimentalWarning: stripTypeScriptTypes` for the map suite, and PowerShell may print `NativeCommandError` around stderr output. Only the exit code and `CHECKS: PASS` matter. A full hvigor build also prints `ArkTS:WARN` permission, exception and deprecated-API advisories; they are not errors.

### 4.2 What the host tests cover

The suites transpile the **real `.ets` source** with the TypeScript compiler bundled in DevEco Studio and run it in Node. Only platform kits are mocked: radio, preferences, Canvas, HTTP/WebSocket and location. Cryptography uses real ECDSA P-256 through Node/OpenSSL with a test-only key.

| Suite | Tests | Covers |
| --- | --- | --- |
| `protocol.test.mjs` | 14 | Signature checks, v1/v2 canonical forms, signed translations, trust scope, expiry, replay, bounded parsing and cache, restore |
| `alert-display.test.mjs` | 8 | PL/EN content selection, original-language fallback, forged translation rejection, expiry fallback, timers |
| `inbox.test.mjs` | 12 | Multiple alerts, unread/read state and persistence, duplicates, revisions, expiry |
| `delivery.test.mjs` | 25 | Delivery queue: full-cache sync, ACK matching, loss and retries, expiry, transport switching, foreground lifecycle, three ViewModels relaying, *Load exercise message* on an active link |
| `integration.test.mjs` | 10 | ViewModel persistence, rejected input, forwarding, concurrency, errors |
| `storage.test.mjs` | 7 | Chunked preferences storage, generation commits, interrupted writes |
| `authority.test.mjs` | 14 | Issuer service: authentication, draft bounds, signatures, idempotency, receipt journal, rate limits |
| `authority-client.test.mjs` | 11 | App-side issuer client and console ViewModel: pinned service, token handling, response checks |
| `emulator-transport.test.mjs` | 12 | WebSocket emulator link: handshake, peers, bounds, deadlines, error paths |
| `mesh-lab-server.test.mjs` | 18 | Test hub over real sockets: RFC 6455 framing, topology, injected loss, host/origin checks |
| `nearlink.test.mjs` | 14 | NearLink adapter with a mocked kit: capability gate (API 20–22 syscap path, API 23+ capability query), permission, exact-name scan, MTU framing, split/coalesced reads, cleanup |
| `build-variants.test.mjs` | 4 | HarmonyOS/Oniro split: stub behavior, matching APIs, NearLink Kit only in `src/harmonyos`, unchanged HarmonyOS product and manifest |
| `map.test.mjs` | 18 | Map pack, attribution, projection, search, distances, Canvas bounds |
| `location.test.mjs` | 3 | One-shot location permission and failure paths |
| `localization.test.mjs` | 4 | Same keys in base/en/pl, every UI key translated, no raw English diagnostics |

### 4.3 Evidence validator

```powershell
node scripts\validate-authority-evidence.mjs   # expects: Authority evidence: 17/17 PASS
```

It replays the captured v1.4 native evidence in `artifacts/logs/`: signatures against the app's pin, saved UI trees, filtered native logs and hub counters. It touches no device, service or key.

## 5. Running the app

### 5.1 One emulator

```powershell
.\scripts\run-demo.ps1 -Device 127.0.0.1:5555   # build, write dist\SafeMesh-<version>.hap + SHA-256, install, launch
.\scripts\run-demo.ps1 -NoRun                   # build and package only
```

Install a downloaded HAP without building:

```powershell
& $hdc -t 127.0.0.1:5555 install -r .\SafeMesh-1.5.1.hap
& $hdc -t 127.0.0.1:5555 shell aa start -b org.safemesh.alerts -a EntryAbility
& $hdc -t 127.0.0.1:5555 shell aa force-stop org.safemesh.alerts           # stop
& $hdc -t 127.0.0.1:5555 shell bm clean -n org.safemesh.alerts -d          # wipe app data (inbox, settings)
```

### 5.2 Single-emulator walkthrough (about 2 minutes)

| Step | Where | Expected |
| --- | --- | --- |
| 1 | Fresh install, Home | English UI on an English system ("Messages", "Home / Map / Relay / Guide") |
| 2 | Gear → Tests and diagnostics → **Load exercise message** | Banner "Verified exercise message received"; inbox shows "Connection outage" |
| 3 | Banner → **Read alert** | "Signature verified · exercise sender", validity time, "Added on this device · Relay hops: 0" |
| 4 | **Map** → search `Bracka` → open a point | 40 PSP points; search works without diacritics; details and distance |
| 5 | Gear → Appearance and **App language: System / Polski / English** | System follows the phone; Polski/English are saved choices and survive a relaunch |
| 6 | Tests and diagnostics → **Run verification test** | "All checks passed" and six rows: Receipt at A, Relay A → B, Relay B → C, Repeated message, Changed content, Expired message |
| 7 | Tests and diagnostics → **Check NearLink support** | "NearLink is unavailable on this device." (emulators have no radio) |

Step 6 runs inside one app process and also loads the exercise into the inbox. Do not run it on B or C before a relay demo.

### 5.3 Three emulators with a custom alert

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\start-authority-demo.ps1             # build + deploy to A, B, C
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\start-authority-demo.ps1 -SkipBuild  # reuse a matching build
```

The launcher prints `AUTHORITY_DEMO_READY=1` when it is done. It starts or reuses:
- the **exercise issuer** on `127.0.0.1:8768`, with its private key and activation code in `.cache\demo-authority\`;
- the **emulator hub** on `127.0.0.1:8765`, which links only A–B and B–C;
- reverse ports, with 8768 forwarded to A only.

| Step | Do | Expected |
| --- | --- | --- |
| 1 | On each emulator: **Relay** → choose A / B / C → **Connect A/B/C** | "Connected"; B shows two neighbours, A and C one each |
| 2 | Optional, to show store-and-forward: `node scripts\mesh-lab-control.mjs links AB` | C is out of range ("Waiting for another device") |
| 3 | On A: Relay → Tests and diagnostics → **Exercise authority**. Type the activation code from `.cache\demo-authority\session-token.txt` off camera → **Sign in** | "Exercise publisher signed in" |
| 4 | On A: choose the alert language, fill in title, instructions and area, priority and validity → **Publish alert** | "Signed and queued for nearby devices." (or "Signed and saved; waiting for nearby devices." when nobody is in range) |
| 5 | Watch B | Banner within about 2 s; detail "Received from device A · Relay hops: 1"; hub shows one A→B data packet and one B→A ACK |
| 6 | `node scripts\mesh-lab-control.mjs links BC` (A leaves, C arrives) | C gets the alert within about 1 s: "Received from device B · Relay hops: 2" |
| 7 | Forged copy: `node scripts\mesh-lab-fixtures.mjs`, then `node scripts\mesh-lab-control.mjs inject B C .cache\mesh-lab\fixtures\tampered.json` | C → Relay shows "Invalid signature rejected"; no ACK and no new inbox item |
| 8 | Duplicate: `… inject B C .cache\mesh-lab\fixtures\duplicate.json` | ACKed again; no new unread item or banner |

Recipients never have a Send button: verified alerts relay automatically. Leaving the app (home, lock screen) pauses the link. On return it reconnects only if it was connected before; after a fresh launch, tap Connect again.

### 5.4 Hub control cheat sheet

```powershell
node scripts\mesh-lab-control.mjs state             # connected nodes, links, per-route counters
node scripts\mesh-lab-control.mjs links AB BC       # who is "in range" (never A–C directly)
node scripts\mesh-lab-control.mjs disconnect A      # drop A's socket
node scripts\mesh-lab-control.mjs drop ack B A 1    # lose the next ACK from B to A (retry demo)
node scripts\mesh-lab-control.mjs reset             # zero counters, cancel pending drops
node scripts\mesh-lab-control.mjs inject B C <file> # deliver a packet file as if B sent it to C
```

The hub never signs, stores or acknowledges alerts. It only routes packets between connected apps. It is a labelled stand-in for NearLink.

## 6. Recording a demo

```powershell
# One emulator window:
python scripts\record-demo.py --duration 120 --output dist\SafeMesh-single.mp4
# Three emulator windows side by side, one capture loop per frame:
Get-CimInstance Win32_Process -Filter "Name='Emulator.exe'" | Select ProcessId, CommandLine   # find A/B/C PIDs
python scripts\record-mesh-demo.py --pids <A> <B> <C> --output dist\SafeMesh-mesh.mp4 --stop-file .cache\stop.flag
New-Item .cache\stop.flag   # stops the three-window recording from another terminal
```

Both use only the `Emulator.exe` windows, never the desktop, and the FFmpeg bundled with DevEco Studio. Keep the windows visible and unminimized, and keep their size unchanged. The recorders refuse to overwrite an output. Never film the activation code, the `.cache` folder or a terminal showing them.

## 7. Other platforms

- **Linux / Oniro (OpenHarmony API 23):** [COMMANDS.md](../COMMANDS.md). Use `scripts/oniro/sign.sh` and `scripts/oniro/deploy.sh`. **Never run `oniro-app sign .`**, because it would sign the HarmonyOS product with the OpenHarmony key.
- **Physical HarmonyOS phones (NearLink):** [docs/PHYSICAL_TESTING.md](PHYSICAL_TESTING.md):
  - Build the `default` product and sign it in DevEco with all phones connected. Never commit the signed `build-profile.json5`.
  - NearLink controls are in Tests and diagnostics → NearLink radio, not on the Relay tab.
  - Discovery needs the other phone's **exact** NearLink name, short ASCII (≤ 9 characters).
  - Evidence comes from `hilog -e SAFEMESH_`: `accepted … hops=1/2`, `ack_matched`, and `SAFEMESH_TRANSPORT_*` for errors.

## 8. Maintenance

### 8.1 Exercise fixture expiry

The bundled exercise is valid until **2026-10-06 19:57:54 UTC**. After that, *Load exercise message* reports a verification failure. To refresh it with the persistent local key, rebuild and redeploy:

```powershell
.\scripts\run-demo.ps1 -RefreshDrill                                                         # one emulator
powershell -ExecutionPolicy Bypass -File scripts\start-mesh-lab.ps1 -RefreshDrill            # all three, same build
```

This changes `DemoAlerts.ets`; commit it only from the machine that holds the shared issuer key. Custom alerts from the issuer console have their own 15 min to 24 h validity.

### 8.2 Map pack

`python scripts\refresh-map.py`, then `node --test tests\map.test.mjs` and a build. This contacts public PSP/OSM services, so do it deliberately and keep the attribution.

### 8.3 Release

1. Bump `versionCode` / `versionName` in `AppScope/app.json5`.
2. Run `.\scripts\check.ps1 -Build`; it must print `CHECKS: PASS`.
3. Install the HAP on the emulators and repeat §5.2 (and §5.3 if relay code changed).
4. Copy `entry\build\default\outputs\default\entry-default-unsigned.hap` to `dist\SafeMesh-<version>.hap` and write the SHA-256 manifest.
5. Update README (status, hashes, links), SUBMISSION.md and AI_WORKFLOW.md.
6. Commit, run `git fetch`, then a normal `git push` (no force), then:
   ```powershell
   gh release create v<version> dist\SafeMesh-<version>.hap dist\SafeMesh-<version>.sha256.txt --title "..." --notes-file notes.md
   ```

### 8.4 Repository rules (from AGENTS.md)

- Commits use the configured `huberthack` identity. Add no AI co-author trailers and do not list authors in documents; AI use is disclosed in AI_WORKFLOW.md.
- Never commit `.cache/`, `dist/`, private keys, activation codes, `.p12`/`.p7b`/`.cer` files or a DevEco-signed `build-profile.json5`.
- Do not rewrite published history.

## 9. Troubleshooting

| Symptom | Fix |
| --- | --- |
| `devecocli` not found | Add `%APPDATA%\npm` to `PATH` (§3) |
| ArkTS check "Cannot find module 'entry/transport/NearLinkTransport'" | You ran `devecocli check arkts` directly. Use `check.ps1`, which mirrors each product's source set |
| Emulator shows the lock screen; app lost its link | Wake it and set the timeout (§3), relaunch the app, Connect again |
| Relay says "Connection failed. Check that the test server is running." | Start the hub with `start-authority-demo.ps1` or `start-mesh-lab.ps1`; check `netstat -ano \| findstr 8765` |
| Issuer console "The local exercise authority is unavailable…" | The issuer is not listening on 8768, or A has no reverse port: rerun `start-authority-demo.ps1 -SkipBuild` |
| "This service does not match the trusted exercise authority" | The app's pinned key does not match `.cache\demo-authority`: run `start-authority-demo.ps1`, which adopts the pin and rebuilds |
| Load exercise message → verification failed | Fixture expired or wrong clock: §8.1 |
| HAP install fails on a phone with "no signature file" | Unsigned emulator HAP: sign in DevEco (physical runbook §3) |
| `build-profile.json5` changed unexpectedly | Someone signed in DevEco or ran `oniro-app sign`: `git checkout -- build-profile.json5` |
| Git reports CRLF warnings | Harmless; `.gitattributes` normalizes to LF on commit |

## 10. Submission status (2026-10-04)

Huawei "Imagine What's Next" deliverables:

| Requirement | Status |
| --- | --- |
| Public source repository | Done: github.com/carrotly-technologies-2026/SafeMesh |
| Reproducible setup, build, install and launch | Done: README, this guide and `check.ps1`. A fresh clone of `main` (`fe5d56b`) from GitHub passed `check.ps1 -Build` on the team laptop: 172/172, ArkTS 0/0, lint 0, build OK ([log](../artifacts/logs/v150-fresh-clone-checks.log)). Builds are not byte-identical, so a rebuilt HAP has a different SHA-256 from the released one. This is the same machine, not a second computer. |
| Working `.hap` | Done: Release v1.5.1 (`SafeMesh-1.5.1.hap`, SHA-256 `5d31a1ca…`) |
| Recorded demonstration | Done: `SafeMesh-1.4.1-demo.mp4` in the releases. **Open:** upload to YouTube (Unlisted) for the form |
| Architecture and implementation description | Done: README (*Architecture*, *Platform capabilities*, *Transport and signature design*) |
| `AI_WORKFLOW.md` | Done. **Open:** the team confirms which agent and model did the v1.2–v1.4 sessions |
| Target HarmonyOS / OpenHarmony / Oniro, min API 20 | Done: `default` (HarmonyOS) and `oniro` (OpenHarmony API 23) products |
| Runs on an emulator | Done: API 24 emulators, native evidence in `artifacts/` |
| English materials | Done: docs, video and app (System language → English on non-Polish systems) |

Remaining work, in order of value:

| # | Task | Owner | Why it matters |
| --- | --- | --- | --- |
| 1 | Physical NearLink test (A → B → C) with recorded evidence, then the README "Physical NearLink validation" section | Team at the venue | Biggest lever for *Use of platform capabilities* and *Demonstration*: today NearLink is implemented but unverified |
| 2 | YouTube upload and form update (links to Release v1.5.1, texts from SUBMISSION.md) | Team | The form requires a YouTube link |
| 3 | Re-run `scripts/oniro/deploy.sh` on the Oniro emulator (API 23) after the merge; add a screenshot to `artifacts/screenshots/oniro-*` | Oniro maintainer | Confirms the merged `oniro` product on its real toolchain |
| 4 | Short pitch deck, if the jury invites teams to present | Team | Rules allow the jury to invite teams; nothing exists yet |
| 5 | Optional: split `pages/Index.ets` (about 1,080 lines) into components | Later | Code readability; deliberately deferred to avoid regressions before judging |
| 6 | Roadmap, not for the hackathon: background relaying with the API 26 `MODE_NEARLINK` continuous task, official issuer integration and key management | — | Documented in README as next steps |
