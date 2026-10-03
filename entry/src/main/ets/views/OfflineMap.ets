import { MapViewModel, MapShape, MapVertex, SafePointViewModel } from '../viewmodel/MapViewModel';
import { MAP_BOUNDS } from '../model/OfflineMapData';

@Component
export struct OfflineMap {
  @ObjectLink vm: MapViewModel;
  @Prop @Watch('onRevisionChanged') revision: number = 0;
  @Prop compact: boolean = false;
  @Prop @Watch('onRevisionChanged') dark: boolean = false;
  @Prop description: string = '';
  onSelect: (id: string) => void = () => {};
  private canvas: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true));
  private widthValue: number = 360;
  private heightValue: number = 280;
  private canvasReady: boolean = false;

  onRevisionChanged(): void { this.draw(); }
  aboutToDisappear(): void { this.canvasReady = false; }

  private color(name: string, fallback: string): string {
    try {
      const value: number = this.getUIContext().getHostContext()!.resourceManager.getColorByNameSync(name);
      return '#' + (value & 0xFFFFFF).toString(16).padStart(6, '0');
    } catch (error) { return fallback; }
  }

  x(lon: number): number {
    return this.widthValue / 2 + (lon - this.vm.centerLon) * this.widthValue / (0.042 / this.vm.zoom);
  }
  y(lat: number): number {
    const span: number = (0.042 / this.vm.zoom) * this.heightValue / this.widthValue * 0.642;
    return this.heightValue / 2 - (lat - this.vm.centerLat) * this.heightValue / span;
  }

  path(shape: MapShape): void {
    this.canvas.beginPath();
    this.trace(shape);
  }

  private visible(shape: MapShape): boolean {
    return this.x(shape.maxLon) >= 0 && this.x(shape.minLon) <= this.widthValue &&
      this.y(shape.minLat) >= 0 && this.y(shape.maxLat) <= this.heightValue;
  }

  private trace(shape: MapShape): void {
    shape.points.forEach((point: MapVertex, index: number) => {
      if (index === 0) { this.canvas.moveTo(this.x(point.lon), this.y(point.lat)); }
      else { this.canvas.lineTo(this.x(point.lon), this.y(point.lat)); }
    });
  }

  private districtLabel(label: string, x: number, y: number): void {
    // Opaque backing keeps text contrast independent of roads and water underneath.
    // The context uses vp; match its text and measured backing to that unit.
    const width: number = this.canvas.measureText(label).width + 8;
    this.canvas.fillStyle = this.color('map_land', '#E8EDE2');
    this.canvas.fillRect(x - 4, y - 13, width, 18);
    this.canvas.fillStyle = this.color('map_label', '#465B50');
    this.canvas.fillText(label, x, y);
  }

  draw(): void {
    if (!this.canvasReady || this.widthValue <= 0 || this.heightValue <= 0) { return; }
    this.canvas.fillStyle = this.color('map_outside', '#F1F2EE');
    this.canvas.fillRect(0, 0, this.widthValue, this.heightValue);
    const left: number = this.x(MAP_BOUNDS.west);
    const top: number = this.y(MAP_BOUNDS.north);
    const mapWidth: number = this.x(MAP_BOUNDS.east) - left;
    const mapHeight: number = this.y(MAP_BOUNDS.south) - top;
    this.canvas.save();
    this.canvas.beginPath();
    this.canvas.rect(left, top, mapWidth, mapHeight);
    this.canvas.clip();
    this.canvas.fillStyle = this.color('map_land', '#E8EDE2');
    this.canvas.fillRect(left, top, mapWidth, mapHeight);
    this.vm.areas.forEach((area: MapShape) => {
      if (!this.visible(area)) { return; }
      this.path(area); this.canvas.closePath();
      this.canvas.fillStyle = area.kind.includes('water') ? this.color('map_water', '#A9CED0') : this.color('map_park', '#CDDDBE');
      this.canvas.fill();
    });
    this.canvas.beginPath();
    this.vm.rivers.forEach((river: MapShape) => {
      if (this.visible(river)) { this.trace(river); }
    });
    this.canvas.strokeStyle = this.color('map_water', '#A9CED0');
    this.canvas.lineWidth = 18 * this.vm.zoom;
    this.canvas.stroke();
    // Batch all streets of the same visual width into a single stroke.
    // The old loop submitted almost 3,000 separate strokes on each redraw.
    for (let layer: number = 0; layer < 2; layer++) {
      this.canvas.beginPath();
      for (const street of this.vm.streets) {
        const major: boolean = street.kind === 'primary' || street.kind === 'secondary';
        if (major === (layer === 1) && this.visible(street)) { this.trace(street); }
      }
      this.canvas.strokeStyle = this.color('map_road', '#FCFDF8');
      this.canvas.lineWidth = layer === 1 ? 4 : 2;
      this.canvas.stroke();
    }
    this.canvas.font = 'bold 11vp sans-serif';
    this.districtLabel('STARE MIASTO', this.x(19.936) - 30, this.y(50.061) - 27);
    this.districtLabel('KAZIMIERZ', this.x(19.947) - 25, this.y(50.051));
    this.canvas.restore();
    this.canvas.strokeStyle = this.color('border', '#CBD5C7');
    this.canvas.lineWidth = 1;
    this.canvas.strokeRect(left, top, mapWidth, mapHeight);
    this.vm.points.forEach((point: SafePointViewModel) => {
      const selected: boolean = point.id === this.vm.selectedId;
      const px: number = this.x(point.lon); const py: number = this.y(point.lat);
      if (px < 0 || px > this.widthValue || py < 0 || py > this.heightValue) { return; }
      this.canvas.beginPath(); this.canvas.arc(px, py, selected ? 12 : 5.5, 0, Math.PI * 2);
      this.canvas.fillStyle = selected ? this.color('map_selected', '#164D40') : this.color('map_point', '#FFFFFF'); this.canvas.fill();
      this.canvas.strokeStyle = this.color('map_selected', '#164D40'); this.canvas.lineWidth = 1.5; this.canvas.stroke();
      if (selected) {
        this.canvas.fillStyle = this.color('map_plus', '#D9FF82'); this.canvas.font = 'bold 15px sans-serif';
        this.canvas.fillText('+', px - 4.5, py + 5);
      }
    });
    const ox: number = this.x(this.vm.originLon); const oy: number = this.y(this.vm.originLat);
    this.canvas.beginPath(); this.canvas.arc(ox, oy, 10, 0, Math.PI * 2);
    this.canvas.fillStyle = this.color('map_origin', '#345FC6') + '33'; this.canvas.fill();
    this.canvas.beginPath(); this.canvas.arc(ox, oy, 4, 0, Math.PI * 2);
    this.canvas.fillStyle = this.color('map_origin', '#345FC6'); this.canvas.fill();
  }

  pick(x: number, y: number): void {
    let closestId: string = '';
    let distance: number = 28;
    for (const point of this.vm.points) {
      const px: number = this.x(point.lon); const py: number = this.y(point.lat);
      if (px < 0 || px > this.widthValue || py < 0 || py > this.heightValue) { continue; }
      const d: number = Math.hypot(px - x, py - y);
      if (d < distance) { closestId = point.id; distance = d; }
    }
    if (closestId.length > 0) { this.onSelect(closestId); }
  }

  build() {
    Canvas(this.canvas)
      .width('100%').height('100%')
      // Every marker has an equivalent native button in the full point list.
      .accessibilityLevel('no')
      .onReady(() => { this.canvasReady = true; this.draw(); })
      .onAreaChange((_old: Area, area: Area) => {
        const width: number = Number(area.width); const height: number = Number(area.height);
        if (width > 0 && height > 0 && (width !== this.widthValue || height !== this.heightValue)) {
          this.widthValue = width; this.heightValue = height; this.draw();
        }
      })
      .onClick((event: ClickEvent) => { this.pick(event.x, event.y); })
  }
}
