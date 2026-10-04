import { AlertViewModel } from '../viewmodel/AlertViewModel';
import { PeerViewModel, RelayEvent, RelayViewModel } from '../viewmodel/RelayViewModel';
import { actionButton, divider, metric, rowLink, sectionTitle } from './Controls';
import { DANGER, INK, MUTED, SUCCESS, SURFACE } from './Theme';
import { UiCopy } from './UiCopy';

/** Exercise tools, the six-check verification test, delivery results and the NearLink radio. */
@Component
export struct DiagnosticsScreen {
  @ObjectLink alerts: AlertViewModel;
  @ObjectLink relay: RelayViewModel;
  @Prop language: string = 'en';
  copy: UiCopy = new UiCopy();
  @Prop initialized: boolean = false;
  @Prop labBusy: boolean = false;
  onOpenAuthority: () => void = () => {};
  onLoadDrill: () => void = () => {};

  private t(key: string): string { return this.copy.text(key, this.language); }

  build() {
    Column({ space: 16 }) {
      Text(this.t('diagnostics_intro')).fontSize(15).fontColor(MUTED).width('100%')
      rowLink($r('sys.symbol.checkmark_shield'), () => this.t('authority_console'),
        () => this.t('authority_console_hint'), 'openAuthority', () => { this.onOpenAuthority(); })
      divider()
      sectionTitle(() => this.t('exercise_actions'))
      actionButton(() => this.t(this.alerts.busy ? 'verifying' : 'receive_drill'), 'diagnosticDrill',
        () => { this.onLoadDrill(); }, () => this.initialized && !this.alerts.busy)
      divider()
      sectionTitle(() => this.t('simulation'))
      Text(this.t('no_radio')).fontSize(13).fontColor(MUTED).width('100%')
      actionButton(() => this.t(this.relay.running ? 'drill_running' : 'run_drill'), 'runRelay',
        () => { this.relay.simulate(); }, () => this.initialized && !this.relay.running, false)
      Text(this.t('test_' + this.relay.testState)).id('relayTestStatus').fontSize(16).fontWeight(FontWeight.Medium).fontColor(INK).width('100%')
      ForEach(this.relay.events, (event: RelayEvent) => {
        Column({ space: 6 }) {
          Text(this.t(event.titleKey)).fontSize(15).fontWeight(FontWeight.Medium).fontColor(event.good ? SUCCESS : DANGER).width('100%')
          Text(this.t(event.detailKey)).fontSize(13).fontColor(MUTED).width('100%')
          if (!event.good) { Text(this.t('packet_' + event.status)).fontSize(13).fontColor(MUTED).width('100%') }
          divider()
        }.width('100%').padding({ top: 8, bottom: 8 })
      }, (event: RelayEvent) => event.id + this.language)
      sectionTitle(() => this.t('delivery_details'))
      Text(this.t('lab_received') + ': ' + this.relay.acceptedCount + '\n' + this.t('lab_rejected') + ': ' + this.relay.rejectedCount +
        '\n' + this.t('queue_failed') + ': ' + this.relay.failedCount).fontSize(14).fontColor(INK).width('100%')
      Text(this.t('queue_note')).fontSize(12).fontColor(MUTED).width('100%')
      divider()
      sectionTitle(() => this.t('physical_radio'))
      Text(this.t('nearlink_notice')).fontSize(14).fontColor(MUTED).width('100%')
      actionButton(() => this.t('check_hardware'), 'checkNearLink', () => { this.relay.probe(); }, () => this.initialized && !this.labBusy, false)
      if (this.relay.transportMode === 'nearlink') {
        Text(this.t('hardware_' + this.relay.hardwareState)).id('nearlinkStatus').fontSize(14).fontColor(MUTED).width('100%')
        if (this.relay.hardwareSupported) {
          TextInput({ placeholder: this.t('peer_name'), text: this.relay.peerName }).id('peerName')
            .fontSize(16).constraintSize({ minHeight: 48 }).fontColor(INK).backgroundColor(SURFACE)
            .onChange((value: string) => { this.relay.peerName = value; })
          actionButton(() => this.t('start_relay'), 'startHardware', () => { this.relay.startHardware(); })
          ForEach(this.relay.peers, (peer: PeerViewModel) => {
            actionButton(() => peer.name + ' · ' + this.t(peer.connected ? 'connected_short' : 'connect'),
              'peer_' + peer.address, () => { this.relay.connect(peer.address); }, () => !peer.connected, false)
          }, (peer: PeerViewModel) => peer.address)
          Row({ space: 8 }) {
            metric(() => this.relay.pendingCount, () => this.t('queue_pending'))
            metric(() => this.relay.acknowledgedCount, () => this.t('queue_acked'))
            metric(() => this.relay.retryCount, () => this.t('queue_retry'))
          }.id('nearlinkMetrics').width('100%').alignItems(VerticalAlign.Top)
          Text(this.t('packet_' + this.relay.lastPacketState)).id('nearlinkPacketStatus').fontSize(13).fontColor(MUTED).width('100%')
          actionButton(() => this.t('stop_relay'), 'stopRelay', () => { this.relay.stop(); }, () => true, false)
        }
      }
      Text(this.t('trust_body')).fontSize(13).fontColor(MUTED).width('100%')
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
}
