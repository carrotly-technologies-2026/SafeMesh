import { PeerViewModel, RelayViewModel } from '../viewmodel/RelayViewModel';
import { actionButton, divider, metric, rowLink } from './Controls';
import { connectionKey } from './Format';
import { ACTION_BG, ACTION_FG, DANGER, INK, MUTED, SOFT, SUCCESS } from './Theme';
import { UiCopy } from './UiCopy';

/** Relay: emulator role, connection, neighbours and delivery counters. */
@Component
export struct RelayScreen {
  @ObjectLink relay: RelayViewModel;
  @Prop language: string = 'en';
  copy: UiCopy = new UiCopy();
  @Link labNode: string;
  @Prop labBusy: boolean = false;
  @Prop initialized: boolean = false;
  onStartLab: () => void = () => {};
  onOpenDiagnostics: () => void = () => {};

  private t(key: string): string { return this.copy.text(key, this.language); }

  @Builder
  private labNodeChoice(node: string) {
    Button({ type: ButtonType.Normal }) {
      Text(node).fontSize(18).fontWeight(FontWeight.Medium).fontColor(this.labNode === node ? ACTION_FG : INK)
    }.id('labNode' + node).layoutWeight(1).constraintSize({ minHeight: 48 }).borderRadius(10)
      .backgroundColor(this.labNode === node ? ACTION_BG : SOFT).accessibilityText(this.t('node_label') + ' ' + node)
      .accessibilitySelected(this.labNode === node).enabled(!this.labBusy).onClick(() => { this.labNode = node; })
  }

  build() {
    Column({ space: 18 }) {
      Text(this.t('relay_intro')).fontSize(16).fontColor(MUTED).width('100%')
      Row({ space: 12 }) {
        SymbolGlyph($r('sys.symbol.phone_transmission_phone')).fontSize(32).maxFontScale(1)
          .fontColor([this.relay.isConnected ? SUCCESS : MUTED]).accessibilityLevel('no')
        Column({ space: 4 }) {
          Text(this.t(connectionKey(this.relay, this.labBusy))).id('labStatus').fontSize(23).fontWeight(FontWeight.Bold).fontColor(INK).width('100%')
          Text(this.t('emulator_transport')).id('labBanner').fontSize(13).fontColor(MUTED).width('100%')
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      }.width('100%').padding({ top: 8, bottom: 8 })
      Text(this.t('lab_node')).fontSize(13).fontColor(MUTED).width('100%')
      Row({ space: 8 }) { this.labNodeChoice('A'); this.labNodeChoice('B'); this.labNodeChoice('C') }.width('100%')
      if (this.relay.isConnected && this.relay.emulatorNode === this.labNode && this.relay.transportMode === 'emulator') {
        actionButton(() => this.t('lab_disconnect') + ' ' + this.relay.emulatorNode, 'labStop',
          () => { this.relay.stop(); }, () => !this.labBusy, false)
      } else {
        actionButton(() => this.t(this.labBusy ? 'lab_connecting' : 'lab_connect') + ' ' + this.labNode,
          'labStart', () => { this.onStartLab(); }, () => this.initialized && !this.labBusy)
      }
      if (this.relay.hardwareState === 'lab_error' || this.relay.hardwareState === 'restore_failed') {
        Text(this.t('hardware_' + this.relay.hardwareState)).id('labConnectionDetail')
          .fontSize(14).fontColor(DANGER).width('100%')
      }
      if (this.relay.transportMode === 'emulator' && this.relay.isConnected) {
        divider()
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
        divider()
        Row({ space: 8 }) {
          metric(() => this.relay.pendingCount, () => this.t('queue_pending'))
          metric(() => this.relay.acknowledgedCount, () => this.t('queue_acked'))
          metric(() => this.relay.retryCount, () => this.t('queue_retry'))
        }.id('labMetrics').width('100%').alignItems(VerticalAlign.Top)
        Text(this.t('relay_automatic')).id('relayAutomatic').fontSize(14).fontColor(SUCCESS).width('100%')
        Text(this.t('packet_' + this.relay.lastPacketState)).id('labPacketStatus').fontSize(13).fontColor(MUTED).width('100%')
      }
      Text(this.t('foreground_notice')).fontSize(13).fontColor(MUTED).width('100%')
      divider()
      rowLink($r('sys.symbol.checkmark_shield'), () => this.t('diagnostics_title'),
        () => this.t('diagnostics_hint'), 'openDiagnostics', () => { this.onOpenDiagnostics(); })
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
}
