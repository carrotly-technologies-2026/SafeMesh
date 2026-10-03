# SafeMesh 1.3 interface work

REQ / DEV / FIX / VAL: ARKUI-02 component page layout with ARKUI-03 / MVVM-01 state observation. Preserve the existing V1 `@State` + `@Observed` architecture and single-page destination/back conventions.

## Screen responsibilities

- Start: current verified alert, saved place entry and connection status. No map preview. With no valid alert, the primary action opens Relay; exercise loading belongs to Diagnostics.
- Map: the only map, address search, map/list choice and point selection. Selecting a marker or row opens a dedicated detail destination; Back preserves the search.
- Relay: actual connection state, role, neighbors and delivery state. Emulator transport is clearly identified. Protocol tests live under Settings / Diagnostics.
- Guide: four short expandable sections, with source links and trust details under Settings.
- Settings: grouped appearance and language choices, diagnostics and data provenance. Native symbols, 48 vp touch targets and system text scaling remain.

The visual hierarchy uses compact page titles, one alert surface, plain list rows, separators and a restrained green accent. No duplicated large disclaimer panels, promotional headings or decorative metrics.

## Evidence before implementation

- Components: `hmos-arkui-scenario-development/references/component-page-building-scenario-development.md`: linear settings rows, native Column/Row/Scroll/List primitives and flexible text allocation.
- State: `hmos-arkui-mvvm-pattern/references/v1-nested-observation.md` and `hmos-arkui-develop-skill/references/quick-apis/08-state-decorators.md`: retain V1 observation, replace changed collections, keep reactive Builder labels as callbacks.
- Signatures: API 24 SDK `ets/api/@ohos.intl.d.ts`, `intl.DateTimeFormat(locale, DateTimeOptions).format(Date)`; public LocalizationKit export verified in its SDK kit configuration. Format validity dates in the selected interface language with an explicit UTC zone.
- Native symbols: names checked against API 24 `ets/build-tools/ets-loader/sysResource.js`; icons use SymbolGlyph and accessible text labels.
- System bars: API 24 `ets/api/@ohos.window.d.ts`, public `WindowStage.getMainWindow()` and `Window.setWindowSystemBarProperties()` (API 9+) explicitly set foreground/background colors on the app's window when configuration changes. This keeps a forced dark appearance readable while the device remains in Light mode.

Signed content gets authenticated language variants. The interface must never translate text outside the signature and still label it verified. Diagnostics use stable localized state keys, not transport exception messages. Missing signed translations retain the original with a clear localized language notice.

## Verification matrix

PL and EN: Home, Map/search/detail/back, Relay, Guide, Settings and Diagnostics. Light, Dark and System appearance; large system text; persistence after restart; foreground resume; signed translations and tampering; separate A/B/C app delivery. Physical NearLink, background delivery and official issuer integration cannot be established by emulator results.
