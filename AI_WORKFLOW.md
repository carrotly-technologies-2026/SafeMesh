# AI Workflow

SafeMesh was developed with substantial AI assistance on 2026-10-03. This disclosure describes the work actually performed and the evidence used to evaluate it. The original civilian emergency-information concept and request came from the human participant; the coding agent carried out research, design, implementation and automated validation. Human acceptance of the final submission is not implied by automated checks.

## Tools used

| Model, agent, tool or skill | Version or source | Role |
| --- | --- | --- |
| OpenAI Codex | GPT-6 agent family identified by the session; exact model snapshot was not recorded | Main coding agent: scope, architecture, integration, ArkUI implementation, build and emulator validation. |
| Codex delegated agents | Same shared workspace; initial NearLink, security and offline-map work, followed by UI/accessibility, delivery, location and demo-tooling tasks | Parallel primary-source research, implementation and focused review/tests with assigned file ownership. |
| Web search and page retrieval tools | Session-provided browser tools | Official Huawei/OpenHarmony API research, PSP/Polish government data and OSM licensing evidence. |
| PowerShell, filesystem reads and patch tools | Windows development host | Inspect exact SDK declarations, apply source changes and invoke reproducible build/test commands. |
| DevEco CLI | 1.3.4, with the challenge's matching verified patches | Scaffold, local documentation search, ArkTS checks, lint, build, device discovery, install/launch, UI inspection, screenshots and logs. |
| DevEco Studio / HarmonyOS SDK | Studio 6.1.1.280, SDK API 24; API 24 phone emulator | Native compiler, runtime, CryptoArchitectureKit and ArkUI validation. |
| Node.js / npm | 24.21.0 / 11.19.0 | Host tests, cryptographic fixture generation and SDK-compiler test harnesses. |
| Python | 3.14.8 on the host | Source-data acquisition, map transformation, refresh and isolated emulator-window recording. |
| FFmpeg / Win32 PrintWindow | FFmpeg 7.1 from the installed Studio JAR; native Windows window-rendering API | Encode live emulator-only frames into a local silent H.264 demonstration. Recorder smoke evidence is separate from final app-video evidence. |
| Built-in image generation (`imagegen`) | Session-provided image-generation tool; exact model snapshot was not recorded | Create the conceptual submission-cover illustration. The cover is not an app screenshot or evidence of physical radio communication. Prompt and final asset are recorded separately. |
| `deveco-cli` skill | Locally installed skill from the challenge/tooling setup | Verified CLI workflows and local documentation retrieval. |
| `ohos-app-scaffold`, `ohos-app-dev` skills | Locally installed challenge skills | Native scaffold, build/run and ordinary application workflow. |
| `ohos-system-app-dev` skill | Locally installed challenge skill, privilege preflight only | Check whether NearLink required system privileges; exact permission metadata showed ordinary-app access suffices. No system-app signing was used. |
| `hmos-arkts-knowledge-retriever` | Locally installed challenge skill and bundled references | ArkTS syntax/API grounding and strict typing guidance. |
| `hmos-arkui-develop-skill`, `hmos-arkui-scenario-development`, `hmos-arkui-mvvm-pattern` | Locally installed challenge skills | ArkUI component, state ownership and ViewModel implementation guidance. |

No external product MCP server is required by SafeMesh, and no external MCP integration is recorded in this implementation's evidence. Session orchestration provided web, shell/file and agent-collaboration tools. The app does not call Codex, a chatbot or an AI service at runtime.

## Important prompts and instructions

The participant's public-safe request, condensed for readability:

> Build a HarmonyOS hackathon app for situations where mobile networks fail. Research Huawei NearLink and try to relay warnings from phone to phone. Authenticate warnings so attackers cannot falsify accepted messages. Make maps and protective-point information available offline. Use the available HarmonyOS emulator and choose an appropriate native language such as ArkTS.

The implementation instructions given to specialist agents were:

