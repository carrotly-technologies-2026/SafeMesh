# Running SafeMesh on Linux (Oniro emulator)

The DevEco Studio emulator is available only on Windows and Apple Silicon macOS. On Linux, SafeMesh runs on the **Oniro emulator** (OpenHarmony 6.1, API 23, QEMU/KVM) as the **`oniro` build product**. NearLink is unavailable in that product because NearLink Kit is HarmonyOS-only.

The same `main` branch builds both products:

| Product | Runtime | NearLink | Built with |
| --- | --- | --- | --- |
| `default` | HarmonyOS, target API 24, minimum API 20 | Real NearLink Kit adapter (`entry/src/harmonyos`) | DevEco Studio or DevEco CLI on Windows/macOS |
| `oniro` | OpenHarmony, API 23, minimum API 20, `deviceTypes: default` | Stub that reports "unsupported" (`entry/src/oniro`) | `oniro-app build --product oniro` on Linux |

The `oniro` differences live in `build-profile.json5` (product, target and signing entry), `entry/build-profile.json5` (`sourceRoots`) and the root `hvigorfile.ts`. For the `oniro` product only, `hvigorfile.ts` sets `deviceTypes` to `default` and drops `ohos.permission.ACCESS_NEARLINK` from the manifest. During that build hvigor still prints a warning that `phone` is not supported; the final HAP declares `default`.

Helper scripts are in `scripts/oniro/`. Paths can be overridden with `OHOS_SDK`, `HDC` and `ONIRO_IMAGES`.

## One-time setup

```bash
# QEMU core and the virtual GPU (no system upgrade; adds new packages only)
sudo pacman -S --needed qemu-base qemu-hw-display-virtio-gpu qemu-hw-display-virtio-gpu-pci

# Oniro emulator image
mkdir -p ~/oniro && cd ~/oniro
curl -LO https://github.com/eclipse-oniro4openharmony/device_board_oniro/releases/latest/download/oniro_emulator.zip
unzip oniro_emulator.zip
sed -i 's/0\.0\.0\.0/127.0.0.1/g' images/run.sh   # keep VNC and serial console local-only

# VNC viewer
flatpak install flathub org.remmina.Remmina

# Build tools: SDK in ~/setup-ohos-sdk, hvigorw/ohpm/hdc in ~/command-line-tools (no Huawei ID needed)
npm install -g @oniroproject/oniro-app
oniro-app sdk install 6.1
oniro-app cmdtools install

# In the repository
cd <path-to>/SafeMesh
scripts/oniro/sign.sh                        # OpenHarmony debug signing for the oniro product
node scripts/prepare-demo-authority.mjs      # local exercise issuer key and activation code
node scripts/generate-demo-alerts.mjs --update-public-key   # pins this machine's issuer key in the app
```

**Signing:** use `scripts/oniro/sign.sh`, not `oniro-app sign .`. `oniro-app sign` writes a signing entry for **every** product, so the HarmonyOS product would also get the OpenHarmony key and stop installing on the DevEco emulator. `sign.sh` copies the public SDK keystore (`OpenHarmony.p12`) and creates `app1-profile.p7b` from the committed profile template. Both files are git-ignored. The committed `signatures/` files and the encrypted passwords in `build-profile.json5` belong to the public OpenHarmony SDK debug key (password `123456`), not to a private release key.

**Issuer key:** `--update-public-key` rewrites `DemoTrust.ets` and `DemoAlerts.ets` with this machine's exercise key. Keep those changes local and do not commit them, because the pinned key must match the issuer key of the machine that runs the shared demo.

## Every session

```bash
scripts/oniro/emulator.sh A        # terminal 1: keep it running; boot takes about a minute
scripts/oniro/emulator.sh B        # optional, terminal 2: second node (created on first run)
scripts/oniro/emulator.sh C        # optional, terminal 3: third node
scripts/oniro/deploy.sh            # sign if needed, build --product oniro, install and launch on every running node
scripts/oniro/services.sh start    # mesh hub (8765) + exercise authority (8768) + port forwards for every running node
```

| Node | hdc target | VNC (Remmina, protocol VNC) | In-emulator hub port | Issuer port |
| --- | --- | --- | --- | --- |
| A | `127.0.0.1:55555` | `127.0.0.1:5900` | 8765 | 8768 |
| B | `127.0.0.1:55556` | `127.0.0.1:5901` | 8766 | — |
| C | `127.0.0.1:55557` | `127.0.0.1:5902` | 8767 | — |

B and C get their own image folders (`~/oniro/instance-B`, `~/oniro/instance-C`) with a fresh `userdata.img` from `oniro_emulator.zip`. The read-only images are copied with `--reflink=auto`. Start emulators before `deploy.sh` and `services.sh`; both skip nodes that are not running.

In each app, open **Relay / Łączność**, choose its node (**A**, **B** or **C**) and tap **Connect / Połącz**. The hub links only A–B and B–C, the same as on Windows (`node scripts/mesh-lab-control.mjs links AB BC` changes it).

## Sending an alert

```bash
node scripts/oniro/send-alert.mjs "Tytuł" "Treść komunikatu" "Kraków" critical
```

The local authority signs the alert and the hub delivers it. Severity is `info`, `warning` or `critical`. The alert is in Polish and valid for 60 minutes. Receiving apps must be connected and in the foreground.

- **One emulator (A):** the script connects as a fake emulator B and sends the alert to A.
- **Three emulators (A, B, C):** the hub has no free node, so it injects the alert as A → B. B verifies it and relays it to C.
- Override the direction with `FROM=C TO=B node scripts/oniro/send-alert.mjs ...`.

The script needs only Node and the running hub and issuer, so it also works with the three DevEco emulators on Windows. It was checked there on 2026-10-04: injected as A → B, B received it at hop 1 and relayed it to C at hop 2.

To publish from the app instead: Settings → **Tests and diagnostics / Testy i diagnostyka** → **Exercise authority / Nadawca ćwiczeń**. The activation code is in `.cache/demo-authority/session-token.txt`. Do not share it or commit it.

## Other commands

```bash
scripts/oniro/services.sh status   # listening ports and port forwards
scripts/oniro/services.sh stop     # stop the hub and the authority
node scripts/mesh-lab-control.mjs state   # hub routes and counters
tail -f .cache/oniro/hub.log .cache/oniro/authority.log

HDC=~/setup-ohos-sdk/linux/23/toolchains/hdc
$HDC list targets
$HDC shell "hilog -x | grep SAFEMESH | tail -20"   # app logs
$HDC shell snapshot_display -f /data/local/tmp/s.jpeg && $HDC file recv /data/local/tmp/s.jpeg .
```

## Troubleshooting

- **Connect fails with "service is not running":** run `scripts/oniro/services.sh start`.
- **"A is not connected to the hub":** restarting the hub drops the app's connection. Tap **Connect / Połącz** again.
- **`hdc` shows no target:** the emulator is still booting. Wait, then run `$HDC tconn 127.0.0.1:55555`.
- **`build-profile.json5` changed after signing:** someone ran `oniro-app sign .`. Restore it with `git checkout -- build-profile.json5` and use `scripts/oniro/sign.sh`.

## Removing everything

```bash
scripts/oniro/services.sh stop
sudo pacman -Rns qemu-base qemu-hw-display-virtio-gpu qemu-hw-display-virtio-gpu-pci
npm uninstall -g @oniroproject/oniro-app
rm -rf ~/oniro ~/setup-ohos-sdk ~/command-line-tools
flatpak uninstall org.remmina.Remmina
```
