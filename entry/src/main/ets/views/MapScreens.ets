import { MapViewModel, SafePointViewModel } from '../viewmodel/MapViewModel';
import { actionButton, divider, iconButton, sectionTitle } from './Controls';
import { OfflineMap } from './OfflineMap';
import { ACTION_BG, ACTION_FG, DANGER, INK, MUTED, SOFT, SUCCESS, SURFACE } from './Theme';
import { UiCopy } from './UiCopy';

/** Offline map, search and nearest protective points. */
@Component
export struct MapScreen {
  @ObjectLink map: MapViewModel;
  @Prop language: string = 'en';
  copy: UiCopy = new UiCopy();
  @Link query: string;
  @Link mapMode: string;
  @Link mapRevision: number;
  @Prop themeRevision: number = 0;
  @Prop dark: boolean = false;
  @Prop viewportHeight: number = 760;
  onSelectPoint: (id: string) => void = () => {};
  onUseLocation: () => void = () => {};
  onScrollTop: () => void = () => {};

  private t(key: string): string { return this.copy.text(key, this.language); }

  private locationMessage(): string {
    return this.t(this.map.locationStatus === 'demo' ? 'demo_origin' : 'location_' + this.map.locationStatus);
  }

  private filteredPoints(): SafePointViewModel[] {
    return this.map.searchPoints(this.query);
  }

  private visiblePoints(): SafePointViewModel[] {
    const points: SafePointViewModel[] = this.filteredPoints();
    return this.mapMode === 'map' && this.query.trim().length === 0 ? points.slice(0, 3) : points;
  }

  @Builder
  private modeChoice(mode: string, key: string) {
    Button({ type: ButtonType.Normal }) {
      Text(this.t(key)).fontSize(14).fontWeight(FontWeight.Medium).fontColor(this.mapMode === mode ? ACTION_FG : INK)
    }.id('mapMode' + mode).layoutWeight(1).constraintSize({ minHeight: 48 }).borderRadius(10)
      .backgroundColor(this.mapMode === mode ? ACTION_BG : SOFT).accessibilitySelected(this.mapMode === mode)
      .onClick(() => { this.mapMode = mode; if (mode === 'map') { this.query = ''; } })
  }

