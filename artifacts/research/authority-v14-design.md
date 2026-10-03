# SafeMesh 1.4: authority publishing and recipient inbox

## Requirements and architecture

The user clarified the product model: an authorized authority publishes an alert; ordinary recipients read and automatically relay it. A publisher in A can reach B, and B can reach C even when A cannot. A transport-role selector is not an issuing permission.

Retain V1 ArkUI / MVVM (MVVM-01 and ARKUI-03). The existing `RelayEngine` already verifies signatures before deduplication, stores one current revision per issuer/alert ID, and forwards only accepted messages. Repeated valid packets are acknowledged again to recover a lost ACK; they do not create another receipt or forwarding event.

- **View:** Home inbox, message detail, incoming-message banner and a separate authenticated issuer console. No manual send action in the recipient Relay screen. Native controls and both PL/EN resources remain.
- **AlertViewModel:** verified inbox snapshots, unread/read state, independent selected detail, and bounded local arrival metadata. Latest-alert compatibility fields remain. Untrusted data cannot populate the inbox. Duplicates do not become unread again or produce another banner.
- **AuthorityViewModel:** draft and login state; asks the issuing service to sign, passes the returned envelope through the same recipient verifier, then seeds the relay queue automatically. The view does not touch protocol or signing objects.
- **AuthorityClient:** bounded, uncached, non-proxied HTTP to a fixed loopback address; no redirects. The service's public key must match the public key pinned into the app. Credentials live only in process memory and are cleared on logout/disposal. A cancelled session cannot be revived by a late response.
- **Demo issuing service:** separate host process, bound to `127.0.0.1:8768`; owns the exercise signing key and requires a random bearer capability. Only emulator A gets that reverse port for the demo. Role A alone grants no privilege. Secrets and the issuance journal live in ignored `.cache/demo-authority`, never in Git or the recipient HAP. No internet is used by issuance or forwarding in this lab.

This local service models an offline authority issuing station. It is not government account integration or evidence of offline private-key custody on a physical phone. It is separate from the transport hub, which still neither signs nor caches alerts. After issuance, the service and A can be unavailable while B forwards its saved signed messages to C.

The service issues exercise-only v2 payloads, fresh IDs, bounded validity, and the same pinned ECDSA P-256/SHA-256 format. A request ID makes uncertain publication retries idempotent; reusing it for a different draft is rejected. Revisions in recipient storage retain the existing deduplication rules.

## API evidence before implementation

- `hmos-arkui-mvvm-pattern/references/add-func-workflow.md`: preserve current state version; Model owns I/O, ViewModel coordinates state, and View consumes ViewModel state only.
- Installed API 24 `ets/api/@ohos.net.http.d.ts`: `createHttp`, `HttpRequest.request` Promise, `HttpDataType.STRING`, response `maxLimit`, connect/read timeouts, `usingCache`, `usingProxy`, and API 23 `maxRedirects`. Kit mapping verified in `@kit.NetworkKit.json`. The demo issuer console is validated on API 24.
- Existing `DeliveryProtocol.createDeliveryId` uses native `cryptoFramework.createRandom().generateRandomSync(16)` for a 128-bit random request ID.
- Typed DTOs and named imports follow the project's existing ArkTS constraints. Host tests execute the actual `.ets` client and ViewModel after type erasure; native verification still requires an emulator pass.

## Validation plan

Publish distinct custom messages from authorized A, receive and open them on B and C, show the exact issuer text, and prove no manual forwarding action on recipients. Test duplicate/retry/read state, late-peer synchronization, B restart, A/signing-service absence, unauthorized publishing, wrong pinned key and rejected tampering. Inspect PL/EN inbox/composer and large text. Keep physical NearLink and suspended/background delivery outside emulator claims.
