# SafeMesh: physical NearLink test runbook

This runbook covers the first test of SafeMesh's NearLink (星闪 / SparkLink) relay on real HarmonyOS phones. Use it with the `main` branch at **v1.5.1 or later**: v1.5.1 fixes NearLink detection on API 20–22 phones. Until now all validation used API 24 emulators, which have no NearLink radio, so **every NearLink result below is still unverified**. Anything marked **verify on site** comes from documentation or code reading and has not been tried on a phone.

> **Read this first.** These points come from reading the code, and each one can ruin a run:
> 1. **Order of loading and connecting.** Since v1.4.1, *Load exercise message* also queues the alert for peers that are already connected, and a newly confirmed channel synchronizes every saved alert. Builds before v1.4.1 pushed only on a new connection, so with an older HAP load the alert on A **before** connecting.
> 2. **All NearLink controls are under Tests and diagnostics → NearLink radio.** The **Relay / Łączność** tab is for emulators only. Its *Connect A/B/C* button switches the phone to the emulator WebSocket transport and stops NearLink. Its banner always reads "Emulator test · local connection, no NearLink radio".
> 3. **Discovery runs only when you tap Start NearLink**, and only for the name in the peer-name field at that moment. To change the name, edit it and tap *Start NearLink* again. This restarts the radio session and drops existing links.
> 4. **Delivery counters in NearLink mode.** Since v1.4.1 the NearLink section shows *Pending / Received by app / Retries* (`nearlinkMetrics`) and the last packet verdict (`nearlinkPacketStatus`) under the peer list. The app ACK is also logged as `status=ack_matched` on the sender.
> 5. **NearLink errors are in hilog, not in the UI.** The UI shows only the generic "NearLink failed. Check permissions and radio settings." Since v1.4.1 every transport error (30 s connect timeout, write failures, SDK error codes) is logged as `SAFEMESH_TRANSPORT_ERROR mode=nearlink op=… code=… message=…`, with link changes as `SAFEMESH_TRANSPORT_STATUS` and `SAFEMESH_TRANSPORT_PEER`.
> 6. **Run verification test also loads the exercise into that phone's inbox.** Never run it on B or C before the relay scenarios.
> 7. Diagnostics shows the fixed text "NearLink has not been tested on physical devices." Keep it out of the jury video, or update the copy only after a recorded pass.

## 1. Goal and pass criteria

| ID | Criterion | Counts as PASS when |
| --- | --- | --- |
| (a) | NearLink capability detected | On every phone, **Check NearLink support** shows "NearLink support detected. Connect a compatible phone." (PL: "Wykryto obsługę NearLink. Połącz zgodny telefon."). |
| (b) | A → B delivery with app ACK | B shows the new-alert banner and an inbox entry. B's alert detail reads "Received from device ‹A address› · Relay hops: 1". B's hilog has `status=accepted … hops=1`, and A's hilog has `status=ack_matched` for the same `alertId`. |
| (c) | A → B → C store-and-forward | A stops NearLink **and** turns the radio off (or leaves range) **before** C starts. C later connects to B, and C's detail reads "Received from device ‹B address› · Relay hops: 2". C's hilog has `status=accepted … hops=2`, and B's hilog has `status=ack_matched`. |
| (d) | Tampered and expired content rejected | **Run verification test** shows "All checks passed" with six green rows, and hilog has `SAFEMESH_NATIVE_DIAGNOSTICS PASS`. This only sanity-checks native crypto and policy on the phone, not rejection over the radio. Optional (d2) in §6 rejects over the air. |

**What counts as evidence.** You need all of the following, otherwise report the scenario as *not demonstrated*:
1. A continuous screen recording from each phone involved, covering the whole scenario.
2. Screenshots of the key states listed in §6.
3. hilog lines filtered on `SAFEMESH_`, with timestamps, exported per phone (§7).
4. Build identity: `git rev-parse HEAD`, `git status --short`, `versionName` from `AppScope/app.json5`, and the SHA-256 of the installed signed HAP.
5. Per phone: model, HarmonyOS version, API level, the NearLink name used, approximate distance, and indoor or outdoor.

A FAIL with good evidence is a valid result. Record it; do not retry silently.

## 2. Hardware and software prerequisites

