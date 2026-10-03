# Recording a native SafeMesh demonstration

The Windows helper records **live frames from the DevEco emulator window**. It uses Win32 `PrintWindow` on the visible `Emulator.exe` process and sends raw frames directly to FFmpeg. It does not capture desktop pixels, microphone audio, other Windows applications or a sequence of preselected screenshots. Open SafeMesh and keep the emulator on the app during the recording.

## Requirements and scope

- Windows, Python 3 and the existing DevEco Studio installation.
- No Python packages or internet download are required. The helper extracts FFmpeg/ffprobe and their DLLs from Studio's `plugins/harmony/lib/ffmpeg-*-windows-x86_64.jar` into ignored `.cache/recorder/`. These binaries are not source submission contents.
- It requires exactly one visible emulator window, or a process selected with `--pid`. It refuses generic windows and has no desktop capture fallback.
- Do not minimize, resize or rotate the emulator while recording. Size changes cause an explicit failure, leaving a `.partial.mp4` instead of a falsely completed demonstration.
- The output is silent H.264 video, 15 fps by default. It can capture UI motion and taps while another terminal drives the app with `devecocli ui`. It does not add a narration, captions or a claim of real NearLink transmission.

DevEco CLI 1.3.4's `ui` and `emulator` help expose screenshots and input interaction but no video recording command. The tested API 24 emulator has no `screenrecord` executable. Its `uitest uiRecord` records input events, not video. Consequently this helper uses a local Windows capture API rather than inventing an unsupported CLI command.

## Record

From the project directory, in one PowerShell terminal:

```powershell
$env:DEVECO_CLI_STUDIO_PATH = 'C:\Users\user\DevEcoStudio'
python scripts\record-demo.py --duration 90 --output dist\SafeMesh-demo.mp4
```

This default includes only the emulator client area, including its simulated phone frame and emulator controls. Existing videos are never overwritten; choose a new output filename when retrying. `--prepare-only` extracts the encoder without recording anything.

For the validated portrait window, whose client size is **591 × 1066 pixels**, crop to the phone display:

```powershell
python scripts\record-demo.py --duration 90 --crop 8,20,478,1030 --output dist\SafeMesh-demo.mp4
```

The crop is explicitly `left,top,width,height`, in emulator client pixels. It is **not universal**: omit it or measure it again after changing emulator window size, host DPI, skin or orientation. The helper checks that the crop remains within the window and aborts if the window changes size during capture.

In the second terminal, drive the demonstration with the documented DevEco CLI commands or interact with the emulator yourself. A suggested sequence is: accepted exercise and validity → offline map, selected point and access caveat → relay drill and six checks → unsupported emulator radio → preparedness guide. Keep the simulation and exercise labels visible. Use app element IDs from `devecocli ui layout`, because IDs can change with UI revisions.

After success, `dist/SafeMesh-demo.capture.json` records frame count, frame rate, dimensions, crop and timing. A slow capture is rejected if more than one second of frames miss their target by over 250 ms; reduce `--fps` if that happens.

Verify the resulting file with the extracted tool:

```powershell
.\.cache\recorder\ffprobe.exe -v error -select_streams v:0 `
  -show_entries stream=codec_name,width,height,r_frame_rate,nb_frames:format=duration,size `
  -of json .\dist\SafeMesh-demo.mp4
```

The helper never publishes the recording. A recording of this emulator remains evidence of native UI and cryptography, not evidence of physical NearLink transmission.

## Validation of the recorder

On 2026-10-03, the helper captured the existing native SafeMesh screen for three seconds. `ffprobe` reported H.264, 478 × 1030, 15 fps, 45 frames, 3.000 seconds. Capture timing reported zero late frames. A decoded frame was visually inspected and contained the phone screen, including SafeMesh, with no Windows desktop content. This smoke artifact lives only in ignored `.cache/recorder/`; the release demonstration must be recorded after final UI validation.

