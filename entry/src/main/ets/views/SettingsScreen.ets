import { MapViewModel } from '../viewmodel/MapViewModel';
import { divider, rowLink, sectionTitle, settingsChoice, settingsToggle, sourceLink } from './Controls';
import { MUTED } from './Theme';
import { UiCopy } from './UiCopy';

/** Appearance, language, relay comfort settings and app information. */
@Component
export struct SettingsScreen {
  @ObjectLink map: MapViewModel;
  @Prop language: string = 'en';
  copy: UiCopy = new UiCopy();
  @Prop themePreference: string = 'system';
  @Prop languagePreference: string = 'system';
  @Prop systemLanguageName: string = 'English';
  @Prop keepScreenOn: boolean = true;
  @Prop alertVibration: boolean = true;
  @Prop settingsBusy: boolean = false;
  appVersion: string = '';
  onChooseTheme: (theme: string) => void = () => {};
  onChooseLanguage: (preference: string) => void = () => {};
  onChooseToggle: (key: string, enabled: boolean) => void = () => {};
  onOpenDiagnostics: () => void = () => {};

  private t(key: string): string { return this.copy.text(key, this.language); }

  build() {
    Column({ space: 12 }) {
      sectionTitle(() => this.t('theme_label'))
      Column() {
        settingsChoice(() => this.t('theme_auto'), 'themeSystem', () => this.themePreference === 'system', () => { this.onChooseTheme('system'); }, () => this.settingsBusy)
        divider()
        settingsChoice(() => this.t('theme_light'), 'themeLight', () => this.themePreference === 'light', () => { this.onChooseTheme('light'); }, () => this.settingsBusy)
        divider()
        settingsChoice(() => this.t('theme_dark'), 'themeDark', () => this.themePreference === 'dark', () => { this.onChooseTheme('dark'); }, () => this.settingsBusy)
      }.width('100%').borderRadius(12).clip(true)
      Text(this.t('theme_auto_hint')).fontSize(12).fontColor(MUTED).width('100%')
      sectionTitle(() => this.t('language_label'))
      Column() {
        settingsChoice(() => this.t('language_auto') + ' · ' + (this.systemLanguageName),
          'languageSystem', () => this.languagePreference === 'system', () => { this.onChooseLanguage('system'); }, () => this.settingsBusy)
        divider()
        settingsChoice(() => 'Polski', 'languagePl', () => this.languagePreference === 'pl', () => { this.onChooseLanguage('pl'); }, () => this.settingsBusy)
        divider()
        settingsChoice(() => 'English', 'languageEn', () => this.languagePreference === 'en', () => { this.onChooseLanguage('en'); }, () => this.settingsBusy)
      }.width('100%').borderRadius(12).clip(true)
      Text(this.t('language_auto_hint')).fontSize(12).fontColor(MUTED).width('100%')
      Text(this.t('text_size_hint')).fontSize(12).fontColor(MUTED).width('100%')
      sectionTitle(() => this.t('relay_comfort_label'))
      Column() {
        settingsToggle(() => this.t('keep_screen_on'), 'keepScreenOn', () => this.keepScreenOn,
          (enabled: boolean) => { this.onChooseToggle('keep_screen_on', enabled); }, () => this.settingsBusy)
        divider()
        settingsToggle(() => this.t('alert_vibration'), 'alertVibration', () => this.alertVibration,
          (enabled: boolean) => { this.onChooseToggle('alert_vibration', enabled); }, () => this.settingsBusy)
      }.width('100%').borderRadius(12).clip(true)
      Text(this.t('relay_comfort_hint')).fontSize(12).fontColor(MUTED).width('100%')
      divider()
      rowLink($r('sys.symbol.checkmark_shield'), () => this.t('diagnostics_title'), () => this.t('diagnostics_hint'),
        'settingsDiagnostics', () => { this.onOpenDiagnostics(); })
      sectionTitle(() => this.t('about_app'))
      Text(this.t('about_body')).fontSize(14).fontColor(MUTED).width('100%')
      Text(this.t('pack_date') + ': ' + this.map.sourceDate + ' · ' + this.map.packSize).fontSize(12).fontColor(MUTED).width('100%')
      sourceLink('https://dane.gov.pl/pl/dataset/28058,punkty-schronienia-w-polsce', () => this.t('source_psp'))
      sourceLink('https://www.openstreetmap.org/copyright', () => this.t('source_osm'))
      Text('SafeMesh ' + this.appVersion).fontSize(12).fontColor(MUTED).width('100%')
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
}