- **NearLink:** use official Huawei/OpenHarmony sources and installed SDK declarations; identify public APIs, permissions and emulator limitations; implement a typed native transport without invented APIs or fabricated peers.
- **Security:** use platform-supported cryptography, a pinned exercise trust root, canonical signed content, strict parsing, expiry/replay controls and mutation-safe persistence; never package an issuer private key or impersonate RCB.
- **Maps:** obtain real, attributed reference data; preserve official availability categories; provide a bounded offline pack and map UI without claiming routes, live access or guaranteed shelter protection.
- **Integration:** build a native ArkTS/ArkUI application, keep simulation labels explicit, test on the running emulator, and record concrete build/runtime evidence.

After asking whether the prototype fully followed HarmonyOS guidance, the participant requested local commits and continued implementation of the remaining audit findings. Follow-up assignments covered accessible controls and native announcements, Polish/English resources, saved appearance/language choices in a dedicated Settings screen, adaptive text, honest saved-point persistence, optional foreground location, full-cache relay synchronization with bounded receipts/retries, and a real emulator-only video recorder. The final navigation has four bottom destinations with native `SymbolGlyph` icons and a native gear at the top right opening Settings; both in-app and system return navigation were exercised. The participant required Git author and committer identity to remain exclusively **Tomek i Hubert**, with no AI co-author trailers; that repository identity rule does not remove the challenge's requirement for truthful disclosure in this file.

The challenge's setup repository was consulted for compatible SDK guidance and the requirement to disclose AI use in this file. SafeMesh started from an Empty Ability scaffold, not a claim that the full challenge template was used. Repository research notes and the implementation contract record the specific technical decisions.

## AI-assisted work log

| Date | Workstream | AI-generated or changed work | Review and validation actually performed |
| --- | --- | --- | --- |
| 2026-10-03 | Product and architecture | Native Home, Map, Relay and Guide flows; separate model/ViewModel/view responsibilities; distinction between emulator simulation and hardware transport. | Main agent inspected the implementation contract, SDK constraints and integrated app behavior. Human supplied the product goal; final human sign-off is not recorded here. |
| 2026-10-03 | NearLink | Public API adapter, permission/capability handling, filtered discovery, bounded message framing and research note. | Exact installed `.d.ts` and permission metadata; official documentation; seven host tests against actual source. Physical radio exchange not tested. |
| 2026-10-03 | Signed alerts | Canonical ECDSA payload, trusted public exercise key, bounded relay/replay policy, fixture generator and protocol tests. | Host cryptographic tests plus native emulator verification, tampering, duplicate and expiry checks. |
| 2026-10-03 | Offline map | PSP/OSM acquisition script, generated map pack, ArkTS model, Canvas rendering and map tests. | Source-record comparison, licensing/provenance review, geometry/selection tests and emulator UI inspection. No field inspection of protective points. |
| 2026-10-03 | App integration | ArkUI screens, preferences storage, relay/alert ViewModels and error handling. | Integrated ArkTS check, lint, successful HAP build, install/launch smoke check, accessibility trees/screenshots and focused integration tests. |
| 2026-10-03 | Reproducibility | README, this disclosure, test scripts and research artifacts. | A fresh local clone at source `1bd015dc9ca3cea9c230b78b0253abfc61a8bcae` passed all 61 host tests, ArkTS 17/0, lint 0 and HAP build. This reused the same computer's Studio/SDK/CLI/cache; it was not another-machine or byte-identical-build verification. |
| 2026-10-03 | HarmonyOS UX follow-up | Alert-first Home, minimum-size native buttons, labelled/selected navigation, searchable alternatives for all 40 map points, announcement calls, PL/EN resources, saved language, Light/Dark/System choices and adaptive layout. | Final native-symbol navigation passed build and emulator smoke. Four tabs, Settings and return navigation were exercised at measured Huge `fontSizeScale=1.45`. Dark + English survived relaunch. System automatic dark and an app Light override under system Dark were inspected. Source cap 2.0 is not a tested scale; ScreenReader and landscape remain untested. |
| 2026-10-03 | Location and saved points | One-shot native foreground location boundary; accuracy/coverage/status handling; save badge updated only after durable write; saved-point reopening and race guards. | Fifteen combined map/location host checks passed against actual implementation with platform mocks. Native save/relaunch restored Bracka 2, and native location-permission denial was exercised. Successful positioning and physical accuracy remain untested. |
| 2026-10-03 | Foreground relay delivery | Full-cache peer synchronization, per-connection random receipt tokens, bounded serialized writes, retries and expiry; restore failure pauses radio startup. | Fourteen host delivery checks cover delayed peers/reconnect, mismatched and stale ACKs, packet/ACK loss, no re-flood, bounds, expiry, bounded native sends and stop/startup failures. The updated native exercise passed 6/6 checks; hardware transport showed no radio, zero peers and zero queue counters. Native radio remains untested. |
| 2026-10-03 | Recording and test setup | Standard-library Python capture of only the Emulator.exe client window, bundled FFmpeg encoding, reproducible check helper and native Settings navigation notes. | Final live emulator demonstration: 90 seconds, H.264, 478×1030, 15 fps, 1,350 frames, zero late frames. Huge 1.45 was exercised; the device was restored to Normal/Light and the app to System/Polish on Home. |
| 2026-10-03 | Submission cover | Conceptual illustration generated with the built-in image-generation tool. | Generation prompt: `artifacts/cover/PROMPT.txt`; final asset: `artifacts/cover/SafeMesh-cover.png`. The illustration communicates the concept and is not a screenshot or proof of radio delivery. |

