# SafeMesh signed alert protocol

Evidence checked on 2026-10-03 against the installed HarmonyOS API 24 SDK. The app uses native ArkTS `cryptoFramework` signature verification. The sample issuer is an explicitly named **exercise authority**, not RCB, PSP, Huawei, a city authority, or any official alerting service.

## Verified platform API

```typescript
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';
const publicKeyBlob: cryptoFramework.DataBlob = { data: base64.decodeSync(publicKeyDer) };
const pair = await cryptoFramework.createAsyKeyGenerator('ECC256').convertKey(publicKeyBlob, null);
const verifier = cryptoFramework.createVerify('ECC256|SHA256');
await verifier.init(pair.pubKey);
const valid = await verifier.verify({ data: utf8Payload }, { data: signatureDer });
```

- Installed declarations: `C:/Users/user/DevEcoStudio/sdk/default/openharmony/ets/api/@ohos.security.cryptoFramework.d.ts`: `convertKey` line 1715, `createAsyKeyGenerator` line 2075, `Verify.verify` line 5269, `createVerify` line 5553. The APIs are public and require no elevated application privilege or dangerous permission. Asynchronous creation/verification dates to API 9; nullable key import dates to API 10. Kit declaration: `.../ets/kits/@kit.CryptoArchitectureKit.d.ts`.
- [Huawei's on-device verification example](https://developer.huawei.com/consumer/en/doc/harmonyos-guides-V14/devicesecurity-taas-verifysignature-V14) uses `ECC256|SHA256` with imported public keys.
- [OpenHarmony algorithm specifications](https://github.com/openharmony/docs/blob/master/en/application-dev/security/CryptoArchitectureKit/crypto-sign-sig-verify-overview.md) document ECDSA/ECC256 with SHA-256. ECDSA P-256 was selected because the exact deployed path has clear documentation. ED25519 key parameter types in the SDK alone do not establish a supported `createVerify` algorithm string.
- `util.TextEncoder.encodeInto` and `util.Base64Helper.decodeSync` are in the installed `@ohos.util.d.ts`, lines 918 and 3348.

## Wire contract

`SignedAlertEnvelope` is JSON containing `payload`, base64 `signature`, and a mutable integer `hops`. Payload fields are explicitly typed in `entry/src/main/ets/model/AlertProtocol.ets`.

Signature input is UTF-8 of a fixed-order JSON array of **strings**:

```
["SafeMesh.Alert.v1", keyId, alertId, decimalRevision, decimalIssuedAtMs,
 decimalExpiresAtMs, severity, area, title, body, JSON.stringify(shelterIds),
 drill ? "1" : "0", decimalMaxHops]
```

This domain separation prevents use of an unrelated signed document as an alert. Fixed position and numeric serialization remove JSON object-key ordering ambiguity. `version` must be exactly 1 and is represented by the domain string. All visible alert content, the exercise flag, timestamps, destination point identifiers, and maximum hop policy are authenticated. Only routing `hops` remains unsigned so relays can increment it. The public key is DER SubjectPublicKeyInfo, P-256; the signature is DER ECDSA using SHA-256, base64 encoded.

`decodeEnvelope` imposes an 8192-byte outer limit and checks every used primitive and array entry. Canonical signed content is limited to 4096 UTF-8 bytes; body 1200 characters, title 160, at most 12 point IDs. Decoding is not authentication: always call `RelayEngine.ingest` before presenting an alert as verified or forwarding it. `nextHop` only emits content already authenticated by that engine.

## Trust and key handling

`DemoTrust.ets` contains only a pinned **public** exercise key. Both the engine and native adapter refuse a demo-key message with `drill=false`, even if its cryptographic signature would otherwise be valid. A network peer cannot supply a new public key and thereby become trusted.

`scripts/generate-demo-alerts.mjs` generates an ephemeral P-256 key in the host process, signs the exercise fixtures, writes only the public key and signed messages, and lets the private key leave memory when the process exits. The private key is never serialized into the mobile app, repository, or a file. Rerunning the script rotates the exercise trust root and fixtures together. Restart the exercise after redeployment; previously persisted fixtures from the old key fail verification.

The current fresh fixture is valid for 72 hours beginning 2026-10-03. `createExpiredAlert` has a genuine signature but an expired window. `createTamperedAlert` alters a genuine fixture after signing. The exercise text refers to central Kraków and gives no signed navigation destination; its point ID list is empty. Map data provenance and actual accessibility are separate from the signature on the exercise text.

A real deployment requires a genuine issuing authority's public key, a secure external signing service/HSM, an authenticated key rotation/revocation scheme, issuing policy, and operational review. An issuer name or a logo in a message is not an authority credential. An untrusted ordinary phone should never gain emergency-issuer privileges.

## Relay behavior

- Ingest verifies structure, known key/drill scope, hop budget, expiry, and future clock skew (maximum five minutes), then the cryptographic signature. Malformed/forged messages never populate the replay cache.
- Replay identity is `(keyId, alertId)`. A stored revision rejects equal or older revisions, independent of signature encoding; concurrent arrivals cannot both be accepted. Revisions must retain the original signed validity window; a new window needs a new alert ID. This prevents a short-lived replacement from letting a still-valid older revision reappear after cache pruning.
- Maximum signed lifetime is 72 hours and maximum signed hop budget is eight. A message at the last hop may be displayed but is not relayed further.
- At most eight verifications may be pending and 128 alert identities cached. A full cache fails closed instead of evicting valid replay entries. Expired entries are pruned.
- Inbound and outbound objects are copied so caller mutation during asynchronous verification cannot change authenticated display/cache content.
- `snapshot()` serializes currently accepted messages for private local storage. `restore()` re-verifies each signature and checks expiry before rebuilding the cache. The host ViewModel must persist successful ingests and restore before accepting radio traffic. Reset is explicitly named `resetDemo()` and is solely an exercise control.
- `accepted()`, `nextHop()`, and `snapshot()` remove expired content on access. `ingest` statuses: `accepted`, `duplicate`, `invalid`, `untrusted`, `expired`, `future`, `hop_limit`, `busy`, `capacity`.

## What the design does not establish

Signatures authenticate content relative to a trusted key. They do not prevent radio jamming, intentional dropping, isolation, authority key compromise, a malicious legitimate authority, or false claims about shelter accessibility. It is not possible to guarantee message delivery across disconnected groups.

The unsigned hop count is a cooperative traffic control, not cryptographically proven path length: a malicious relay can reset it. Expiry and persistent replay suppression help limit this, and real deployments also need peer-level rate limiting and carefully sized airtime budgets. Restoring from an empty/reinstalled device loses local replay history; signed expiry remains in force. The validity checks depend on the device clock and must be augmented with a trusted-time/clock-uncertainty policy for deployment under adversarial conditions.

The prototype does not include signed cancellation, authority revocation propagation, an audited key registry, cryptographic hop chains, location authentication, or routing guarantees. Do not claim that verified signatures make the whole emergency system safe for operational use.

## Foreground reliable peer delivery

`DeliveryProtocol.ets` wraps the unchanged signed envelope in `safemesh.data.v1` with a 128-bit random `deliveryId`. The token comes from native `cryptoFramework.createRandom().generateRandomSync(16)`; these are documented in the installed SDK's `@ohos.security.cryptoFramework.d.ts` at lines 1433 and 1332. The data decoder accepts at most 9216 UTF-8 bytes, below the native adapter's 16384-byte frame bound. Legacy raw signed envelopes remain valid incoming messages, although legacy peers cannot participate in the new acknowledgement protocol.

A `safemesh.ack.v1` frame names the delivery token, authority key ID, alert ID, and revision. `DeliveryQueue` accepts it only for an outstanding, actually attempted packet belonging to the same connected peer address and exact token/identity/revision. Reconnect creates new tokens, so an old connection's ACK cannot clear a new request. ACK handling neither adds nor removes alert content from the trusted cache. It never changes an alert's authenticity badge. These are **cooperative receiving-app acknowledgements**, not proof that a human read a warning, that a hostile peer will relay it, or that a peer identity is cryptographically trustworthy.

The receiver sends a success ACK only after `AlertViewModel.receive` returns `accepted` or a cryptographically verified `duplicate`, and only while the signed alert is still valid. A duplicate causes another ACK, allowing recovery from a lost ACK, but is not flooded onward again. Malformed, forged, unknown-authority, expired, future, or otherwise rejected messages receive no success ACK. ACKs themselves are never ACKed. A receipt means the receiving application verified and retained the alert in its process; the UI separately reports any failure to persist that verified state to disk.

`AlertViewModel.allAccepted()` exposes copies of every current, verified cached message for synchronization. A delayed or reconnected peer receives this full bounded cache rather than only the currently visible alert. The queue retains at most eight peers with 128 current alert identities each and at most 64 short ACK control packets. All data and control writes share a serial pump, with at most four writes in one batch, avoiding native send overlap. A data item gets at most three attempts per connection, with waits of two seconds and four seconds before the next attempts and eight seconds for the final receipt. Missing ACKs produce `retry_exhausted`; a local radio write is not counted as acknowledged delivery. Expiry is pruned during queue metrics/ticks as well as rechecked against the authenticated cache before every send. Stopped/disconnected queues discard their connection tokens; the signed alert cache remains available for later synchronization.

Relay startup awaits successful restoration of private local replay state. Storage read failures pause forwarding instead of silently starting with an empty cache, and a later restoration attempt may recover. A restored engine is published only after both snapshot and legacy reads complete. The retry timer is owned by the foreground RelayViewModel and is cleared on stop; late callbacks are guarded by a generation token. This is **not background delivery**, a system emergency alert service, a guaranteed radio mesh, or an authenticated end-to-end delivery receipt system.

Machine-readable UI metrics are `pendingCount`, `acknowledgedCount`, `retryCount`, and `failedCount`; `deliveryStatus` is one of `idle`, `awaiting_ack`, `acknowledged`, `retry_exhausted`, `stopped`, `restore_failed`, or `queue_error`. ACK totals count matching peer receipts in the current local relay session, not people reached.

The app's wait for each native send is also bounded to three seconds. A timeout consumes an attempt but never produces a successful ACK. Stop resolves the queue-owned wait and clears its deadline timer immediately. The native API does not expose cancellation of an individual write, so an underlying write may finish later; transport stop performs the available channel cleanup, late ACKs are ignored, and any later promise rejection is already handled. Startup checks the same lifecycle generation after restore, native start, and discovery, cleaning up a native start that finishes after Stop rather than reviving the relay.

The reproducible command `node --test tests/delivery.test.mjs` currently runs fourteen checks against the actual delivery codec, queue, ViewModels, and signature protocol. Tests use a fresh isolated test authority and real Node/OpenSSL signatures, with controlled radio loss and a deterministic clock. They cover multi-message delayed-peer synchronization, reconnect, bounded batches/capacity, mismatched and old-token ACKs, retries exhausted after loss, lost-ACK duplicate handling without re-flood, expiry, startup failure/recovery, stopping during an in-flight or hung operation, send deadlines, late native rejection, and Stop during restore/start/discovery. These resolve the audit gaps of newest-message-only reconnect behavior, local-write-only success reporting, unrestricted pending ACK expectations, and startup races. Physical hardware validation remains necessary.

## Validation and integration

Run `node --test tests/protocol.test.mjs`. These tests transpile the actual `.ets` implementation using the installed SDK's TypeScript compiler. Only the platform kits are adapted to Node/OpenSSL and UTF-8/base64 primitives; the protocol logic is not reimplemented in the test. `ARKTS_TYPESCRIPT_PATH` may point to another installed compiler.

The nine host tests cover genuine signatures and signed-field mutation; cache poisoning; concurrent replay; demo-to-live escalation; expiry/future/hop and malformed messages; three peers with duplicate loops; mutation isolation; bounded parsing; restore/reverification; bounded capacity and revision rollback. They verify cryptography and policy but **do not establish that native CryptoArchitectureKit works on the emulator or physical NearLink hardware**.

Required native checkpoint: on the HarmonyOS device, `new RelayEngine().ingest(createDemoAlert())` returns `accepted`, the same alert returns `duplicate`, a tampered fixture returns `invalid`, and the expired fixture returns `expired`. Native evidence is recorded by the app/device verification workflow separately. The three virtual peers exercise actual verification and relay policy with an in-process transport, not actual NearLink radio transmissions.

The separate `node --test tests/integration.test.mjs` suite contains nine reproducible asynchronous integration checks against the actual `AlertViewModel.ets`, `RelayViewModel.ets`, and protocol sources. It checks retention of authenticated content after rejected input, restore-before-receive replay defense, storage failures, zero traffic for forged packets, exact authenticated forwarding, concurrent duplicate handling and busy state, callback/send rejection handling, and exact expiry. Preferences and radio are explicitly mocked; signatures use Node/OpenSSL. Exercise time is fixed only inside the host test process, so these tests remain deterministic after the bundled drill expires. They do not replace device or physical-radio testing.

## Bounded native preferences persistence

The installed API declaration `@ohos.data.preferences.d.ts` lines 115–146 limits a string value to **8192 characters**; keys are limited to 80. The documented promise methods used by `LocalStore.ets` are `get` (line 1079), `put` (1437), and `flush` (1733). Storing the whole 128-alert relay snapshot in one preference value would exceed that limit.

`LocalStore` therefore bounds a logical string at `128 * 8192` UTF-16 units and splits it into chunks of at most 2048 units without separating a surrogate pair. All keys stay below the native key limit. Each logical key has two bounded chunk slots. A replacement writes the inactive slot and flushes those complete chunks before updating and flushing a small head descriptor. The previous active slot is untouched until this publication. Failed publication restores the old in-process head and propagates the error, so the ViewModel reports a save failure. Reads and writes are serialized; incomplete generations and oversized descriptors fail closed. Access before initialization throws, while access during initialization awaits it. Small legacy values remain readable.

This is a two-phase generation protocol over the native preferences API, not a claim of transactional or power-loss guarantees stronger than the platform provides. After an ambiguous final flush failure, either durable head is acceptable because its full referenced generation was already flushed. `node --test tests/storage.test.mjs` runs seven tests against the actual LocalStore source, modeling the native string limit, UTF-8 conversion, initialization, concurrent operations, missing chunks, and failures before and during head publication. Tests include the maximum supported snapshot size and restart recovery.
