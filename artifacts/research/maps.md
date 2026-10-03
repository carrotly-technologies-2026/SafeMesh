# Offline Kraków map and protective points

Research and bundle created on 2026-10-03. The app ships a bounded central Kraków map, so first launch can work without connectivity. This pack is not a complete city inventory or an evacuation-routing graph.

## Official protective-point data

The primary source is **Komenda Główna Państwowej Straży Pożarnej**, published on Poland's open-data portal:

- Human-readable resource: <https://dane.gov.pl/pl/dataset/28058,punkty-schronienia-w-polsce/resource/1393918>
- Resource metadata: <https://api.dane.gov.pl/1.4/resources/1393918>
- Dataset metadata and licence: <https://api.dane.gov.pl/1.4/datasets/28058>
- Downloadable CSV: <https://api.dane.gov.pl/resources/1393918,punkty-schronienia-dane-csv/file>
- Publisher's original CSV: <https://gdziesieukryc.pl/PS_XML/punkty_schronienia.csv>

Metadata inspected on 2026-10-03 identifies 86,388 records, data date **2026-09-28**, weekly updates, and **CC BY 4.0**. These are dates of the published dataset, not evidence that each object was physically checked on that date. Source identifiers, names, type, address, availability and geographic coordinates are retained. No protective capacity or live operational status is invented.

The pack selects 40 published records closest to Rynek Główny (50.06143, 19.93658), within latitude 50.04–50.08 and longitude 19.915–19.97. There are 697 matching source records in these bounds as of this snapshot. The 40-record display is deliberately a subset: its UI must not claim that omitted points do not exist or that the nearest included point is the nearest available protective location.

Kraków's municipal BIP refers residents to the PSP application: <https://www.bip.krakow.pl/?dok_id=239497>.

The PSP explicitly distinguishes **punkty schronienia** (temporary protective places in existing infrastructure) from high-protection shelters. Its explanation also confirms offline municipal data packs: <https://www.gov.pl/web/kmpsp-poznan/nowa-aplikacja-gdzie-sie-ukryc---punkty-schronienia2>.

PSP explains the access categories and that the map does not itself grant entry to restricted objects: <https://www.gov.pl/web/kmpsp-warszawa/gdzie-sie-ukryc---sprawdz-najblizsze-punkty-schronienia-ps>.

## Offline map data

The map uses OpenStreetMap vector geometry retrieved with a bounded, manual Overpass request. An initial POST returned HTTP 504 and a documented mirror timed out. A narrower request sent as GET to the main instance succeeded. Future manual refreshes make one GET request. The map contains selected streets and pedestrian streets, closed park/water polygons, and river centerlines. Geometry is simplified by approximately 4 metres; it is an overview, not a navigable road graph. No raster tiles from the community tile server are downloaded.

- OSM data licence and attribution: <https://www.openstreetmap.org/copyright>
- Full ODbL: <https://opendatacommons.org/licenses/odbl/1-0/>
- Overpass operator's usage guidance: <https://dev.overpass-api.de/overpass-doc/en/preface/commons.html>
- API endpoint: <https://overpass-api.de/api/interpreter>
- Documented public instance and usage terms: <https://wiki.openstreetmap.org/wiki/Overpass_API#Public_Overpass_API_instances>
- OSM raster-tile policy explicitly prohibits offline prefetching/bulk downloading: <https://operations.osmfoundation.org/policies/tiles/>
- A future larger regional pack can be generated from Geofabrik's official extract distribution: <https://download.geofabrik.de/europe/poland/malopolskie.html>.

Display **© OpenStreetMap contributors (ODbL) · KG PSP (CC BY 4.0)** visibly on or beside the map. Link to the corresponding licences in the app information screen. The generated JSON exposes the OSM geometry and attribution for redistribution under ODbL; PSP records remain a separately identified CC BY 4.0 collection in the same pack. The metadata includes exact request, source URLs, source dates and SHA-256 digests of original downloads.