## Workflow

### Ideation and architecture

The user proposed phone-to-phone emergency warnings and offline protective-point discovery. AI translated that into a demonstrable scope: a signed-alert engine independent of transport, a real NearLink adapter for future physical tests, a transparent emulator relay simulation and a bundled local map.

Research changed the design. NearLink exposes peer data APIs but no automatic application-level mesh router. The installed API 24 requires a scan filter and cannot scan by service UUID; the controlled hardware flow therefore uses a peer's device name. The emulator has no NearLink radio. These facts shaped the interface and prevented a false radio-demo claim.

The map is shipped as a small reference pack inside the HAP so first launch can work offline. The app does not invent protective-point locations or treat proximity as a safe route.

### Implementation and review

The main agent owned scaffold, UI and integration. Three delegated agents worked on NearLink, cryptographic protocol and map/data tasks, with explicit file ownership to reduce conflicting edits. Agents shared API contracts and source evidence; the main agent integrated callbacks and ViewModel flows.

The continuation used another coordinated work pass over UI/resources, location/save state, queue delivery and recording. The V1 observation architecture was preserved; a V1/V2 migration was not introduced as incidental cleanup. The map's native point list supplies equivalent actions for users who cannot use Canvas markers. Polish/English product text uses resource lookup, while signed alert text is displayed unchanged so a translation is not confused with authenticated bytes. The optional location action requests permissions only when selected and does not persist or relay the resulting position.

The delivery queue separates local radio writes from receiving-application receipts. ACKs use random per-connection correlation tokens and are accepted only for matching pending content. They are not authority signatures, authenticated recipient identities, durable-storage proofs or evidence that a person read a warning. Full-cache synchronization and bounded retries improve the foreground prototype without creating a claim of background mesh reliability.

Generated code was reviewed against installed SDK types and local ArkTS/ArkUI guidance. The mobile app uses only the exercise public key. The host generator signs bounded, expiring drill fixtures with a temporary private key that is not saved. Prototype trust constraints are documented in [security.md](artifacts/research/security.md).

AI review is not independent security certification. No human field verification, external penetration test or authority approval is claimed.

### Testing and debugging