  @Builder
  private pointRow(point: SafePointViewModel) {
    Button({ type: ButtonType.Normal }) {
      Row({ space: 12 }) {
        Column({ space: 5 }) {
          Text(point.address).fontSize(16).fontWeight(FontWeight.Medium).fontColor(INK).width('100%')
          Text(this.t(point.availabilityKey) + (this.map.savedId === point.id ? ' · ' + this.t('saved_short') : ''))
            .fontSize(12).fontColor(MUTED).width('100%')
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        Text(this.map.distanceText(point, this.language)).fontSize(13).fontWeight(FontWeight.Medium).fontColor(INK)
        SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(13).maxFontScale(1).fontColor([MUTED]).accessibilityLevel('no')
      }.width('100%').padding({ top: 16, bottom: 16 })
    }.id('point_' + point.id).width('100%').constraintSize({ minHeight: 68 }).backgroundColor(Color.Transparent)
      .borderRadius(6).accessibilityText(point.address + '. ' + this.map.distanceText(point, this.language) + '. ' +
        this.t(point.availabilityKey)).onClick(() => { this.onSelectPoint(point.id); })
    divider()
  }

  @Builder
  private mapTools() {
    Row({ space: 8 }) {
      iconButton($r('sys.symbol.plus'), () => this.t('zoom_in'), 'zoomIn',
        () => { this.map.changeZoom(0.5); this.mapRevision++; })
      iconButton($r('sys.symbol.minus'), () => this.t('zoom_out'), 'zoomOut',
        () => { this.map.changeZoom(-0.5); this.mapRevision++; })
      Button({ type: ButtonType.Normal }) {
        Text(this.t('recenter')).fontSize(14).fontColor(INK)
      }.id('recenterMap').layoutWeight(1).constraintSize({ minHeight: 48 }).backgroundColor(Color.Transparent)
        .onClick(() => { this.map.recenter(); this.mapRevision++; })
    }.width('100%').backgroundColor(SURFACE).borderRadius(10)
  }

  build() {
    Column({ space: 12 }) {
      Row({ space: 8 }) {
        Text(this.t('central_krakow')).fontSize(17).fontWeight(FontWeight.Medium).fontColor(INK).layoutWeight(1)
        Text(this.t('offline_short')).fontSize(12).fontColor(SUCCESS)
      }.width('100%')
      TextInput({ placeholder: this.t('search_points'), text: this.query }).id('searchPoints')
        .fontSize(16).constraintSize({ minHeight: 48 }).backgroundColor(SURFACE).fontColor(INK)
        .placeholderColor(MUTED).borderRadius(12).maxLength(100).accessibilityText(this.t('search_points'))
        .onChange((value: string) => { this.query = value; if (value.trim().length > 0) { this.mapMode = 'list'; } })
      Row({ space: 4 }) { this.modeChoice('map', 'map'); this.modeChoice('list', 'point_list') }.width('100%')
      if (this.mapMode === 'map' && this.query.trim().length === 0) {
        OfflineMap({ vm: this.map, revision: this.mapRevision + this.themeRevision, dark: this.dark,
          description: this.t('map_description'), onSelect: (id: string) => { this.onSelectPoint(id); } })
          .id('offlineMap').height(this.viewportHeight < 540 ? 190 : 270).width('100%').borderRadius(12).clip(true)
        this.mapTools()
        Text(this.t('map_attribution')).fontSize(10).fontColor(MUTED).width('100%')
      }
      Text(this.t(this.map.originIsDevice ? 'device_origin' : 'demo_origin')).id('mapOrigin')
        .fontSize(12).fontColor(MUTED).width('100%')
      if (this.mapMode === 'map') {
        actionButton(() => this.t(this.map.locationBusy ? 'locating' : 'use_location'), 'useLocation',
          () => { this.onUseLocation(); }, () => !this.map.locationBusy, false)
        if (this.map.locationStatus !== 'demo' && this.map.locationStatus !== 'ready') {
          Text(this.locationMessage()).fontSize(13).fontColor(MUTED).width('100%')
        }
        if (this.map.originIsDevice) {
          actionButton(() => this.t('reset_origin'), 'resetOrigin',
            () => { this.map.resetOrigin(); this.mapRevision++; }, () => true, false)
        }
      }
      Row() {
        Text(this.t(this.mapMode === 'map' ? 'nearest_points' : 'results')).fontSize(15)
          .fontWeight(FontWeight.Medium).fontColor(INK).layoutWeight(1)
        Text(this.filteredPoints().length + ' / ' + this.map.points.length).id('resultCount').fontSize(13).fontColor(MUTED)
      }.width('100%').margin({ top: 8 })
      Column() {
        ForEach(this.visiblePoints(), (point: SafePointViewModel) => { this.pointRow(point) },
          (point: SafePointViewModel) => point.id + this.language + String(point.distance))
      }.width('100%')
      if (this.filteredPoints().length === 0) {
        Text(this.t('no_results')).fontSize(16).fontColor(INK).width('100%').padding({ top: 16, bottom: 16 })
      }
      if (this.mapMode === 'map') {
        actionButton(() => this.t('all_points'), 'allPoints', () => { this.mapMode = 'list'; this.onScrollTop(); }, () => true, false)
      }
      Text(this.t('distance_notice')).fontSize(12).fontColor(MUTED).width('100%')
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
}

/** Details of one PSP protective point, with save and show-on-map actions. */
@Component
export struct PointDetailScreen {
  @ObjectLink map: MapViewModel;
  @Prop language: string = 'en';
  copy: UiCopy = new UiCopy();
  @Prop initialized: boolean = false;
  onSavePoint: () => void = () => {};
  onShowOnMap: () => void = () => {};

  private t(key: string): string { return this.copy.text(key, this.language); }

  build() {
    Column({ space: 20 }) {
      Text(this.map.selected().address).id('pointAddress').fontSize(28).fontWeight(FontWeight.Bold).fontColor(INK).width('100%')
      Text(this.map.distanceText(this.map.selected(), this.language) + ' · ' + this.t('straight_line'))
        .fontSize(15).fontColor(MUTED).width('100%')
      divider()
      Column({ space: 8 }) {
        sectionTitle(() => this.t('access_label'))
        Text(this.t(this.map.selected().availabilityKey)).id('pointAccess').fontSize(20).fontWeight(FontWeight.Medium).fontColor(INK).width('100%')
        Text(this.t('access_notice')).fontSize(14).fontColor(MUTED).width('100%')
      }.alignItems(HorizontalAlign.Start).width('100%')
      actionButton(() => this.t(this.map.saveBusy ? 'saving' : this.map.savedId === this.map.selectedId ? 'saved_point' : 'save_point'),
        'savePoint', () => { this.onSavePoint(); }, () => this.initialized && !this.map.saveBusy && this.map.savedId !== this.map.selectedId)
      actionButton(() => this.t('show_on_map'), 'showOnMap', () => {
        this.onShowOnMap();
      }, () => true, false)
      if (this.map.saveError.length > 0) {
        Text(this.t(this.map.saveError === 'load_failed' ? 'saved_load_failed' : 'save_failed'))
          .fontSize(14).fontColor(DANGER).width('100%')
      }
      divider()
      Column({ space: 6 }) {
        Text(this.t('source_psp')).fontSize(14).fontColor(INK).width('100%')
        Text(this.t('pack_date') + ': ' + this.map.selected().sourceDate).fontSize(12).fontColor(MUTED).width('100%')
        Text(this.t('point_scope')).fontSize(12).fontColor(MUTED).width('100%')
      }.width('100%')
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
}
