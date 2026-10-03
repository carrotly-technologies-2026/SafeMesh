# SafeMesh 1.4 native authority and inbox validation

Recorded on 3–4 October 2026 using three separate HarmonyOS API 24 emulator apps on one Windows host. This validates the local exercise-authority workflow and the app's store-and-forward behavior over the labelled WebSocket emulator transport. It does not validate physical NearLink radio or a production warning authority.

The [captured-evidence assertions](../logs/authority-v14-assertions.json) pass **17/17** checks. Reproduce that review without operating a device using `node scripts/validate-authority-evidence.mjs`. The checker verifies the two signatures against the app's actual public pin and checks saved UI trees, filtered native logs and hub counters. Replaying evidence is separate from repeating the live scenario.

## Build and artifact identity

The [completed combined check run](../logs/authority-v14-final-checks-build.log) passed **167 host tests**, **21 ArkTS files with zero errors**, **zero Code Linter issues**, and **BUILD SUCCESSFUL**. All three [deployments](../logs/authority-v14-final-deploy.log) reported **Smoke: PASS**, with individual records for [A](../logs/authority-v14-smoke-A.log), [B](../logs/authority-v14-smoke-B.log) and [C](../logs/authority-v14-smoke-C.log). The **36 ArkTS permission/exception/deprecation advisories** and the unsigned-package warning remain separate from the zero error/linter counts.

The HAP used for the recorded native scenario has SHA-256:

```text
dd7ca2cd80ee741ca5f1570d2dbe1135084b6cca0ef838f473cfd1c22cd16e5e
```

The app's public exercise-key SHA-256 is `28a007edbe7e9cf5cf0805c38d4ebdfffff05dc1fc5522b31d7e4caf69208d55`. Public keys are verification material, not issuer credentials. This report contains no operator token or private key.

The public [credential-scan record](../logs/authority-v14-secret-scan.json) identifies that HAP. Release files are the [v1.4 HAP](../../dist/SafeMesh-1.4.0.hap), [source ZIP](../../dist/SafeMesh-1.4.0-source.zip), [SHA-256 manifest](../../dist/SafeMesh-1.4.0.sha256.txt) and [exact-package scan report](../../dist/SafeMesh-1.4.0-package-scan.json). The exact-package report is kept outside the source ZIP to avoid a self-referential archive checksum; consult its `passed` field and per-artifact hashes for the completed packaging check. The source commit at the start of this review was `5804dc3`; the release ZIP includes subsequent validation records and launcher corrections.

## Observed native scenario

| Check | Recorded result | Evidence |
| --- | --- | --- |
| Custom publication on A | Two distinct v2 exercise alerts were typed in the native console, authenticated, signed by the separate local issuer service and verified in the app. Both retain the exact custom text. | [Signed envelopes](../logs/authority-v14-issued-alerts.json), [A published two](../screenshots/authority-v14-a-two-published.png) |
| A → B arrival | B received both alerts at hop 1 while on Map. Arrival banners appeared; its inbox went from zero to one, then two unread messages. No recipient Send action was used. | [B UI assertions](../logs/authority-v14-b-ui-assertions.json), [first banner](../screenshots/authority-v14-b-first-banner.png), [two unread](../screenshots/authority-v14-b-two-unread.png) |
| Lost ACK | The hub deliberately dropped the first B → A ACK. A retried; B recognized a verified duplicate and ACKed again. The first delivery had two data attempts, one dropped ACK and one forwarded ACK. | [First route counters](../logs/authority-v14-hub-first.json), [B native verdicts](../logs/authority-v14-b-native-before-restart.log) |
| Read state | Opening each B detail changed unread 2 → 1 → 0 while preserving both inbox entries and the full signed text. | [B UI assertions](../logs/authority-v14-b-ui-assertions.json), [first detail](../screenshots/authority-v14-b-first-detail-pl.png), [second detail](../screenshots/authority-v14-b-second-detail-pl.png) |
| Issuer unavailable | A's app and the host issuer service were stopped. C remained empty while isolated after both alerts had already been issued. | [Issuer offline](../logs/authority-v14-issuer-offline.json), [C isolated](../screenshots/authority-v14-c-isolated-two-issued.png) |
| B process restart | `devecocli run --skip-build` relaunched B with the same HAP and no uninstall. PID changed **23026 → 25827**. B restored both messages and their read state while the issuer was offline. | [Restart record](../logs/authority-v14-b-restart.json), [restored inbox](../screenshots/authority-v14-b-restored.png) |
| B → C after restart | With only B–C linked and A absent, B forwarded its saved messages automatically. C received two unread messages, each at hop 2, and verified the original signed text. A → C routing stayed zero. | [B–C topology](../logs/authority-v14-hub-bc-topology.json), [delivery counters](../logs/authority-v14-hub-delivered.json), [C inbox](../screenshots/authority-v14-c-two-unread.png), [first detail](../screenshots/authority-v14-c-first-detail.png), [second detail](../screenshots/authority-v14-c-second-detail.png) |
| Duplicate after reading | Injecting a genuine duplicate produced one additional ACK, no extra inbox row, no new unread state and no arrival banner. | [Before](../logs/authority-v14-hub-before-duplicate.json), [after](../logs/authority-v14-hub-after-duplicate.json), [unchanged inbox](../logs/authority-v14-c-after-duplicate.json) |
| Tampered packet | An explicitly injected packet with changed signed content was rejected. It received no ACK or onward forwarding and did not replace the verified text or mark the inbox unread. | [Native verdicts](../logs/authority-v14-c-native.log), [before counters](../logs/authority-v14-hub-before-tampered.json), [after counters](../logs/authority-v14-hub-after-tampered.json), [preserved detail](../screenshots/authority-v14-c-verified-after-tampered.png) |

