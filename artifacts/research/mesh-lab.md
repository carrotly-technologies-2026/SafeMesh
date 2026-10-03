# SafeMesh 1.2: native three-emulator transport lab

This lab exchanges actual packets between three independent HarmonyOS app processes. Each app runs the same native signature verifier, private storage, relay policy, delivery queue and receiving-app acknowledgements used by SafeMesh. An explicitly labelled loopback WebSocket mock replaces the packet link. It does not measure physical NearLink discovery, MTU behavior, range, interference, battery use or background delivery.

The recorded native sequence passed A → B with ACK loss/retry, restored B's saved alert after its app process restarted, and delivered B → C with A disconnected. C accepted the unchanged signed alert at hop 2. Separate injections demonstrated tamper/expiry rejection and duplicate acknowledgement without another forward to C. These are exercise messages from the demo issuer, not RCB or production-authority warnings.

## Architecture and local setup

The loopback WebSocket hub routes packets only along configured edges. The default topology is A—B—C, with no A—C edge. The hub neither signs, verifies, caches nor acknowledges alerts. Delayed delivery must therefore come from the cache in app B. Test role names are routing labels, not authenticated device identities.

| Role | Local emulator | Device loopback port | Host hub port |
| --- | --- | --- | --- |
| A | HackYeahPhone | 8765 | 8765 |
| B | SafeMeshB | 8766 | 8765 |
| C | SafeMeshC | 8767 | 8765 |

HDC reverse forwarding connects each device port to the host hub. This HDC build deduplicates identical forwarding specifications across targets, so three identical `tcp:8765 tcp:8765` requests are insufficient even when all report success. Distinct device ports were verified in `hdc fport ls`. The application selects one of the three fixed loopback URLs from its A/B/C role; it accepts no arbitrary server URL.

The existing three API 24 emulators share the installed system image and each have 4 GB RAM. On this emulator version, creating instances with `--device-type Phone` and the default screen profile succeeded after an earlier custom configuration failed to appear. The launcher uses existing instances and does not download SDKs, accept licences, uninstall apps or clear application storage.

From the project folder on the configured Windows host:

```powershell
$env:DEVECO_CLI_STUDIO_PATH = 'C:\Users\user\DevEcoStudio'
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/start-mesh-lab.ps1
```

The launcher builds once and deploys the same HAP to all three devices in sequence, requiring successful CLI exit codes and native smoke checks. It discovers serials by emulator name, verifies each reverse mapping and checks the hub's service identity before reusing it. A new hub runs hidden; logs and its PID are stored in ignored `.cache/mesh-lab/`. The successful native launcher run is recorded in [mesh-lab-helper-final-run.log](../logs/mesh-lab-helper-final-run.log).

Use `-SkipBuild` for an already-built HAP. Emulator names can be supplied with `-EmulatorA`, `-EmulatorB`, and `-EmulatorC`. The launcher preserves an existing hub's test controls and warns about a custom topology or pending drops. It does not click app controls or clear storage.