The final verified application source is **`1bd015dc9ca3cea9c230b78b0253abfc61a8bcae`**. All **61 host tests across seven suites passed**, with zero failures; see [v1.1 checks](artifacts/logs/v11-checks.log). Final native-symbol navigation verification reported **no ArkTS errors in 17 files**, with separate permission/exception advisories, **zero lint issues**, successful HAP build and emulator install/launch **Smoke: PASS**. Evidence: [ArkTS](artifacts/logs/v11-release-arkts.log), [lint](artifacts/logs/v11-release-lint.log), [build](artifacts/logs/v11-release-build.log), [run](artifacts/logs/v11-release-run.log). Earlier 40-test, 58-test and Settings-build results remain historical checkpoints.

A fresh local clone checked out that exact source and independently reran `scripts/check.ps1 -Build`: **61 host PASS, ArkTS 17/0, lint 0, build PASS**. See [clean-checkout log](artifacts/logs/v11-clean-checkout.log) and [summary](artifacts/logs/v11-clean-checkout-summary.txt). This used the same computer and existing SDK/CLI/cache, not a clean second machine. The tooling changed only lockfile line endings; normalized content matched the commit. No byte-identical-build claim is made. The release HAP SHA-256 is `42406469e63c55df70ba3d9472b48df4b7c3a9a4722f560128fb9e9f2d5cc005`.

```powershell
$env:DEVECO_CLI_STUDIO_PATH = 'C:\Users\user\DevEcoStudio'
node --test tests/protocol.test.mjs tests/nearlink.test.mjs tests/map.test.mjs tests/integration.test.mjs tests/storage.test.mjs tests/location.test.mjs tests/delivery.test.mjs
devecocli.cmd check arkts --project .
devecocli.cmd check lint --format json .
devecocli.cmd build
devecocli.cmd run --skip-build --module entry --device 127.0.0.1:5555
```

Tests execute actual application source after transpilation/type erasure. They do not duplicate the relay algorithm in a separate test-only implementation. Host kit adapters deliberately mock radio, preferences or Canvas as needed; Node/OpenSSL backs host cryptographic operations. The app also exercised native cryptography on the emulator.

The updated relay UI again passed **6 / 6** native checks: acceptance at A, B and C, duplicate suppression, tampered-text rejection and expired-alert rejection. See [relay result](artifacts/screenshots/v11-relay.json). [NearLink state](artifacts/screenshots/v11-nearlink.json) separately reports unavailable radio, zero connected peers and zero pending, acknowledged, retry and failed queue counts; the simulation does not increment physical-delivery metrics.

The follow-up helper `scripts/check.ps1` discovers all `tests/*.test.mjs` suites and runs host, ArkTS and lint checks; `-Build` additionally builds the HAP. Native evidence confirms [Dark + English restored after relaunch](artifacts/screenshots/v11-settings-restored.json), [Bracka 2 restored as the saved point](artifacts/screenshots/v11-saved-restored.json), and [location permission denied](artifacts/screenshots/v11-location-denied.json). Host tests cover storage failure/race outcomes; a successful native save does not prove those failure paths. Remaining native checks include ScreenReader reading order/announcements, landscape/narrow-window adaptation, successful location fixes, outside-area handling and physical GPS accuracy.

The [final demonstration](dist/SafeMesh-demo.mp4) is a **90-second live emulator recording**, H.264 at **478×1030**, **15 fps**, **1,350 frames** and **zero late frames**; see [capture metadata](artifacts/logs/v11-demo-capture.json). It uses `PrintWindow` capture of the emulator client area and FFmpeg encoding, not a screenshot slideshow or desktop recording. It demonstrates app and emulator behavior, not physical NearLink exchange.

