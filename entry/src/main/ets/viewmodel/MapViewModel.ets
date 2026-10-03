import { MAP_AREAS, MAP_STREETS, MAP_RIVERS, SAFE_POINTS, MAP_SOURCE_DATE,
  MAP_ATTRIBUTION, MAP_PACK_BYTES, MAP_BOUNDS } from '../model/OfflineMapData';
import { LocalStore } from '../model/LocalStore';
import { common } from '@kit.AbilityKit';
import { DeviceLocation, DevicePosition } from '../model/DeviceLocation';

export class MapVertex {
  lat: number;
  lon: number;
  constructor(lat: number, lon: number) { this.lat = lat; this.lon = lon; }
}

export class MapShape {
  kind: string;
  points: MapVertex[];
  minLat: number = 90;
  maxLat: number = -90;
  minLon: number = 180;
  maxLon: number = -180;
  constructor(kind: string, points: MapVertex[]) {
    this.kind = kind; this.points = points;
    for (const point of points) {
      this.minLat = Math.min(this.minLat, point.lat);
      this.maxLat = Math.max(this.maxLat, point.lat);
      this.minLon = Math.min(this.minLon, point.lon);
      this.maxLon = Math.max(this.maxLon, point.lon);
    }
  }
}

export class SafePointViewModel {
  id: string = '';
  name: string = '';
  address: string = '';
  lat: number = 0;
  lon: number = 0;
  availability: string = '';
  availabilityKey: string = 'availability_unknown';
  description: string = '';
  source: string = '';
  sourceDate: string = '';
  distance: number = 0;
  distanceLabel: string = '';
}

@Observed
export class MapViewModel {
  points: SafePointViewModel[] = [];
  streets: MapShape[] = [];
  areas: MapShape[] = [];
  rivers: MapShape[] = [];
  selectedId: string = '';
  savedId: string = '';
  saveBusy: boolean = false;
  saveError: string = '';
  locationBusy: boolean = false;
  locationStatus: string = 'demo';
  locationAccuracy: number = 0;
  originIsDevice: boolean = false;
  private saveRevision: number = 0;
  private locationRevision: number = 0;
  zoom: number = 1;
  centerLat: number = 50.0614;
  centerLon: number = 19.9372;
  originLat: number = 50.0614;
  originLon: number = 19.9372;
  sourceDate: string = MAP_SOURCE_DATE;
  attribution: string = MAP_ATTRIBUTION;
  packSize: string = (MAP_PACK_BYTES / 1024).toFixed(0) + ' KB';

  constructor() {
    this.points = SAFE_POINTS.map((point) => {
      const item = new SafePointViewModel();
      item.id = point.id; item.name = point.name; item.address = point.address;
      item.lat = point.lat; item.lon = point.lon;
      item.availability = point.availability; item.availabilityKey = this.accessKey(point.availability);
      item.description = point.description; item.source = point.source; item.sourceDate = point.sourceDate;
      item.distance = this.distance(point.lat, point.lon);
      item.distanceLabel = item.distance < 1000 ? Math.round(item.distance) + ' m' :
        (item.distance / 1000).toFixed(1) + ' km';
      return item;
    }).sort((a: SafePointViewModel, b: SafePointViewModel) => a.distance - b.distance);
    this.streets = MAP_STREETS.map((line) => new MapShape(line.kind,
      line.points.map((point) => new MapVertex(point.lat, point.lon))));
    this.areas = MAP_AREAS.map((line) => new MapShape(line.kind,
      line.points.map((point) => new MapVertex(point.lat, point.lon))));
    this.rivers = MAP_RIVERS.map((line) => new MapShape(line.kind,
      line.points.map((point) => new MapVertex(point.lat, point.lon))));
    if (this.points.length > 0) { this.selectedId = this.points[0].id; }
  }

  distance(lat: number, lon: number): number {
    const radians: number = Math.PI / 180;
    const dy: number = (lat - this.originLat) * radians;
    const dx: number = (lon - this.originLon) * radians;
    const a: number = Math.sin(dy / 2) ** 2 + Math.cos(lat * radians) *
      Math.cos(this.originLat * radians) * Math.sin(dx / 2) ** 2;
    const bounded: number = Math.max(0, Math.min(1, a));
    return 6371000 * 2 * Math.atan2(Math.sqrt(bounded), Math.sqrt(1 - bounded));
  }

  selected(): SafePointViewModel {
    return this.points.find((point: SafePointViewModel) => point.id === this.selectedId) ?? new SafePointViewModel();
  }

  saved(): SafePointViewModel | undefined {
    return this.points.find((point: SafePointViewModel) => point.id === this.savedId);
  }

  distanceText(point: SafePointViewModel, language: string): string {
    if (!Number.isFinite(point.distance) || point.distance < 0) { return '—'; }
    if (point.distance < 1000) { return Math.round(point.distance) + ' m'; }
    const value: string = (point.distance / 1000).toFixed(1);
    return (language === 'pl' ? value.replace('.', ',') : value) + ' km';
  }

