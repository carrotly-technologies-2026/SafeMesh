import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { accessibility } from '@kit.AccessibilityKit';
import { intl } from '@kit.LocalizationKit';
import { LocalStore } from '../model/LocalStore';
import { AlertViewModel } from '../viewmodel/AlertViewModel';
import { MapViewModel, SafePointViewModel } from '../viewmodel/MapViewModel';
import { RelayViewModel, RelayEvent, PeerViewModel } from '../viewmodel/RelayViewModel';
import { OfflineMap } from '../views/OfflineMap';
import { UiCopy } from '../views/UiCopy';

const INK: Resource = $r('app.color.ink');
const MUTED: Resource = $r('app.color.muted');
const PAPER: Resource = $r('app.color.paper');
const SURFACE: Resource = $r('app.color.surface');
const SOFT: Resource = $r('app.color.soft');
const ACTION_BG: Resource = $r('app.color.action_bg');
const ACTION_FG: Resource = $r('app.color.action_fg');
const WARNING_BG: Resource = $r('app.color.warning_bg');
const WARNING_FG: Resource = $r('app.color.warning_fg');
const BORDER: Resource = $r('app.color.border');
const SUCCESS: Resource = $r('app.color.success');

@Entry
@Component
struct Index {
  @State tab: number = 0;
  @State mapRevision: number = 0;
  @State notice: string = '';
  @State language: string = 'pl';
  @State themePreference: string = 'system';
  @State settingsBusy: boolean = true;
  @State initialized: boolean = false;
  @State query: string = '';
  @State mapMode: string = 'map';
  @State guideExpanded: number = 0;
  @State labNode: string = 'A';
  @State labBusy: boolean = false;
  @State viewportWidth: number = 360;
  @State viewportHeight: number = 760;
  @StorageLink('safeMeshDark') dark: boolean = false;
  @StorageLink('safeMeshFontScale') fontScale: number = 1;
  @StorageLink('safeMeshThemeRevision') themeRevision: number = 0;
  private store: LocalStore = new LocalStore();
  private copy: UiCopy = new UiCopy();
  @State @Watch('onAlertChanged') alerts: AlertViewModel = new AlertViewModel(this.store);
  @State map: MapViewModel = new MapViewModel();
  @State @Watch('onRelayChanged') relay: RelayViewModel = new RelayViewModel(this.alerts);
  private pageScroll: Scroller = new Scroller();
  private lastAnnouncedAlert: string = '';
  private lastAnnouncedRelay: string = '';
  private previousTab: number = 0;
  private pointParent: number = 1;
  private diagnosticsParent: number = 4;

  aboutToAppear(): void {
    const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.copy.initialize(context);
    this.initialize(context);
  }

  onPageHide(): void { this.alerts.dispose(); this.relay.suspend(); }

  onPageShow(): void { this.alerts.resume(); this.relay.foreground(); }

  onBackPress(): boolean {
    if (this.tab < 4) { return false; }
    this.goBack();
    return true;
  }

  aboutToDisappear(): void {
    this.alerts.dispose();
    this.relay.stop();
  }

  private t(key: string): string { return this.copy.text(key, this.language); }

  private async initialize(context: common.UIAbilityContext): Promise<void> {
    this.relay.setContext(context);
    try {
      await this.store.init(context);
      const savedLanguage: string = await this.store.read('ui_language');
      this.language = savedLanguage === 'en' ? 'en' : 'pl';
      context.getApplicationContext().setLanguage(this.language);
      this.alerts.setLanguage(this.language);
      const savedNode: string = await this.store.read('lab_node');
      this.labNode = savedNode === 'B' || savedNode === 'C' ? savedNode : 'A';
      const savedTheme: string = await this.store.read('ui_theme');
      this.themePreference = savedTheme === 'light' || savedTheme === 'dark' ? savedTheme : 'system';
      this.applyTheme(this.themePreference);
      await this.map.restoreSaved(this.store);
      await this.alerts.restore();
      await this.relay.probe();
    } catch (error) {
      console.error('SAFEMESH_INIT_ERROR ' + String(error));
      this.notice = this.t('init_failed');
    }
    finally { this.initialized = true; this.settingsBusy = false; }
  }

