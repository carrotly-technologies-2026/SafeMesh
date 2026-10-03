# AI Workflow

SafeMesh was developed with substantial AI assistance on 2026-10-03 and 2026-10-04. This disclosure describes the work actually performed and the evidence used to evaluate it. The original civilian emergency-information concept and request came from the human participant; the coding agent carried out research, design, implementation and automated validation. Human acceptance of the final submission is not implied by automated checks.

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
| Claude Code (Anthropic) | Claude Opus 5.5 (`claude-opus-5-5`), Claude Code CLI on Windows, 2026-10-04 | Review of the project against the Huawei challenge rules and judging criteria, then the v1.4.1 completion pass: language default, NearLink diagnostics fixes and a regression test, check/build/deploy, the three-emulator recorder and scripted demo video, and documentation, licence and release preparation. |
| Claude Code delegated agent | Same model, read-only research plus one new file | Wrote the first draft of `docs/PHYSICAL_TESTING.md` from the source, resources, research notes and local HarmonyOS docs (`devecocli docs search/read`). It found the pre-1.4.1 NearLink diagnostics gaps listed below. The main agent fixed those gaps and edited the runbook. |
| Pillow, Studio FFmpeg | Pillow 12.3 on the host; FFmpeg from the Studio JAR | Render the demo's title card, device labels, captions and end card, and compose them over the unedited capture. The bundled FFmpeg has no `drawtext`, so text is rendered as images. |

No external product MCP server is required by SafeMesh, and no external MCP integration is recorded in this implementation's evidence. Session orchestration provided web, shell/file and agent-collaboration tools. The app does not call Codex, a chatbot or an AI service at runtime.

## Important prompts and instructions

The participant's public-safe request, condensed for readability:

> Build a HarmonyOS hackathon app for situations where mobile networks fail. Research Huawei NearLink and try to relay warnings from phone to phone. Authenticate warnings so attackers cannot falsify accepted messages. Make maps and protective-point information available offline. Use the available HarmonyOS emulator and choose an appropriate native language such as ArkTS.

The implementation instructions given to specialist agents were:

- **NearLink:** use official Huawei/OpenHarmony sources and installed SDK declarations; identify public APIs, permissions and emulator limitations; implement a typed native transport without invented APIs or fabricated peers.
- **Security:** use platform-supported cryptography, a pinned exercise trust root, canonical signed content, strict parsing, expiry/replay controls and mutation-safe persistence; never package an issuer private key or impersonate RCB.
- **Maps:** obtain real, attributed reference data; preserve official availability categories; provide a bounded offline pack and map UI without claiming routes, live access or guaranteed shelter protection.
- **Integration:** build a native ArkTS/ArkUI application, keep simulation labels explicit, test on the running emulator, and record concrete build/runtime evidence.

