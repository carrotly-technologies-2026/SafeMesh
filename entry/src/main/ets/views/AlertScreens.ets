import { AlertInboxItem, AlertViewModel } from '../viewmodel/AlertViewModel';
import { MapViewModel } from '../viewmodel/MapViewModel';
import { RelayViewModel } from '../viewmodel/RelayViewModel';
import { actionButton, divider, rowLink, sectionTitle } from './Controls';
import { connectionKey, formatUtc } from './Format';
import { ACTION_BG, ACTION_FG, BORDER, DANGER, INK, MUTED, SUCCESS, SURFACE, WARNING_BG, WARNING_FG } from './Theme';
import { UiCopy } from './UiCopy';

/** Home: inbox of verified alerts, saved place and connection summary. */
@Component
export struct HomeScreen {
  @ObjectLink alerts: AlertViewModel;
  @ObjectLink map: MapViewModel;
  @ObjectLink relay: RelayViewModel;
  @Prop language: string = 'en';
  copy: UiCopy = new UiCopy();
  @Prop labBusy: boolean = false;
  onOpenMessage: (identity: string) => void = () => {};
  onSelectPoint: (id: string) => void = () => {};
  onSelectTab: (index: number) => void = () => {};

  private t(key: string): string { return this.copy.text(key, this.language); }

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
  private alertCard() {
    Column({ space: 12 }) {
      Row({ space: 8 }) {
        SymbolGlyph(this.alerts.received ? $r('sys.symbol.checkmark_shield') : $r('sys.symbol.bell'))
          .fontSize(20).maxFontScale(1).fontColor([this.alerts.received ? SUCCESS : MUTED]).accessibilityLevel('no')
        Text(this.t(this.alerts.received ? 'signature_verified' :
          this.alerts.verificationState === 'expired' ? 'alert_expired' : 'no_alert'))
          .id('emptyVerificationBadge').fontSize(13).fontWeight(FontWeight.Medium)
          .fontColor(this.alerts.received ? SUCCESS : MUTED).layoutWeight(1)
      }.width('100%')
      Text(this.alerts.received ? this.alerts.title : this.t('ready_title')).id('readyTitle')
        .fontSize(24).fontWeight(FontWeight.Bold).fontColor(INK).width('100%')
      Text(this.alerts.received ? this.alerts.body : this.t('ready_body')).id('readyBody')
        .fontSize(16).fontColor(INK).width('100%')
      if (this.alerts.received) {
        if (this.alerts.languageFallback) {
          Text(this.t('original_language_' + this.alerts.contentLanguage)).fontSize(12).fontColor(MUTED).width('100%')
        }
        divider()
        Text(this.t('valid_until') + ' ' + formatUtc(this.alerts.expiresAt, this.language))
          .fontSize(12).fontColor(MUTED).width('100%')
      } else {
        actionButton(() => this.t('connect_devices'), 'connectDevices', () => { this.onSelectTab(2); })
      }
      if (this.alerts.persistenceState === 'save_failed' || this.alerts.persistenceState === 'load_failed') {
        Text(this.t('persistence_' + this.alerts.persistenceState)).fontSize(13).fontColor(DANGER).width('100%')
      }
    }.width('100%').alignItems(HorizontalAlign.Start).padding(18).backgroundColor(SURFACE)
      .borderRadius(14).border({ width: 1, color: BORDER })
  }

  @Builder
  private inboxRow(message: AlertInboxItem) {
    Button({ type: ButtonType.Normal }) {
      Column({ space: 8 }) {
        Row({ space: 8 }) {
          Text(this.t('issuer_authority')).fontSize(12).fontColor(MUTED).layoutWeight(1)
          if (message.unread) {
            Text(this.t('unread_short')).fontSize(11).fontWeight(FontWeight.Medium).fontColor(SUCCESS)
          }
        }.width('100%')
        Row({ space: 12 }) {
          Text(message.title).fontSize(20).fontWeight(message.unread ? FontWeight.Bold : FontWeight.Medium)
            .fontColor(INK).layoutWeight(1).maxLines(3).textOverflow({ overflow: TextOverflow.Ellipsis })
          SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(15).maxFontScale(1).fontColor([MUTED])
            .accessibilityLevel('no')
        }.width('100%')
        Text(message.area).fontSize(14).fontColor(INK).width('100%')
        Text(this.t('issued_at') + ' ' + formatUtc(message.issuedAt, this.language)).fontSize(12).fontColor(MUTED).width('100%')
      }.alignItems(HorizontalAlign.Start).width('100%').padding({ top: 18, bottom: 18 })
    }.id('message_' + message.alertId + '_' + message.revision).width('100%').constraintSize({ minHeight: 64 })
      .backgroundColor(Color.Transparent).borderRadius(8)
      .accessibilityText((message.unread ? this.t('unread_short') + '. ' : '') + message.title + '. ' + message.area)
      .onClick(() => { this.onOpenMessage(message.identity); })
    divider()
  }

