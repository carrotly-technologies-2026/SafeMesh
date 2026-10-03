# SafeMesh readiness and HarmonyOS UX audit

2026-10-03. Scope: source review, existing native screenshots/test evidence, official Huawei design documentation and the hackathon challenge. This is a development audit, not Huawei certification or a complete accessibility/security assessment. No application behavior was changed during this audit.

## Assessment

SafeMesh is a working native ArkTS/ArkUI emulator prototype. It is not a complete operational emergency-warning system and cannot yet be described as fully aligned with all HarmonyOS UX guidelines. Forty host tests and six native drill checks establish the particular behaviors documented in [VALIDATION.md](VALIDATION.md); they do not measure all product requirements or design compliance.

The visual identity is coherent, but conformity involves accessible interaction, meaningful information hierarchy, system settings, readable typography and adaptation to the supported device configurations. Custom branding and a custom tab bar are not inherently prohibited. Native Tabs, system symbols and resource tokens are useful implementation choices, not blanket requirements to copy Huawei's visual appearance. The manifest targets phones; tablet/PC support is not automatically required.

## Concrete fixes and validation gaps

| Priority | Finding | Evidence and next action |
| --- | --- | --- |
| High | Touch targets too small | Map controls at `Index.ets:161–165` are 36×36 vp; Explore at line122 is 34 vp high. No expanded response region exists. Huawei's installed touch-target guidance recommends48×48 vp and sets40×40 vp as the lower bound. Enlarge the targets and verify native hit areas. |
| High | Incomplete accessibility | Custom clickable Columns lack explicit roles/selected-state semantics. Icon-only controls lack action labels. Map Canvas exposes no semantic points; only8 of40 points appear in the text list (`Index.ets:183`). Provide equivalent access to all points, meaningful labels/states and appropriate alert announcements; test with the screen reader. |
| High, product judgment | Active alert is below a large slogan and map | `Index.ets:93–140`, `screenshots/home-final.png`. Put current emergency information and its next action before promotional copy. This prioritization is an assessment of this app's purpose, not a quoted mandatory Huawei rule. |
| Medium | Light mode is forced | `EntryAbility.ets:25` sets `COLOR_MODE_LIGHT`; colors are hardcoded. Add theme resources and respect the user's system setting. The dark resource folder alone does not fix the app. |
| Medium | Large text and responsive layouts unverified | Many8–11 fp labels, fixed line heights and a14 vp navigation-label height (`Index.ets:308`). Verify1.75×/2× text, narrow phone windows, landscape and supported split-screen configurations. This is a risk from source review, not a reproduced clipping failure in those configurations. |
| Medium | Readability/contrast | Calculated inactive navigation contrast `#8D9A8F` on white is about2.94:1; muted text `#65776C` on `#E4ECD9` about3.92:1. Rework secondary text colors and verify relevant contrast thresholds. These ratios alone do not establish AppGallery rejection. |
| Medium | No Polish interface localization | Most UI strings are hardcoded English while source addresses/availability are Polish. Move copy into resources and add Polish/English variants for the intended audience. |
| Medium, functional defect | Save badge can claim success after a failed save | `Index.ets:56–58` assigns `savedId` before awaiting storage. An error notice appears on failure, but the button can still read “Saved on this phone.” Commit UI state after successful persistence or roll it back on failure. Also provide a clear way to reopen the saved point. |

Successful current behaviors include actual native components, clear exercise labeling, consistent visual hierarchy, visible data attribution, native signature checks, marker selection, persistence and adequate status/gesture-area spacing on the tested emulator.

## Functional scope still outstanding

- **Physical NearLink:** only an in-process relay simulation was exercised. The native adapter still needs compatible-device validation, including permission/radio state, discovery, MTU framing, interruption and multi-device forwarding.
- **Mesh behavior:** current API24 discovery requires the other device's exact name and a selected connection. There is no automatic discovery of every nearby participant. `RelayViewModel.sendToPeer()` sends one currently selected alert on a new connection; it does not synchronize the full set of older still-valid messages. Add queue synchronization, retry/acknowledgement policy and measured duplicate/traffic controls for a broader mesh claim.
- **Lifecycle:** continuous background/locked-screen delivery, battery behavior and recovery from interruptions are not implemented or demonstrated.
- **Authority:** the trusted signer is a demo issuer only. Official alerts, issuer operations, key rotation/revocation and trusted-time policy are absent. Signatures do not prevent radio jamming or message dropping.
- **Maps:**40 real PSP reference points and vector data are bundled. Location is a labelled demo origin. There is no live GPS, route planning, in-app regional pack download/update, or live verification of protective-point access. Bundling does satisfy first-launch offline availability, but not a full map-download product flow.
- **Distribution:** the current unsigned HAP was accepted by the emulator. Physical-phone signing and AppGallery readiness were not validated.

## Hackathon deliverables

The challenge explicitly allows an emulator demonstration and does not require physical NearLink proof when hardware limitations are honestly disclosed. The native crypto, storage and UI demonstrate actual platform use. Minimum API20 / target24, source, HAP, setup/build/run instructions, architecture explanation and AI disclosure are present.

Still required before submission:

1. **Public source repository.** The user has currently authorized local Git commits only. Local Git and a ZIP do not fulfill the public-repository requirement.
2. **Brief recorded demonstration.** Screenshots and a written walkthrough exist; a video has not been recorded.

Additionally, a clean build on another machine would strengthen reproducibility evidence. Neither a Conductor project nor the supplied full project template is a mandatory requirement for this native app.

## Sources and verification basis

- [Huawei HarmonyOS NEXT design overview](https://developer.huawei.com/consumer/en/design/): components, UX standards, design resources and adaptation.
- [Huawei app planning and quality](https://developer.huawei.com/consumer/cn/app/planning).
- [Huawei layout foundations](https://developer.huawei.com/consumer/cn/doc/doccenter-ux-design/design-layout-basics-0000001795579413): orientation, font size and window-size adaptation.
- Installed official DevEco documentation read by the design auditor: `ide_touch-target-size`, `faqs-arkui-307`, `arkts-universal-attributes-accessibility`, `arkui-support-for-aging-adaptation`. Some web pages did not expose full content; the bundled official documentation provided the specific touch/accessibility/large-text guidance.
- [Challenge requirements](https://github.com/onirodeveloper/hackyeah2026-challenge/blob/main/hackathon_challenge.md), also inspected in the local challenge checkout: required deliverables, technical requirements and evaluation criteria.
- Local source: `entry/src/main/ets/pages/Index.ets`, `entryability/EntryAbility.ets`, `views/OfflineMap.ets`, `viewmodel/RelayViewModel.ets`, `viewmodel/AlertViewModel.ets`; [native validation record](VALIDATION.md).

Recommended order: fix misleading save state and alert priority; accessibility/touch/text; theme/localization/adaptation; broader relay behavior; device testing; recorded demo and eventual publication.