| Item | Requirement | How to check |
| --- | --- | --- |
| Phones | 2 minimum for (a), (b), (d); **3 for (c)**. Label them A, B, C with tape. | — |
| NearLink hardware | The phone settings have a NearLink (星闪) entry. | Settings > Multi-device collaboration > NearLink (设置 > 多设备协同 > 星闪), or Settings > NearLink & Bluetooth (设置 > 星闪和蓝牙). English labels: verify on site. |
| OS level | **API ≥ 20 (HarmonyOS 6.0+) with NearLink hardware.** The gate is `canIUse('SystemCapability.Communication.NearLink.Core')`. From API 23 the app also asks `manager.isNearLinkSupported()`; on API 20–22 that function does not exist (since v1.5.1 the app no longer calls it there). The NearLink APIs used start at API 13 (scan, advertising) and API 18 (data transfer). | `& $hdc -t <serial> shell param get const.ohos.apiversion` |
| Phone access | Owner's consent to enable developer options and USB debugging, rename the device, and change screen-lock or clock settings. | Ask the mentors. |
| Cables | One USB-C **data** cable per phone and enough laptop ports. | — |
| Laptop | Windows, DevEco Studio 6.1.1 in `C:\Users\user\DevEcoStudio`, HarmonyOS SDK API 24 **including HMS kits** (NearLink Kit; a plain OpenHarmony SDK is not enough), Node 24, DevEco CLI 1.3.4. | `devecocli.cmd -V`, `node --version` |
| Account | Huawei developer account with **real-name/identity verification done**. Internet on the laptop and a correctly synced clock, both needed for signing. | Sign in once in DevEco Studio before the session. |
| Repo | `main` with a clean tree. Note the commit. | `git status --short` |
| Authority (optional) | `.cache/demo-authority/` on **this** laptop. It holds the private key and token, is git-ignored, and must match the app pin. | §6, path (ii) |
| Emulators | Closed during the session, so `hdc` never targets an emulator by mistake. | `hdc list targets` shows only phones. |

## 3. Signing for physical devices

The repository has `"signingConfigs": []`, so every build produces `entry-default-unsigned.hap`, which installs **only on emulators**. A phone rejects it with `9568320 … no signature file`.

