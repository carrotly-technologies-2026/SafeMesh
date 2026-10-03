import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { accessibility } from '@kit.AccessibilityKit';
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

@Entry
@Component
struct Index {
  @State tab: number = 0;
  @State mapRevision: number = 0;
  @State notice: string = '';
  @State language: string = 'pl';
  @State themePreference: string = 'system';
  @State settingsBusy: boolean = true;
  @State query: string = '';
  @State labVisible: boolean = false;
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
  private expiryTimer: number = -1;
  private pageScroll: Scroller = new Scroller();
  private lastAnnouncedAlert: string = '';
  private lastAnnouncedRelay: string = '';
  private previousTab: number = 0;

  aboutToAppear(): void {
    const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.copy.initialize(context);
    this.initialize(context);
    this.expiryTimer = setInterval(() => { this.alerts.refreshExpiry(); }, 10000);
  }

  onPageHide(): void { this.relay.stop(); }

  onBackPress(): boolean {
    if (this.tab !== 4) { return false; }
    this.closeSettings();
    return true;
  }

  aboutToDisappear(): void {
    if (this.expiryTimer !== -1) { clearInterval(this.expiryTimer); }
    this.alerts.dispose();
    this.relay.stop();
  }

  private t(key: string): string { return this.copy.text(key, this.language); }

  private async initialize(context: common.UIAbilityContext): Promise<void> {
    try {
      await this.store.init(context);
      const savedLanguage: string = await this.store.read('ui_language');
      this.language = savedLanguage === 'en' ? 'en' : 'pl';
      context.getApplicationContext().setLanguage(this.language);
      const savedTheme: string = await this.store.read('ui_theme');
      this.themePreference = savedTheme === 'light' || savedTheme === 'dark' ? savedTheme : 'system';
      this.applyTheme(this.themePreference);
      await this.map.restoreSaved(this.store);
      this.relay.setContext(context);
      await this.alerts.restore();
      await this.relay.probe();
    } catch (error) {
      console.error('SAFEMESH_INIT_ERROR ' + String(error));
      this.notice = this.t('init_failed');
    }
    finally { this.settingsBusy = false; }
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
    const identity: string = this.alerts.received ? this.alerts.title + this.alerts.issueTime : '';
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
    if (!this.relay.running && this.relay.events.length > 0 && this.relay.testStatus !== this.lastAnnouncedRelay) {
      this.lastAnnouncedRelay = this.relay.testStatus;
      this.announce(this.t('diagnostics') + ': ' + this.relay.testStatus);
    }
  }