After asking whether the prototype fully followed HarmonyOS guidance, the participant requested local commits and continued implementation of the remaining audit findings. Follow-up assignments covered accessible controls and native announcements, Polish/English resources, saved appearance/language choices in a dedicated Settings screen, adaptive text, honest saved-point persistence, optional foreground location, full-cache relay synchronization with bounded receipts/retries, and a real emulator-only video recorder. The final navigation has four bottom destinations with native `SymbolGlyph` icons and a native gear at the top right opening Settings; both in-app and system return navigation were exercised. The team required Git author and committer identity to stay with the team's configured GitHub account, with no AI co-author trailers; that repository identity rule does not remove the challenge's requirement for truthful disclosure in this file.

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
| 2026-10-03/04 | v1.2–v1.4: mesh lab, localized signed alerts, authority console and inbox | Local WebSocket hub and `EmulatorTransport` for three separate emulator apps; signed PL/EN alert variants; authenticated loopback exercise issuer, recipient inbox, unread state and automatic relay. Recorded in commits `30ab0ce` to `ad45ebf`. The tools listed above were used. The repository does not record which agent and model ran each of these sessions; the team should confirm this row. | 96, then 130, then 167 host tests per checkpoint. Native evidence: [v1.2 lab report](artifacts/research/mesh-lab.md), [v1.3 report](artifacts/research/ui-v13-validation.md) and [v1.4 report](artifacts/research/authority-v14-validation.md), with 17/17 assertions over captured v1.4 evidence. |
| 2026-10-04 | Challenge review (Claude Code) | Read-only analysis of the code, evidence, public repository and the Huawei challenge rules, details and workshop slides. It found: no v1.4 video, and the old video did not show the relay; no HAP reachable from the repository; Polish-only first launch; challenge area not stated; stale `SUBMISSION.md` and form guide; no licence. | Host tests rerun read-only: 167/167. Findings were checked against the rules PDFs (byte-identical to the organizer URLs) and the public GitHub API. |
| 2026-10-04 | v1.4.1 completion (Claude Code) | First launch follows the system language. `RelayViewModel.loadDrill()` shares with connected peers, with a new regression test. NearLink delivery counters and verdict in diagnostics. `SAFEMESH_TRANSPORT_*` hilog lines. `scripts/record-mesh-demo.py`. Documentation and Apache-2.0 `LICENSE`. | `check.ps1 -Build`: 168/168 host tests, ArkTS 21 files / 0 errors, Code Linter 0 issues, build successful ([log](artifacts/logs/v141-checks-build.log)). The same HAP was installed on three API 24 emulators with cleared data. First launch showed English on the `en-Latn-US` system. The scripted scenario passed: publish on A, hop 1 on B, C isolated, hop 2 on C after A left, forged copy shown as rejected on C with no ACK in the hub counters, map search and the NearLink check. |
| 2026-10-04 | Demo video (Claude Code) | A Python driver used `uitest uiInput` and `uitest dumpLayout` to operate the three apps while `record-mesh-demo.py` captured them in one loop. A composition script added the title card, labels, captions, a marked 3× segment and the end card. | Single take, 142.5 s live at 12 fps, zero late frames ([capture](artifacts/logs/v141-demo-capture.json)). The [action log](artifacts/logs/v141-demo-actions.log) masks the activation code, and a token scan of the new logs found no match. Frames were reviewed at key moments before publishing. |
| 2026-10-04 | v1.5.0: OpenHarmony / Oniro merge and System language (Claude Code) | Merged the team member's `testing` branch, which contained an Oniro / OpenHarmony port with Linux scripts. The port is kept as a second build product instead of replacing the HarmonyOS build. `oniro` product and target, `sourceRoots` with the HarmonyOS adapter in `src/harmonyos` and the stub in `src/oniro`, shared link types in `RelayTransport.ets`, Oniro-only manifest changes in the root `hvigorfile.ts`, and `scripts/oniro/sign.sh` replacing `oniro-app sign`, which would have signed every product. The HarmonyOS issuer pin and fixtures were kept, because the branch pinned a key from another machine. Added a per-product ArkTS check in `check.ps1`, `tests/build-variants.test.mjs`, and a System / Polski / English language setting. The tools the team member used for the Oniro port are not recorded here. | 172/172 host tests; ArkTS 0 errors for both source sets; Code Linter 0; the HarmonyOS HAP still declares `phone` and `ACCESS_NEARLINK` and contains the NearLink Kit adapter. The `oniro` product built, packaged and signed with the OpenHarmony SDK (the API 24 OpenHarmony part of the DevEco SDK, on Windows). Its HAP declares `default`, has no `ACCESS_NEARLINK` and contains the stub. Native: [language flow 5/5](artifacts/logs/v150-language-preference.json) and [relay smoke](artifacts/logs/v150-relay-smoke.json). The API 23 Oniro emulator run after the merge is still to be repeated. |

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

**Current checkpoint, v1.4.1:** 168/168 host tests, ArkTS 21 files / 0 errors, Code Linter 0 issues, build successful, three-emulator demo run on the same HAP (SHA-256 `a2cf126786d6a1dce58fe96020fc31c63b776dd7a4593eb2e95d8c9e361ffd3e`). See the [checks log](artifacts/logs/v141-checks-build.log) and the README section *v1.4.1*. The v1.4.0 native scenario and its 17/17 evidence assertions are in the [v1.4 report](artifacts/research/authority-v14-validation.md).

The paragraphs below describe the **historical v1.1 checkpoint**. Its source commit `1bd015dc…` was a pre-publication local commit and is **not** in the published GitHub history; the published history starts at `61dcf03`. The v1.1 logs it refers to remain in `artifacts/logs/`.