Final native configuration testing exercised the ordinary Huge font option at **measured `fontSizeScale=1.45`** across all four tabs, Settings and return navigation: [Home](artifacts/screenshots/v11-release-huge-home.png), [Map](artifacts/screenshots/v11-release-huge-map.png), [Relay](artifacts/screenshots/v11-release-huge-relay.png), [Guide](artifacts/screenshots/v11-release-huge-guide.png), [Settings](artifacts/screenshots/v11-release-huge-settings.png), [return to Map](artifacts/screenshots/v11-release-huge-back-map.json). [Configuration logs](artifacts/logs/v11-font-configuration-final.log) establish 1.45 and Normal at 1.0. The source permits scaling up to 2.0, but 1.75/2.0 rendering was not tested. [System automatic dark](artifacts/screenshots/v11-system-auto-dark-settings.json) and [an app Light override under system Dark](artifacts/screenshots/v11-system-light-override.png) were also inspected. The device was restored to Normal text/Light system appearance, with the app in System/Polish on [Home](artifacts/screenshots/v11-release-restored-home.json). Senior mode was not enabled because it also changes icons and the home screen.

Evidence lives in [artifacts/logs](artifacts/logs/), [artifacts/screenshots](artifacts/screenshots/) and [artifacts/research](artifacts/research/). Build/run results and screenshots apply to recorded checkpoints; they should be rerun after subsequent changes. Host persistence tests do not, by themselves, prove every native lifecycle or storage scenario.

## Unsuccessful approaches and corrections

- **Assuming the emulator could validate NearLink radio:** official documentation ruled this out. The app now separates an in-process three-peer simulation from hardware capability checks and does not fabricate radio traffic.
- **Copying the newest web API into API 24:** current documentation includes API 26 `@ohos.nearlink.*` interfaces. The implementation instead follows installed `@kit.NearLinkKit` declarations and their actual callback signatures.
- **Unfiltered API 24 discovery:** empty filters are invalid and service UUID filtering is absent. The adapter requires an exact peer name; no unassigned manufacturer ID is inserted as a workaround.
- **Incorrect initial `BusinessError` import:** an isolated ArkTS check caught the error. The import was corrected to `@kit.BasicServicesKit` using SDK evidence.
- **Callback typing during integration:** method declarations did not contextualize callback object literals in the integrated ArkTS check. Function-valued interface properties resolved the issue without introducing `any`.
- **Initial map query failures:** an Overpass POST returned a gateway timeout and a mirror timed out. A smaller bounded GET query succeeded; the refresh script records the actual source request and does not bulk-download raster tiles.
- **Preferences capacity during final review:** an alert-cache snapshot can exceed the platform's per-string limit. The storage specialist added bounded chunking and generation commits; final storage tests and native checks are recorded with the validation artifacts rather than inferred from the earlier single-alert demo.
- **Strict ArkTS rethrow typing:** final static checks rejected two untyped caught values being rethrown. Explicit `Error` objects resolved the issue; the checker then passed all 13 source files and all 40 host tests passed again.
- **Builder state refresh:** native screenshots exposed relay circles retaining their initial colour after the successful drill. Reading observed state inside the builder fixed the circles; dynamic button labels were also changed to read current state. A fresh native build and screenshot verified the active A/B/C result.
- **Initial audit gaps:** native components and passing drill checks did not establish full UX readiness. The follow-up replaced undersized controls and weak semantics, moved alert information first, added theme/language resources and adaptive layout, and corrected saved-point state after write failures. Recorded native checks now cover final navigation and selected configuration/persistence paths; ScreenReader and landscape remain separate validation gates.
- **Newest-message-only synchronization:** the original connection callback only sent the currently selected alert. The delivery follow-up synchronizes the verified bounded cache, correlates receipts and retries a bounded number of times. Host packet-loss tests validate policy; they do not prove radio delivery.
- **Video capture availability:** DevEco CLI exposed screenshots but no video command, and the emulator lacked `screenrecord`. The implemented Windows helper records only the emulator window with installed Studio FFmpeg; there is no fallback to the private desktop.

