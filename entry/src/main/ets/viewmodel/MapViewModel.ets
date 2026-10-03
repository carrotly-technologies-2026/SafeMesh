import { MAP_AREAS, MAP_STREETS, MAP_RIVERS, SAFE_POINTS, MAP_SOURCE_DATE,
  MAP_ATTRIBUTION, MAP_PACK_BYTES } from '../model/OfflineMapData';

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
  description: string = '';
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
      item.availability = point.availability; item.description = point.description;
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

  select(id: string): void {
    const point: SafePointViewModel | undefined = this.points.find((item: SafePointViewModel) => item.id === id);
    if (point === undefined) { return; }
    this.selectedId = id;
    this.centerLat = point.lat; this.centerLon = point.lon;
  }

  changeZoom(delta: number): void { this.zoom = Math.max(0.65, Math.min(5, this.zoom + delta)); }
  recenter(): void { this.centerLat = this.originLat; this.centerLon = this.originLon; this.zoom = 1; }
}
