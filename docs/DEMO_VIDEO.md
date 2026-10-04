# SafeMesh demo video

**2 min 58 s, 1080p, narrated, with burned-in captions and a separate `.srt` file.** Watch it on [YouTube](https://youtu.be/oJHTDktnwL4). The subtitles are attached to the [submission pack](https://github.com/carrotly-technologies-2026/SafeMesh/releases/tag/submission-1.6.0) as `SafeMesh-demo-1.6.0.srt`.

The demo part is one real, synchronized recording of three separate SafeMesh v1.6.0 apps on three HarmonyOS API 24 emulators, driven by a script. The opening, the diagram and the closing scenes are motion graphics. The map in them is drawn from the Kraków map pack that ships inside the app.

## Chapters

| Time | Chapter | What you see |
| --- | --- | --- |
| 0:00 | The problem | The real central-Kraków street map from the app's map pack. Illustrative cell towers go offline, and phones link up into a mesh. |
| 0:09 | SafeMesh | Title. The 40 protective points from the PSP dataset light up on the map. |
| 0:19 | How a warning travels | Diagram: the issuer signs, A verifies, B verifies, ACKs and relays, A leaves, C gets the alert at hop 2, and an altered copy is rejected. |
| 0:37 | Live demo | Three emulators side by side, unedited apart from the marked speed-ups (see below). |
| 0:48 | Everyone joins | A, B and C connect to the labelled local test link. Only A–B are in range. |
| 0:56 | The issuer | A signs in to the exercise-issuer console with an activation code (masked) and writes an English alert. Shown at 4.7×. |
| 1:10 | Hop 1 | B verifies the signature, saves and acknowledges the alert and shows a banner. The detail screen reads "Received from device A · Relay hops: 1". C has nothing. |
| 1:18 | A leaves | The test link changes to B–C only. |
| 1:21 | Hop 2 | C receives the alert from B: "Received from device B · Relay hops: 2". A and C were never connected. |
| 1:31 | Forged copy | A copy with changed text is injected towards C. C shows "Invalid signature rejected": no ACK, not stored, not forwarded. |
| 1:39 | Offline map | B searches `florianska` without Polish letters and finds the three protective points on ul. Floriańska, then opens one. |
| 1:53 | NearLink | A runs the NearLink capability check. The emulator has no radio and the app says "NearLink is unavailable on this device." |
| 2:04 | Platform | The HarmonyOS kits SafeMesh uses, and the second build product for OpenHarmony / Oniro. |
| 2:20 | Human-centric | Real screenshots in English and Polish, light and dark, from the [screen gallery](gallery/README.md). |
| 2:28 | Evidence | 177 host tests, 0 ArkTS errors, 0 lint issues, 17/17 native evidence assertions, and the check output. |
| 2:40 | What is real, what is next | What is simulated and labelled, and the next steps: NearLink on phones and background relaying. |
| 2:50 | End | The repository link and a QR code. |

## YouTube description (copy and paste)

```text
SafeMesh: verified emergency alerts that travel phone to phone when the mobile network is down.
Native HarmonyOS app (ArkTS + ArkUI), HackYeah 2026, Huawei "Imagine What's Next".
Three separate apps on three HarmonyOS API 24 emulators. A labelled local test link stands in for the NearLink radio. Narration is a synthesized voice.

0:00 The problem
0:09 SafeMesh
0:19 How a warning travels
0:37 Live demo: three emulators
0:56 The issuer publishes a signed alert
1:10 Hop 1: B verifies, stores and acknowledges
1:18 A leaves, B meets C
1:21 Hop 2: C receives it from B
1:31 A forged copy is rejected
1:39 Offline map and search
1:53 NearLink capability check
2:04 Built on HarmonyOS and OpenHarmony / Oniro
2:20 Polish and English, light and dark
2:28 Evidence
2:40 What is real, what is next

Code, HAP, pitch deck and every screen: https://github.com/carrotly-technologies-2026/SafeMesh
```

Add `SafeMesh-demo-1.6.0.srt` as English subtitles.

## What is real and what is simulated

| Real | Simulated, and labelled in the app and in the video |
| --- | --- |
| Three separate app processes on three API 24 emulators, recorded in one capture loop, so the timing between phones is real. | The radio: emulators have no NearLink, so a local WebSocket test link carries packets between the apps. It routes only A–B, then only B–C. It never signs, stores or acknowledges. |
| On-device ECDSA P-256 verification, storage, ACKs, the rejection of the forged copy, the map search and every screen. | The issuer: a local exercise signing service on the laptop, not RCB or any authority. Alerts are marked as exercises. |

The forged packet is derived by `scripts/mesh-lab-fixtures.mjs` from a genuine signed exercise alert by changing its text, and is injected by the test hub. Nothing in the app was changed for the recording.

## Edits

- **Speed-ups, always shown with an on-screen badge:**
  - 4.7× while A signs in and types the alert;
  - 10.4× while C opens the Relay tab;
  - 4.9× while B opens the map;
  - 3.2× while A scrolls to the NearLink check.
- **Holds:** the last frame is held while the final narration line ends.
- **Overlays:** device labels, the link state between phones, a moving dot for each packet, and short result chips. These follow the logged times of each step.
- **Unchanged:** the phone screens are not edited.

## Narration

The voice is synthesized, not a team member. It uses the **Kokoro-82M** text-to-speech model (Apache-2.0, voice `af_heart`), run offline on the laptop through `kokoro-onnx`. The script is [`scripts/demo-video/narration.json`](../scripts/demo-video/narration.json). The captions use the same text, with "Kraków" spelled the Polish way. Sound cues (a soft chime, a "verified" ping, a "rejected" buzz, a short whoosh for packets) and a very quiet background pad are synthesized from sine waves and noise in `render.py`. No music samples or third-party audio are used.

### Transcript

1. When a flood or a blackout takes down the mobile network, people lose the thing they need most: a warning they can trust.
2. This is SafeMesh: a native HarmonyOS app that carries signed emergency alerts from phone to phone, with no internet and no cell network.
3. An authorised issuer signs every alert. Each phone checks that signature before it shows, stores or forwards anything.
4. Phones pass alerts to whoever is in range, hop by hop, and confirm each delivery. Altered or expired copies are rejected.
5. Here it is, running on three HarmonyOS emulators. A local test link stands in for the radio: A can reach B, B can reach C, but A never reaches C.
6. Each phone joins the relay. Nobody presses send: verified alerts move on automatically.
7. On phone A, a signed-in exercise issuer writes an alert. The private key stays in a separate signing service; the app only gets the signed alert and verifies it on the device.
8. Phone B checks the signature, saves the alert, acknowledges it and shows a banner. C is out of range, so it has nothing yet.
9. Now A leaves, and B comes into range of C.
10. C receives the alert from B at hop 2. A and C never met. That's store-and-forward.
11. Next, someone injects a forged copy with changed text. C rejects it: no acknowledgement, not stored, not forwarded.
12. The map works offline too: 40 State Fire Service protective points in central Kraków ship inside the app, and search works even without Polish characters.
13. For real phones, SafeMesh includes a NearLink adapter for HarmonyOS's own short-range radio. The emulator has no radio, and the app says so.
14. SafeMesh is built on the platform itself: NearLink, the Crypto Architecture Kit, location, storage, accessibility and localization.
15. And the same code builds an OpenHarmony product for the open-source Oniro emulator.
16. It speaks Polish and English, follows dark mode and large text, and announces new alerts to screen readers.
17. Every claim is backed by evidence: 177 automated tests, zero compiler and linter issues, recorded native runs, and a build anyone can reproduce.
18. The radio between emulators is simulated, and clearly labelled. Next: NearLink on real phones, and relaying in the background.
19. SafeMesh. The network can fail. The warning still arrives.

## How it was made (and how to make it again)

Everything is scripted, in [`scripts/demo-video/`](../scripts/demo-video/):

```powershell
# 1. Narration (offline TTS; model files from the kokoro-onnx release, not in the repository)
pip install kokoro-onnx soundfile numpy pillow playwright imageio-ffmpeg
python scripts/demo-video/narrate.py --models <folder with kokoro-v1.0.onnx and voices-v1.0.bin>

# 2. The three-emulator run, recorded while the script drives it
#    (needs the setup from README "Publish a custom alert to three emulators")
python scripts/demo-video/drive.py --pids <A-pid> <B-pid> <C-pid>

# 3. The screen gallery (used in the "human-centric" scene)
python scripts/capture-gallery.py --device 127.0.0.1:5555 --peer 127.0.0.1:5557:B --peer 127.0.0.1:5559:C

# 4. Compose: timeline, frames, audio mix, H.264/AAC encode, captions
python scripts/demo-video/render.py --out dist/SafeMesh-demo-1.6.0.mp4
```

- **`narrate.py`** writes one WAV per line and their durations.
- **`drive.py`**:
  - clears the three apps and connects only A–B on the hub;
  - starts `scripts/record-mesh-demo.py`;
  - drives the phones with `uitest`, waiting for each narration line before the next step;
  - logs every step's time and saves full-resolution stills for the pitch deck.
- **`render.py`**:
  - turns the step times into a timeline: 1× where something happens, and compressed navigation with a badge;
  - draws the map pack as SVG;
  - renders [`scenes.html`](../scripts/demo-video/scenes.html) frame by frame in headless Edge through Playwright. Every visual is a function of the video time, so the output is deterministic;
  - mixes the narration and cues, normalizes loudness to −16 LUFS and encodes with FFmpeg (libx264, CRF 17, AAC 192 kb/s).

The run used for the release recorded 146.3 s at 15 fps with zero late frames. The activation code was typed into a masked field and never logged.
