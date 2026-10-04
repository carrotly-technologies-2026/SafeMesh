import { bundleManager, common, ConfigurationConstant } from '@kit.AbilityKit';
import { accessibility } from '@kit.AccessibilityKit';
import { window } from '@kit.ArkUI';
import { i18n } from '@kit.LocalizationKit';
import { AlertFeedback } from '../model/AlertFeedback';
import { LocalStore } from '../model/LocalStore';
import { AlertViewModel, AlertInboxItem } from '../viewmodel/AlertViewModel';
import { AuthorityViewModel } from '../viewmodel/AuthorityViewModel';
import { MapViewModel } from '../viewmodel/MapViewModel';
import { RelayViewModel } from '../viewmodel/RelayViewModel';
import { HomeScreen, MessageDetailScreen } from '../views/AlertScreens';
import { AuthorityScreen } from '../views/AuthorityScreen';
import { divider, iconButton } from '../views/Controls';
import { DiagnosticsScreen } from '../views/DiagnosticsScreen';
import { GuideScreen } from '../views/GuideScreen';
import { MapScreen, PointDetailScreen } from '../views/MapScreens';
import { RelayScreen } from '../views/RelayScreen';
import { SettingsScreen } from '../views/SettingsScreen';
import { ACTION_BG, ACTION_FG, BORDER, INK, MUTED, PAPER, SOFT, SUCCESS, SURFACE } from '../views/Theme';
import { UiCopy } from '../views/UiCopy';


@Entry
@Component
struct Index {
  @State tab: number = 0;
  @State mapRevision: number = 0;
  @State notice: string = '';
  @State language: string = 'en';
  @State languagePreference: string = 'system';
  @State themePreference: string = 'system';
  @State keepScreenOn: boolean = true;
  @State alertVibration: boolean = true;
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
  private feedback: AlertFeedback = new AlertFeedback();
  private screenKeptOn: boolean = false;
  private appVersion: string = '';
  @State @Watch('onAlertChanged') alerts: AlertViewModel = new AlertViewModel(this.store);
  @State map: MapViewModel = new MapViewModel();
  @State @Watch('onRelayChanged') relay: RelayViewModel = new RelayViewModel(this.alerts);
  @State authority: AuthorityViewModel = new AuthorityViewModel(this.alerts, this.relay);
  private pageScroll: Scroller = new Scroller();
  private lastAnnouncedAlert: string = '';
  private lastAnnouncedRelay: string = '';
  private previousTab: number = 0;
  private pointParent: number = 1;
  private diagnosticsParent: number = 4;
  private messageParent: number = 0;
  private lastArrivalSequence: number = 0;