1. Run `git status --short` and note anything already modified.
2. On each phone, open Settings > About phone (shown as the device name; 设置 > 关于本机) and tap **Software version** 7 times. Enter the PIN; the phone reboots. Then open Settings > System > Developer options (设置 > 系统 > 开发者选项) and enable **USB debugging**.
3. Connect **all phones at once** and accept **Allow USB debugging** on each. Run `& $hdc list targets` and note one serial per phone. Automatic signing writes every connected device into the debug profile.
4. In DevEco Studio, open the project and go to **File > Project Structure... > Project > Signing Configs**. **Sign In** with the Huawei account, tick **Automatically generate signature**, and click **OK**. Leave *Associate with registered application* unticked unless an AGC app with the same bundle name already exists. *Support HarmonyOS* applies only to OpenHarmony projects; this one is HarmonyOS.
5. DevEco generates `.p12/.csr/.cer/.p7b` under `%USERPROFILE%\.ohos\config\` and writes a `signingConfigs` entry named `default` into `build-profile.json5`. It must match `products[0].signingConfig: "default"`.
6. If you add a phone later, reconnect **all** phones and sign again. The limit is 150 automatic signings per account per 30 days.

Common signing errors:

| Error | Fix |
| --- | --- |
| "…calibrate the system time…" | Sync the laptop clock (Windows: Date & time → Sync now) and sign again. |
| "Failed to query agreement signing records" | The account is not identity-verified, or a proxy is in the way. Set DevEco's HTTP proxy to *No proxy*. |
| "Unable to create the profile due to a lack of a device" | Run `& $hdc -t <serial> shell bm get --udid`. It must print the UDID. |

> **WARNING: do not commit signing changes.** Automatic signing writes **absolute local certificate paths and encrypted passwords** into `build-profile.json5`.
> - Never commit that change, the `.ohos\config` files, or any `.p12/.cer/.p7b/.csr`. `.gitignore` covers the certificate extensions but **not** `build-profile.json5`.
> - Before any commit, run `git diff --stat` and make sure `build-profile.json5` is not listed.
> - After the session, restore it with `git checkout -- build-profile.json5`. If you need it again later, keep it with `git stash push build-profile.json5 -m "local phone signing"`.
> - The emulator helpers `scripts/run-demo.ps1` and `scripts/start-authority-demo.ps1` install the **unsigned** HAP, so they are for emulators only.

**Product warning.** Build and install the **`default`** product (HarmonyOS), which DevEco uses unless told otherwise. The `oniro` product (OpenHarmony / Oniro, see COMMANDS.md) replaces the NearLink adapter with a stub and drops `ACCESS_NEARLINK`. Never run `oniro-app sign .` in this checkout: it would add the OpenHarmony key to the HarmonyOS product. *Historical note:* the `testing` branch (PR #1) holds an **OpenHarmony public-debug-key** signing setup for Oniro/OpenHarmony (`runtimeOS: "OpenHarmony"`, `signatures/OpenHarmony.p12`). It replaces `NearLinkTransport.ets` with a stub that is always unavailable and drops `ACCESS_NEARLINK`. **Do not use it for these tests.**

## 4. Build, install and launch on each phone

**Option A, DevEco Studio:** pick a phone in the device dropdown and choose **Run 'entry'** (Shift+F10). Repeat for each phone.

**Option B, CLI** (from PowerShell, in the repo):

```powershell
Set-Location C:\Users\user\SafeMesh
$env:DEVECO_CLI_STUDIO_PATH = 'C:\Users\user\DevEcoStudio'
$env:Path += ';' + (Join-Path $env:APPDATA 'npm')
$hdc = Join-Path $env:DEVECO_CLI_STUDIO_PATH 'sdk\default\openharmony\toolchains\hdc.exe'
& $hdc list targets
$A = '<serial A>'; $B = '<serial B>'; $C = '<serial C>'
devecocli.cmd build                     # or: devecocli.cmd run --module entry --device $A
$hap = 'entry\build\default\outputs\default\entry-default-signed.hap'   # name: verify on site
Get-FileHash $hap -Algorithm SHA256     # record it
foreach ($s in $A, $B, $C) {
  & $hdc -t $s install -r $hap
  & $hdc -t $s shell aa start -b org.safemesh.alerts -a EntryAbility
  & $hdc -t $s shell param get const.ohos.apiversion
}
```

- **Fresh inbox on B and C** (required before (b) and (c)): `& $hdc -t $B shell bm clean -d -n org.safemesh.alerts`, then relaunch. Home must show "No current alert / Brak aktualnego alertu".
- **Restart the app:** `& $hdc -t $B shell aa force-stop org.safemesh.alerts`, then the `aa start` command above.
- **Install errors:**

| Error | Cause or fix |
| --- | --- |
| `9568320 no signature file` | The unsigned HAP was used. Install the signed one. |
| Profile or device mismatch | The phone was not connected while signing. Sign again. |
| "compatibleSdkVersion … do not match" | The phone is below API 20. |
| Signature differs from the installed app | Uninstall first: `& $hdc -t $s uninstall org.safemesh.alerts`. This deletes the app data. |

## 5. Pre-flight on each phone

| # | Check | Detail |
| --- | --- | --- |
| 1 | NearLink **on** | Settings > Multi-device collaboration > NearLink (设置 > 多设备协同 > 星闪). Do **not** use airplane mode, which may switch radios off. Turn Wi-Fi and mobile data **off** for the radio runs. |
| 2 | **Exact NearLink name** noted | Read it on the NearLink settings page. The app scans **only by exact device name** (1–30 chars) because API 24 `ScanFilters` cannot filter by service UUID. Huawei's FAQ reports advertised names being cut to 9 bytes, so use **short ASCII names of 9 characters or fewer** (e.g. `SM-A`, `SM-B`, `SM-C`). Rename with the owner's consent under Settings > About phone > Device name (设置 > 关于本机 > 设备名称); verify on site that the NearLink page shows the new name. |
| 3 | Clock correct | Turn automatic date and time on. The fixture is valid **2026-10-03 19:57:54 UTC → 2026-10-06 19:57:54 UTC**. Alerts dated more than **5 minutes** in the future are rejected as `future`. |
| 4 | Screen stays on, app in foreground | The relay stops whenever the page is hidden (screen lock, home, app switch). Since v1.6.0, Settings → *Keep screen on while connected* (on by default) keeps the screen awake while a link is active. Turn auto-lock off or enable the developer option *Stay awake* (verify on site), or run `& $hdc -t $s shell power-shell setmode 602` and `& $hdc -t $s shell power-shell timeout -o 7200000` (both confirmed on the API 24 emulator on 2026-10-04; verify on a phone). Turn on Do Not Disturb. |
| 5 | App language | Tap the gear → **App language / Język aplikacji** → *System*, *Polski* or *English*. *System* (the default) follows the phone: Polish on a Polish phone, English otherwise. Use the same on all phones so the video is consistent. |
| 6 | Permissions | The NearLink prompt appears at the first **Start NearLink**; choose **Allow**. Location is used only by Map → *Use my location* and is not needed here. Optional fallback: `hdc install -g` pre-grants permissions for debug HAPs (hdc API 24+, verify). |
| 7 | hilog ready | Run the commands below on every phone. |

```powershell
foreach ($s in $A, $B, $C) {
  & $hdc -t $s shell hilog -Q pidoff;  & $hdc -t $s shell hilog -Q domainoff   # disable flow control
  & $hdc -t $s shell hilog -G 16M;     & $hdc -t $s shell hilog -r            # bigger buffer, clear
}
& $hdc -t $A shell hilog -e SAFEMESH_    # one live window per phone (the -e filter runs on the device)
```

**Role card** (print it). Only the phone that scans taps **Connect**:

| Role | Peer-name field | Taps Connect on | Notes |
| --- | --- | --- | --- |
| A | B's exact name | B | Holds the signed alert before connecting. |
| B | **leave empty** | nobody | Only advertises and accepts links. Stays foreground the whole time. |
| C | B's exact name | B | Starts only after A has gone. |

## 6. Test procedure

**UI path to NearLink:** tap the header gear (*Open settings / Otwórz ustawienia*) → **Tests and diagnostics / Testy i diagnostyka**, then scroll to **NearLink radio / Radio NearLink**. Alternatively, use the bottom row of the **Relay / Łączność** tab.

| Control (EN / PL) | Node id | Notes |
| --- | --- | --- |
| Check NearLink support / Sprawdź obsługę NearLink | `checkNearLink` | Re-probes the radio. It also switches back to NearLink if the emulator transport was selected. |
| Exact nearby phone name / Dokładna nazwa pobliskiego telefonu | `peerName` | Visible only when the probe reports support. |
| Start NearLink / Uruchom NearLink | `startHardware` | Asks for permission, opens the port, advertises, and scans for the typed name. |
| ‹name› · Connect / Połącz → ‹name› · Connected / Połączono | `peer_<address>` | One button per discovered or connected peer. Incoming peers show an empty name. |
| Stop NearLink / Zatrzymaj NearLink | `stopRelay` | Explicit stop. Does not auto-resume. |
| Load exercise message / Wczytaj wiadomość ćwiczebną | `diagnosticDrill` | Under *Exercise message / Wiadomość ćwiczebna*. |
| Run verification test / Uruchom test weryfikacji | `runRelay` | The 6-check local test. |
| Pending · Received by app · Retries | `nearlinkMetrics` | v1.4.1+. Shown under the peer list while NearLink is supported. |
| Last packet verdict | `nearlinkPacketStatus` | v1.4.1+. For example "Invalid signature rejected" or "Receipt confirmed". |
| Delivery results / Wyniki przekazywania | — | *Messages received / Odebrane wiadomości*, *Packets rejected / Odrzucone pakiety*, *Failed / Nieudane*. |
| Exercise authority / Nadawca ćwiczeń | `openAuthority` | Top row of diagnostics. |

The NearLink status line (`nearlinkStatus`) can show:

| State | EN | PL |
| --- | --- | --- |
| available | NearLink support detected. Connect a compatible phone. | Wykryto obsługę NearLink. Połącz zgodny telefon. |
| ready | NearLink ready. Search by the other phone's name. | NearLink gotowy. Wyszukaj drugi telefon po nazwie. |
| discovering | Searching for the phone… | Wyszukiwanie telefonu… |
| off | Enable NearLink in phone settings, then start relaying. | Włącz NearLink w ustawieniach telefonu, a potem uruchom przekazywanie. |
| unsupported | NearLink is unavailable on this device. | NearLink jest niedostępny na tym urządzeniu. |
| permission_denied | NearLink access denied. Check nearby-device permissions. | Brak dostępu do NearLink. Sprawdź uprawnienia do pobliskich urządzeń. |
| error | NearLink failed. Check permissions and radio settings. | Błąd NearLink. Sprawdź uprawnienia i ustawienia radia. |

### (a) Capability, on every phone
1. Launch SafeMesh, open Tests and diagnostics, and tap **Check NearLink support**.
2. Take a screenshot of the status line. PASS is the *available* text above. *off* means the hardware is present but the switch is off: fix it and re-check.

### Get a signed alert onto phone A
**(i) Bundled fixture (default, needs no laptop service).** On A, tap **Load exercise message**. With v1.4.1 this works before or after A connects to B.
- Expect the banner "Verified exercise message received. / Odebrano zweryfikowany komunikat ćwiczebny." and the inbox title "Connection outage / Przerwa w łączności".
- The detail should read "Added on this device · Relay hops: 0". The alert ID is `krakow-hackyeah-exercise-001`, defined in `entry/src/main/ets/model/DemoAlerts.ets`.
- If the fixture has expired or will expire during the session, refresh it **on this laptop** (it uses the persistent key in `.cache/demo-authority/`). Then rebuild and reinstall on **all** phones:

```powershell
node scripts/generate-demo-alerts.mjs   # rewrites DemoAlerts.ets/DemoTrust.ets with a new 72 h window; key not rotated
devecocli.cmd build                     # then reinstall the signed HAP on A, B and C (§4)
```

**(ii) Exercise authority over USB** (optional; custom text). The app calls `http://127.0.0.1:8768`. On a phone, that address has to be reverse-forwarded to the laptop. `hdc rport` is documented as a generic hdc feature, but it has not been tried on a USB phone: **verify on site**.

