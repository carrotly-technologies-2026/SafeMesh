# SafeMesh hackathon submission

Copy the sections below into the submission form. The project is a working native HarmonyOS emulator prototype; physical NearLink exchange is the next validation milestone.

## Problem

When mobile networks fail during a crisis, people can lose access to both emergency warnings and the information needed to act on them. An alert may tell someone to seek shelter without explaining where nearby protective locations are. Forwarded messages introduce another risk: recipients cannot easily tell whether the content has been altered. SafeMesh addresses these connected problems: keeping warnings accessible, checking their authenticity and providing practical offline reference information.

## Solution

SafeMesh is a native HarmonyOS application built with ArkTS and ArkUI. It combines digitally signed alerts, an offline map and a relay engine designed to pass verified messages between nearby phones. Every receiving device checks the issuer's signature before accepting or forwarding an alert. The bundled map covers central Kraków and contains 40 protective-point records published by Poland's State Fire Service (PSP), with address search and saved places. Polish and English interfaces and Light, Dark and System themes make the app adaptable to users' preferences. A NearLink adapter is implemented; the current emulator demonstrates relay logic through a clearly labelled simulation.

## Cover Image

Upload [SafeMesh-cover.png](artifacts/cover/SafeMesh-cover.png).

Suggested alt text: Three connected phones above a stylized city map, illustrating signed alerts, offline maps and nearby-device relaying.

The cover is a conceptual illustration generated with the built-in imagegen tool. It does not depict measured radio coverage or actual app screens. The [generation prompt](artifacts/cover/PROMPT.txt) is included for transparency.

## What's done so far and goal of the project

We have built and run a native HarmonyOS prototype with on-device signature verification, rejection of altered and expired alerts, duplicate suppression and persistent alert storage. It includes an offline Kraków map, search across all 40 bundled points, saved places, language settings and theme preferences. The relay engine includes cached-message synchronization, bounded retries and receiving-app acknowledgements. Validation includes 61 automated host tests, six native signature/relay checks and a recorded emulator demonstration.

Our next goal is a controlled trial on compatible physical phones: phone A passes an alert to B, A disconnects, and B later delivers it to C without internet. We then want to improve usability and work with public-safety organisations on trustworthy issuing and practical deployment. Physical NearLink exchange remains unverified. Current alerts are signed exercises, with no official RCB integration, and listed protective points do not guarantee current access or condition.

## Instructions on how to open the project

1. Extract `SafeMesh-source.zip` and open its `SafeMesh` folder in **DevEco Studio**. Select the folder containing `build-profile.json5` and `oh-package.json5`.
2. Use the tested toolchain: **DevEco Studio 6.1.1**, **Huawei HarmonyOS SDK API 24 including HMS kits**, **Node.js 24** and **DevEco CLI 1.3.4** with the organizer's patches. Complete the fresh-machine setup in [README](README.md#run-on-windows) if these are not installed.
3. Start an **API 24 phone emulator**. Open PowerShell in the extracted project folder and run the commands below, replacing the Studio path and device serial as needed.

```powershell
$env:DEVECO_CLI_STUDIO_PATH = 'C:\path\to\DevEcoStudio'
devecocli.cmd device list --format json
powershell -ExecutionPolicy Bypass -File scripts/run-demo.ps1 -Device '127.0.0.1:5555' -RefreshDrill
```

The helper refreshes the time-limited exercise fixtures, builds the HAP, installs it and launches the app. Use the actual serial printed by `device list`.

4. On **Home**, receive a signed exercise. Open **Map** to browse and search the offline points. On **Relay**, run the signed relay drill; the expected result is **6/6 checks passed**. Use the upper-right gear to change the language or theme. The default language is Polish; **Ustawienia → English** switches the interface.

The supplied `SafeMesh-demo.hap` is an unsigned debug package validated on the emulator. Physical phones require development signing and compatible NearLink hardware. The prebuilt exercise expires on **2026-10-06 at 15:19:32 UTC**; the refresh command above creates a new 72-hour exercise and rebuilds it.

## Files to attach

- `artifacts/cover/SafeMesh-cover.png` — cover image.
- `dist/SafeMesh-source.zip` — complete tracked source and documentation.
- `dist/SafeMesh-demo.hap` — emulator application package.
- `dist/SafeMesh-demo.mp4` — 90-second native emulator demonstration.
- `dist/SHA256SUMS.txt` — checksums for the three files in `dist` above.

Project authors: **Tomek and Hubert**. Development-tool assistance is documented in [AI_WORKFLOW.md](AI_WORKFLOW.md). The source has local commits; no public repository has been published.