  aboutToAppear(): void {
    const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.copy.initialize(context);
    try {
      this.appVersion = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT).versionName;
    } catch (error) { this.appVersion = ''; }
    this.initialize(context);
  }

  onPageHide(): void { this.alerts.dispose(); this.relay.suspend(); }

  onPageShow(): void { this.alerts.resume(); this.relay.foreground(); this.followSystemLanguage(); }

  onBackPress(): boolean {
    if (this.tab < 4) { return false; }
    this.goBack();
    return true;
  }

  aboutToDisappear(): void {
    this.applyKeepScreenOn(false);
    this.alerts.dispose();
    this.relay.stop();
    this.authority.dispose();
  }

  private t(key: string): string { return this.copy.text(key, this.language); }

  private async initialize(context: common.UIAbilityContext): Promise<void> {
    this.relay.setContext(context);
    try {
      await this.store.init(context);
      const savedLanguage: string = await this.store.read('ui_language');
      // No saved choice (or 'system') follows the device language; 'pl'/'en' are explicit choices.
      this.languagePreference = savedLanguage === 'pl' || savedLanguage === 'en' ? savedLanguage : 'system';
      this.language = this.resolvedLanguage(this.languagePreference);
      this.authority.draftLanguage = this.language;
      context.getApplicationContext().setLanguage(this.language);
      this.alerts.setLanguage(this.language);
      const savedNode: string = await this.store.read('lab_node');
      this.labNode = savedNode === 'B' || savedNode === 'C' ? savedNode : 'A';
      const savedTheme: string = await this.store.read('ui_theme');
      this.themePreference = savedTheme === 'light' || savedTheme === 'dark' ? savedTheme : 'system';
      this.applyTheme(this.themePreference);
      // Both relay comfort settings default to on; only an explicit 'off' disables them.
      this.keepScreenOn = (await this.store.read('keep_screen_on')) !== 'off';
      this.alertVibration = (await this.store.read('alert_vibration')) !== 'off';
      await this.map.restoreSaved(this.store);
      await this.alerts.restore();
      await this.relay.probe();
    } catch (error) {
      console.error('SAFEMESH_INIT_ERROR ' + String(error));
      this.notice = this.t('init_failed');
    }
    finally { this.initialized = true; this.settingsBusy = false; }
  }

  /** A Polish system language selects Polish; every other locale selects English. */
  private systemLanguage(): string {
    try { return i18n.System.getSystemLanguage().toLowerCase().startsWith('pl') ? 'pl' : 'en'; }
    catch (error) { return 'en'; }
  }

  private resolvedLanguage(preference: string): string {
    return preference === 'pl' || preference === 'en' ? preference : this.systemLanguage();
  }

  /** With the System preference, a device language change applies when the app returns to the foreground. */
  private followSystemLanguage(): void {
    if (!this.initialized || this.languagePreference !== 'system') { return; }
    const language: string = this.systemLanguage();
    if (language === this.language) { return; }
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      context.getApplicationContext().setLanguage(language);
      this.language = language;
      this.alerts.setLanguage(language);
    } catch (error) { this.notice = this.t('language_failed'); }
  }

  /** preference is 'system', 'pl' or 'en'; the stored value is the preference, not the resolved language. */
  private async chooseLanguage(preference: string): Promise<void> {
    if (this.settingsBusy) { return; }
    this.settingsBusy = true;
    this.notice = '';
    let applied: boolean = false;
    try {
      const language: string = this.resolvedLanguage(preference);
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      context.getApplicationContext().setLanguage(language);
      this.language = language;
      this.languagePreference = preference;
      this.alerts.setLanguage(language);
      applied = true;
      await this.store.write('ui_language', preference);
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

  private async chooseToggle(key: string, enabled: boolean): Promise<void> {
    if (this.settingsBusy) { return; }
    this.settingsBusy = true;
    this.notice = '';
    if (key === 'keep_screen_on') { this.keepScreenOn = enabled; this.updateKeepScreenOn(); }
    else { this.alertVibration = enabled; }
    try {
      await this.store.write(key, enabled ? 'on' : 'off');
      this.announce(this.t('settings_saved'));
    } catch (error) { this.notice = this.t('settings_save_failed'); }
    finally { this.settingsBusy = false; }
  }

  /** While relaying, keep the screen awake like a navigation session; leaving the app still pauses relaying. */
  private updateKeepScreenOn(): void {
    this.applyKeepScreenOn(this.keepScreenOn && this.relay.isConnected);
  }

  private applyKeepScreenOn(keep: boolean): void {
    if (keep === this.screenKeptOn) { return; }
    this.screenKeptOn = keep;
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      window.getLastWindow(context)
        .then((mainWindow: window.Window) => mainWindow.setWindowKeepScreenOn(keep))
        .then(() => { console.info('SAFEMESH_KEEP_SCREEN_ON ' + keep); })
        .catch(() => { this.screenKeptOn = !keep; console.warn('SAFEMESH_KEEP_SCREEN_ON failed'); });
    } catch (error) { this.screenKeptOn = !keep; }
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
    if (this.alerts.arrivalSequence !== this.lastArrivalSequence) {
      this.lastArrivalSequence = this.alerts.arrivalSequence;
      const message: AlertInboxItem | undefined = this.alerts.getMessage(this.alerts.arrivalIdentity);
      if (message !== undefined) {
        this.announce(this.t('new_alert') + '. ' + message.title);
        if (this.alertVibration) { this.feedback.vibrate(message.severity); }
      }
    }
    const identity: string = this.alerts.received ? this.alerts.currentIdentity : '';
    if (identity !== this.lastAnnouncedAlert) {
      const previous: string = this.lastAnnouncedAlert;
      this.lastAnnouncedAlert = identity;
      if (identity.length === 0 && previous.length > 0) { this.announce(this.t('alert_expired')); }
    }
  }

  private async loadDrill(): Promise<void> {
    try {
      await this.relay.loadDrill();
      if (!this.alerts.received) { this.notice = this.t('verify_failed'); this.announce(this.notice); }
    } catch (error) { this.notice = this.t('verify_failed'); }
  }

  private onRelayChanged(): void {
    this.updateKeepScreenOn();
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
    this.selectTab(this.tab === 8 ? 5 : this.tab === 7 ? this.messageParent :
      this.tab === 5 ? this.diagnosticsParent : this.tab === 6 ? this.pointParent : this.previousTab);
  }

  private async openMessage(identity: string): Promise<void> {
    this.messageParent = this.tab === 7 ? this.messageParent : this.tab;
    try {
      const opened: boolean = await this.alerts.openMessage(identity);
      if (opened && this.alerts.selectedMessage()?.identity === identity) {
        this.selectTab(7);
        if (this.alerts.persistenceState === 'save_failed') { this.notice = this.t('read_save_failed'); }
      } else { this.notice = this.t('message_unavailable'); }
    } catch (error) { this.notice = this.t('persistence_load_failed'); }
  }

  private async signInAuthority(): Promise<void> {
    await this.authority.login();
    this.announce(this.t('authority_state_' + this.authority.state));
  }

  private async publishAlert(): Promise<void> {
    const published: boolean = await this.authority.publish();
    this.announce(this.t('authority_state_' + this.authority.state));
    if (published) { this.pageScroll.scrollTo({ xOffset: 0, yOffset: 0 }); }
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

  private locationMessage(): string {
    return this.t(this.map.locationStatus === 'demo' ? 'demo_origin' : 'location_' + this.map.locationStatus);
  }

  private pageTitle(): string {
    if (this.tab === 0) { return 'SafeMesh'; }
    return this.t(this.tab === 1 ? 'map' : this.tab === 2 ? 'relay' : this.tab === 3 ? 'guide' :
      this.tab === 4 ? 'settings_tab' : this.tab === 5 ? 'diagnostics_title' : this.tab === 6 ? 'point_type' :
      this.tab === 7 ? 'message_detail' : 'authority_console');
  }

  @Builder
  private header() {
    Row({ space: 4 }) {
      if (this.tab >= 4) {
        iconButton($r('sys.symbol.arrow_left'), () => this.t('back_settings'), 'backSettings', () => { this.goBack(); })
      }
      Text(this.pageTitle()).fontSize(this.tab === 0 ? 22 : 23).fontWeight(FontWeight.Bold)
        .fontColor(INK).layoutWeight(1)
      if (this.tab < 4) {
        iconButton($r('sys.symbol.gearshape'), () => this.t('open_settings'), 'openSettings', () => { this.openSettings(); })
      }
    }.width('100%').constraintSize({ maxWidth: 720, minHeight: 56 })
      .padding({ left: this.tab >= 4 ? 8 : 20, right: 8, top: 2, bottom: 2 })
  }

  @Builder
  private incomingBanner() {
    if (this.alerts.getMessage(this.alerts.arrivalIdentity) !== undefined) {
      Row({ space: 4 }) {
        Button({ type: ButtonType.Normal }) {
          Column({ space: 4 }) {
            Text(this.t('new_alert')).fontSize(12).fontWeight(FontWeight.Medium).fontColor(SUCCESS).width('100%')
            Text(this.alerts.getMessage(this.alerts.arrivalIdentity)?.title ?? '').fontSize(15)
              .fontWeight(FontWeight.Medium).fontColor(INK).maxLines(this.viewportHeight < 540 ? 1 : 2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
            Text(this.t('read_message')).fontSize(13).fontWeight(FontWeight.Medium).fontColor(SUCCESS).width('100%')
          }.width('100%').alignItems(HorizontalAlign.Start).padding(12)
        }.id('readIncoming').layoutWeight(1).constraintSize({ minHeight: 48 }).backgroundColor(Color.Transparent)
          .borderRadius(10).accessibilityText(this.t('read_message') + '. ' +
            (this.alerts.getMessage(this.alerts.arrivalIdentity)?.title ?? ''))
          .onClick(() => { this.openMessage(this.alerts.arrivalIdentity); })
        iconButton($r('sys.symbol.xmark'), () => this.t('dismiss'), 'dismissIncoming', () => { this.alerts.dismissArrival(); })
      }.width('100%').constraintSize({ maxWidth: 720 }).backgroundColor(SOFT)
        .border({ width: { bottom: 1 }, color: BORDER }).padding({ left: 8, right: 8 })
    }
  }

  @Builder
  private navItem(index: number, key: string, icon: Resource) {
    Button({ type: ButtonType.Normal }) {
      Column({ space: 5 }) {
        Row({ space: 4 }) {
          SymbolGlyph(icon).fontSize(23).maxFontScale(1).fontColor([this.tab === index ? SUCCESS : MUTED])
            .fontWeight(this.tab === index ? FontWeight.Bold : FontWeight.Normal).accessibilityLevel('no')
          if (index === 0 && this.alerts.unreadCount > 0) {
            Text(String(this.alerts.unreadCount)).fontSize(10).maxFontScale(1).fontWeight(FontWeight.Bold)
              .fontColor(ACTION_FG).padding(4).backgroundColor(ACTION_BG).borderRadius(12).accessibilityLevel('no')
          }
        }.justifyContent(FlexAlign.Center).width('100%')
        Text(this.t(key)).fontSize(12).fontWeight(this.tab === index ? FontWeight.Bold : FontWeight.Normal)
          .fontColor(this.tab === index ? INK : MUTED).textAlign(TextAlign.Center).width('100%')
      }.width('100%')
    }.layoutWeight(1).constraintSize({ minHeight: 56 }).padding({ left: 2, right: 2, top: 8, bottom: 8 })
      .backgroundColor(Color.Transparent).borderRadius(8).id('tab' + index)
      .accessibilityText(this.t(key) + (index === 0 && this.alerts.unreadCount > 0 ?
        '. ' + this.t('unread_count') + ': ' + this.alerts.unreadCount : ''))
      .accessibilitySelected(this.tab === index).onClick(() => { this.selectTab(index); })
  }

  @Builder
  private navigation() {
    Column() {
      divider()
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
      this.incomingBanner()
      Scroll(this.pageScroll) {
        Column({ space: 16 }) {
          if (this.notice.length > 0) {
            Row({ space: 8 }) {
              Text(this.notice).fontSize(14).fontColor(INK).layoutWeight(1)
              iconButton($r('sys.symbol.xmark'), () => this.t('dismiss'), 'dismissNotice', () => { this.notice = ''; })
            }.padding({ left: 12 }).width('100%').backgroundColor(SOFT).borderRadius(10)
          }
          if (this.tab === 0) {
            HomeScreen({ alerts: this.alerts, map: this.map, relay: this.relay, language: this.language, copy: this.copy,
              labBusy: this.labBusy, onOpenMessage: (identity: string) => { this.openMessage(identity); },
              onSelectPoint: (id: string) => { this.selectPoint(id); }, onSelectTab: (index: number) => { this.selectTab(index); } })
          } else if (this.tab === 1) {
            MapScreen({ map: this.map, language: this.language, copy: this.copy, query: this.query, mapMode: this.mapMode,
              mapRevision: this.mapRevision, themeRevision: this.themeRevision, dark: this.dark,
              viewportHeight: this.viewportHeight, onSelectPoint: (id: string) => { this.selectPoint(id); },
              onUseLocation: () => { this.useLocation(); },
              onScrollTop: () => { this.pageScroll.scrollTo({ xOffset: 0, yOffset: 0 }); } })
          } else if (this.tab === 2) {
            RelayScreen({ relay: this.relay, language: this.language, copy: this.copy, labNode: this.labNode,
              labBusy: this.labBusy, initialized: this.initialized, onStartLab: () => { this.startLab(); },
              onOpenDiagnostics: () => { this.diagnosticsParent = 2; this.selectTab(5); } })
          } else if (this.tab === 3) {
            GuideScreen({ language: this.language, copy: this.copy, guideExpanded: this.guideExpanded })
          } else if (this.tab === 4) {
            SettingsScreen({ map: this.map, language: this.language, copy: this.copy, themePreference: this.themePreference,
              languagePreference: this.languagePreference,
              systemLanguageName: this.systemLanguage() === 'pl' ? 'Polski' : 'English',
              keepScreenOn: this.keepScreenOn, alertVibration: this.alertVibration, settingsBusy: this.settingsBusy,
              appVersion: this.appVersion,
              onChooseTheme: (theme: string) => { this.chooseTheme(theme); },
              onChooseLanguage: (preference: string) => { this.chooseLanguage(preference); },
              onChooseToggle: (key: string, enabled: boolean) => { this.chooseToggle(key, enabled); },
              onOpenDiagnostics: () => { this.diagnosticsParent = 4; this.selectTab(5); } })
          } else if (this.tab === 5) {
            DiagnosticsScreen({ alerts: this.alerts, relay: this.relay, language: this.language, copy: this.copy,
              initialized: this.initialized, labBusy: this.labBusy, onOpenAuthority: () => { this.selectTab(8); },
              onLoadDrill: () => { this.loadDrill(); } })
          } else if (this.tab === 6) {
            PointDetailScreen({ map: this.map, language: this.language, copy: this.copy, initialized: this.initialized,
              onSavePoint: () => { this.savePoint(); },
              onShowOnMap: () => { this.query = ''; this.mapMode = 'map'; this.selectTab(1); } })
          } else if (this.tab === 7) {
            MessageDetailScreen({ alerts: this.alerts, language: this.language, copy: this.copy,
              onSelectTab: (index: number) => { this.selectTab(index); } })
          } else {
            AuthorityScreen({ authority: this.authority, language: this.language, copy: this.copy,
              viewportHeight: this.viewportHeight, onSignIn: () => { this.signInAuthority(); },
              onPublish: () => { this.publishAlert(); },
              onOpenMessage: (identity: string) => { this.openMessage(identity); } })
          }
        }.width('100%').constraintSize({ maxWidth: 680 }).padding({ left: 20, right: 20, top: 12, bottom: 24 })
      }.layoutWeight(1).width('100%').scrollBar(BarState.Auto).align(Alignment.Top)
      if (this.tab < 4) { this.navigation() }
    }.width('100%').height('100%').backgroundColor(PAPER)
      .onAreaChange((_old: Area, area: Area) => { this.viewportWidth = Number(area.width); this.viewportHeight = Number(area.height); })
  }
}