  searchPoints(query: string): SafePointViewModel[] {
    const normalized: string = this.searchText(query);
    if (normalized.length === 0) { return this.points; }
    const terms: string[] = normalized.split(/\s+/);
    return this.points.filter((point: SafePointViewModel) => {
      const text: string = this.searchText(point.address);
      return terms.every((term: string) => text.includes(term));
    });
  }

  private searchText(value: string): string {
    // Polish addresses remain source text; keyboard accents are optional in search.
    return value.trim().toLowerCase().replace(/ą/g, 'a').replace(/ć/g, 'c').replace(/ę/g, 'e')
      .replace(/ł/g, 'l').replace(/ń/g, 'n').replace(/ó/g, 'o').replace(/ś/g, 's')
      .replace(/ź/g, 'z').replace(/ż/g, 'z');
  }

  private accessKey(value: string): string {
    if (value === 'Na żądanie') { return 'availability_request'; }
    if (value === 'Całodobowa') { return 'availability_all_day'; }
    if (value === 'Określone godziny') { return 'availability_hours'; }
    // A new source category must not leak untranslated text or imply live access.
    return 'availability_unknown';
  }

  select(id: string): boolean {
    const point: SafePointViewModel | undefined = this.points.find((item: SafePointViewModel) => item.id === id);
    if (point === undefined) { return false; }
    this.selectedId = id;
    this.centerLat = point.lat; this.centerLon = point.lon;
    return true;
  }

  async restoreSaved(store: LocalStore): Promise<void> {
    const revision: number = this.saveRevision;
    try {
      const id: string = await store.read('saved_point');
      if (revision !== this.saveRevision) { return; }
      this.savedId = this.points.some((point: SafePointViewModel) => point.id === id) ? id : '';
      this.saveError = '';
    } catch (error) {
      if (revision === this.saveRevision) { this.saveError = 'load_failed'; }
    }
  }

  async saveSelected(store: LocalStore): Promise<boolean> {
    if (this.saveBusy) { return false; }
    const id: string = this.selectedId;
    if (!this.points.some((point: SafePointViewModel) => point.id === id)) {
      this.saveError = 'invalid_point';
      return false;
    }
    this.saveRevision++;
    this.saveBusy = true;
    this.saveError = '';
    try {
      await store.write('saved_point', id);
      // A badge describes durable state, never an optimistic failed write.
      this.savedId = id;
      return true;
    } catch (error) {
      this.saveError = 'save_failed';
      return false;
    } finally { this.saveBusy = false; }
  }

  openSaved(): boolean {
    return this.select(this.savedId);
  }

  async locate(context: common.UIAbilityContext): Promise<boolean> {
    if (this.locationBusy) { return false; }
    const revision: number = ++this.locationRevision;
    this.locationBusy = true;
    try {
      const position: DevicePosition = await new DeviceLocation().locate(context);
      if (revision !== this.locationRevision) { return false; }
      this.locationStatus = position.status;
      if (position.status !== 'ready') { return false; }
      if (position.accuracy > 250) { this.locationStatus = 'poor_accuracy'; return false; }
      if (position.latitude < MAP_BOUNDS.south || position.latitude > MAP_BOUNDS.north ||
        position.longitude < MAP_BOUNDS.west || position.longitude > MAP_BOUNDS.east) {
        this.locationStatus = 'outside_pack';
        return false;
      }
      this.originLat = position.latitude;
      this.originLon = position.longitude;
      this.locationAccuracy = position.accuracy;
      this.originIsDevice = true;
      this.updateDistances();
      this.recenter();
      return true;
    } catch (error) {
      if (revision === this.locationRevision) { this.locationStatus = 'unavailable'; }
      return false;
    } finally { this.locationBusy = false; }
  }

  resetOrigin(): void {
    this.locationRevision++;
    this.originLat = 50.0614;
    this.originLon = 19.9372;
    this.originIsDevice = false;
    this.locationStatus = 'demo';
    this.locationAccuracy = 0;
    this.updateDistances();
    this.recenter();
  }

  private updateDistances(): void {
    this.points = this.points.map((previous: SafePointViewModel) => {
      const point: SafePointViewModel = new SafePointViewModel();
      point.id = previous.id; point.name = previous.name; point.address = previous.address;
      point.lat = previous.lat; point.lon = previous.lon;
      point.availability = previous.availability; point.availabilityKey = previous.availabilityKey;
      point.description = previous.description; point.source = previous.source; point.sourceDate = previous.sourceDate;
      point.distance = this.distance(point.lat, point.lon);
      point.distanceLabel = point.distance < 1000 ? Math.round(point.distance) + ' m' :
        (point.distance / 1000).toFixed(1) + ' km';
      return point;
    }).sort((a: SafePointViewModel, b: SafePointViewModel) => a.distance - b.distance);
  }

  changeZoom(delta: number): void { this.zoom = Math.max(0.65, Math.min(5, this.zoom + delta)); }
  recenter(): void { this.centerLat = this.originLat; this.centerLon = this.originLon; this.zoom = 1; }
}
