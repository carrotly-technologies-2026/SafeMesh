# SafeMesh: hackathon submission

Paste-ready text for the HackYeah 2026 submission form. Challenge: **Huawei, “Imagine What’s Next”**. All jury-facing material is in English.

## Links

- Code repository: https://github.com/carrotly-technologies-2026/SafeMesh
- Release with the HAP and demo video: https://github.com/carrotly-technologies-2026/SafeMesh/releases/tag/v1.4.1
- Demo video file: https://github.com/carrotly-technologies-2026/SafeMesh/releases/download/v1.4.1/SafeMesh-1.4.1-demo.mp4 (the form asks for a YouTube link: upload this file as *Unlisted* or *Public* and paste that link)
- Cover image: [artifacts/cover/SafeMesh-cover.png](artifacts/cover/SafeMesh-cover.png). Alt text: *Three connected phones above a stylized city map, illustrating signed alerts, offline maps and nearby-device relaying.* The cover is a conceptual illustration generated with an image tool; its [prompt](artifacts/cover/PROMPT.txt) is included. It is not an app screenshot.

## Challenge area

**Human-Centric Technology** (lead) and **Spatial Experiences**. SafeMesh keeps trustworthy safety information available when mobile networks fail. Every phone verifies the issuer's signature, so forged or altered warnings are rejected. The UI is inclusive (PL/EN, dark mode, large text, screen-reader announcements) and privacy-preserving (location is never stored or relayed). The relay follows physical proximity, A → B → C, and an offline map shows nearby protective points.

## Problem

During a crisis, a mobile-network outage can cut people off from warnings and from the information they need to act on them. This is a documented risk: ITU's December 2022 interim assessment of Ukraine reported that almost 11% of mobile operators' base stations were out of service. Forwarded messages add a second problem, because recipients cannot tell whether the text was altered. People need warnings they can trust and local protective-point information that works without connectivity.

## Solution

SafeMesh is a native HarmonyOS app built with ArkTS and ArkUI. An authenticated issuer publishes a signed alert, and phones pass it on to nearby phones that are in range. Each phone verifies the ECDSA P-256 signature on the device, with a pinned public key, before it stores, displays, acknowledges or forwards the alert. Altered, expired and duplicate packets are rejected or suppressed. A phone that received an alert keeps it and later hands it to phones that were never in range of the issuer (store-and-forward, with app-level ACKs and bounded retries).

The app also bundles an offline map of 40 State Fire Service (PSP) protective points in central Kraków, with search and a saved place. It offers Polish and English, light and dark themes and large-text support.

The NearLink (星闪) radio adapter is implemented with NearLink Kit. On emulators, which have no radio, a clearly labelled local test link connects three separate app processes.

## What's done so far and goal of the project

Before the event, nothing existed; the whole project was created at HackYeah on 3–4 October 2026, with AI coding agents disclosed in AI_WORKFLOW.md.

Done and demonstrated on three API 24 emulators (release v1.4.1):
- Authenticated exercise-issuer console and signed custom alerts.
- Automatic relay A → B → C, with C receiving at hop 2 after A has left.
- App ACKs with retries, and rejection of forged content.
- Inbox with unread state that survives restarts.
- Offline PSP map with search.
- PL/EN, light/dark and large-text support.

Evidence: 168 automated host tests, a clean ArkTS check and Code Linter, 17/17 assertions over recorded native evidence for the v1.4 multi-emulator scenario, and a captioned demo video of the final build.

Next step: the first physical NearLink test on HarmonyOS phones, following docs/PHYSICAL_TESTING.md. After that: background relaying with the API 26 NearLink continuous-task mode, and work with public-safety organisations on authorised issuing and data maintenance.

Current limits, stated in the app and README:
- Alerts are signed exercises, with no official RCB integration.
- Relaying works while the app is in the foreground.
- Map records do not confirm current access.

## Instructions on how to open the project

1. **Quickest check, install the prebuilt HAP.** Start any API 20+ HarmonyOS phone emulator in DevEco Studio, download `SafeMesh-1.4.1.hap` from the release, then run:
   ```powershell
   $hdc = Join-Path $env:USERPROFILE 'DevEcoStudio\sdk\default\openharmony\toolchains\hdc.exe'
   & $hdc list targets
   & $hdc -t <serial> install -r .\SafeMesh-1.4.1.hap
   & $hdc -t <serial> shell aa start -b org.safemesh.alerts -a EntryAbility
   ```
2. **Build from source.** Clone the repository and open it in **DevEco Studio 6.1.1** with the **HarmonyOS SDK API 24 including HMS kits** (NearLink Kit is not in a plain OpenHarmony SDK). Install **Node.js 24** and **DevEco CLI 1.3.4** with the organizers' patches, following README → *Run on Windows*. Then run `.\scripts\check.ps1 -Build` (tests, ArkTS check, lint, build) and `.\scripts\run-demo.ps1 -Device <serial>` (build, install, launch).
3. **Single emulator, about 2 minutes.**
   - The app starts in English on a non-Polish system; the gear icon switches PL/EN.
   - Gear → Tests and diagnostics → **Load exercise message**, then open it from the banner.
   - **Map**: search "Bracka" and open a point.
   - **Run verification test**: expect 6/6 checks.
   - **Check NearLink support**: the emulator reports no radio.
4. **Three emulators with a custom alert.** Follow README → *Publish a custom alert to three emulators*. `scripts/start-authority-demo.ps1` starts the local issuer and test hub and installs the same HAP on A, B and C.

The bundled exercise fixture is valid until **2026-10-06 19:57:54 UTC**. Custom alerts carry their own 15-minute to 24-hour validity. README → *Refresh an expired exercise* regenerates the fixture.

## Files

- `SafeMesh-1.4.1.hap`, `SafeMesh-1.4.1-demo.mp4` and `SafeMesh-1.4.1.sha256.txt`, attached to GitHub Release v1.4.1.
- `artifacts/cover/SafeMesh-cover.png`: cover image.

Built by the SafeMesh team at HackYeah 2026. AI-assisted development is documented in [AI_WORKFLOW.md](AI_WORKFLOW.md).