  private selectPoint(id: string): void {
    this.map.select(id);
    this.mapRevision++;
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

  private closeSettings(): void {
    this.selectTab(this.previousTab);
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
    try { await this.relay.startEmulator(this.labNode); }
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
    const query: string = this.query.trim().toLocaleLowerCase();
    return this.map.points.filter((point: SafePointViewModel) =>
      query.length === 0 || point.address.toLocaleLowerCase().includes(query));
  }

  private availability(value: string): string {
    if (value === 'Na żądanie') { return this.t('availability_request'); }
    if (value === 'Całodobowa') { return this.t('availability_all_day'); }
    if (value === 'Określone godziny') { return this.t('availability_hours'); }
    return value;
  }

  @Builder
  private action(label: () => string, id: string, action: () => void, enabled: () => boolean = () => true, primary: boolean = true) {
    Button({ type: ButtonType.Normal }) {
      Text(label()).fontSize(16).fontWeight(FontWeight.Medium)
        .fontColor(primary ? ACTION_FG : INK).textAlign(TextAlign.Center).width('100%')
    }.id(id).width('100%').constraintSize({ minHeight: 48 }).padding(14)
      .backgroundColor(primary ? ACTION_BG : SOFT).borderRadius(16)
      .enabled(enabled()).opacity(enabled() ? 1 : 0.6).onClick(action)
      .accessibilityText(label())
  }

  @Builder
  private heading(title: () => string, subtitle: () => string) {
    Column({ space: 8 }) {
      Text(title()).fontSize(28).fontWeight(FontWeight.Bold).fontColor(INK).width('100%')
      Text(subtitle()).fontSize(16).fontColor(MUTED).width('100%')
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  private header() {
    Row({ space: 8 }) {
      if (this.tab === 4) {
        Button({ type: ButtonType.Normal }) {
          SymbolGlyph($r('sys.symbol.arrow_left')).fontSize(24).maxFontScale(1).fontColor([INK])
            .accessibilityLevel('no')
        }.id('backSettings').width(48).height(48).backgroundColor(SOFT).borderRadius(24)
          .accessibilityText(this.t('back_settings')).onClick(() => { this.closeSettings(); })
        Text(this.t('settings_tab')).fontSize(23).fontWeight(FontWeight.Bold).fontColor(INK).layoutWeight(1)
      } else {
        Text('safemesh').fontSize(23).fontWeight(FontWeight.Bold).fontColor(INK).layoutWeight(1)
        Button({ type: ButtonType.Normal }) {
          SymbolGlyph($r('sys.symbol.gearshape')).fontSize(24).maxFontScale(1).fontColor([INK])
            .accessibilityLevel('no')
        }.id('openSettings').width(48).height(48).backgroundColor(SOFT).borderRadius(24)
          .accessibilityText(this.t('open_settings')).onClick(() => { this.openSettings(); })
      }
    }.width('100%').constraintSize({ maxWidth: 720 }).padding({ left: 20, right: 20, top: 8, bottom: 8 })
  }

  @Builder
  private drillBanner() {
    Text(this.t('exercise') + ' · ' + this.t('exercise_notice'))
      .fontSize(13).fontColor(WARNING_FG).width('100%').padding(14)
      .backgroundColor(WARNING_BG).borderRadius(14)
  }

  @Builder
  private alertCard() {
    Column({ space: 12 }) {
      Text(this.t(this.alerts.received ? 'verified_exercise' : 'no_alert'))
        .fontSize(14).fontWeight(FontWeight.Bold).fontColor(WARNING_FG)
      Text(this.alerts.received ? this.alerts.title : this.t('ready_title'))
        .fontSize(25).fontWeight(FontWeight.Bold).fontColor(INK).width('100%')
      if (this.alerts.received) {
        Text(this.t('signature_verified')).fontSize(14).fontWeight(FontWeight.Medium).fontColor($r('app.color.success'))
        Text(this.t('signed_original')).fontSize(12).fontColor(MUTED)
      }
      Text(this.alerts.received ? this.alerts.body : this.t('ready_body')).fontSize(16).fontColor(INK).width('100%')
      if (this.alerts.received) {
        Text(this.t('valid_until') + ': ' + this.alerts.expiry).fontSize(14).fontColor(MUTED)
        Text(this.t('persistence_' + this.alerts.persistenceState)).fontSize(13).fontColor(MUTED)
      }
      this.action(() => this.t(this.alerts.busy ? 'verifying' : this.alerts.received ? 'see_relay' : 'receive_drill'), 'receiveDrill', () => { if (this.alerts.received) { this.selectTab(2); } else { this.loadDrill(); } }, () => !this.alerts.busy)
    }.width('100%').alignItems(HorizontalAlign.Start).padding(20).backgroundColor(WARNING_BG).borderRadius(24)
  }

  @Builder
  private homeView() {
    Column({ space: 20 }) {
      this.alertCard()
      Column({ space: 14 }) {
        Text(this.t('offline_area')).fontSize(14).fontWeight(FontWeight.Bold).fontColor(MUTED)
        Text(this.t('central_krakow')).fontSize(24).fontWeight(FontWeight.Bold).fontColor(INK)
        OfflineMap({ vm: this.map, revision: this.mapRevision + this.themeRevision, dark: this.dark, compact: true,
          description: this.t('map_description'), onSelect: (id: string) => { this.selectPoint(id); this.selectTab(1); } })
          .height(this.viewportHeight < 480 ? 140 : 180).borderRadius(16).clip(true)
        Text(this.map.attribution).fontSize(12).fontColor(MUTED).width('100%')
        Text(this.map.points.length + ' ' + this.t('point_count')).fontSize(18).fontWeight(FontWeight.Bold).fontColor(INK)
        Text(this.t('bundled_points')).fontSize(14).fontColor(MUTED)
        this.action(() => this.t('explore'), 'exploreMap', () => { this.selectTab(1); }, () => true, false)
        if (this.map.savedId.length > 0) {
          this.action(() => this.t('open_saved'), 'homeSavedPoint', () => {
            if (this.map.openSaved()) { this.mapRevision++; this.selectTab(1); }
          }, () => true, false)
        }
      }.width('100%').alignItems(HorizontalAlign.Start).padding(20).backgroundColor(SOFT).borderRadius(24)
      Text(this.t('offline_ready')).fontSize(14).fontColor(MUTED).width('100%')
      this.heading(() => this.t('community'), () => this.t('community_body'))
      this.action(() => this.t('see_relay'), 'exploreRelay', () => { this.selectTab(2); }, () => true, false)
    }.width('100%')
  }

  @Builder
  private mapControls() {
    Row({ space: 8 }) {
      Button('+').id('zoomIn').constraintSize({ minWidth: 48, minHeight: 48 }).fontSize(24).padding(8)
        .fontColor(INK).backgroundColor(SURFACE).accessibilityText(this.t('zoom_in'))
        .onClick(() => { this.map.changeZoom(0.5); this.mapRevision++; })
      Button('−').id('zoomOut').constraintSize({ minWidth: 48, minHeight: 48 }).fontSize(24).padding(8)
        .fontColor(INK).backgroundColor(SURFACE).accessibilityText(this.t('zoom_out'))
        .onClick(() => { this.map.changeZoom(-0.5); this.mapRevision++; })
      Button({ type: ButtonType.Normal }) {
        Text(this.t('recenter')).fontSize(14).fontColor(INK).textAlign(TextAlign.Center)
      }.id('recenterMap').constraintSize({ minHeight: 48 }).layoutWeight(1).padding(12)
        .backgroundColor(SURFACE).borderRadius(16).accessibilityText(this.t('recenter'))
        .onClick(() => { this.map.recenter(); this.mapRevision++; })
    }.width('100%')
  }

  @Builder
  private selectedPoint() {
    Column({ space: 10 }) {
      Text(this.t('selected_point')).fontSize(14).fontWeight(FontWeight.Bold).fontColor(MUTED)
      Text(this.map.selected().address).fontSize(23).fontWeight(FontWeight.Bold).fontColor(INK).width('100%')
      Text(this.t('point_type') + ' · ' + this.availability(this.map.selected().availability))
        .fontSize(16).fontColor(INK).width('100%')
      Text(this.map.selected().distanceLabel).fontSize(16).fontWeight(FontWeight.Bold).fontColor(INK)
      Text(this.t('access_notice')).fontSize(14).fontColor(MUTED).width('100%')
      this.action(() => this.t(this.map.saveBusy ? 'saving' :
        this.map.savedId === this.map.selectedId ? 'saved_point' : 'save_point'), 'savePoint', () => { this.savePoint(); }, () => !this.map.saveBusy)
      if (this.map.saveError.length > 0) {
        Text(this.t(this.map.saveError === 'load_failed' ? 'saved_load_failed' : 'save_failed'))
          .fontSize(14).fontColor($r('app.color.danger')).width('100%')
      }
    }.alignItems(HorizontalAlign.Start).padding(20).width('100%').backgroundColor(SURFACE).borderRadius(24)
  }

  @Builder
  private mapView() {
    Column({ space: 18 }) {
      this.heading(() => this.t('find_point'), () => this.t('central_krakow'))
      Text(this.t('map_description')).fontSize(14).fontColor(MUTED).width('100%')
      Text(this.t(this.map.originIsDevice ? 'device_origin' : 'demo_origin')).fontSize(14).fontColor(MUTED).width('100%')
      OfflineMap({ vm: this.map, revision: this.mapRevision + this.themeRevision, dark: this.dark, description: this.t('map_description'),
        onSelect: (id: string) => { this.selectPoint(id); } })
        .height(this.viewportHeight < 480 ? 200 : 280).width('100%').borderRadius(20).clip(true)
      this.mapControls()
      Text(this.map.attribution).fontSize(12).fontColor(MUTED).width('100%')
      this.action(() => this.t(this.map.locationBusy ? 'locating' : 'use_location'), 'useLocation', () => { this.useLocation(); }, () => !this.map.locationBusy, false)
      if (this.map.locationStatus !== 'demo') {
        Text(this.locationMessage()).fontSize(14).fontColor(MUTED).width('100%')
      }
      if (this.map.originIsDevice) {
        Text(this.t('accuracy') + ': ' + Math.round(this.map.locationAccuracy) + ' m').fontSize(14).fontColor(MUTED)
        this.action(() => this.t('reset_origin'), 'resetOrigin', () => { this.map.resetOrigin(); this.mapRevision++; }, () => true, false)
      }
      this.selectedPoint()
      if (this.map.savedId.length > 0 && this.map.savedId !== this.map.selectedId) {
        this.action(() => this.t('open_saved'), 'openSavedPoint', () => {
          if (this.map.openSaved()) { this.mapRevision++; }
        }, () => true, false)
      }
      Text(this.t('distance_notice')).fontSize(14).fontColor(MUTED).width('100%')
      Text(this.t('all_points')).fontSize(23).fontWeight(FontWeight.Bold).fontColor(INK).width('100%')
      TextInput({ placeholder: this.t('search_points'), text: this.query }).id('searchPoints')
        .fontSize(16).constraintSize({ minHeight: 52 }).backgroundColor(SURFACE).fontColor(INK)
        .placeholderColor(MUTED).accessibilityText(this.t('search_points'))
        .onChange((value: string) => { this.query = value; })
      Text(this.t('results') + ': ' + this.filteredPoints().length + ' / ' + this.map.points.length)
        .fontSize(14).fontColor(MUTED).width('100%')
      ForEach(this.filteredPoints(), (point: SafePointViewModel) => {
        Button({ type: ButtonType.Normal }) {
          Column({ space: 6 }) {
            Text(point.address).fontSize(16).fontWeight(FontWeight.Medium).fontColor(INK).width('100%')
            Text(this.availability(point.availability) + ' · ' + point.distanceLabel).fontSize(14).fontColor(MUTED).width('100%')
          }.width('100%').alignItems(HorizontalAlign.Start)
        }.id('point_' + point.id).width('100%').constraintSize({ minHeight: 64 }).padding(16)
          .backgroundColor(point.id === this.map.selectedId ? SOFT : SURFACE).borderRadius(16)
          .accessibilityText(point.address + ', ' + this.availability(point.availability) + ', ' + point.distanceLabel)
          .accessibilitySelected(point.id === this.map.selectedId)
          .onClick(() => { this.selectPoint(point.id); this.pageScroll.scrollTo({ xOffset: 0, yOffset: 0 }); })
      }, (point: SafePointViewModel) => point.id)
      if (this.filteredPoints().length === 0) {
        Text(this.t('no_results')).fontSize(16).fontColor(INK).width('100%')
      }
      Text(this.t('pack_date') + ': ' + this.map.sourceDate + ' · ' + this.map.packSize)
        .fontSize(13).fontColor(MUTED).width('100%')
    }.width('100%')
  }

  @Builder
  private nodeBadge(letter: string, label: () => string, level: number) {
    Column({ space: 8 }) {
      Text(letter).fontSize(26).fontWeight(FontWeight.Bold).fontColor(INK)
      Text(label()).fontSize(14).fontColor(INK).textAlign(TextAlign.Center).width('100%')
    }.layoutWeight(1).padding(12).constraintSize({ minHeight: 84 })
      .backgroundColor(this.relay.stage >= level ? SOFT : SURFACE).borderRadius(16)
      .accessibilityGroup(true)
  }

  @Builder
  private labNodeChoice(node: string) {
    Button({ type: ButtonType.Normal }) {
      Text(node).fontSize(20).fontWeight(FontWeight.Bold).fontColor(this.labNode === node ? ACTION_FG : INK)
    }.id('labNode' + node).layoutWeight(1).constraintSize({ minHeight: 48 })
      .backgroundColor(this.labNode === node ? ACTION_BG : SOFT).borderRadius(16)
      .accessibilityText(this.t('lab_node') + ' ' + node).accessibilitySelected(this.labNode === node)
      .enabled(!this.labBusy).onClick(() => { this.labNode = node; })
  }

  @Builder
  private meshLabView() {
    Column({ space: 14 }) {
      Text(this.t('lab_title')).fontSize(23).fontWeight(FontWeight.Bold).fontColor(INK).width('100%')
      Text(this.t('lab_explanation')).fontSize(14).fontColor(MUTED).width('100%')
      Text(this.t('lab_node')).fontSize(16).fontWeight(FontWeight.Bold).fontColor(INK).width('100%')
      Row({ space: 8 }) {
        this.labNodeChoice('A')
        this.labNodeChoice('B')
        this.labNodeChoice('C')
      }.width('100%')
      this.action(() => this.t(this.labBusy ? 'lab_connecting' : 'lab_connect') + ' ' + this.labNode,
        'labStart', () => { this.startLab(); }, () => !this.labBusy)
      if (this.relay.transportMode === 'emulator') {
        Text(this.t('lab_active') + ' ' + this.relay.emulatorNode).id('labActiveNode')
          .fontSize(18).fontWeight(FontWeight.Bold).fontColor(INK).width('100%')
        Text(this.t('hardware_' + this.relay.hardwareState)).id('labStatus')
          .fontSize(16).fontColor(INK).width('100%')
        if (this.relay.hardwareState === 'lab_error' || this.relay.hardwareState === 'restore_failed') {
          Text(this.t('diagnostics') + ': ' + this.relay.hardwareStatus).id('labConnectionDetail')
            .fontSize(13).fontColor(MUTED).width('100%')
        }
        Text(this.t('lab_peers') + ': ' + this.relay.peerCount).id('labPeerCount')
          .fontSize(16).fontColor(INK).width('100%')
        ForEach(this.relay.peers, (peer: PeerViewModel) => {
          Text(peer.name + ' · ' + this.t(peer.connected ? 'connected_short' : 'lab_disconnected_peer'))
            .fontSize(14).fontColor(MUTED).width('100%')
        }, (peer: PeerViewModel) => peer.address)
        this.action(() => this.t('lab_send_drill'), 'labSendDrill', () => { this.sendLabDrill(); },
          () => !this.labBusy && !this.alerts.busy)
        this.action(() => this.t('share_alert'), 'labShare', () => { this.relay.share(); },
          () => !this.labBusy && this.alerts.received, false)
        this.action(() => this.t('lab_disconnect'), 'labStop', () => { this.relay.stop(); },
          () => !this.labBusy, false)
        Text(this.t('lab_received') + ': ' + this.relay.acceptedCount + '\n' +
          this.t('lab_rejected') + ': ' + this.relay.rejectedCount + '\n' +
          this.t('queue_pending') + ': ' + this.relay.pendingCount + '\n' +
          this.t('queue_acked') + ': ' + this.relay.acknowledgedCount + '\n' +
          this.t('queue_retry') + ': ' + this.relay.retryCount + '\n' +
          this.t('queue_failed') + ': ' + this.relay.failedCount)
          .id('labMetrics').fontSize(14).fontColor(INK).width('100%')
        Text(this.t('diagnostics') + ': ' + this.relay.lastPacketStatus)
          .id('labPacketStatus').fontSize(13).fontColor(MUTED).width('100%')
        this.action(() => this.t('lab_return_radio'), 'labReturnRadio', () => { this.relay.probe(); },
          () => !this.labBusy, false)
      }
      Text(this.t('lab_topology')).fontSize(14).fontColor(MUTED).width('100%')
    }.padding(20).width('100%').alignItems(HorizontalAlign.Start).backgroundColor(SURFACE).borderRadius(24)
  }

  @Builder
  private relayView() {
    Column({ space: 18 }) {
      this.heading(() => this.t('relay_title'), () => this.t('relay_intro'))
      this.action(() => this.t(this.labVisible ? 'lab_hide' : 'lab_open'), 'openMeshLab',
        () => { this.labVisible = !this.labVisible; }, () => true, false)
      if (this.labVisible) { this.meshLabView() }
      Column({ space: 16 }) {
        Text(this.t('simulation')).fontSize(20).fontWeight(FontWeight.Bold).fontColor(INK).width('100%')
        Text(this.t('no_radio')).fontSize(14).fontColor(MUTED).width('100%')
        Row({ space: 8 }) {
          this.nodeBadge('A', () => this.t('node_a'), 1)
          this.nodeBadge('B', () => this.t('node_b'), 2)
          this.nodeBadge('C', () => this.t('node_c'), 3)
        }.width('100%')
        this.action(() => this.t(this.relay.running ? 'drill_running' : 'run_drill'), 'runRelay', () => { this.relay.simulate(); }, () => !this.relay.running)
        Text(this.t('diagnostics')).fontSize(14).fontWeight(FontWeight.Bold).fontColor(MUTED)
        Text(this.relay.testStatus).id('relayTestStatus').fontSize(16).fontColor(INK).width('100%')
      }.alignItems(HorizontalAlign.Start).padding(20).width('100%').backgroundColor(SOFT).borderRadius(24)
      ForEach(this.relay.events, (event: RelayEvent) => {
        Column({ space: 8 }) {
          Text((event.good ? '✓ ' : '! ') + event.title).fontSize(16).fontWeight(FontWeight.Medium).fontColor(INK).width('100%')
          Text(event.detail).fontSize(14).fontColor(MUTED).width('100%')
        }.padding(16).width('100%').backgroundColor(SURFACE).borderRadius(16).accessibilityGroup(true)
      }, (event: RelayEvent) => event.id)
      if (this.relay.transportMode !== 'emulator') {
      Column({ space: 14 }) {
        Text('NearLink').fontSize(24).fontWeight(FontWeight.Bold).fontColor(INK)
        Text(this.relay.peerCount + ' ' + this.t('connected')).fontSize(14).fontColor(MUTED)
        Text(this.t('hardware_' + this.relay.hardwareState)).fontSize(16).fontColor(INK).width('100%').id('nearlinkStatus')
        if (this.relay.hardwareState === 'error' || this.relay.hardwareState === 'queue_error' ||
          this.relay.hardwareState === 'restore_failed' || this.relay.hardwareState === 'cleanup_failed') {
          Text(this.t('diagnostics') + ': ' + this.relay.hardwareStatus).fontSize(13).fontColor(MUTED).width('100%')
        }
        Text(this.t('nearlink_notice')).fontSize(14).fontColor(MUTED).width('100%')
        Text(this.t('queue_metrics')).fontSize(16).fontWeight(FontWeight.Bold).fontColor(INK).width('100%')
        Text(this.t('queue_pending') + ': ' + this.relay.pendingCount + '\n' +
          this.t('queue_acked') + ': ' + this.relay.acknowledgedCount + '\n' +
          this.t('queue_retry') + ': ' + this.relay.retryCount + '\n' +
          this.t('queue_failed') + ': ' + this.relay.failedCount).fontSize(14).fontColor(INK).width('100%')
        Text(this.t('queue_note')).fontSize(13).fontColor(MUTED).width('100%')
        this.action(() => this.t('check_hardware'), 'checkNearLink', () => { this.relay.probe(); }, () => true, false)
        if (this.relay.hardwareSupported) {
          TextInput({ placeholder: this.t('peer_name'), text: this.relay.peerName }).id('peerName')
            .fontSize(16).constraintSize({ minHeight: 52 }).backgroundColor(SOFT).fontColor(INK).placeholderColor(MUTED)
            .accessibilityText(this.t('peer_name')).onChange((value: string) => { this.relay.peerName = value; })
          this.action(() => this.t('start_relay'), 'startHardware', () => { this.relay.startHardware(); })
          ForEach(this.relay.peers, (peer: PeerViewModel) => {
            this.action(() => peer.name + ' · ' + this.t(peer.connected ? 'connected_short' : 'connect'), 'peer_' + peer.address, () => { this.relay.connect(peer.address); }, () => !peer.connected, false)
          }, (peer: PeerViewModel) => peer.address)
          this.action(() => this.t('share_alert'), 'shareAlert', () => { this.relay.share(); }, () => this.alerts.received)
          this.action(() => this.t('stop_relay'), 'stopRelay', () => { this.relay.stop(); }, () => true, false)
        }
      }.padding(20).width('100%').alignItems(HorizontalAlign.Start).backgroundColor(SURFACE).borderRadius(24)
      }
      Text(this.t('technical_note')).fontSize(13).fontColor(MUTED).width('100%')
    }.width('100%')
  }

  @Builder
  private guideItem(number: string, title: () => string, detail: () => string) {
    Column({ space: 10 }) {
      Text(number + ' · ' + title()).fontSize(19).fontWeight(FontWeight.Bold).fontColor(INK).width('100%')
      Text(detail()).fontSize(16).fontColor(INK).width('100%')
    }.width('100%').alignItems(HorizontalAlign.Start).padding(20).backgroundColor(SURFACE).borderRadius(20)
  }

  @Builder
  private sourceLink(url: string, label: () => string) {
    Hyperlink(url, label()).color(INK).width('100%')
      .constraintSize({ minHeight: 48 }).padding({ top: 12, bottom: 12 })
  }

  @Builder
  private guideView() {
    Column({ space: 20 }) {
      this.heading(() => this.t('guide_title'), () => this.t('guide_intro'))
      this.guideItem('01', () => this.t('guide1_title'), () => this.t('guide1_body'))
      this.guideItem('02', () => this.t('guide2_title'), () => this.t('guide2_body'))
      this.guideItem('03', () => this.t('guide3_title'), () => this.t('guide3_body'))
      this.guideItem('04', () => this.t('guide4_title'), () => this.t('guide4_body'))
      Column({ space: 12 }) {
        Text(this.t('trust_title')).fontSize(23).fontWeight(FontWeight.Bold).fontColor(INK).width('100%')
        Text(this.t('trust_body')).fontSize(16).fontColor(INK).width('100%')
        Text(this.t('trust_limits')).fontSize(14).fontColor(MUTED).width('100%')
      }.padding(20).width('100%').alignItems(HorizontalAlign.Start).backgroundColor(SOFT).borderRadius(24)
      Text(this.t('sources')).fontSize(23).fontWeight(FontWeight.Bold).fontColor(INK).width('100%')
      this.sourceLink('https://www.openstreetmap.org/copyright', () => 'OpenStreetMap contributors · ODbL')
      this.sourceLink('https://dane.gov.pl/pl/dataset/28058,punkty-schronienia-w-polsce', () => this.t('source_psp'))
      this.sourceLink('https://creativecommons.org/licenses/by/4.0/', () => 'CC BY 4.0')
      this.sourceLink('https://www.gov.pl/web/poradnikbezpieczenstwa', () => this.t('source_safety'))
      Text(this.t('external_links')).fontSize(14).fontColor(MUTED).width('100%')
    }.width('100%')
  }

  @Builder
  private settingsChoice(label: () => string, id: string, selected: () => boolean, action: () => void) {
    Button({ type: ButtonType.Normal }) {
      Text((selected() ? '✓  ' : '') + label()).fontSize(16).fontWeight(FontWeight.Medium)
        .fontColor(INK).width('100%')
    }.id(id).width('100%').constraintSize({ minHeight: 52 }).padding(16)
      .backgroundColor(selected() ? SOFT : SURFACE).borderRadius(16)
      .accessibilityText(label()).accessibilitySelected(selected())
      .enabled(!this.settingsBusy).onClick(action)
  }

  @Builder
  private settingsView() {
    Column({ space: 18 }) {
      Text(this.t('settings_intro')).fontSize(16).fontColor(MUTED).width('100%')
      Text(this.t('theme_label')).fontSize(23).fontWeight(FontWeight.Bold).fontColor(INK).width('100%')
      this.settingsChoice(() => this.t('theme_auto'), 'themeSystem', () => this.themePreference === 'system',
        () => { this.chooseTheme('system'); })
      this.settingsChoice(() => this.t('theme_light'), 'themeLight', () => this.themePreference === 'light',
        () => { this.chooseTheme('light'); })
      this.settingsChoice(() => this.t('theme_dark'), 'themeDark', () => this.themePreference === 'dark',
        () => { this.chooseTheme('dark'); })
      Text(this.t('theme_auto_hint')).fontSize(14).fontColor(MUTED).width('100%')
      Text(this.t('language_label')).fontSize(23).fontWeight(FontWeight.Bold).fontColor(INK).width('100%')
      this.settingsChoice(() => 'Polski', 'languagePl', () => this.language === 'pl', () => { this.chooseLanguage('pl'); })
      this.settingsChoice(() => 'English', 'languageEn', () => this.language === 'en', () => { this.chooseLanguage('en'); })
      Text(this.t('text_size_hint')).fontSize(14).fontColor(MUTED).width('100%')
    }.width('100%')
  }

  @Builder
  private navItem(index: number, label: () => string, icon: Resource) {
    Button({ type: ButtonType.Normal }) {
      Column({ space: 4 }) {
        SymbolGlyph(icon).fontSize(24).maxFontScale(1).fontColor([INK])
          .fontWeight(this.tab === index ? FontWeight.Bold : FontWeight.Normal).accessibilityLevel('no')
        Text(label()).fontSize(this.fontScale >= 1.6 ? 13 : 12).fontWeight(this.tab === index ? FontWeight.Bold : FontWeight.Medium)
          .fontColor(INK).textAlign(TextAlign.Center).width('100%')
      }.width('100%')
    }.layoutWeight(1).constraintSize({ minHeight: 48 }).padding({ left: 2, right: 2, top: 8, bottom: 8 })
      .borderRadius(16).backgroundColor(this.tab === index ? SOFT : SURFACE)
      .id('tab' + index).accessibilityText(label()).accessibilitySelected(this.tab === index)
      .onClick(() => { this.selectTab(index); })
  }

  @Builder
  private navigation() {
    if (this.fontScale >= 1.6 || this.viewportWidth < 340) {
      Column({ space: 4 }) {
        Row({ space: 4 }) {
          this.navItem(0, () => this.t('home'), $r('sys.symbol.house'))
          this.navItem(1, () => this.t('map'), $r('sys.symbol.map'))
        }.width('100%')
        Row({ space: 4 }) {
          this.navItem(2, () => this.t('relay'), $r('sys.symbol.phone_transmission_phone'))
          this.navItem(3, () => this.t('guide'), $r('sys.symbol.book'))
        }.width('100%')
      }.padding(8).width('100%').backgroundColor(SURFACE)
    } else {
      Row({ space: 4 }) {
        this.navItem(0, () => this.t('home'), $r('sys.symbol.house'))
        this.navItem(1, () => this.t('map'), $r('sys.symbol.map'))
        this.navItem(2, () => this.t('relay'), $r('sys.symbol.phone_transmission_phone'))
        this.navItem(3, () => this.t('guide'), $r('sys.symbol.book'))
      }.width('100%').padding(8).backgroundColor(SURFACE)
    }
  }

  build() {
    Column() {
      this.header()
      Scroll(this.pageScroll) {
        Column({ space: 16 }) {
          this.drillBanner()
          if (this.relay.transportMode === 'emulator') {
            Text(this.t('lab_banner') + ' ' + this.relay.emulatorNode).id('labBanner')
              .fontSize(14).fontWeight(FontWeight.Bold).fontColor(WARNING_FG).width('100%')
              .padding(12).backgroundColor(WARNING_BG).borderRadius(14)
          }
          if (this.notice.length > 0) {
            Column({ space: 8 }) {
              Text(this.notice).fontSize(16).fontColor(INK).width('100%')
              this.action(() => this.t('dismiss'), 'dismissNotice', () => { this.notice = ''; }, () => true, false)
            }.padding(16).width('100%').backgroundColor(SOFT).borderRadius(16)
          }
          if (this.tab === 0) { this.homeView() }
          else if (this.tab === 1) { this.mapView() }
          else if (this.tab === 2) { this.relayView() }
          else if (this.tab === 3) { this.guideView() }
          else { this.settingsView() }
        }.padding(this.viewportWidth < 340 ? 12 : 20).width('100%').constraintSize({ maxWidth: 720 })
      }.layoutWeight(1).width('100%').scrollBar(BarState.Auto).align(Alignment.Top)
      if (this.tab !== 4) { this.navigation() }
    }.width('100%').height('100%').backgroundColor(PAPER)
      .onAreaChange((_old: Area, area: Area) => {
        this.viewportWidth = Number(area.width);
        this.viewportHeight = Number(area.height);
      })
  }
}
