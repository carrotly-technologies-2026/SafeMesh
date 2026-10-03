# HarmonyOS UI upgrade

## Scope and routing

The UI audit found undersized controls, missing semantics on custom navigation, limited accessible map alternatives, forced light mode, hardcoded English copy, and an emergency alert placed below promotional content.

Implementation uses the ArkUI development, scenario and MVVM skills. Route: REQ → DEV → VAL, primary ARKUI-02; component-page-building and text-component secondary scenes. The existing V1 `@Component`, `@State`, `@Observed` and `@ObjectLink` architecture is preserved. Presentation-only language/search/window state remains in the page; point persistence/location and relay state remain in their ViewModels.

Skill references read: `hmos-arkui-scenario-development/references/arkui-02-route.md`, `component-page-building-scenario-development.md`, `text-component-scenario-development.md`, `hmos-arkui-mvvm-pattern/references/v1-nested-observation.md`, and the ArkUI style guide.

## Focused API evidence

- **Components:** Installed DevEco documentation `ide_touch-target-size` specifies 48×48 vp recommended, 40×40 minimum. FAQ `faqs-arkui-307` confirms the default touch region equals component bounds. Interactive buttons now have minimum 48 vp targets. Multiline button content uses native `Button` + `Text` with minimum rather than fixed height.
- **Accessibility:** DevEco guide `arkts-universal-attributes-accessibility` documents labels, native/control roles, selected state and explicit announcements. Installed API24 `ets/component/common.d.ts` verifies `accessibilityText`, `accessibilitySelected(boolean)` (API13), and `accessibilityLevel`. `@ohos.accessibility.d.ts` verifies `sendAccessibilityEvent(EventInfo): Promise<void>` and `announceForAccessibility` with `textAnnouncedForAccessibility` (API12). No elevated permission is requested.
- **State:** Installed skill V1 observation reference verifies `@Observed`/`@ObjectLink` for nested map state. `@Watch` is used for alert/result announcements and Canvas revision/theme redraws. AppStorage contains only shared system configuration values needed by the page and custom Canvas.
- **Language:** SDK24 `@kit.LocalizationKit` exports `resourceManager`. `getConfigurationSync`, `getOverrideResourceManager(Configuration)` (API12), and `getStringByNameSync` provide deterministic PL/EN resource lookup. `ApplicationContext.setLanguage(string)` (API11) updates platform/permission resource language. The selected language is persisted; the Kraków demo starts in Polish.
- **Theme/configuration:** `ApplicationContext.setColorMode(COLOR_MODE_NOT_SET)` follows system appearance. `UIAbility` inherits `Ability.onConfigurationUpdate(Configuration)`; configuration exposes `colorMode` and `fontSizeScale`. Light/dark semantic colors are resource-backed. Canvas resolves current colors via `getColorByNameSync`; configuration changes trigger a redraw.
- **Layout:** [Huawei layout foundations](https://developer.huawei.com/consumer/cn/doc/doccenter-ux-design/design-layout-basics-0000001795579413) cover font-size, orientation and window adaptation. Installed guide `arkui-support-for-aging-adaptation` requires non-overlapping, untruncated content at 1.75×+ font scale. Text and button labels wrap without fixed text heights; navigation changes to two rows for large fonts or narrow windows, the page width is capped at 720 vp, and short windows use a shorter map.

## Resulting behavior

The signed alert or no-current-alert state is first on Home. Exercise labeling remains explicit. The primary workflow stays available without connectivity.

Navigation uses native buttons with labels, selected semantics and adequate targets. All 40 map points are available as searchable native buttons with address, availability and distance. The visual Canvas is excluded from screen-reader traversal because these controls provide the equivalent actions. Tap selection uses a click recognizer so scrolling over the map does not select a point on touch-up.

Optional device position is a one-time foreground measurement. Demo origin, device fix, accuracy, denied permissions and outside-pack conditions are distinguished. Distances remain straight-line; no walking route or live access guarantee is implied. Saved-point badges reflect the ViewModel's confirmed durable state.

Polish and English product copy is stored in resources. Signed message content is displayed unchanged in its original language. Technical diagnostic output also keeps its original language and is labelled accordingly. This avoids presenting translated content as if it were the signed bytes.

Native alert and drill-result announcements are implemented. The app stops its foreground relay when its page is hidden. Real relay queue metrics explicitly describe receiving-application acknowledgements, not human reads or authenticated peer identity.

## Validation handoff

Root owns integrated ArkTS/lint/build, installation, screenshots and final commit. Required device checks: light and dark appearance (including map), immediate PL/EN switch and preference restoration, native navigation selected state, all-point search, save failure/restoration, optional location denial/success/outside-pack, 1.75× and 2× font, narrow/landscape layout, alert priority and six-check drill.

Do not claim screen-reader certification from metadata inspection. Actual screen-reader reading order and announcements still require an enabled screen-reader session. Physical NearLink tests remain separate from emulator UI checks. This change is an implementation of identified improvements, not certification against every HarmonyOS/AppGallery requirement.

## Contrast and localization follow-up

The resource palette was checked against the actual text/background combinations in `Index.ets`, using linearized sRGB relative luminance and `(Llighter + 0.05) / (Ldarker + 0.05)`. [W3C contrast guidance](https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html) uses 4.5:1 for ordinary text and 3:1 for large text. This is a useful numerical check, not an assertion of full HarmonyOS or WCAG certification. The table covers normal active states; disabled controls and system-generated pressed/focus states were not evaluated here.

| Text / background | Light | Dark |
| --- | ---: | ---: |
| ink / paper | 10.89:1 | 15.13:1 |
| ink / surface | 11.86:1 | 12.77:1 |
| ink / soft | 9.77:1 | 10.09:1 |
| ink / warning background | 10.04:1 | 10.99:1 |
| muted / paper | 6.71:1 | 10.37:1 |
| muted / surface | 7.31:1 | 8.76:1 |
| muted / soft | 6.02:1 | 6.92:1 |
| muted / warning background | 6.19:1 | 7.53:1 |
| warning text / warning background | 6.15:1 | 8.89:1 |
| success / warning background | 6.02:1 | 8.74:1 |
| error / surface | 6.67:1 | 9.03:1 |
| action foreground / action background | 10.96:1 | 11.31:1 |

All tested active application text pairs exceed 4.5:1. The map's painted district labels now use a small opaque `map_land` backing, added after the audit found that bare text over water or roads could fall below 4.5:1. The actual label pair is therefore `map_label` / `map_land`: **6.14:1 light, 9.63:1 dark**, independent of underlying geometry. This uses the existing Canvas `fillRect` operation and adds two rectangle fills without increasing the stroke count. Location names and actions also have the separate accessible native point list. The selected-map-marker plus sign passes at 8.56:1 light and 11.31:1 dark.

Resource inventory after the operational-status fix and dedicated Settings addition: `base`, `pl`, and `en` each contain **150 unique, non-empty keys**, with identical key sets; base content matches Polish. All literal `this.t(...)` keys, all six non-demo location states, all five persistence states, and all fifteen hardware states resolve in every language. Language-dependent builder labels and enabled states are evaluated through getter callbacks to avoid stale V1 builder values.

Operational strings are localized: save/restoration success or failure, unsupported/off/available NearLink, permission denial, discovery, stop, queue/wait states and normal error summaries. `AlertViewModel.persistenceState` and `RelayViewModel.hardwareState` are stable presentation keys; the previous English diagnostic fields remain for tests and troubleshooting. Detailed English radio errors appear only under an explicit technical-result label.

The English text that intentionally remains visible is different: the original signed alert title/body is displayed unchanged and explicitly labelled as original signed content; simulated protocol test events/results are marked technical diagnostics. Map addresses, district names, peer device names, licence names and attributions retain their source/proper names. Known PSP availability values are translated. Unknown future source availability values would retain the source text rather than invent a translation.

Alert issue/expiry timestamps now display unambiguous `YYYY-MM-DD HH:mm UTC`, independent of the emulator's regional M/D date format. Signed timestamp values are unchanged. Resource and source inspection checks passed; native switching, font scaling, appearance and screen-reader validation are reported separately by the root agent.

Root confirmed native Polish/English switching, including dynamic builder button labels. Final source changes include localized operational states, UTC timestamps and opaque map-label backings; these require the root's next integrated build before their native behavior is claimed as verified.

## Native checkpoint and dedicated Settings

The installed build preceding the dedicated Settings tab was checked on the API24 emulator in Light and Dark. Native screenshots and layout dumps are stored as `artifacts/screenshots/v11-final-light-home.*`, `v11-final-light-map.*`, `v11-final-dark-home.*`, and `v11-final-dark-map.*`. The signed alert, localized saved-signature state, UTC expiry, map, colors and navigation rendered correctly in those captured views. This was a native UI check, not a screen-reader or physical NearLink test.

The system's Huge text preset was selected and Senior mode was cancelled. `v11-final-settings-huge-after.json` confirms Huge. That checkpoint exposed a real configuration omission: text did not scale because the app lacked the global font-following profile. It is therefore not recorded as a successful enlarged-font test. Light and Normal were restored and SafeMesh returned to Polish Home before the next source changes.

The user then requested a dedicated Settings tab. `tab4` now contains explicit System/Light/Dark choices (`themeSystem`, `themeLight`, `themeDark`) and Polski/English choices (`languagePl`, `languageEn`). The header language shortcut and Guide settings section have been removed. `ui_theme` and `ui_language` persist independently; controls remain disabled during initial preference restoration and while a write is pending. Successful changes use selected semantics and a brief accessibility announcement without inserting a layout-shifting notice. Failed application or persistence is described explicitly.

The saved theme preference is separate from the effective configuration. System mode uses `COLOR_MODE_NOT_SET`; configuration callbacks update effective appearance and a Canvas revision, not the preference. Normal phone navigation has five native buttons in one row, 12 fp labels and minimum 48 vp targets. The label size was reduced from 13 fp after the native Polish Settings label wrapped its last letter. Large-font/narrow navigation uses three rows to preserve readable labels.

The installed official guides `arkui-support-for-aging-adaptation`, `faqs-ability-166`, and `faqs-ability-144` establish that system font scaling is opt-in. `AppScope/app.json5` now references `AppScope/resources/base/profile/configuration.json` with `fontSizeScale: "followSystem"` and `fontSizeMaxScale: "2.0"`. No imperative `setFontSizeScale` override is used. The configuration logger records only font scale/color mode as `SAFEMESH_UI_CONFIGURATION` so native testing can report the actual scale instead of inferring it from a slider index. This profile and the new Settings tab need the root's integrated build and native validation.

Build schema correction: API 24 PreBuild rejected fontSizeMaxScale value 2.0 (00303038); the reported enum accepts the exact string 2. Changed the profile accordingly before rebuilding. ArkTS and lint had already passed; they do not validate this profile enum.

Final native map review found district text was sized in physical pixels while its backing used vp. District labels now explicitly use `bold 11vp sans-serif`, with backing width derived from `measureText(label).width + 8` and an 18 vp height. The official [Canvas font and measurement reference](https://github.com/openharmony/docs/blob/master/en/application-dev/reference/apis-arkui/arkui-ts/ts-canvasrenderingcontext2d.md#font) permits both `px` and `vp` font units; the default context uses vp. Installed API24 `ets/component/canvas.d.ts` declares `measureText` at line 4906 and `font` at line 5043. Only the host Canvas mock gained a `measureText` stub; it does not prove native typography. The root's next native screenshot validates the final painted result.

## Requested navigation refinement: native symbols and header settings

The final navigation replaces the five-button checkpoint with four bottom destinations (Home, Map, Relay, Guide), each with a native `SymbolGlyph` and localized label. Settings opens through the 48 vp `openSettings` gear at the top right. In Settings, the bottom bar is hidden and `backSettings` plus native `onBackPress` return to the previously selected destination. Labels still scale with the system; decorative icons retain a 24 fp base size capped at scale 1, and the owning buttons provide localized accessibility text. Large-font/narrow layouts use two rows of two destinations. Resources now contain 152 matching unique keys in base/pl/en.

Focused API evidence before coding: the installed `symbolglyph.d.ts` confirms `SymbolGlyph(Resource)` at line 75, `fontSize(number | string | Resource)` at 1012, `fontColor(Array<ResourceColor>)` at 1042, and API18 `maxFontScale` at 1256. `common.d.ts:30734` confirms `@Entry.onBackPress(): void | boolean`; true consumes Back and false retains normal system behavior. The devecocli document `API参考/ArkUI_方舟UI框架/ArkTS组件/文本与输入/SymbolGlyph/ts-basic-components-symbolglyph` verifies component behavior and system resource usage. V1 state rules were checked in the ArkUI skill's `references/quick-rules/03-state-v1.md`; existing `@State tab` controls rendering, and an ordinary numeric field retains the previous destination without introducing V2 state.

All six symbol names were verified against the installed API24 resource registry `ets/build-tools/ets-loader/sysResource.js`: `sys.symbol.house` (3651), `map` (4306), `phone_transmission_phone` (4148), `book` (4053), `gearshape` (3611), and `arrow_left` (4797). SDK metadata reports API24/ETS6.1.1.125. The implementation uses these exact resources, with `fontColor([INK])` for light/dark adaptation. Native rendering and Back behavior require the root's integrated check/build and device pass after this source change.