  build() {
    Column({ space: 16 }) {
      this.contextLine()
      Row({ space: 8 }) {
        Text(this.t('home_alerts')).fontSize(29).fontWeight(FontWeight.Bold).fontColor(INK).layoutWeight(1)
        if (this.alerts.unreadCount > 0) {
          Text(String(this.alerts.unreadCount)).id('unreadCount').fontSize(16).fontWeight(FontWeight.Bold)
            .fontColor(ACTION_FG).padding({ left: 12, right: 12, top: 7, bottom: 7 }).backgroundColor(ACTION_BG).borderRadius(20)
            .accessibilityText(this.t('unread_count') + ': ' + this.alerts.unreadCount)
        }
      }.width('100%')
      if (this.alerts.inbox.length === 0) { this.alertCard() }
      else {
        Column() {
          ForEach(this.alerts.inbox, (message: AlertInboxItem) => { this.inboxRow(message) },
            (message: AlertInboxItem) => message.identity + this.language + String(message.unread))
        }.id('messageInbox').width('100%')
        if (this.alerts.persistenceState === 'save_failed' || this.alerts.persistenceState === 'load_failed') {
          Text(this.t('persistence_' + this.alerts.persistenceState)).fontSize(13).fontColor(DANGER).width('100%')
        }
      }
      sectionTitle(() => this.t('your_place'))
      if (this.map.saveError === 'load_failed') {
        Text(this.t('saved_load_failed')).fontSize(13).fontColor(DANGER).width('100%')
      }
      if (this.map.saved() !== undefined) {
        rowLink($r('sys.symbol.bookmark'), () => this.map.saved()?.address ?? '',
          () => this.t('saved_on_phone'), 'homeSavedPoint', () => { this.onSelectPoint(this.map.savedId); })
      } else {
        rowLink($r('sys.symbol.bookmark'), () => this.t('choose_place'),
          () => this.t('choose_place_hint'), 'exploreMap', () => { this.onSelectTab(1); })
      }
      divider()
      rowLink($r('sys.symbol.phone_transmission_phone'), () => this.t(connectionKey(this.relay, this.labBusy)),
        () => this.relay.isConnected ? this.relay.peerCount + ' ' + this.t('nearby_devices') : this.t('connection_home_hint'),
        'exploreRelay', () => { this.onSelectTab(2); })
      Text(this.t('exercise_notice')).id('exerciseNotice').fontSize(12).fontColor(MUTED).width('100%')
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
}

/** Full text of one verified alert with its local receipt metadata. */
@Component
export struct MessageDetailScreen {
  @ObjectLink alerts: AlertViewModel;
  @Prop language: string = 'en';
  copy: UiCopy = new UiCopy();
  onSelectTab: (index: number) => void = () => {};

  private t(key: string): string { return this.copy.text(key, this.language); }

  private receiptOrigin(message: AlertInboxItem): string {
    if (message.sourcePeer === 'authority') { return this.t('receipt_authority_source'); }
    if (message.sourcePeer === 'local_test') { return this.t('receipt_local_source'); }
    if (message.sourcePeer.length === 0) { return this.t('receipt_unknown_source'); }
    return this.t('receipt_peer') + ' ' + message.sourcePeer;
  }

  @Builder
  private messageContent(message: AlertInboxItem) {
    Column({ space: 18 }) {
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.checkmark_shield')).fontSize(22).maxFontScale(1).fontColor([SUCCESS]).accessibilityLevel('no')
        Text(this.t('signature_verified')).id('verificationBadge').fontSize(13).fontColor(SUCCESS).layoutWeight(1)
      }.width('100%')
      Text(message.title).id('alertTitle').fontSize(28).fontWeight(FontWeight.Bold).fontColor(INK).width('100%')
      Text(this.t('issuer_authority') + ' · ' + this.t('exercise')).id('messageIssuer')
        .fontSize(13).fontWeight(FontWeight.Medium).fontColor(WARNING_FG).width('100%')
      Text(message.area).id('messageArea').fontSize(17).fontWeight(FontWeight.Medium).fontColor(INK).width('100%')
      Text(message.body).id('alertBody').fontSize(17).fontColor(INK).width('100%')
      if (message.languageFallback) {
        Text(this.t('original_language_' + message.contentLanguage)).fontSize(12).fontColor(MUTED).width('100%')
      }
      divider()
      Text(this.t('severity_' + message.severity)).fontSize(14).fontWeight(FontWeight.Medium).fontColor(INK).width('100%')
      Text(this.t('issued_at') + ' ' + formatUtc(message.issuedAt, this.language) + '\n' +
        this.t('valid_until') + ' ' + formatUtc(message.expiresAt, this.language)).fontSize(13).fontColor(MUTED).width('100%')
      sectionTitle(() => this.t('receipt_local'))
      if (message.receivedAt > 0) {
        Text(this.t('received_at') + ' ' + formatUtc(message.receivedAt, this.language)).fontSize(13).fontColor(INK).width('100%')
      }
      Text(this.receiptOrigin(message) +
        ' · ' + this.t('receipt_hops') + ': ' + message.hops).id('messageRoute').fontSize(13).fontColor(INK).width('100%')
      Text(this.t('receipt_notice')).fontSize(12).fontColor(MUTED).width('100%')
      Text(this.t('exercise_notice')).fontSize(12).fontColor(MUTED).width('100%')
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  build() {
    if (this.alerts.selectedMessage() !== undefined) {
      ForEach([this.alerts.selectedMessage()!], (message: AlertInboxItem) => { this.messageContent(message) },
        (message: AlertInboxItem) => message.identity + this.language + String(message.unread))
    } else {
      Column({ space: 16 }) {
        Text(this.t('message_unavailable')).fontSize(17).fontColor(INK).width('100%')
        actionButton(() => this.t('back_to_inbox'), 'backToInbox', () => { this.onSelectTab(0); }, () => true, false)
      }.width('100%')
    }
  }
}