```powershell
node -e "import('./scripts/prepare-demo-authority.mjs').then(m => { m.assertPinnedAuthority(m.loadAuthority()); console.log('PIN OK'); })"
Get-NetTCPConnection -LocalPort 8768 -State Listen -ErrorAction SilentlyContinue   # reuse a running service
node scripts/demo-authority-server.mjs        # only if nothing listens; separate window, leave running
& $hdc -t $A rport tcp:8768 tcp:8768
& $hdc -t $A fport ls                         # expect: <A> tcp:8768 tcp:8768 [Reverse]
```

On A, tap the gear → Tests and diagnostics → **Exercise authority / Nadawca ćwiczeń**, then do the following:
1. Enter the 64-hex **Activation code / Kod dostępu** from `.cache\demo-authority\session-token.txt`. Type it off camera, or run `devecocli.cmd ui text --device $A --id authorityToken ((Get-Content .cache\demo-authority\session-token.txt -Raw).Trim())` (verify on a phone). The code then appears in that process's arguments, so never record the terminal.
2. Tap **Sign in / Zaloguj się**, then fill in *Title*, *Instructions* and *Area*.
3. Set *Valid for* to **4 hours** or **24 hours** and tap **Publish alert / Opublikuj alert**.

Publishing queues the alert to peers that are **already connected**, so path (ii) also works after connecting. In hilog, the alert ID looks like `authority-<hex>`.