  private async chooseLanguage(language: string): Promise<void> {
    if (this.settingsBusy) { return; }
    this.settingsBusy = true;
    this.notice = '';
    let applied: boolean = false;
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      context.getApplicationContext().setLanguage(language);
      this.language = language;
      this.alerts.setLanguage(language);
      applied = true;
      await this.store.write('ui_language', language);
      this.announce(this.t('language_saved'));
    } catch (error) { this.notice = this.t(applied ? 'language_failed' : 'settings_apply_failed'); }
    finally { this.settingsBusy = false; }
  }

  private applyTheme(theme: string): void {
    const mode: ConfigurationConstant.ColorMode = theme === 'light' ? ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT :
      theme === 'dark' ? ConfigurationConstant.ColorMode.COLOR_MODE_DARK : ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    context.getApplicationContext().setColorMode(mode);
    this.mapRevision++;
  }

  private async chooseTheme(theme: string): Promise<void> {
    if (this.settingsBusy) { return; }
    this.settingsBusy = true;
    this.notice = '';
    let applied: boolean = false;
    try {
      this.applyTheme(theme);
      this.themePreference = theme;
      applied = true;
      await this.store.write('ui_theme', theme);
      this.announce(this.t('settings_saved'));
    } catch (error) { this.notice = this.t(applied ? 'settings_save_failed' : 'settings_apply_failed'); }
    finally { this.settingsBusy = false; }
  }

  private announce(message: string): void {
    const event: accessibility.EventInfo = {
      type: 'announceForAccessibility',
      bundleName: 'org.safemesh.alerts',
      triggerAction: 'common',
      textAnnouncedForAccessibility: message
    };
    accessibility.sendAccessibilityEvent(event).catch(() => {});
  }

  private onAlertChanged(): void {
    const identity: string = this.alerts.received ? this.alerts.currentIdentity : '';
    if (identity !== this.lastAnnouncedAlert) {
      const previous: string = this.lastAnnouncedAlert;
      this.lastAnnouncedAlert = identity;
      if (identity.length > 0) { this.announce(this.t('new_alert') + ' ' + this.alerts.title); }
      else if (previous.length > 0) { this.announce(this.t('alert_expired')); }
    }
  }

  private async loadDrill(): Promise<void> {
    try {
      await this.alerts.loadDrill();
      if (!this.alerts.received) { this.notice = this.t('verify_failed'); this.announce(this.notice); }
    } catch (error) { this.notice = this.t('verify_failed'); }
  }

  private onRelayChanged(): void {
    if (!this.relay.running && this.relay.events.length > 0 && this.relay.testState !== this.lastAnnouncedRelay) {
      this.lastAnnouncedRelay = this.relay.testState;
      this.announce(this.t('test_' + this.relay.testState));
    }
  }

  private selectPoint(id: string): void {
    if (!this.map.select(id)) { return; }
    this.mapRevision++;
    this.pointParent = this.tab === 0 ? 0 : 1;
    this.selectTab(6);
    this.announce(this.t('selected_point') + ': ' + this.map.selected().address);
  }

  private selectTab(index: number): void {
    this.pageScroll.scrollTo({ xOffset: 0, yOffset: 0 });
    this.tab = index;
    this.notice = '';
  }

  private openSettings(): void {
    if (this.tab === 4) { return; }
    this.previousTab = this.tab;
    this.selectTab(4);
  }

  private goBack(): void {
    this.selectTab(this.tab === 5 ? this.diagnosticsParent : this.tab === 6 ? this.pointParent : this.previousTab);
  }

  private async savePoint(): Promise<void> {
    const saved: boolean = await this.map.saveSelected(this.store);
    this.notice = this.t(saved ? 'saved_point' : 'save_failed');
    this.announce(this.notice);
  }

  private async useLocation(): Promise<void> {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    await this.map.locate(context);
    this.mapRevision++;
    this.announce(this.locationMessage());
  }

  private async startLab(): Promise<void> {
    if (this.labBusy) { return; }
    this.labBusy = true;
    try {
      await this.relay.startEmulator(this.labNode);
      if (this.relay.hardwareState === 'lab_ready') { await this.store.write('lab_node', this.labNode); }
    }
    catch (error) { this.notice = this.t('hardware_lab_error'); }
    finally { this.labBusy = false; }
  }

  private async sendLabDrill(): Promise<void> {
    if (this.labBusy || this.alerts.busy) { return; }
    this.labBusy = true;
    try {
      await this.alerts.loadDrill();
      if (this.alerts.received) { await this.relay.share(); }
      else { this.notice = this.t('verify_failed'); }
    } catch (error) { this.notice = this.t('verify_failed'); }
    finally { this.labBusy = false; }
  }

  private locationMessage(): string {
    return this.t(this.map.locationStatus === 'demo' ? 'demo_origin' : 'location_' + this.map.locationStatus);
  }

  private filteredPoints(): SafePointViewModel[] {
    return this.map.searchPoints(this.query);
  }

  private formatTime(value: number): string {
    if (value <= 0) { return ''; }
    try {
      return new intl.DateTimeFormat(this.language === 'pl' ? 'pl-PL' : 'en-GB', {
        day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit', hour12: false, timeZone: 'UTC'
      }).format(new Date(value)) + ' UTC';
    } catch (error) { return new Date(value).toISOString().slice(0, 16).replace('T', ' ') + ' UTC'; }
  }

  private connected(): boolean {
    return this.relay.isConnected;
  }

  private connectionTitle(): string {
    if (this.relay.lifecycleState === 'paused') { return this.t('connection_paused'); }
    if (this.connected()) { return this.t('connection_active'); }
    if (this.labBusy) { return this.t('connection_connecting'); }
    return this.t('connection_off');
  }

  private pageTitle(): string {
    if (this.tab === 0) { return 'SafeMesh'; }
    return this.t(this.tab === 1 ? 'map' : this.tab === 2 ? 'relay' : this.tab === 3 ? 'guide' :
      this.tab === 4 ? 'settings_tab' : this.tab === 5 ? 'diagnostics_title' : 'point_type');
  }

  private visiblePoints(): SafePointViewModel[] {
    const points: SafePointViewModel[] = this.filteredPoints();
    return this.mapMode === 'map' && this.query.trim().length === 0 ? points.slice(0, 3) : points;
  }

  @Builder
  private action(label: () => string, id: string, action: () => void,
    enabled: () => boolean = () => true, primary: boolean = true) {
    Button({ type: ButtonType.Normal }) {
      Text(label()).fontSize(15).fontWeight(FontWeight.Medium).fontColor(primary ? ACTION_FG : INK)
        .textAlign(TextAlign.Center).width('100%')
    }.id(id).width('100%').constraintSize({ minHeight: 48 }).padding(12).borderRadius(12)
      .backgroundColor(primary ? ACTION_BG : SOFT).enabled(enabled()).opacity(enabled() ? 1 : 0.5)
      .accessibilityText(label()).onClick(action)
  }

  @Builder
  private iconButton(icon: Resource, label: () => string, id: string, action: () => void) {
    Button({ type: ButtonType.Normal }) {
      SymbolGlyph(icon).fontSize(22).maxFontScale(1).fontColor([INK]).accessibilityLevel('no')
    }.id(id).width(48).height(48).borderRadius(12).backgroundColor(Color.Transparent)
      .accessibilityText(label()).onClick(action)
  }

  @Builder
  private divider() { Divider().color(BORDER).strokeWidth(0.5) }

  @Builder
  private section(key: string) {
    Text(this.t(key)).fontSize(13).fontWeight(FontWeight.Medium).fontColor(MUTED).width('100%')
      .margin({ top: 8, bottom: 4 })
  }

  @Builder
  private rowLink(icon: Resource, title: () => string, detail: () => string, id: string, action: () => void) {
    Button({ type: ButtonType.Normal }) {
      Row({ space: 14 }) {
        SymbolGlyph(icon).fontSize(23).maxFontScale(1).fontColor([INK]).accessibilityLevel('no')
        Column({ space: 4 }) {
          Text(title()).fontSize(16).fontWeight(FontWeight.Medium).fontColor(INK).width('100%')
          if (detail().length > 0) { Text(detail()).fontSize(13).fontColor(MUTED).width('100%') }
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(15).maxFontScale(1).fontColor([MUTED])
          .accessibilityLevel('no')
      }.width('100%').padding({ top: 16, bottom: 16 })
    }.id(id).width('100%').constraintSize({ minHeight: 64 }).backgroundColor(Color.Transparent)
      .borderRadius(8).accessibilityText(title() + '. ' + detail()).onClick(action)
  }

  @Builder
  private header() {
    Row({ space: 4 }) {
      if (this.tab >= 4) {
        this.iconButton($r('sys.symbol.arrow_left'), () => this.t('back_settings'), 'backSettings', () => { this.goBack(); })
      }
      Text(this.pageTitle()).fontSize(this.tab === 0 ? 22 : 23).fontWeight(FontWeight.Bold)
        .fontColor(INK).layoutWeight(1)
      if (this.tab < 4) {
        this.iconButton($r('sys.symbol.gearshape'), () => this.t('open_settings'), 'openSettings', () => { this.openSettings(); })
      }
    }.width('100%').constraintSize({ maxWidth: 720, minHeight: 56 })
      .padding({ left: this.tab >= 4 ? 8 : 20, right: 8, top: 2, bottom: 2 })
  }

  @Builder
  private contextLine() {
    Row({ space: 8 }) {
      Text(this.t('central_krakow')).fontSize(13).fontColor(MUTED).layoutWeight(1)
      Text(this.t('exercise') + (this.relay.transportMode === 'emulator' ? ' · ' + this.relay.emulatorNode : ''))
        .id('exerciseBadge').fontSize(12).fontWeight(FontWeight.Medium).fontColor(WARNING_FG)
        .padding({ left: 9, right: 9, top: 5, bottom: 5 }).backgroundColor(WARNING_BG).borderRadius(6)
    }.width('100%').margin({ bottom: 4 })
  }

  @Builder
  private alertView() {
    Column({ space: 12 }) {
      Row({ space: 8 }) {
        SymbolGlyph(this.alerts.received ? $r('sys.symbol.checkmark_shield') : $r('sys.symbol.bell'))
          .fontSize(20).maxFontScale(1).fontColor([this.alerts.received ? SUCCESS : MUTED]).accessibilityLevel('no')
        Text(this.t(this.alerts.received ? 'signature_verified' :
          this.alerts.verificationState === 'expired' ? 'alert_expired' : 'no_alert'))
          .id('verificationBadge').fontSize(13).fontWeight(FontWeight.Medium)
          .fontColor(this.alerts.received ? SUCCESS : MUTED).layoutWeight(1)
      }.width('100%')
      Text(this.alerts.received ? this.alerts.title : this.t('ready_title')).id('alertTitle')
        .fontSize(24).fontWeight(FontWeight.Bold).fontColor(INK).width('100%')
      Text(this.alerts.received ? this.alerts.body : this.t('ready_body')).id('alertBody')
        .fontSize(16).fontColor(INK).width('100%')
      if (this.alerts.received) {
        if (this.alerts.languageFallback) {
          Text(this.t('original_language_' + this.alerts.contentLanguage)).fontSize(12).fontColor(MUTED).width('100%')
        }
        this.divider()
        Text(this.t('valid_until') + ' ' + this.formatTime(this.alerts.expiresAt))
          .fontSize(12).fontColor(MUTED).width('100%')
      } else {
        this.action(() => this.t('connect_devices'), 'connectDevices', () => { this.selectTab(2); })
      }
      if (this.alerts.persistenceState === 'save_failed' || this.alerts.persistenceState === 'load_failed') {
        Text(this.t('persistence_' + this.alerts.persistenceState)).fontSize(13).fontColor($r('app.color.danger')).width('100%')
      }
    }.width('100%').alignItems(HorizontalAlign.Start).padding(18).backgroundColor(SURFACE)
      .borderRadius(14).border({ width: 1, color: BORDER })
  }

  @Builder
  private homeView() {
    Column({ space: 16 }) {
      this.contextLine()
      Text(this.t('home_alerts')).fontSize(29).fontWeight(FontWeight.Bold).fontColor(INK).width('100%')
      this.alertView()
      this.section('your_place')
      if (this.map.saveError === 'load_failed') {
        Text(this.t('saved_load_failed')).fontSize(13).fontColor($r('app.color.danger')).width('100%')
      }
      if (this.map.saved() !== undefined) {
        this.rowLink($r('sys.symbol.bookmark'), () => this.map.saved()?.address ?? '',
          () => this.t('saved_on_phone'), 'homeSavedPoint', () => { this.selectPoint(this.map.savedId); })
      } else {
        this.rowLink($r('sys.symbol.bookmark'), () => this.t('choose_place'),
          () => this.t('choose_place_hint'), 'exploreMap', () => { this.selectTab(1); })
      }
      this.divider()
      this.rowLink($r('sys.symbol.phone_transmission_phone'), () => this.connectionTitle(),
        () => this.connected() ? this.relay.peerCount + ' ' + this.t('nearby_devices') : this.t('connection_home_hint'),
        'exploreRelay', () => { this.selectTab(2); })
      Text(this.t('exercise_notice')).id('exerciseNotice').fontSize(12).fontColor(MUTED).width('100%')
    }.width('100%').alignItems(HorizontalAlign.Start)
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
        this.t(point.availabilityKey)).onClick(() => { this.selectPoint(point.id); })
    this.divider()
  }

  @Builder
  private mapTools() {
    Row({ space: 8 }) {
      this.iconButton($r('sys.symbol.plus'), () => this.t('zoom_in'), 'zoomIn',
        () => { this.map.changeZoom(0.5); this.mapRevision++; })
      this.iconButton($r('sys.symbol.minus'), () => this.t('zoom_out'), 'zoomOut',
        () => { this.map.changeZoom(-0.5); this.mapRevision++; })
      Button({ type: ButtonType.Normal }) {
        Text(this.t('recenter')).fontSize(14).fontColor(INK)
      }.id('recenterMap').layoutWeight(1).constraintSize({ minHeight: 48 }).backgroundColor(Color.Transparent)
        .onClick(() => { this.map.recenter(); this.mapRevision++; })
    }.width('100%').backgroundColor(SURFACE).borderRadius(10)
  }

  @Builder
  private mapView() {
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
          description: this.t('map_description'), onSelect: (id: string) => { this.selectPoint(id); } })
          .id('offlineMap').height(this.viewportHeight < 540 ? 190 : 270).width('100%').borderRadius(12).clip(true)
        this.mapTools()
        Text(this.t('map_attribution')).fontSize(10).fontColor(MUTED).width('100%')
      }
      Text(this.t(this.map.originIsDevice ? 'device_origin' : 'demo_origin')).id('mapOrigin')
        .fontSize(12).fontColor(MUTED).width('100%')
      if (this.mapMode === 'map') {
        this.action(() => this.t(this.map.locationBusy ? 'locating' : 'use_location'), 'useLocation',
          () => { this.useLocation(); }, () => !this.map.locationBusy, false)
        if (this.map.locationStatus !== 'demo' && this.map.locationStatus !== 'ready') {
          Text(this.locationMessage()).fontSize(13).fontColor(MUTED).width('100%')
        }
        if (this.map.originIsDevice) {
          this.action(() => this.t('reset_origin'), 'resetOrigin',
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
        this.action(() => this.t('all_points'), 'allPoints', () => { this.mapMode = 'list'; this.pageScroll.scrollTo({ xOffset: 0, yOffset: 0 }); }, () => true, false)
      }
      Text(this.t('distance_notice')).fontSize(12).fontColor(MUTED).width('100%')
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  private pointDetail() {
    Column({ space: 20 }) {
      Text(this.map.selected().address).id('pointAddress').fontSize(28).fontWeight(FontWeight.Bold).fontColor(INK).width('100%')
      Text(this.map.distanceText(this.map.selected(), this.language) + ' · ' + this.t('straight_line'))
        .fontSize(15).fontColor(MUTED).width('100%')
      this.divider()
      Column({ space: 8 }) {
        this.section('access_label')
        Text(this.t(this.map.selected().availabilityKey)).id('pointAccess').fontSize(20).fontWeight(FontWeight.Medium).fontColor(INK).width('100%')
        Text(this.t('access_notice')).fontSize(14).fontColor(MUTED).width('100%')
      }.alignItems(HorizontalAlign.Start).width('100%')
      this.action(() => this.t(this.map.saveBusy ? 'saving' : this.map.savedId === this.map.selectedId ? 'saved_point' : 'save_point'),
        'savePoint', () => { this.savePoint(); }, () => this.initialized && !this.map.saveBusy && this.map.savedId !== this.map.selectedId)
      this.action(() => this.t('show_on_map'), 'showOnMap', () => {
        this.query = ''; this.mapMode = 'map'; this.selectTab(1);
      }, () => true, false)
      if (this.map.saveError.length > 0) {
        Text(this.t(this.map.saveError === 'load_failed' ? 'saved_load_failed' : 'save_failed'))
          .fontSize(14).fontColor($r('app.color.danger')).width('100%')
      }
      this.divider()
      Column({ space: 6 }) {
        Text(this.t('source_psp')).fontSize(14).fontColor(INK).width('100%')
        Text(this.t('pack_date') + ': ' + this.map.selected().sourceDate).fontSize(12).fontColor(MUTED).width('100%')
        Text(this.t('point_scope')).fontSize(12).fontColor(MUTED).width('100%')
      }.width('100%')
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  private labNodeChoice(node: string) {
    Button({ type: ButtonType.Normal }) {
      Text(node).fontSize(18).fontWeight(FontWeight.Medium).fontColor(this.labNode === node ? ACTION_FG : INK)
    }.id('labNode' + node).layoutWeight(1).constraintSize({ minHeight: 48 }).borderRadius(10)
      .backgroundColor(this.labNode === node ? ACTION_BG : SOFT).accessibilityText(this.t('node_label') + ' ' + node)
      .accessibilitySelected(this.labNode === node).enabled(!this.labBusy).onClick(() => { this.labNode = node; })
  }

  @Builder
  private metric(value: () => number, key: string) {
    Column({ space: 5 }) {
      Text(String(value())).fontSize(26).fontWeight(FontWeight.Medium).fontColor(INK)
      Text(this.t(key)).fontSize(12).fontColor(MUTED).textAlign(TextAlign.Center).width('100%')
    }.layoutWeight(1).padding({ top: 16, bottom: 16 })
  }

  @Builder
  private relayView() {
    Column({ space: 18 }) {
      Text(this.t('relay_intro')).fontSize(16).fontColor(MUTED).width('100%')
      Row({ space: 12 }) {
        SymbolGlyph($r('sys.symbol.phone_transmission_phone')).fontSize(32).maxFontScale(1)
          .fontColor([this.connected() ? SUCCESS : MUTED]).accessibilityLevel('no')
        Column({ space: 4 }) {
          Text(this.connectionTitle()).id('labStatus').fontSize(23).fontWeight(FontWeight.Bold).fontColor(INK).width('100%')
          Text(this.t('emulator_transport')).id('labBanner').fontSize(13).fontColor(MUTED).width('100%')
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      }.width('100%').padding({ top: 8, bottom: 8 })
      Text(this.t('lab_node')).fontSize(13).fontColor(MUTED).width('100%')
      Row({ space: 8 }) { this.labNodeChoice('A'); this.labNodeChoice('B'); this.labNodeChoice('C') }.width('100%')
      if (this.connected() && this.relay.emulatorNode === this.labNode && this.relay.transportMode === 'emulator') {
        this.action(() => this.t('lab_disconnect') + ' ' + this.relay.emulatorNode, 'labStop',
          () => { this.relay.stop(); }, () => !this.labBusy, false)
      } else {
        this.action(() => this.t(this.labBusy ? 'lab_connecting' : 'lab_connect') + ' ' + this.labNode,
          'labStart', () => { this.startLab(); }, () => this.initialized && !this.labBusy)
      }
      if (this.relay.hardwareState === 'lab_error' || this.relay.hardwareState === 'restore_failed') {
        Text(this.t('hardware_' + this.relay.hardwareState)).id('labConnectionDetail')
          .fontSize(14).fontColor($r('app.color.danger')).width('100%')
      }
      if (this.relay.transportMode === 'emulator' && this.connected()) {
        this.divider()
        Row() {
          Text(this.t('neighbors')).fontSize(15).fontWeight(FontWeight.Medium).fontColor(INK).layoutWeight(1)
          Text(String(this.relay.peerCount)).id('labPeerCount').fontSize(15).fontColor(MUTED)
        }.width('100%')
        if (this.relay.peerCount === 0) {
          Text(this.t('waiting_neighbors')).fontSize(14).fontColor(MUTED).width('100%')
        }
        ForEach(this.relay.peers.filter((peer: PeerViewModel) => peer.connected), (peer: PeerViewModel) => {
          Row({ space: 10 }) {
            Text(peer.address).fontSize(17).fontWeight(FontWeight.Medium).fontColor(INK).width(36)
            Text(this.t('neighbor_connected')).fontSize(14).fontColor(MUTED).layoutWeight(1)
            SymbolGlyph($r('sys.symbol.checkmark_circle')).fontSize(20).maxFontScale(1).fontColor([SUCCESS]).accessibilityLevel('no')
          }.width('100%').constraintSize({ minHeight: 48 })
        }, (peer: PeerViewModel) => peer.address)
        this.divider()
        Row({ space: 8 }) {
          this.metric(() => this.relay.pendingCount, 'queue_pending')
          this.metric(() => this.relay.acknowledgedCount, 'queue_acked')
          this.metric(() => this.relay.retryCount, 'queue_retry')
        }.id('labMetrics').width('100%').alignItems(VerticalAlign.Top)
        this.action(() => this.t('share_alert'), 'labShare', () => { this.relay.share(); },
          () => !this.labBusy && this.alerts.received)
        Text(this.t('packet_' + this.relay.lastPacketState)).id('labPacketStatus').fontSize(13).fontColor(MUTED).width('100%')
      }
      Text(this.t('foreground_notice')).fontSize(13).fontColor(MUTED).width('100%')
      this.divider()
      this.rowLink($r('sys.symbol.checkmark_shield'), () => this.t('diagnostics_title'),
        () => this.t('diagnostics_hint'), 'openDiagnostics', () => { this.diagnosticsParent = 2; this.selectTab(5); })
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  private guideItem(index: number, title: string, body: string) {
    Column({ space: 0 }) {
      Button({ type: ButtonType.Normal }) {
        Row({ space: 12 }) {
          Text('0' + (index + 1)).fontSize(13).fontColor(MUTED).width(26)
          Text(this.t(title)).fontSize(17).fontWeight(FontWeight.Medium).fontColor(INK).layoutWeight(1)
          SymbolGlyph(this.guideExpanded === index ? $r('sys.symbol.minus') : $r('sys.symbol.plus'))
            .fontSize(18).maxFontScale(1).fontColor([MUTED]).accessibilityLevel('no')
        }.padding({ top: 18, bottom: 18 }).width('100%')
      }.id('guideItem' + index).width('100%').constraintSize({ minHeight: 60 }).backgroundColor(Color.Transparent)
        .borderRadius(6).accessibilityText(this.t(title)).accessibilityDescription(this.t(this.guideExpanded === index ? 'collapse' : 'expand'))
        .onClick(() => { this.guideExpanded = this.guideExpanded === index ? -1 : index; })
      if (this.guideExpanded === index) {
        Text(this.t(body)).fontSize(15).fontColor(INK).width('100%').padding({ left: 38, bottom: 20 })
      }
      this.divider()
    }.width('100%')
  }

  @Builder
  private sourceLink(url: string, label: () => string) {
    Hyperlink(url, label()).color(INK).width('100%').constraintSize({ minHeight: 48 })
      .padding({ top: 12, bottom: 12 })
  }

  @Builder
  private guideView() {
    Column({ space: 16 }) {
      Text(this.t('guide_intro')).fontSize(15).fontColor(MUTED).width('100%')
      Column() {
        this.guideItem(0, 'guide1_title', 'guide1_body')
        this.guideItem(1, 'guide2_title', 'guide2_body')
        this.guideItem(2, 'guide3_title', 'guide3_body')
        this.guideItem(3, 'guide4_title', 'guide4_body')
      }.width('100%')
      Text(this.t('guide_offline')).fontSize(12).fontColor(MUTED).width('100%')
      this.sourceLink('https://www.gov.pl/web/poradnikbezpieczenstwa', () => this.t('source_safety'))
      Text(this.t('external_links')).fontSize(12).fontColor(MUTED).width('100%')
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  private settingsChoice(label: () => string, id: string, selected: () => boolean, action: () => void) {
    Button({ type: ButtonType.Normal }) {
      Row({ space: 16 }) {
        Text(label()).fontSize(16).fontColor(INK).layoutWeight(1)
        SymbolGlyph(selected() ? $r('sys.symbol.checkmark_circle_fill_1') : $r('sys.symbol.circle'))
          .fontSize(22).maxFontScale(1).fontColor([selected() ? SUCCESS : MUTED]).accessibilityLevel('no')
      }.width('100%').padding(16)
    }.id(id).width('100%').constraintSize({ minHeight: 54 }).backgroundColor(SURFACE).borderRadius(0)
      .accessibilityText(label()).accessibilitySelected(selected()).enabled(!this.settingsBusy).onClick(action)
  }

  @Builder
  private settingsView() {
    Column({ space: 12 }) {
      this.section('theme_label')
      Column() {
        this.settingsChoice(() => this.t('theme_auto'), 'themeSystem', () => this.themePreference === 'system', () => { this.chooseTheme('system'); })
        this.divider()
        this.settingsChoice(() => this.t('theme_light'), 'themeLight', () => this.themePreference === 'light', () => { this.chooseTheme('light'); })
        this.divider()
        this.settingsChoice(() => this.t('theme_dark'), 'themeDark', () => this.themePreference === 'dark', () => { this.chooseTheme('dark'); })
      }.width('100%').borderRadius(12).clip(true)
      Text(this.t('theme_auto_hint')).fontSize(12).fontColor(MUTED).width('100%')
      this.section('language_label')
      Column() {
        this.settingsChoice(() => 'Polski', 'languagePl', () => this.language === 'pl', () => { this.chooseLanguage('pl'); })
        this.divider()
        this.settingsChoice(() => 'English', 'languageEn', () => this.language === 'en', () => { this.chooseLanguage('en'); })
      }.width('100%').borderRadius(12).clip(true)
      Text(this.t('text_size_hint')).fontSize(12).fontColor(MUTED).width('100%')
      this.divider()
      this.rowLink($r('sys.symbol.checkmark_shield'), () => this.t('diagnostics_title'), () => this.t('diagnostics_hint'),
        'settingsDiagnostics', () => { this.diagnosticsParent = 4; this.selectTab(5); })
      this.section('about_app')
      Text(this.t('about_body')).fontSize(14).fontColor(MUTED).width('100%')
      Text(this.t('pack_date') + ': ' + this.map.sourceDate + ' · ' + this.map.packSize).fontSize(12).fontColor(MUTED).width('100%')
      this.sourceLink('https://dane.gov.pl/pl/dataset/28058,punkty-schronienia-w-polsce', () => this.t('source_psp'))
      this.sourceLink('https://www.openstreetmap.org/copyright', () => this.t('source_osm'))
      Text('SafeMesh 1.3.0').fontSize(12).fontColor(MUTED).width('100%')
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  private diagnosticsView() {
    Column({ space: 16 }) {
      Text(this.t('diagnostics_intro')).fontSize(15).fontColor(MUTED).width('100%')
      this.section('exercise_actions')
      this.action(() => this.t(this.alerts.busy ? 'verifying' : 'receive_drill'), 'diagnosticDrill',
        () => { this.loadDrill(); }, () => this.initialized && !this.alerts.busy)
      if (this.relay.transportMode === 'emulator' && this.connected()) {
        this.action(() => this.t('lab_send_drill'), 'labSendDrill', () => { this.sendLabDrill(); }, () => !this.labBusy, false)
      }
      this.divider()
      this.section('simulation')
      Text(this.t('no_radio')).fontSize(13).fontColor(MUTED).width('100%')
      this.action(() => this.t(this.relay.running ? 'drill_running' : 'run_drill'), 'runRelay',
        () => { this.relay.simulate(); }, () => this.initialized && !this.relay.running, false)
      Text(this.t('test_' + this.relay.testState)).id('relayTestStatus').fontSize(16).fontWeight(FontWeight.Medium).fontColor(INK).width('100%')
      ForEach(this.relay.events, (event: RelayEvent) => {
        Column({ space: 6 }) {
          Text(this.t(event.titleKey)).fontSize(15).fontWeight(FontWeight.Medium).fontColor(event.good ? SUCCESS : $r('app.color.danger')).width('100%')
          Text(this.t(event.detailKey)).fontSize(13).fontColor(MUTED).width('100%')
          if (!event.good) { Text(this.t('packet_' + event.status)).fontSize(13).fontColor(MUTED).width('100%') }
          this.divider()
        }.width('100%').padding({ top: 8, bottom: 8 })
      }, (event: RelayEvent) => event.id + this.language)
      this.section('delivery_details')
      Text(this.t('lab_received') + ': ' + this.relay.acceptedCount + '\n' + this.t('lab_rejected') + ': ' + this.relay.rejectedCount +
        '\n' + this.t('queue_failed') + ': ' + this.relay.failedCount).fontSize(14).fontColor(INK).width('100%')
      Text(this.t('queue_note')).fontSize(12).fontColor(MUTED).width('100%')
      this.divider()
      this.section('physical_radio')
      Text(this.t('nearlink_notice')).fontSize(14).fontColor(MUTED).width('100%')
      this.action(() => this.t('check_hardware'), 'checkNearLink', () => { this.relay.probe(); }, () => this.initialized && !this.labBusy, false)
      if (this.relay.transportMode === 'nearlink') {
        Text(this.t('hardware_' + this.relay.hardwareState)).id('nearlinkStatus').fontSize(14).fontColor(MUTED).width('100%')
        if (this.relay.hardwareSupported) {
          TextInput({ placeholder: this.t('peer_name'), text: this.relay.peerName }).id('peerName')
            .fontSize(16).constraintSize({ minHeight: 48 }).fontColor(INK).backgroundColor(SURFACE)
            .onChange((value: string) => { this.relay.peerName = value; })
          this.action(() => this.t('start_relay'), 'startHardware', () => { this.relay.startHardware(); })
          ForEach(this.relay.peers, (peer: PeerViewModel) => {
            this.action(() => peer.name + ' · ' + this.t(peer.connected ? 'connected_short' : 'connect'),
              'peer_' + peer.address, () => { this.relay.connect(peer.address); }, () => !peer.connected, false)
          }, (peer: PeerViewModel) => peer.address)
          this.action(() => this.t('share_alert'), 'shareAlert', () => { this.relay.share(); }, () => this.alerts.received)
          this.action(() => this.t('stop_relay'), 'stopRelay', () => { this.relay.stop(); }, () => true, false)
        }
      }
      Text(this.t('trust_body')).fontSize(13).fontColor(MUTED).width('100%')
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  private navItem(index: number, key: string, icon: Resource) {
    Button({ type: ButtonType.Normal }) {
      Column({ space: 5 }) {
        SymbolGlyph(icon).fontSize(23).maxFontScale(1).fontColor([this.tab === index ? SUCCESS : MUTED])
          .fontWeight(this.tab === index ? FontWeight.Bold : FontWeight.Normal).accessibilityLevel('no')
        Text(this.t(key)).fontSize(12).fontWeight(this.tab === index ? FontWeight.Bold : FontWeight.Normal)
          .fontColor(this.tab === index ? INK : MUTED).textAlign(TextAlign.Center).width('100%')
      }.width('100%')
    }.layoutWeight(1).constraintSize({ minHeight: 56 }).padding({ left: 2, right: 2, top: 8, bottom: 8 })
      .backgroundColor(Color.Transparent).borderRadius(8).id('tab' + index)
      .accessibilityText(this.t(key)).accessibilitySelected(this.tab === index).onClick(() => { this.selectTab(index); })
  }

  @Builder
  private navigation() {
    Column() {
      this.divider()
      if (this.fontScale >= 1.6 || this.viewportWidth < 340) {
        Column({ space: 2 }) {
          Row({ space: 4 }) { this.navItem(0, 'home', $r('sys.symbol.house')); this.navItem(1, 'map', $r('sys.symbol.map')) }.width('100%')
          Row({ space: 4 }) { this.navItem(2, 'relay', $r('sys.symbol.phone_transmission_phone')); this.navItem(3, 'guide', $r('sys.symbol.book')) }.width('100%')
        }.padding(6).width('100%')
      } else {
        Row({ space: 4 }) {
          this.navItem(0, 'home', $r('sys.symbol.house'))
          this.navItem(1, 'map', $r('sys.symbol.map'))
          this.navItem(2, 'relay', $r('sys.symbol.phone_transmission_phone'))
          this.navItem(3, 'guide', $r('sys.symbol.book'))
        }.width('100%').padding({ left: 8, right: 8, top: 4, bottom: 4 })
      }
    }.width('100%').backgroundColor(SURFACE)
  }

  build() {
    Column() {
      this.header()
      Scroll(this.pageScroll) {
        Column({ space: 16 }) {
          if (this.notice.length > 0) {
            Row({ space: 8 }) {
              Text(this.notice).fontSize(14).fontColor(INK).layoutWeight(1)
              this.iconButton($r('sys.symbol.xmark'), () => this.t('dismiss'), 'dismissNotice', () => { this.notice = ''; })
            }.padding({ left: 12 }).width('100%').backgroundColor(SOFT).borderRadius(10)
          }
          if (this.tab === 0) { this.homeView() }
          else if (this.tab === 1) { this.mapView() }
          else if (this.tab === 2) { this.relayView() }
          else if (this.tab === 3) { this.guideView() }
          else if (this.tab === 4) { this.settingsView() }
          else if (this.tab === 5) { this.diagnosticsView() }
          else { this.pointDetail() }
        }.width('100%').constraintSize({ maxWidth: 680 }).padding({ left: 20, right: 20, top: 12, bottom: 24 })
      }.layoutWeight(1).width('100%').scrollBar(BarState.Auto).align(Alignment.Top)
      if (this.tab < 4) { this.navigation() }
    }.width('100%').height('100%').backgroundColor(PAPER)
      .onAreaChange((_old: Area, area: Area) => { this.viewportWidth = Number(area.width); this.viewportHeight = Number(area.height); })
  }
}