## UX constraints

- Use “Punkty schronienia” / “Protective points”, not “verified bomb shelters”. The generic CSV type “Obiekt ochrony ludności” does not establish a particular blast-protection rating.
- Show the source's exact availability category and “Dostępność według źródła; brak potwierdzenia na żywo”. A stale data pack cannot prove an entrance is open or an object is intact.
- Display the offline coverage boundary, publication date and “Wybrany wycinek, niepełna lista”. Outside it, say no pack is available; do not draw invented streets or markers.
- If showing distances, label them as straight-line distance. Do not present a straight line through buildings, rivers or hazards as a walking/evacuation route.
- Keep demo alerts clearly marked as exercises and keep real reference map data separately attributed. Cryptographic verification of an exercise message proves the configured demo key signed it, not that RCB issued it.
- The emergency message can highlight an authority-specified point ID; do not automatically choose a “safe” location solely by proximity during an actual incident.
- Bundle a starter pack in the HAP for this demo. A production first-run city download should show size, region, progress and last update, use an offline-authorized map source, validate downloaded content, and retain the previous complete pack until the update succeeds.

## Reproducibility

`python scripts/refresh-map.py` downloads current metadata and CSV, verifies the expected source licence, makes one bounded Overpass request, and regenerates:

- `entry/src/main/resources/rawfile/map-pack.json`
- `entry/src/main/ets/model/OfflineMapData.ets`

Run the refresh manually during preparation, not on every end-user application launch. Public Overpass infrastructure is not a production backend for all app users.

The ArkTS model uses explicit named classes, declared fields and constructor assignment, following the locally installed ArkTS guide sections `02-Basic-Syntax/classes.md` and `02-Basic-Syntax/collection-types.md` from `hmos-arkts-knowledge-retriever`.

## Generated pack and validation

The generated pack contains 2,902 street polylines, 71 closed area polygons, 10 river centerlines and 40 PSP points. OSM snapshot: **2026-10-03T15:19:36Z**. JSON: **413,617 bytes**; generated ArkTS: **468,563 bytes**; together under 1 MB.

Checked all 40 source IDs, names, addresses and access categories against the original PSP CSV and checked rounded coordinates to within 0.00000006 degrees. All points are inside the intended bounds. There are no duplicate point IDs or duplicate geometry IDs within each layer; all coordinates are finite; all filled polygons are closed. The script passed Python syntax validation. App compilation is checked by the primary implementation task.

Source access categories in this subset: 25 “Na żądanie”, 13 “Całodobowa”, 2 “Określone godziny”. They must not be collapsed into an “open now” status.

The generated ArkTS module exports `GeoPoint`, `MapBounds`, `MapLine`, `SafePoint`, `MAP_BOUNDS`, `MAP_CENTER`, `MAP_SOURCE_DATE`, `MAP_OSM_DATE`, `MAP_PACK_LABEL`, `MAP_PACK_BYTES`, `MAP_ATTRIBUTION`, `MAP_NOTICE`, `MAP_STREETS`, `MAP_AREAS`, `MAP_RIVERS` and `SAFE_POINTS`. River centerlines should be stroked, while `MAP_AREAS` can be filled. Renderers should clip to their map viewport because complete intersecting OSM ways can extend beyond the requested bounds.

Repeatable host checks are in `tests/map.test.mjs`; run `node --test tests/map.test.mjs` with the installed Node.js 24. They execute the actual ArkTS data, viewmodel, coordinate and drawing methods after type erasure, with a Canvas adapter. Checks cover source-record preservation and attribution, finite geometry/bounds, geodesic reference distances, nearest-point ordering, unknown-ID nonmutation, valid selection, local coordinate alignment, marker picking, downloaded-extent clipping and a Canvas submission budget. They do not prove native ArkUI lifecycle behavior or pixel rendering; the emulator build remains the native check.
