import { AuthorityViewModel } from '../viewmodel/AuthorityViewModel';
import { actionButton, choiceButton, divider, rowLink, sectionTitle } from './Controls';
import { INK, MUTED, SUCCESS, SURFACE } from './Theme';
import { UiCopy } from './UiCopy';

/** Authenticated exercise-issuer console (local demo authority). */
@Component
export struct AuthorityScreen {
  @ObjectLink authority: AuthorityViewModel;
  @Prop language: string = 'en';
  copy: UiCopy = new UiCopy();
  @Prop viewportHeight: number = 760;
  onSignIn: () => void = () => {};
  onPublish: () => void = () => {};
  onOpenMessage: (identity: string) => void = () => {};

  private t(key: string): string { return this.copy.text(key, this.language); }

  @Builder
  private authorityForm() {
    Column({ space: 12 }) {
      sectionTitle(() => this.t('message_language'))
      Row({ space: 8 }) {
        choiceButton(() => 'Polski', 'draftLanguagePl', () => this.authority.draftLanguage === 'pl',
          () => { this.authority.draftLanguage = 'pl'; }, () => this.authority.busy)
        choiceButton(() => 'English', 'draftLanguageEn', () => this.authority.draftLanguage === 'en',
          () => { this.authority.draftLanguage = 'en'; }, () => this.authority.busy)
      }.width('100%')
      Text(this.t('message_language_hint')).fontSize(12).fontColor(MUTED).width('100%')
      sectionTitle(() => this.t('draft_title'))
      TextInput({ text: this.authority.draftTitle, placeholder: this.t('draft_title_hint') }).id('draftTitle')
        .fontSize(16).fontColor(INK).placeholderColor(MUTED).backgroundColor(SURFACE).borderRadius(10)
        .constraintSize({ minHeight: 52 }).maxLength(160).enabled(!this.authority.busy)
        .accessibilityText(this.t('draft_title')).onChange((value: string) => { this.authority.draftTitle = value; })
      sectionTitle(() => this.t('draft_body'))
      TextArea({ text: this.authority.draftBody, placeholder: this.t('draft_body_hint') }).id('draftBody')
        .fontSize(16).fontColor(INK).placeholderColor(MUTED).backgroundColor(SURFACE).borderRadius(10)
        .height(this.viewportHeight < 540 ? 130 : 180).maxLength(1200).enabled(!this.authority.busy)
        .accessibilityText(this.t('draft_body')).onChange((value: string) => { this.authority.draftBody = value; })
      Text(this.authority.draftBody.length + ' / 1200').fontSize(12).fontColor(MUTED).width('100%').textAlign(TextAlign.End)
      sectionTitle(() => this.t('draft_area'))
      TextInput({ text: this.authority.draftArea, placeholder: this.t('draft_area_hint') }).id('draftArea')
        .fontSize(16).fontColor(INK).placeholderColor(MUTED).backgroundColor(SURFACE).borderRadius(10)
        .constraintSize({ minHeight: 52 }).maxLength(120).enabled(!this.authority.busy)
        .accessibilityText(this.t('draft_area')).onChange((value: string) => { this.authority.draftArea = value; })
      sectionTitle(() => this.t('draft_severity'))
      Column({ space: 8 }) {
        Row({ space: 8 }) {
          choiceButton(() => this.t('severity_info'), 'severityInfo', () => this.authority.severity === 'info',
            () => { this.authority.severity = 'info'; }, () => this.authority.busy)
          choiceButton(() => this.t('severity_warning'), 'severityWarning', () => this.authority.severity === 'warning',
            () => { this.authority.severity = 'warning'; }, () => this.authority.busy)
        }.width('100%')
        Row() {
          choiceButton(() => this.t('severity_critical'), 'severityCritical', () => this.authority.severity === 'critical',
            () => { this.authority.severity = 'critical'; }, () => this.authority.busy)
        }.width('100%')
      }.width('100%')
      sectionTitle(() => this.t('draft_validity'))
      Row({ space: 6 }) {
        choiceButton(() => this.t('validity_15'), 'validity15', () => this.authority.validForMinutes === 15,
          () => { this.authority.validForMinutes = 15; }, () => this.authority.busy)
        choiceButton(() => this.t('validity_60'), 'validity60', () => this.authority.validForMinutes === 60,
          () => { this.authority.validForMinutes = 60; }, () => this.authority.busy)
      }.width('100%')
      Row({ space: 6 }) {
        choiceButton(() => this.t('validity_240'), 'validity240', () => this.authority.validForMinutes === 240,
          () => { this.authority.validForMinutes = 240; }, () => this.authority.busy)
        choiceButton(() => this.t('validity_1440'), 'validity1440', () => this.authority.validForMinutes === 1440,
          () => { this.authority.validForMinutes = 1440; }, () => this.authority.busy)
      }.width('100%')
      Text(this.t('authority_publish_hint')).fontSize(13).fontColor(MUTED).width('100%')
      actionButton(() => this.t(this.authority.busy ? 'authority_publishing' : 'authority_publish'), 'publishAlert',
        () => { this.onPublish(); }, () => !this.authority.busy && this.authority.authenticated &&
          this.authority.draftTitle.trim().length > 0 && this.authority.draftBody.trim().length > 0 &&
          this.authority.draftArea.trim().length > 0)
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  build() {
    Column({ space: 16 }) {
      Text(this.t('authority_intro')).fontSize(15).fontColor(MUTED).width('100%')
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.checkmark_shield')).fontSize(22).maxFontScale(1)
          .fontColor([this.authority.authenticated ? SUCCESS : MUTED]).accessibilityLevel('no')
        Text(this.t(this.authority.authenticated ? 'authority_authenticated' : 'authority_login_title'))
          .fontSize(19).fontWeight(FontWeight.Bold).fontColor(INK).layoutWeight(1)
      }.width('100%')
      Text(this.t('authority_state_' + this.authority.state)).id('authorityStatus').fontSize(14).fontColor(MUTED).width('100%')
      if (!this.authority.authenticated) {
        sectionTitle(() => this.t('authority_token'))
        TextInput({ text: this.authority.tokenInput, placeholder: this.t('authority_token_hint') }).id('authorityToken')
          .type(InputType.Password).enableAutoFill(false).showPasswordIcon(false).copyOption(CopyOptions.None)
          .fontSize(16).fontColor(INK).placeholderColor(MUTED).backgroundColor(SURFACE).borderRadius(10)
          .constraintSize({ minHeight: 52 }).maxLength(64).enabled(!this.authority.busy)
          .accessibilityText(this.t('authority_token')).onChange((value: string) => { this.authority.tokenInput = value; })
        Text(this.t('authority_token_notice')).fontSize(12).fontColor(MUTED).width('100%')
        actionButton(() => this.t(this.authority.busy ? 'authority_signing_in' : 'authority_login'), 'authorityLogin',
          () => { this.onSignIn(); }, () => !this.authority.busy && this.authority.tokenInput.trim().length > 0)
      } else {
        actionButton(() => this.t('authority_logout'), 'authorityLogout', () => { this.authority.logout(); },
          () => !this.authority.busy, false)
        if (this.authority.lastPublishedIdentity.length > 0) {
          rowLink($r('sys.symbol.bell'), () => this.t('view_published'), () => this.authority.lastPublishedTitle,
            'viewPublished', () => { this.onOpenMessage(this.authority.lastPublishedIdentity); })
        }
        divider()
        this.authorityForm()
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
}