For a reproducible repeat, use `-RefreshDrill` to generate a new exercise key/fixtures, rebuild and redeploy **all three apps** together, even if the prior exercise has not expired. Otherwise previously accepted alerts remain duplicates by design. `-SkipBuild` and `-RefreshDrill` cannot be combined. Old cache entries fail signature verification under the new demo key; no data wipe is required. Never refresh only one emulator.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/start-mesh-lab.ps1 -RefreshDrill
```

The current signed exercise expires at **2026-10-06T17:45:51.662Z**. Fixture refresh retains the 72-hour validity limit and does not ship the temporary issuer private key.

On each app, open Relay, expand the multi-emulator test panel, choose the appropriate role and connect. The global mock-transport label stays visible when navigating to Home or Map. Leave the apps in the foreground. Choosing the NearLink check explicitly ends the lab transport.

## Topology and fault controls

The hub binds only `127.0.0.1:8765`. HTTP administration requires its loopback Host and a compatible Origin. WebSocket handshakes also accept the two fixed HDC port aliases. Inputs are bounded to three nodes, 16 KiB packets and 64 KiB outer messages. Malformed protocol frames and duplicate identities are rejected. Packets without an active permitted route are counted as lost/blocked, without disconnecting an otherwise valid sender. Control injection is an explicit test operation and is counted separately.

```powershell
node scripts/mesh-lab-control.mjs state
node scripts/mesh-lab-control.mjs reset
node scripts/mesh-lab-control.mjs links AB
node scripts/mesh-lab-control.mjs links BC
node scripts/mesh-lab-control.mjs links AB BC
node scripts/mesh-lab-control.mjs drop ack B A 1
node scripts/mesh-lab-control.mjs disconnect A
node scripts/mesh-lab-control.mjs disconnect B
```

`reset` clears counters and queued loss rules; it does not clear app caches, disconnect nodes or change topology. `links AB` leaves a connected C isolated. `disconnect A` closes the local lab socket; it does not stop the app or erase storage. The hub assigns a packet's source from the connected role, rather than trusting a client-supplied source. Role labels are still cooperative test identities, not peer authentication.

For deterministic tamper, expiry and duplicate injection, derive bounded wire packets from the existing public signed fixtures:

```powershell
node scripts/mesh-lab-fixtures.mjs
node scripts/mesh-lab-control.mjs inject A B .cache/mesh-lab/fixtures/tampered.json
node scripts/mesh-lab-control.mjs inject A B .cache/mesh-lab/fixtures/expired.json
node scripts/mesh-lab-control.mjs inject A B .cache/mesh-lab/fixtures/duplicate.json
```

The fixture helper verifies the existing signatures with the pinned public key, changes only the tampered packet's body, and adds deterministic test-only delivery tokens. It never signs, rotates keys or refreshes dates. It fails if the current exercise is already expired; use the all-three `-RefreshDrill` workflow first. The [recorded fixture manifest](../logs/mesh-lab-05-fixture-manifest.json) identifies the tested source and validity period.

Dropping an ACK triggers a resend and a duplicate acknowledgement by the receiving app. The hub classifies only the outer data/ACK type to select a fault; it does not validate authority signatures or generate ACKs. Native application logs record node, verdict, alert ID and hops, without message bodies, positions or private keys. A successful ACK is a cooperative app receipt, not a human-read receipt or a new authority signature.

## Reproduce the native sequence

1. Start the lab with a fresh common exercise build. On each app, connect its assigned A/B/C role. Set `links AB` and `reset`; C can remain connected to the hub while having no permitted neighbor.
2. Before sharing from A, run `drop ack B A 1`. Load the signed drill on A and share it. B should display a verified, saved alert. A should record one retry and one receiving-app acknowledgement; C should still have no alert.
3. Disconnect A from the hub. Reinstall/relaunch the **same HAP** on B with `devecocli.cmd run --skip-build --module entry --device SafeMeshB`. Do not uninstall or clear data. Confirm B's Home screen says stored signatures were rechecked before reconnecting its B role.
4. Switch to `links BC`. B should synchronize its restored cache to C. Confirm a native C verdict of `accepted` with `hops=2`, a B → C packet and C → B ACK, with A → C remaining zero.
5. Reconnect A and restore `links AB BC`. Derive the fault fixtures, then inject tampered and expired packets A → B. Compare before/after route counters: neither injection should cause a success ACK or another B → C forward. B must retain the original verified content.
6. Inject the duplicate. B should record `duplicate` and send one ACK to A; B → C should stay unchanged.

The first recorded stage-3 run needed an explicit `disconnect B` after B restarted: HDC left the old host-side socket occupying role B. This manual control is part of the evidence, not an automatic-reconnect claim. Heartbeat hardening was added afterward, as described below.

## Recorded native evidence

All three instances run the native API 24 HAP, not Node copies of the relay. The device clock was UTC+8 and the host clock UTC+2; native log dates of October 4 correspond to October 3 UTC in host artifacts.

The saved [native assertion report](../logs/mesh-lab-native-results.json) records **8 / 8 PASS** for stages 01–06, using HAP SHA-256 `ab65c38028633dc6a87c882b133fd1224ca90a3575c1dada2520b90d68e6b9d8`. A subsequent adapter diagnostic change produced a different final package; the complete packet scenario is attributed to this tested HAP rather than silently reassigned to the newer build.

| Stage | Observed result | Evidence |
| --- | --- | --- |
| 02: A → B and lost ACK | A → B forwarded 2 packets. B accepted hop 1, then classified the retransmission as duplicate. B → A dropped the first ACK and forwarded the second. A showed 1 retry / 1 ACK. Connected but isolated C showed no alert. | [Hub state](../logs/mesh-lab-02-lost-ack-state.json), [B native log](../logs/mesh-lab-02-b-receive.log), [A counters](../screenshots/mesh-lab-02-a-retry-metrics.png), [B verified Home](../screenshots/mesh-lab-02-b-verified-home.png), [C isolated Home](../screenshots/mesh-lab-02-c-isolated-home.png). |
| 03: B durable restoration | B's app PID changed from 23058 to 32164 after same-HAP reinstall/relaunch with preferences retained. A was disconnected; B's Home reported saved signatures rechecked. The stale host-side B socket was manually disconnected before reconnection. | [B restart](../logs/mesh-lab-03-b-restart.log), [restored Home](../screenshots/mesh-lab-03-b-restored-home.png), [isolated state](../logs/mesh-lab-03-b-restored-isolated-state.json), [process proof](../logs/mesh-lab-04-process-proof.json). |
| 04: restored B → C | With only B–C enabled and A disconnected, B → C forwarded 1 packet and C → B forwarded 1 ACK; A → C stayed 0. C accepted hop 2 at native time 02:20:14.433; the new B process logged the matching ACK. | [Hub state](../logs/mesh-lab-04-b-to-c-state.json), [C native log](../logs/mesh-lab-04-c-receive.log), [B after restart](../logs/mesh-lab-04-b-restored-relay.log), [C verified Home](../screenshots/mesh-lab-04-c-verified-home.png). |
| 05: tampered / expired injection | Two injected packets reached B. Its native verdicts were `invalid` and `expired`; rejection count became 2. B → A forwarded stayed 3, and B → C stayed 1: no success ACK or onward forwarding. The original verified alert remained displayed. | [Before counters](../logs/mesh-lab-05-before-invalid-state.json), [after counters](../logs/mesh-lab-05-after-invalid-state.json), [B rejection log](../logs/mesh-lab-05-b-rejected.log), [rejection metrics](../screenshots/mesh-lab-05-b-rejection-metrics.png), [original retained](../screenshots/mesh-lab-05-b-original-retained.png). |
| 06: explicit duplicate | B logged `duplicate`, hop 1, at 02:23:42.058. B → A forwarded increased 3 → 4 for its ACK; B → C stayed 1, with no new accepted alert. | [Duplicate native log](../logs/mesh-lab-06-b-duplicate.log), [hub state](../logs/mesh-lab-06-duplicate-state.json). |

After heartbeat, route-loss and adapter-diagnostic changes, the final check/build passed **96 host tests across nine suites**, **19 ArkTS files / zero errors**, 29 permission/exception advisories, **zero lint issues** and **BUILD SUCCESSFUL**. The [combined final log](../logs/mesh-lab-final-checks-build.log) records every suite and check. Host tests include real local WebSocket sockets and mocked native adapter APIs; they are distinct from the native app observations above.

The final v1.2 package is [SafeMesh-mesh-lab-1.2.0.hap](../../dist/SafeMesh-mesh-lab-1.2.0.hap), SHA-256 `5372d8d19d3ef8dfaba215b93966015afbbdedb440bd127e557b945ff1746cfe`, with its [own checksum manifest](../../dist/SafeMesh-mesh-lab-1.2.0.sha256.txt). Application source commit: `f634791067ea2d33257929fddb21c6bc59762495`. The [final deployment log](../logs/mesh-lab-final-deploy.log) records installation and launch on all three emulators. Existing v1.1 HAP/video/source archives remain untouched.

The final build was then reconnected as A/B/C, restoring and re-verifying its cached alerts. It exchanged cached packets and matched app ACKs over A–B and B–C. All three were left on Home in the foreground: [A](../screenshots/mesh-lab-final-a-home.png), [B](../screenshots/mesh-lab-final-b-home.png), [C](../screenshots/mesh-lab-final-c-home.png). The [final state](../logs/mesh-lab-final-state.json) and [hub log](../logs/mesh-lab-final-hub.log) retain the topology and routing evidence.

The final diagnostic fix also passed a native regression: B's app attempted occupied role A, displayed `hub: Node ID is already connected (0)` after cleanup, then successfully connected as B with two neighbors and cleared the old error. See [visible error](../screenshots/mesh-lab-final-b-error-detail.png), [recovered layout](../screenshots/mesh-lab-final-b-reconnected.json) and [B runtime log](../logs/mesh-lab-final-b-runtime.log).

## Native findings during integration

Fresh B/C installations exposed an empty-cache decoding failure that the pre-populated first emulator did not show. `decodeEnvelope` and `decodeDataPacket` now reject an empty string before invoking the native text encoder. A host regression first reproduced `Cannot read properties of undefined (reading 'length')` with an encoder returning no byte array for empty input, then passed after the guards. B and C subsequently completed native empty-cache initialization and received their first verified alert in stages 02/04.

Native execution also showed that dynamically importing the kit namespace did not provide `webSocket.createWebSocket`. The adapter uses the standard public NetworkKit import. The manifest includes the normal `INTERNET` permission needed by the local socket; there is no external service in this lab.

The API 24 native WebSocket sends a **portless loopback Origin**. The hub now accepts that exact loopback-origin form only for WebSocket upgrades whose Host matches one of the three fixed port aliases. HTTP administration retains its stricter origin check. Arbitrary remote origins or hosts are not allowed; the fix does not expose an external listener.

HDC's stale socket after B's process exit motivated WebSocket heartbeat handling: the hub sends a Ping after **5 seconds**, with a random nonce and a **10-second Pong deadline**. Only the matching Pong clears that deadline. Timers are cleared on close, and an unresponsive connection is removed so its role can be reused. A topology/disconnection race is treated as packet loss, leaving healthy sender sockets open for the app's bounded retry policy.

The subsequent native heartbeat test passed. B restarted from PID 32164 to 10540; the stale role disappeared automatically **12.257 seconds after relaunch began**, with no administrative disconnect, while A and C remained connected. B then reconnected on its first attempt and all three roles were present. Evidence: [automatic removal](../logs/mesh-lab-08-stale-peer-removed.json) and [reconnected state](../logs/mesh-lab-08-reconnected-state.json). This later result addresses the manual stale-role cleanup needed in stage 03.

## Scope and remaining checks

- Three separate native app processes, local packet delivery, native cryptography, cache restoration, application ACK/retry policy and rejection behavior were exercised. The local hub is an intentional transport mock, not a NearLink radio simulator.
- Physical NearLink remains unverified. Its existing dynamic Kit-loading path needs a device/API review before phone trials; SDK-supported named lazy Kit imports provide a candidate, but no physical runtime result is claimed here.
- The hub has no authority private key, message cache or automated alert acknowledgement. Cooperative A/B/C labels do not authenticate device identities. Signatures authenticate exercise content under the pinned demo key only.
- The apps must remain in the foreground. Locked-screen/background delivery, battery/range/congestion behavior, field protective-point access and successful physical GPS remain separate validation tasks.
- Existing v1.1 screenshots, the 90-second single-emulator video and its clean-checkout build remain historical checkpoints. They are not proof of the v1.2 multi-emulator transport. No publication is implied by retaining local artifacts.
