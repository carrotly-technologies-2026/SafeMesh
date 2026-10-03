# AI Workflow

SafeMesh was developed with substantial AI assistance on 2026-10-03. This disclosure describes the work actually performed and the evidence used to evaluate it. The original civilian emergency-information concept and request came from the human participant; the coding agent carried out research, design, implementation and automated validation. Human acceptance of the final submission is not implied by automated checks.

## Tools used

| Model, agent, tool or skill | Version or source | Role |
| --- | --- | --- |
| OpenAI Codex | GPT-6 agent family identified by the session; exact model snapshot was not recorded | Main coding agent: scope, architecture, integration, ArkUI implementation, build and emulator validation. |
| Codex delegated agents | Same shared workspace; NearLink, security and offline-map specialists | Parallel primary-source research, transport/protocol/map implementation and focused review/tests. |
| Web search and page retrieval tools | Session-provided browser tools | Official Huawei/OpenHarmony API research, PSP/Polish government data and OSM licensing evidence. |
| PowerShell, filesystem reads and patch tools | Windows development host | Inspect exact SDK declarations, apply source changes and invoke reproducible build/test commands. |
| DevEco CLI | 1.3.4, installed on the development machine | Scaffold, local documentation search, ArkTS checks, lint, build, device discovery, install/launch, UI inspection, screenshots and logs. |
| DevEco Studio / HarmonyOS SDK | Studio 6.1.1 installation, SDK API 24; API 24 phone emulator | Native compiler, runtime, CryptoArchitectureKit and ArkUI validation. |
| Node.js | 24.x | Host tests, cryptographic fixture generation and SDK-compiler test harnesses. |
| Python | Installed host Python | Source-data acquisition, map transformation and reproducible refresh. |
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

The challenge's setup repository was consulted for compatible SDK guidance and the requirement to disclose AI use in this file. SafeMesh started from an Empty Ability scaffold, not a claim that the full challenge template was used. Repository research notes and the implementation contract record the specific technical decisions.

## AI-assisted work log

| Date | Workstream | AI-generated or changed work | Review and validation actually performed |
| --- | --- | --- | --- |
| 2026-10-03 | Product and architecture | Native Home, Map, Relay and Guide flows; separate model/ViewModel/view responsibilities; distinction between emulator simulation and hardware transport. | Main agent inspected the implementation contract, SDK constraints and integrated app behavior. Human supplied the product goal; final human sign-off is not recorded here. |
| 2026-10-03 | NearLink | Public API adapter, permission/capability handling, filtered discovery, bounded message framing and research note. | Exact installed `.d.ts` and permission metadata; official documentation; seven host tests against actual source. Physical radio exchange not tested. |
| 2026-10-03 | Signed alerts | Canonical ECDSA payload, trusted public exercise key, bounded relay/replay policy, fixture generator and protocol tests. | Host cryptographic tests plus native emulator verification, tampering, duplicate and expiry checks. |
| 2026-10-03 | Offline map | PSP/OSM acquisition script, generated map pack, ArkTS model, Canvas rendering and map tests. | Source-record comparison, licensing/provenance review, geometry/selection tests and emulator UI inspection. No field inspection of protective points. |
| 2026-10-03 | App integration | ArkUI screens, preferences storage, relay/alert ViewModels and error handling. | Integrated ArkTS check, lint, successful HAP build, install/launch smoke check, accessibility trees/screenshots and focused integration tests. |
| 2026-10-03 | Reproducibility | README, this disclosure, test scripts and research artifacts. | Commands and paths checked against the workspace; limitations kept explicit rather than treating emulator results as radio evidence. |

## Workflow

### Ideation and architecture

The user proposed phone-to-phone emergency warnings and offline protective-point discovery. AI translated that into a demonstrable scope: a signed-alert engine independent of transport, a real NearLink adapter for future physical tests, a transparent emulator relay simulation and a bundled local map.

Research changed the design. NearLink exposes peer data APIs but no automatic application-level mesh router. The installed API 24 requires a scan filter and cannot scan by service UUID; the controlled hardware flow therefore uses a peer's device name. The emulator has no NearLink radio. These facts shaped the interface and prevented a false radio-demo claim.

The map is shipped as a small reference pack inside the HAP so first launch can work offline. The app does not invent protective-point locations or treat proximity as a safe route.

### Implementation and review

