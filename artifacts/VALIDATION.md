# SafeMesh 1.1 validation record

Recorded 2026-10-03. Final application source: local commit `1bd015dc9ca3cea9c230b78b0253abfc61a8bcae`. Target: HarmonyOS 6.1.1 / API 24 emulator `127.0.0.1:5555`; package `org.safemesh.alerts`, minimum API 20 / target 24. Runtime evidence is from API 24 only.

## Packaged artifacts

- `dist/SafeMesh-demo.hap`: debug unsigned emulator package, SHA-256 `42406469e63c55df70ba3d9472b48df4b7c3a9a4722f560128fb9e9f2d5cc005`.
- `dist/SafeMesh-demo.mp4`: silent 90-second native demonstration, H.264, 478 x 1030, 15 fps, 1,350 live frames, zero late frames. SHA-256 `95e928f6cf8f3ed8a10e3dc9c69475c94caa935abd384ee65d413a0978532df6`.
- `dist/SafeMesh-source.zip`: source archive of the final local Git revision, including subsequent documentation/evidence commits. `dist/SHA256SUMS.txt` records all three artifact hashes.

The video captures only the emulator window through PrintWindow; decoded frames at 30, 60, 85 and 89 seconds were inspected. It shows native alert/map/relay/settings behavior, including the six-check result and Dark/English settings. It is not physical NearLink evidence. [Capture metadata](logs/v11-demo-capture.json). Nothing was published or uploaded.

## Automated and native checks

| Check | Observed result | Evidence |
| --- | --- | --- |
| Host suites | **61 passed, 0 failed**, seven suites exercising actual application sources | [Full run](logs/v11-checks.log), [clean checkout](logs/v11-clean-checkout.log) |
| Final ArkTS | **17 files, 0 errors**; permission/possible-exception advisories remain | [Static log](logs/v11-release-arkts.log) |
| Final Code Linter | **0 errors, 0 warnings, 0 suggestions** | [Lint](logs/v11-release-lint.log) |
| Final HAP build/install/launch | **BUILD SUCCESSFUL**, exit 0; install and launch succeeded, **Smoke: PASS** | [Build](logs/v11-release-build.log), [run](logs/v11-release-run.log) |
| Clean checkout | Fresh local clone of the source commit on this same host; host/static/lint/build checks passed | [Log](logs/v11-clean-checkout.log). This is not a second-machine test. |
| Four native destinations | Native house/map/phone-transfer/book icons with labels and selected state render; header gear opens Settings | [Home](screenshots/v11-release-home.png), [map](screenshots/v11-release-map.png) |
| Settings return navigation | Settings hides the bottom bar; header arrow and system Back both return to the previous Map screen | [Settings](screenshots/v11-gear-settings.json), [arrow return](screenshots/v11-gear-back-map.json), [system Back](screenshots/v11-gear-system-back.json) |
| Language and preferences | PL/EN copy and dynamic labels change; Dark + English survive normal redeployment/relaunch; signed payload remains unchanged | [Restored selection](screenshots/v11-settings-restored.json), [restored Home](screenshots/v11-restored-dark-en.png), final video |
| System appearance and override | Automatic mode follows system Dark. App Light remains light under system Dark. App Dark also renders the Canvas in dark colors | [Automatic](screenshots/v11-system-auto-dark-settings.png), [override](screenshots/v11-system-light-override.png), [final dark map](screenshots/v11-gear-dark-map.png) |
| Offline map/search | Geometry and points render, zoom works; `Bracka` returns **3 / 40** records | [Final map](screenshots/v11-release-map.png), [search](screenshots/v11-search-final.json) |
| Durable saved point | Saved `ul. Bracka 2, Kraków`; after relaunch, the Home saved-point action reopens that address and its saved badge | [Save](screenshots/v11-save-bracka.json), [restore](screenshots/v11-saved-restored.json) |
| Alert restoration | Stored alert is restored, signatures re-verified, expiry shown unambiguously in UTC | [Restored Home](screenshots/v11-restored-dark-en.png) |
| Optional location denial | Native permission dialog opens; denial retains the previous origin and shows a localized explanation | [Request](screenshots/v11-location-request.json), [denial](screenshots/v11-location-denied.json) |
| Native signed relay drill | **6 / 6:** A/B/C acceptance, duplicate suppression, modified-content rejection and expired-alert rejection | [Result](screenshots/v11-relay.json), final native video |
| Honest radio state | Emulator reports no NearLink radio, 0 physical peers and zero physical queue metrics | [State](screenshots/v11-nearlink.json), [screen](screenshots/v11-nearlink.png) |
| System text scaling | Huge measured as **fontSizeScale=1.45**, with readable scrollable Home/Settings; Normal restored as 1.0 | [Configuration log](logs/v11-font-configuration-final.log), [Huge Home](screenshots/v11-font-huge-home.png). Final four-icon layout check is recorded below. |