The test hub's fault-injection controls are explicit local test tools. The hub neither signs alerts nor generates recipient ACKs and does not store messages for disconnected peers. The retained copy in the restarted B app supplied the late C delivery.

## Language, appearance and large text

The native recipient UI was inspected in Polish/light and English/dark. Custom alerts had a signed Polish original with no English alternate: changing the UI to English retained that original and displayed the language notice. It did not invent an unsigned English translation. See [English inbox](../screenshots/authority-v14-b-inbox-dark-en.png), [English detail](../screenshots/authority-v14-b-detail-dark-en.png) and [UI assertions](../logs/authority-v14-b-ui-assertions.json).

The emulator's normal **Huge** text preset reported an actual `fontSizeScale=1.45`, recorded in the [configuration log](../logs/authority-v14-b-fontscale.log). The inbox and scrollable detail were inspected at that scale: [Home](../screenshots/authority-v14-b-huge-home.png), [detail top](../screenshots/authority-v14-b-huge-detail-top.png), [detail bottom](../screenshots/authority-v14-b-huge-detail-bottom.png). This is evidence for **1.45×**, not a 2× native test or a complete accessibility certification. Screen-reader behavior and landscape remain outside this checkpoint.

## Issuer authentication and deployment boundaries

The host backend tests cover missing/wrong credentials, strict request bounds, signature verification, tampering, distinct identities, persisted idempotency across restart, concurrent retries, failed journal writes and traffic budgets. Only the host service holds the exercise private key. The HAP pins the public key; session authorization requires a separately provisioned bearer token. Emulator role A alone grants no signing authority.

Source candidates and decompressed HAP entries, including compiled ArkTS, were scanned for the active authority token/private key, common encodings and private-key PEM blocks. No match was found in the [recorded scan](../logs/authority-v14-secret-scan.json). This is a bounded credential check, not proof that every possible encoded secret is absent. The separate [package scan](../../dist/SafeMesh-1.4.0-package-scan.json) records the exact final source ZIP and HAP, including decompressed nested entries.

The Windows authority launcher was reviewed for explicit pin adoption, forced rebuild on pin changes, safe build reuse, hidden background processes, authenticated service identity checks and a reverse-port grant limited to the uniquely named emulator A. Parser/static checks passed, including [11/11 device-mapping cases](../logs/authority-v14-launcher-mapping.json). The first live run correctly fell back from `-SkipBuild` to a full build when no matching build receipt existed. After correcting Windows PowerShell device-array handling and surfacing delegated mesh output, the [final reuse run](../logs/authority-v14-launcher-final.log) exited **0** with `AUTHORITY_DEMO_READY=1`: exactly three target devices were inspected, A–B/B–C topology was visible, the verified existing issuer was reused, and the matching build receipt allowed `-SkipBuild` without fallback. The HAP hash remained unchanged. Exact release archive checks are recorded separately in the package-scan report.

## Limits

- All messages in this run are signed **exercises**. There is no RCB integration, official government account validation, production key custody/revocation or operational emergency-service claim.
- Three real emulator processes communicated through a local transport mock. Physical NearLink discovery, radio range, interoperability and battery performance require physical devices.
- Delivery runs while apps remain in the foreground. A fresh process requires reconnecting; no suspended/background delivery guarantee is made.
- Previous-hop labels and hop counters are local receipt metadata, not an authenticated route. ACK means receipt by the receiving app, not reading by a person or a guarantee of onward delivery.
- The map is a reference pack; current protective-point availability, structural condition and safe routes were not validated by this communication test.
- This is a same-host development and native-emulator checkpoint, not a fresh-machine installation test. Historical v1.3 videos remain v1.3 evidence; no v1.4 video is claimed here.