### (b) A → B delivery with app ACK
1. **B:** Tests and diagnostics → leave the name empty → **Start NearLink** → *Allow*. Wait for "NearLink ready…". B is now advertising. Keep it on screen.
2. **A** (the alert is already loaded): type B's exact name → **Start NearLink** → *Allow*. Wait for "Searching for the phone…".
   - If the first Start after the permission prompt does not reach that state, tap Start NearLink again.
3. **A:** within about 60 s, the button **"‹B name› · Connect"** appears. Tap it **once**. The app waits up to 30 s for the channel callback, after which the button reads **"‹B name› · Connected"**. Home then shows *Connected* with *1 nearby devices*.
4. **B** should show:
   - the banner "Verified exercise message received." → tap **Read alert / Przeczytaj alert**;
   - the detail "Received from device ‹A address› · Relay hops: 1" (PL: "Odebrano z urządzenia … · Przekazania: 1");
   - under Delivery results, *Messages received: 1*.
5. **hilog:** B shows `SAFEMESH_RELAY_RECEIVE node=nearlink status=accepted alertId=krakow-hackyeah-exercise-001 hops=1`, and A shows `… status=ack_matched alertId=krakow-hackyeah-exercise-001 hops=-1`.
   - If A has no `ack_matched` about 15 s after the first send (three attempts with backoff), A's *Failed* goes to 1. That is a **FAIL of (b)**: record it.
6. Take screenshots of A (Connected), B (banner, detail) and B (Delivery results).