The suites cover protocol, radio adapter, map, ViewModels, chunked storage, location boundary and delivery queues. Radio, storage, location and Canvas boundaries are mocked where needed; host cryptography uses Node/OpenSSL. Native checks establish the separate observed HarmonyOS behavior. Storage failure and packet-loss simulations are not physical power-loss/radio tests.

## Final layout checkpoint

The final four-icon navigation passed at Huge (measured font scale 1.45): all four labels remained readable on Home, Map, Relay and Guide. Settings, language choices, the header gear and return to the previous Map screen were checked. The three simulation-card labels wrap onto two lines without clipping. Evidence: `screenshots/v11-release-huge-*` PNGs and layout JSON, including `v11-release-huge-back-map.json`.

The emulator was restored to Normal text (1.0), Light system appearance and SafeMesh System/Polish/Home, with a passing launch smoke check. See `screenshots/v11-release-restore-normal.json`, `v11-release-restore-light.json` and `v11-release-restored-home.*`. The configured maximum is 2x, but neither 1.75x nor 2x rendering is claimed; ScreenReader interaction remains untested.

## Evidence limits

- Only an emulator was available. Physical NearLink scanning, delivery, range, congestion, battery and continuous background/locked-screen forwarding remain unverified. ACKs mean cooperative receiving-app receipt, not authenticated peer identity, guaranteed durable storage or human readership.
- Only a pinned exercise issuer is trusted. No official RCB feed, operational signing service, revocation infrastructure or trusted-time policy is integrated. The valid fixture expires **2026-10-06 15:19:32 UTC**; regenerate and rebuild for later demos.
- The map contains 40 real PSP reference records, not a complete city inventory or a guarantee of shelter condition/access. Distances are straight-line. Native GPS success, inaccurate/outside-pack fixes and physical positioning accuracy were not verified; host cases cover those branches. CLI scene injection requires Emulator 7+, whereas this emulator is 6.1.1.200.
- ScreenReader reading order/announcements, landscape, narrow-window and split-screen adaptation remain untested. Semantic labels and contrast checks do not imply certification.
- The unsigned HAP is validated on this emulator only. Physical phones require signing/provisioning. Publication remains outstanding: only local commits are authorized.

## Earlier checkpoints

The original revision passed 40 host tests and native drill checks: [host](logs/host-tests-final.log), [build/run](logs/final-build-run.log). The follow-up [58-test run](logs/upgrade-host-tests.log) predates bounded-send/startup regression additions. Older screenshot names containing `final` or `release`, and the intermediate five-tab Settings screenshots, retain their historical names. Use `v11-release-*`, `v11-gear-*`, the final video and this record for the current navigation.

Research: [NearLink](research/nearlink.md), [security](research/security.md), [maps](research/maps.md), [location/save state](research/location-and-saved-points.md), [UI](research/ui-upgrade.md). Reproduction: [README](../README.md).