The v1.1 verified application source was **`1bd015dc9ca3cea9c230b78b0253abfc61a8bcae`**. All **61 host tests across seven suites passed**, with zero failures; see [v1.1 checks](artifacts/logs/v11-checks.log). Final native-symbol navigation verification reported **no ArkTS errors in 17 files**, with separate permission/exception advisories, **zero lint issues**, successful HAP build and emulator install/launch **Smoke: PASS**. Evidence: [ArkTS](artifacts/logs/v11-release-arkts.log), [lint](artifacts/logs/v11-release-lint.log), [build](artifacts/logs/v11-release-build.log), [run](artifacts/logs/v11-release-run.log). Earlier 40-test, 58-test and Settings-build results remain historical checkpoints.

A fresh local clone checked out that exact source and independently reran `scripts/check.ps1 -Build`: **61 host PASS, ArkTS 17/0, lint 0, build PASS**. See [clean-checkout log](artifacts/logs/v11-clean-checkout.log) and [summary](artifacts/logs/v11-clean-checkout-summary.txt). This used the same computer and existing SDK/CLI/cache, not a clean second machine. The tooling changed only lockfile line endings; normalized content matched the commit. No byte-identical-build claim is made. The release HAP SHA-256 is `42406469e63c55df70ba3d9472b48df4b7c3a9a4722f560128fb9e9f2d5cc005`.

```powershell
$env:DEVECO_CLI_STUDIO_PATH = Join-Path $env:USERPROFILE 'DevEcoStudio'
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
- **Demo automation on 2026-10-04:** `devecocli ui click --id` took about 2.5 s per tap because it dumps the layout each time. The driver switched to `uitest dumpLayout` plus `uitest uiInput click`, about 1.3 s per tap. The first takes failed because the open soft keyboard hid lower fields, so the driver now taps `KeyHideKbd`. They also failed because the console and detail screens have no bottom tab bar, so the driver now goes back first. Only the final, complete take was used.
- **Background relaying (rejected on 2026-10-04):** the local HarmonyOS documentation shows that the NearLink continuous-task mode (`MODE_NEARLINK`) exists only from API 26. The modes available on API 20–24 (`dataTransfer`, `bluetoothInteraction`) are checked for consistency by the system. A mismatched task would be suspended and would look added for show, so no background mode or notification was added.

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
- The source is public on GitHub, and v1.4.1 with its HAP and demo video is published as a GitHub Release. Validation on another computer has not been done; all builds used this Windows host.
- AI-generated code and AI review may miss defects. This prototype requires further independent review and physical/operational validation before real emergency use.

## Lessons learned

- Inspect the exact installed SDK before choosing imports, callbacks or permissions; a newer documentation page can describe a different API generation.
- A credible hackathon demo can show real cryptographic behavior while clearly identifying simulated transport.
- Preserve the distinction between authenticated message content, transport success and verified real-world conditions.
- Bound untrusted inputs, verify before forwarding, and retain previously authenticated state when rejecting malicious input.
- Public map provenance and source availability categories are part of product correctness, not optional presentation details.
- Save reproducible tests and runtime artifacts alongside code so reviewers can distinguish measured behavior from intended behavior.

## Submission-form guide (2026-10-03, superseded)

On 2026-10-04 the team entered the project in the **Huawei** challenge. The Polish form guide described below suggested the DEFENCE category and v1.1 numbers. It was therefore removed from the repository; it remains in Git history at `5804dc3`. The current paste-ready text is [SUBMISSION.md](SUBMISSION.md).


Codex reviewed the existing project documentation, validation evidence and main source components to prepare `artifacts/submission/SafeMesh-jak-wypelnic-Hacktribe.pdf` and a companion UTF-8 text file. The guide contains Polish field instructions and English copy for the Hacktribe form. The participant stated that nothing existed before the event; the guide uses that account for the new-project chronology and asks the team to verify it before submission. Team size and unpublished links are not invented.

Local Python Playwright with Microsoft Edge reached the supplied `/add/` URL and was redirected to sign-in. No authenticated form inspection or submission occurred; field names come from the participant's pasted form. Web research checked the current DEFENCE category description and an ITU historical telecommunications-outage statistic. ReportLab generated the PDF; PyMuPDF checked seven-page output, text extraction and rendered previews. Existing test results are attributed to recorded evidence, not claimed as newly executed. No repository push, video upload or project publication was performed.

## AI feature disclosure

**Not applicable.** AI assisted development only. SafeMesh performs no model inference, sends no user data to an AI service and has no AI-generated runtime warning or navigation flow.