The main agent owned scaffold, UI and integration. Three delegated agents worked on NearLink, cryptographic protocol and map/data tasks, with explicit file ownership to reduce conflicting edits. Agents shared API contracts and source evidence; the main agent integrated callbacks and ViewModel flows.

Generated code was reviewed against installed SDK types and local ArkTS/ArkUI guidance. The mobile app uses only the exercise public key. The host generator signs bounded, expiring drill fixtures with a temporary private key that is not saved. Prototype trust constraints are documented in [security.md](artifacts/research/security.md).

AI review is not independent security certification. No human field verification, external penetration test or authority approval is claimed.

### Testing and debugging

The project includes reproducible host checks. The final combined run of the five suites below passed **40 tests, with zero failures**, including seven storage checks after the storage-hardening iteration. See `artifacts/logs/host-tests-final.log`.

```powershell
$env:DEVECO_CLI_STUDIO_PATH = 'C:\Users\user\DevEcoStudio'
node --test tests/protocol.test.mjs tests/nearlink.test.mjs tests/map.test.mjs tests/integration.test.mjs tests/storage.test.mjs
devecocli.cmd check arkts --project .
devecocli.cmd check lint --format json .
devecocli.cmd build
devecocli.cmd run --skip-build --module entry --device 127.0.0.1:5555
```

Tests execute actual application source after transpilation/type erasure. They do not duplicate the relay algorithm in a separate test-only implementation. Host kit adapters deliberately mock radio, preferences or Canvas as needed; Node/OpenSSL backs host cryptographic operations. The app also exercised native cryptography on the emulator.

Observed native checkpoints: full build success, install/launch **Smoke: PASS**, integrated ArkTS check without errors, lint with zero errors/warnings, and the relay UI's **6 / 6** checks. The six native checks cover acceptance at A, B and C, duplicate suppression, tampered-text rejection and expired-alert rejection. The UI separately reports NearLink unavailable and zero connected physical peers.

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

## Known limitations

An additional read-only design and requirements review is recorded in [READINESS_AUDIT.md](artifacts/READINESS_AUDIT.md). It identified small touch targets, accessibility/theme/localization gaps, a save-state error case and incomplete multi-message synchronization. Findings were recorded for follow-up; they were not silently treated as fixed. The user subsequently requested local Git commits; the initial implementation, tests and documentation were committed as a baseline after development, rather than reconstructed as a fictitious chronological development history.

- Only an API 24 emulator was available. No physical NearLink packet delivery, range, battery profile, congestion behavior or cross-device discovery has been demonstrated.
- The app minimum is API 20; the native NearLink capability query needs API 23 or later and compatible hardware. The app handles unavailable capability dynamically.
- The relay is an active-session prototype. Background/locked-screen continuity and end-to-end delivery acknowledgements are not implemented or claimed.
- Exercise keys do not authorize real warnings. There is no official RCB integration, live authority key registry, revocation service or audited issuance system.
- The device clock influences expiry. Unsigned hop counts constrain cooperative forwarding but are not cryptographic path proofs. Signatures cannot prevent radio jamming or deliberate dropping.
- The bundled map includes only 40 selected central Kraków points. Access categories come from published PSP data; physical condition and current entrance availability are unverified. The app does not provide evacuation routing or live GPS.
- Fixture validity is 72 hours; regenerate with `node scripts/generate-demo-alerts.mjs`, rebuild and restart the demo when presenting later.
- The unsigned HAP used successfully on the emulator still requires appropriate signing/provisioning for a physical phone.
- AI-generated code and AI review may miss defects. This prototype requires further independent review and physical/operational validation before real emergency use.

## Lessons learned

- Inspect the exact installed SDK before choosing imports, callbacks or permissions; a newer documentation page can describe a different API generation.
- A credible hackathon demo can show real cryptographic behavior while clearly identifying simulated transport.
- Preserve the distinction between authenticated message content, transport success and verified real-world conditions.
- Bound untrusted inputs, verify before forwarding, and retain previously authenticated state when rejecting malicious input.
- Public map provenance and source availability categories are part of product correctness, not optional presentation details.
- Save reproducible tests and runtime artifacts alongside code so reviewers can distinguish measured behavior from intended behavior.

## AI feature disclosure

**Not applicable.** AI assisted development only. SafeMesh performs no model inference, sends no user data to an AI service and has no AI-generated runtime warning or navigation flow.