## Known limitations

The initial read-only design review and subsequent implementation status are recorded in [READINESS_AUDIT.md](artifacts/READINESS_AUDIT.md). Small targets, missing semantics, forced light appearance, missing product localization, misleading save state and newest-message-only synchronization received source changes. The audit separates source changes, host evidence, completed native checks and outstanding validation. Initial implementation, tests and documentation were committed as a local baseline after development, rather than reconstructed as fictitious chronological history. Git author/committer identity follows `AGENTS.md`; AI assistance remains disclosed here.

- Only an API 24 emulator was available. No physical NearLink packet delivery, range, battery profile, congestion behavior or cross-device discovery has been demonstrated.
- The app minimum is API 20; the native NearLink capability query needs API 23 or later and compatible hardware. The app handles unavailable capability dynamically.
- The relay is an active-session prototype. Background/locked-screen continuity is not implemented or claimed. Per-link receiving-application ACKs do not establish authenticated end-to-end delivery or human receipt.
- Exercise keys do not authorize real warnings. There is no official RCB integration, live authority key registry, revocation service or audited issuance system.
- The device clock influences expiry. Unsigned hop counts constrain cooperative forwarding but are not cryptographic path proofs. Signatures cannot prevent radio jamming or deliberate dropping.
- The bundled map includes only 40 selected central Kraków points. Access categories come from published PSP data; physical condition and current entrance availability are unverified. Optional foreground location is a single fix with accuracy/coverage gates, not continuous tracking, proven physical accuracy or evacuation routing. No in-app regional pack download/update exists.
- Fixture validity is 72 hours; regenerate with `node scripts/generate-demo-alerts.mjs`, rebuild and restart the demo when presenting later.
- The unsigned HAP used successfully on the emulator still requires appropriate signing/provisioning for a physical phone.
- ScreenReader interaction, landscape and physical GPS remain untested. Large text was measured at 1.45; the source cap of 2.0 is not a validation result.
- Final native-symbol navigation verification, the live emulator video and same-host clean-checkout build are complete. Validation on another computer and public source publication remain outstanding; the user has authorized local commits only.
- AI-generated code and AI review may miss defects. This prototype requires further independent review and physical/operational validation before real emergency use.

## Lessons learned

- Inspect the exact installed SDK before choosing imports, callbacks or permissions; a newer documentation page can describe a different API generation.
- A credible hackathon demo can show real cryptographic behavior while clearly identifying simulated transport.
- Preserve the distinction between authenticated message content, transport success and verified real-world conditions.
- Bound untrusted inputs, verify before forwarding, and retain previously authenticated state when rejecting malicious input.
- Public map provenance and source availability categories are part of product correctness, not optional presentation details.
- Save reproducible tests and runtime artifacts alongside code so reviewers can distinguish measured behavior from intended behavior.

## Submission-form guide (2026-10-03)

Codex reviewed the existing project documentation, validation evidence and main source components to prepare `artifacts/submission/SafeMesh-jak-wypelnic-Hacktribe.pdf` and a companion UTF-8 text file. The guide contains Polish field instructions and English copy for the Hacktribe form. The participant stated that nothing existed before the event; the guide uses that account for the new-project chronology and asks the team to verify it before submission. Team size and unpublished links are not invented.

Local Python Playwright with Microsoft Edge reached the supplied `/add/` URL and was redirected to sign-in. No authenticated form inspection or submission occurred; field names come from the participant's pasted form. Web research checked the current DEFENCE category description and an ITU historical telecommunications-outage statistic. ReportLab generated the PDF; PyMuPDF checked seven-page output, text extraction and rendered previews. Existing test results are attributed to recorded evidence, not claimed as newly executed. No repository push, video upload or project publication was performed.

## AI feature disclosure

**Not applicable.** AI assisted development only. SafeMesh performs no model inference, sends no user data to an AI service and has no AI-generated runtime warning or navigation flow.
