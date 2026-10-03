# Foreground location and saved-point state

Implementation 2026-10-03, exact installed HarmonyOS API 24 SDK with app minimum 20.

## Scope and evidence

- `@kit.LocationKit` exports `geoLocationManager`; installed `ets/api/@ohos.geoLocationManager.d.ts` declares `getCurrentLocation(request?: CurrentLocationRequest | SingleLocationRequest): Promise<Location>` at line 889 and `isLocationEnabled(): boolean` at 966. `CurrentLocationRequest` at 2687 has `priority` and `timeoutMs`. These request fields and the asynchronous API are available before minimum API 20.
- Capability: `SystemCapability.Location.Location.Core`. User-granted permissions `ohos.permission.APPROXIMATELY_LOCATION` and `ohos.permission.LOCATION` are requested together, only after the user selects the location action. Approximate-only consent is allowed; insufficient accuracy is explained in the UI.
- `DeviceLocation.ets` is a native API boundary. It returns typed outcome codes, bounds-checks coordinates/accuracy and uses a 10,000 ms request timeout. It never enables a system switch automatically, persists a location or sends it to a peer.
- `MapViewModel.ets` owns origin and save state. A usable device position must have reported accuracy≤250m and be inside the bundled extent. Otherwise the previous origin remains; a status explains denial, disabled services, unsupported provider, poor accuracy or missing area coverage. Distances remain straight-line reference distances, never safe-route claims.
- The map shows one acquired fix, not a continuously tracked live position. Reset to the demo origin invalidates an in-flight response. A location provider and actual positioning accuracy still require physical-device validation.

## Save-state correction

`saveSelected(store)` snapshots the selected point ID, rejects double submissions, awaits durable storage and changes `savedId` only on success. A failed write retains the prior durable point and exposes an error. A late restore cannot overwrite a newer save. Unknown persisted IDs are ignored, and `openSaved()` selects an existing saved point without introducing fabricated coordinates.

## Validation

`node --test tests/map.test.mjs tests/location.test.mjs` passed 15 checks at this checkpoint. Four map cases cover save success/failure, concurrent selection/restore, device-origin bounds and stale requests; three location cases exercise the actual provider source against permission/service mocks. Existing geometry/source/render tests also remain in the map suite.

Host tests do not establish physical GPS accuracy. Native permission handling, UI localization and changed map rendering are recorded in the integrated validation checkpoint.

On the API 24 emulator, selecting the location action opened the native foreground location permission dialog. Denying it returned to the map with the Polish permission-denied explanation, retained the Rynek demo origin and selected point, and left map/save actions usable. Repeating the action after denial returned the same state. Evidence: `artifacts/screenshots/v11-location-request.json` and `v11-location-denied.json`.

The installed emulator is 6.1.1.200. DevEco CLI rejected its geolocation scene command because scene injection requires Emulator 7.0 or later. No simulated successful GPS fix or physical GPS accuracy is claimed; success, poor-accuracy and outside-pack paths currently have host coverage only. The emulator was not upgraded during app validation.
