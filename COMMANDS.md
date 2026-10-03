# Running SafeMesh on Linux (Oniro emulator)

The DevEco Studio emulator is available only on Windows and Apple Silicon macOS. On Linux, SafeMesh runs on the **Oniro emulator** (OpenHarmony 6.1, API 23, QEMU/KVM) as an OpenHarmony build. NearLink is unavailable in that build because NearLink Kit is HarmonyOS-only.

Helper scripts are in `scripts/oniro/`. Paths can be overridden with `HDC` and `ONIRO_IMAGES`.

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

# In the repository: OpenHarmony debug signing and the local exercise authority key
cd ~/Repozytoria/safemesh
oniro-app sign .
node scripts/prepare-demo-authority.mjs
node scripts/generate-demo-alerts.mjs --update-public-key   # pins the new public key in the app
```

The OpenHarmony build needs the project changes on the `oniro` branch: `runtimeOS: "OpenHarmony"`, API 23, `deviceTypes: ["default"]`, hvigor `modelVersion` 5.1.0 and a stub `NearLinkTransport.ets`.

## Every session

```bash
scripts/oniro/emulator.sh          # terminal 1: keep it running; boot takes about a minute
scripts/oniro/deploy.sh            # build, install and launch the app
scripts/oniro/services.sh start    # mesh hub (8765) + exercise authority (8768) + port forwards
```

View the screen in Remmina: protocol **VNC**, address `127.0.0.1:5900`.

In the app, open **Łączność**, choose **A** and tap **Połącz**.

## Sending an alert

```bash
node scripts/oniro/send-alert.mjs "Tytuł" "Treść komunikatu" "Kraków" critical
```

The script acts as emulator B: the local authority signs the alert, the hub delivers it to A, and A verifies, stores and acknowledges it. Severity is `info`, `warning` or `critical`; the alert is in Polish and valid for 60 minutes. A must be connected and in the foreground.

To publish from the app instead: Settings → **Testy i diagnostyka** → **Nadawca ćwiczeń**. The activation code is in `.cache/demo-authority/session-token.txt`. Do not share it or commit it.

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
- **"A is not connected to the hub":** restarting the hub drops the app's connection. Tap **Połącz** again.
- **`hdc` shows no target:** the emulator is still booting. Wait, then run `$HDC tconn 127.0.0.1:55555`.

## Removing everything

```bash
scripts/oniro/services.sh stop
sudo pacman -Rns qemu-base qemu-hw-display-virtio-gpu qemu-hw-display-virtio-gpu-pci
npm uninstall -g @oniroproject/oniro-app
rm -rf ~/oniro ~/setup-ohos-sdk ~/command-line-tools
flatpak uninstall org.remmina.Remmina
```