### (c) A → B → C store-and-forward
1. **A goes away:** on A, tap **Stop NearLink**, then switch NearLink **off** in Settings, or carry A well out of range. Film this. B's entry for A should change from *Connected* back to *Connect*.
2. **Optional persistence proof:** on B, run `aa force-stop` and then `aa start` (§4). B's Home must still list the alert, re-verified from storage. Open diagnostics and tap **Start NearLink** again; it does not restart automatically after a relaunch. Leave the name empty.
3. **Wait** at least a minute so the delay is visible in the video, then **C:** type B's exact name → **Start NearLink** → *Allow* → tap **"‹B name› · Connect"**.
4. **C** should show the banner and the detail "Received from device ‹B address› · Relay hops: **2**" (PL: "Przekazania: 2"), plus *Messages received: 1*.
5. **hilog:** C shows `status=accepted … hops=2`, and B shows `status=ack_matched`. A must have no new lines, because it was off.
6. If C cannot find B after A left, tap **Start NearLink** on B again. This restarts advertising and keeps B's saved inbox.

### (d) Rejection sanity check, after (b) and (c)
1. On each phone, tap **Run verification test**. Expect "All checks passed / Wszystkie próby poprawne" and six rows:
   - *Receipt at A*
   - *Relay A → B*
   - *Relay B → C*
   - *Repeated message*
   - *Changed content*
   - *Expired message*
2. In hilog, expect `SAFEMESH_NATIVE_DIAGNOSTICS PASS [...]`. This test runs in one process with no radio.
3. **Optional (d2), expiry over the air.** Do this only with the owner's consent, as the very last test.
   - Set C's clock manually past `2026-10-06 19:58 UTC`, then connect C to B. Expect C to log `status=expired` and show *Packets rejected: 1*.
   - B gets no `ack_matched`, and B's *Failed* becomes 1 after about 15 s.
   - Restore automatic time afterwards.

**hilog status reference** (`SAFEMESH_RELAY_RECEIVE node=nearlink status=…`):

| Status | Meaning |
| --- | --- |
| `accepted` | Verified, stored and ACKed. |
| `duplicate` | Already stored. ACKed again but not forwarded. |
| `ack_matched` / `ack_unmatched` | The sender's queue got or ignored a receipt. |
| `invalid` | Signature does not match. |
| `untrusted` | Unknown key ID or not a drill. |
| `expired` | Past the alert's expiry. |
| `future` | Issued more than 5 minutes ahead of this phone's clock. |
| `hop_limit` | More than 8 hops. |
| `malformed` | Not a SafeMesh packet. |
| `processing_failed` | Error while processing the packet. |

Transport tags (v1.4.1+), useful when a run fails:

| Tag | Example | Meaning |
| --- | --- | --- |
| `SAFEMESH_TRANSPORT_STATUS` | `mode=nearlink state=ready peers=1` | Radio session state and confirmed channel count. |
| `SAFEMESH_TRANSPORT_PEER` | `mode=nearlink connected=true name=SM-B` | First discovery of a peer and every link change (repeated scan results are not logged). |
| `SAFEMESH_TRANSPORT_ERROR` | `mode=nearlink op=connect code=0 message=No channel confirmation within 30 seconds…` | Any adapter or SDK failure with its code. Packets and alert text are never logged. |

Other `SAFEMESH_` tags: `SAFEMESH_NATIVE_DIAGNOSTICS`, `SAFEMESH_RELAY_ERROR`, `SAFEMESH_INIT_ERROR`, `SAFEMESH_RESTORE_ERROR` and `SAFEMESH_UI_CONFIGURATION`. Lines appear as `I A03d00/JSAPP: SAFEMESH_…`.

## 7. Evidence capture

- **Screen recording:** use the phone's built-in screen recorder from the control panel (verify on site). Alternatively, use DevEco Studio's **Log** tab → *record* (physical devices only, phone kept unlocked), or the documented commands:

  ```powershell
  & $hdc -t $B shell aa start -b com.huawei.hmos.screenrecorder -a com.huawei.hmos.screenrecorder.ServiceExtAbility --ps "CustomizedFileName" "physical-b.mp4"
  & $hdc -t $B shell aa start -b com.huawei.hmos.screenrecorder -a com.huawei.hmos.screenrecorder.ServiceExtAbility   # stop
  & $hdc -t $B shell mediatool query physical-b.mp4 -u                                                            # then hdc file recv <path> .
  ```