References: [Microsoft PrintWindow](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-printwindow) explains that the target application renders its window into the supplied device context; [FFmpeg rawvideo documentation](https://ffmpeg.org/ffmpeg-formats.html#rawvideo) documents explicit dimensions, pixel format and frame rate for live raw input.

## Reversible emulator display test setup

The following navigation was verified on the English API 24 emulator with a **1320 × 2856** device display. These coordinates are device pixels, unrelated to the Windows crop above. Record original settings before repeating the check. In this workspace the original values were Light / dark mode Off, text Normal, text weight Normal, display size Default and Senior mode Off.

The native Settings bundle exposes main ability `com.huawei.hmos.settings.MainAbility`. Launching a system Settings bundle is not supported by `devecocli run` (that command runs the current project), so the SDK launch command is used for this one operation:

```powershell
$hdc = Join-Path $env:DEVECO_CLI_STUDIO_PATH 'sdk\default\openharmony\toolchains\hdc.exe'
& $hdc -t 127.0.0.1:5555 shell aa start -b com.huawei.hmos.settings -a com.huawei.hmos.settings.MainAbility
devecocli.cmd ui click --device 127.0.0.1:5555 --id display_settings
```

Settings may resume its previous subpage; navigate back with the top-left button at **126,234** until the Settings home is visible, then select `display_settings`.

| Action in Display & brightness | Verified selector |
| --- | --- |
| Dark all day | `devecocli.cmd ui click --device 127.0.0.1:5555 955 1681` |
| Restore Light | `devecocli.cmd ui click --device 127.0.0.1:5555 365 1681` |
| Read current theme | `ui layout`; text node `Setting.Display.display_setting.dark_mode.result`: `All day` / `Off` |
| Open font controls | `ui click --id Setting.Display.screen_zoom.screen_zoom_mode` |
| Text size Huge | Font slider position **1100,1946**, value `5.000000` |
| Restore text Normal | Font slider position **460,1946**, value `2.000000` |
| Back to Display & brightness | **126,234** |

On first selecting Huge, Settings offered a Senior mode dialog. Dismiss it using `advanced_dialog_button_1` (Cancel). Senior mode also changes icon sizes and the home screen; it was inspected but never enabled. The Huge label and slider value were verified, but **the numeric app `fontSizeScale` was not obtained**, so the slider value `5` must not be reported as a 5× scale or as proof of ≥1.75×. The Settings preview's layout is deliberately kept stable while its sample content grows.

For screen-reader test setup, Settings home → `accessibility_feature`; the visible row ID is `Setting.Accessibility.visual_group.accessibility_screen_reader_entry`. ScreenReader remained Off during this setup inspection; discovering this menu is not an accessibility interaction test.

After this inspection, Normal text and Light mode were restored and verified in layout dumps; SafeMesh was returned to the foreground through `devecocli run --skip-build`, with `Smoke: PASS`. Read-only/inspection evidence is in ignored `.cache/recorder/settings-*.json` and `settings-huge.png`. These are setup observations of the old installed build, not final UI validation evidence.

## Clean-machine setup findings for the main README

The workspace's verified CLI is **`@deveco/deveco-cli@1.3.4`**, with two upstream hackathon patches already applied. A fresh installation should document both exact version installation and the challenge repository's verified patch procedure:

```powershell
npm.cmd install -g @deveco/deveco-cli@1.3.4
node <challenge-checkout>\scripts\apply-devecocli-patches.mjs
```

The patch script and its two JSON specifications must remain together inside the challenge checkout. The first patch fixes per-file linter diagnostics. The second disables the Windows memory sampler that previously caused command-runner instability. The script checks exact hashes and recognizes already patched installations. Do not substitute an unpinned `latest` version or apply the 1.3.4 patch to another version.

Source: the verified local challenge files `scripts/apply-devecocli-patches.mjs`, `patches/devecocli/1.3.4/001-lint-files-with-issues.json`, `patches/devecocli/1.3.4/002-disable-windows-memory-sampler.json` and its README. [Challenge repository](https://github.com/onirodeveloper/hackyeah2026-challenge).

Node **22 or later** is required by the CLI; this workspace was verified with Node **24.21.0** and npm **11.19.0**. The tests also use Node 24 features, so Node 24 is the project's documented choice. DevEco Studio **6.1.1.280** supplies the API 24 toolchain. Its bundled older Node should not replace the working Node 24 CLI runtime on PATH. A fresh machine still needs the selected SDK/system image, an emulator instance, accepted vendor agreements and host virtualization; those are prerequisite setup rather than HAP dependencies.
