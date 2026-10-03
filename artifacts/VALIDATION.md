# SafeMesh validation record

Recorded 2026-10-03. Target: HarmonyOS 6.1.1 / API 24 phone emulator, serial `127.0.0.1:5555`. Package: `org.safemesh.alerts`, minimum API 20, target API 24. Native NearLink adapter requires API 23+ and compatible physical hardware.

## Final artifact

- `dist/SafeMesh-demo.hap`, debug unsigned emulator HAP.
- SHA-256: `eccb9ca5f5f5ac996df0a3a7762e7450c5ef382f9936fa09099b5b89f6f6fd1b`.
- Built and deployed by `powershell -ExecutionPolicy Bypass -File scripts/run-demo.ps1`.
- Build successful, installation successful, launch successful, `Smoke: PASS`. See [final build/run log](logs/final-build-run.log).
- This emulator accepted the unsigned artifact. Physical-phone installation requires appropriate signing and provisioning; that was not tested.

## Automated checks

| Check | Result | Evidence |
| --- | --- | --- |
| Host suites | 40 passed, 0 failed | [Host test log](logs/host-tests-final.log) |
| ArkTS static check | 13 files, 0 errors | [ArkTS log](logs/arkts-check-final.log) |
| Code Linter | 0 errors, 0 warnings, 0 suggestions | [Lint log](logs/lint-final.log) |
| HAP build and emulator smoke | Passed | [Build/run log](logs/final-build-run.log) |

Host suites comprise 9 protocol, 7 transport, 8 map, 9 ViewModel integration and 7 storage tests. They execute the actual application sources with explicitly mocked platform boundaries and Node/OpenSSL crypto. Native checks below establish the tested HarmonyOS behavior separately. Storage host checks include the maximum bounded snapshot, Unicode chunks, initialization/concurrency and simulated failed/ambiguous commits; no physical power-loss test was performed.

The separate ArkTS checker emits permission and possible-exception advisories. `ACCESS_NEARLINK` is declared in the manifest and requested at runtime. Native failures are caught at the adapter, verification and persistence boundaries. Physical permission prompts remain untested on this emulator.

## Native interaction checks

| Behavior | Observed result | Evidence |
| --- | --- | --- |
| Home | Branded interface, bundled map and exercise label render | [Home](screenshots/home-final.png) |
| Offline map | Roads, PSP markers and attribution render; zoom works | [Map](screenshots/map-final.png) |
| Marker selection | Tapping a marker changed selection to `ul. Łobzowska 8, Kraków`, 597 m from the demo origin | [Selection tree](screenshots/map-picked-layout.json) |
| Point persistence | Saved `Rynek Główny 1, Kraków`; after redeployment/relaunch its button reads `Saved on this phone` | [Saved](screenshots/saved-point-layout.json), [restored](screenshots/persistence-map-layout.json) |
| Alert persistence | Relaunch restored the exercise with `Signature verified · demo authority` and `Saved signatures re-verified` | [Tree](screenshots/persistence-alert-layout.json), [screen](screenshots/alert-restored.png) |
| Native relay drill | A/B/C accepted with native ECDSA; duplicate suppressed; modified text invalid; expired fixture rejected; 6/6 | [Final relay](screenshots/relay-release.png), [tree](screenshots/relay-release-layout.json), [all six results](screenshots/relay-top.png) |
| Hardware probe | `NearLink radio is unavailable on this device. Emulator relay uses simulation.` and `0 connected` | [Hardware tree](screenshots/hardware-final-layout.json) |
| Guide | Offline preparation information and trust explanation render | [Guide](screenshots/guide-final.png) |

Screenshots before the final builder-colour fix remain as intermediate evidence. `relay-release.png` is the final relay appearance. The persistence check used normal redeployment/relaunch preserving app data; it was not a device factory reset, uninstall, crash-recovery or power-cycle test.

## Limits of this evidence

- Three virtual relay engines run inside one app. No physical NearLink transfer, range, congestion, battery or background availability was measured.
- Only the pinned exercise issuer is trusted. There is no RCB integration, operational authority key or live warning feed. The included valid fixture expires on 2026-10-06 at 15:19:32 UTC; regenerate and rebuild for a later demo.
- The map is a bounded reference extract with 40 actual PSP records and OSM geometry. Source availability is not live access confirmation or a shelter safety guarantee. The origin is a labelled demo position, with straight-line distances and no evacuation route.
- Device time, signing-key custody, revocation and denial-of-service remain deployment considerations. Signatures authenticate signed content under the pinned-key assumption; they cannot guarantee delivery or physical safety.

Source evidence: [NearLink](research/nearlink.md), [security](research/security.md), [maps](research/maps.md). Reproduction instructions and test commands: [README](../README.md).