- **Screenshots:** `devecocli.cmd ui screenshot --device $B --path artifacts\screenshots\physical-<date>-b-hop1.png`. Alternatively:

  ```powershell
  & $hdc -t $B shell snapshot_display -f /data/local/tmp/b.jpeg
  & $hdc -t $B file recv /data/local/tmp/b.jpeg artifacts\screenshots\physical-<date>-b-hop1.jpeg
  ```

- **UI state as JSON** (optional, like the emulator evidence): `devecocli.cmd ui layout --device $C --format json | Out-File -Encoding utf8 artifacts\logs\physical-<date>-c-layout.json`
- **hilog export** after each scenario (works even if the USB cable was unplugged during the run, thanks to the 16 MB buffer): `& $hdc -t $B shell hilog -x -e SAFEMESH_ | Out-File -Encoding utf8 artifacts\logs\physical-<date>-b-hilog.txt`. Keep unfiltered dumps (`hilog -x`) in the git-ignored `.cache\`, because they contain other apps' and personal data.
- **Naming:** `artifacts/logs/physical-<yyyymmdd>-<role>-<what>.txt` and `artifacts/screenshots/physical-<yyyymmdd>-<scenario>-<role>-<what>.png`. Add a `physical-<yyyymmdd>-run.txt` with build identity, phones, distances, times and PASS/FAIL per scenario. Keep raw videos outside Git; commit only a final cut under GitHub's 100 MB limit, if at all.
- **Never capture or commit** the following. Blur or crop anything that slips into a shot.
  - the activation code or `session-token.txt`
  - `authority.json` (the private key)
  - the DevEco signing dialog
  - `build-profile.json5` with `signingConfigs`, or `%USERPROFILE%\.ohos\config`
  - the Huawei account e-mail
  - `bm get --udid` output (device UDIDs)
  - phone owners' notifications or personal data
- **Close-out:**
  1. Run `& $hdc -t $A fport rm tcp:8768 tcp:8768` and stop the authority service if you started it.
  2. Run `git checkout -- build-profile.json5`, then `git status --short`.
  3. Return the phones with their original names, clock, lock and developer settings.

## 8. Troubleshooting

| Symptom | Likely cause → action |
| --- | --- |
| "NearLink is unavailable on this device." | No NearLink hardware (no NearLink entry in Settings), or API < 20. With a build older than v1.5.1 it also happened on API 20–22 phones; reinstall the current build. Otherwise record the phone as unsupported. |
| "Enable NearLink in phone settings…" | Switch NearLink on (§5.1), then tap **Check NearLink support** and **Start NearLink**. |
| "NearLink access denied…" | The permission was refused. Allow it in the app's permission settings (path: verify on site), or uninstall and reinstall to get the prompt again. |
| "NearLink failed…" right after Start | Read `SAFEMESH_TRANSPORT_ERROR … op=start code=…`. Possible causes: a stale port (`1009700020` UUID already registered) after a crash, so force-stop and relaunch; advertising rejected, so shorten the device name; NearLink switched off mid-start. System NearLink lines: `hilog -x -e "[Nn]ear[Ll]ink"` (verify). |
| Stays on "Searching for the phone…" | Check that the name is exact (case, spaces, truncation). Use `devecocli.cmd ui text --device $A --id peerName "SM-B"` to avoid typos. Make sure the other phone tapped **Start NearLink** and is unlocked and in the foreground. Move phones to 0.5–2 m (advertising uses the default low TX power). Tap Start NearLink again. |
| Connect never turns into *Connected*; generic error after 30 s | No channel confirmation within 30 s. Check that B's app is foreground and started. Tap once more, Stop/Start on both phones, toggle NearLink off and on, or try connecting from the other side. |
| Connected, but B shows nothing | With a pre-1.4.1 build, A loaded the alert **after** connecting: Stop NearLink → Start NearLink → Connect on A. Check B's hilog: `invalid/untrusted/expired/future` (see below). No line at all means framing or MTU, so check A's *Pending/Retries* and `SAFEMESH_TRANSPORT_ERROR op=send` after about 15 s. |
| "Send in progress" (internal code 1009700023) | Logged as `SAFEMESH_TRANSPORT_ERROR op=send code=1009700023`. A previous chunked write is still running, or the SDK is congested. The queue retries 3× per connection. If *Failed* rises, Stop/Start and reconnect, which re-queues. |
| MTU issues | Chunks are `min(MTU, 1024)` bytes. If the connection callback reports MTU < 8, data **and ACKs** are refused, so B may accept while A never sees `ack_matched`. There is no UI workaround; record it as a finding (needs a code change). |
| Load exercise message → "could not be verified… may have expired" | Check the phone clock, then refresh the fixture (§6 (i)) and reinstall on all phones. |
| `invalid` / `untrusted` on B or C | The phones run different builds or pins. Reinstall the **same** signed HAP everywhere. The authority shows "This service does not match the trusted exercise authority." when the key ≠ the pin; run the PIN check. |
| `future` | The receiver's clock is more than 5 min behind the issue time. Turn automatic time on. |
| Relay tab says "Paused"; links gone | The app left the foreground (lock, home, notification action). On return it restarts advertising and discovery but **not** the connection: tap the peer again. Keep the screen on. |
| "Connection failed. Check that the test server is running." | Someone tapped *Connect A/B/C* on the Relay tab (emulator transport). Go to diagnostics → **Check NearLink support** → **Start NearLink**. |
| No `SAFEMESH_` lines in hilog | Flow control (`hilog -Q pidoff`), a non-debug build, or the wrong `-t` serial. Check that `hilog -x` shows any app output. |
| `hdc list targets` empty or *Unauthorized* | Accept the USB debugging prompt, use a data cable, re-plug, or use DevEco's *Troubleshoot Device Connections*. |
| Authority "…unavailable…" | The service is not listening on 8768, or `rport` is missing (`fport ls`). Fall back to the fixture. |

## 9. Jury video (60–90 s) and README template

| Time | Shot | Shows |
| --- | --- | --- |
| 0–5 s | Title card | "SafeMesh · physical NearLink test · ‹date› · ‹model›" and "Exercise messages, not official alerts". |
| 5–12 s | Table camera: three labelled phones, USB unplugged | Wi-Fi and mobile data off, NearLink on (control panel). |
| 12–20 s | A screen: Check NearLink support | The "NearLink support detected…" text. |
| 20–28 s | A: Load exercise message | Banner and the inbox entry "Connection outage". |
| 28–45 s | A: B's name, Start NearLink, Connect → Connected; cut to B | B's banner → Read alert → "Relay hops: 1". |
| 45–55 s | A: Stop NearLink, NearLink switch off; A leaves the frame | The source is gone. |
| 55–75 s | C: B's name, Start NearLink, Connect; C's banner | C's detail "Received from device … · Relay hops: 2". |
| 75–85 s | Laptop terminal | The hilog lines `accepted hops=1`, `ack_matched`, `accepted hops=2` (no tokens on screen). |
| 85–90 s | End card | Real results only (placeholders below), plus the limits: foreground only, exact-name discovery. |

Avoid filming the Relay tab: its banner says "Emulator test · local connection, no NearLink radio". Do not narrate range or reliability you did not measure.

**Paste into README** as `## Physical NearLink validation`, filling every placeholder. Do not publish it until the evidence exists:

```markdown
## Physical NearLink validation

**Result: ‹PASS / PARTIAL / FAIL›.** On ‹YYYY-MM-DD› we ran SafeMesh ‹versionName› (commit `‹hash›`, debug-signed HAP SHA-256 `‹sha256›`) on ‹N› × ‹phone model› with HarmonyOS ‹version› (API ‹n›), Wi-Fi and mobile data off, at about ‹x› m apart ‹indoors/outdoors›.
- (a) NearLink capability: detected on ‹n›/‹N› phones.
- (b) A → B: ‹result›; B displayed the signed exercise at hop ‹n›; A logged the app acknowledgement: ‹yes/no›.
- (c) Store-and-forward: after A ‹stopped NearLink and switched the radio off›, C received the alert from B at hop ‹n›, ‹t› minutes later: ‹result›.
- (d) On-device verification test: ‹6/6 or result›. ‹Optional over-the-air expiry check: result›.
Evidence: [video](‹link›), [logs](artifacts/logs/), [screenshots](artifacts/screenshots/) (files `physical-‹date›-*`).
Limitations: ‹number of runs›; discovery needs the peer's exact NearLink name; relaying works only while the app is in the foreground; range, battery use and background delivery were not measured.
```
