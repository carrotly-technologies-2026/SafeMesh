import { common } from '@kit.AbilityKit';
import { NearLinkTransport, NearLinkStatus, NearLinkPeer, NearLinkCallbacks } from '../transport/NearLinkTransport';
import { RelayEngine, RelayResult, SignedAlertEnvelope, decodeEnvelope } from '../model/AlertProtocol';
import { createDemoAlert, createTamperedAlert, createExpiredAlert } from '../model/DemoAlerts';
import { AlertViewModel } from './AlertViewModel';

export class RelayEvent {
  id: string;
  title: string;
  detail: string;
  good: boolean;
  constructor(id: string, title: string, detail: string, good: boolean) {
    this.id = id; this.title = title; this.detail = detail; this.good = good;
  }
}

export class PeerViewModel {
  address: string = '';
  name: string = '';
  connected: boolean = false;
}

@Observed
export class RelayViewModel {
  stage: number = 0;
  running: boolean = false;
  events: RelayEvent[] = [];
  hardwareStatus: string = 'Hardware not checked';
  hardwareSupported: boolean = false;
  peerCount: number = 0;
  peers: PeerViewModel[] = [];
  peerName: string = '';
  testStatus: string = 'Run the drill to verify a real signature on this device.';
  acceptedCount: number = 0;
  rejectedCount: number = 0;
  lastPacketStatus: string = 'No radio packet received';
  private alertVM: AlertViewModel;
  private transport: NearLinkTransport;
  private context: common.UIAbilityContext | undefined = undefined;

  constructor(alertVM: AlertViewModel) {
    this.alertVM = alertVM;
    const callbacks: NearLinkCallbacks = {
      onStatus: (status: NearLinkStatus): void => {
        this.hardwareStatus = status.message;
        this.hardwareSupported = status.supported;
        this.peerCount = status.connectedPeers;
      },
      onPeer: (peer: NearLinkPeer): void => {
        const previous: PeerViewModel | undefined = this.peers.find((old: PeerViewModel) => old.address === peer.address);
        const item: PeerViewModel = new PeerViewModel();
        item.address = peer.address; item.name = peer.name; item.connected = peer.connected;
        this.peers = this.peers.filter((old: PeerViewModel) => old.address !== item.address).concat([item]);
        if (peer.connected && (previous === undefined || !previous.connected)) {
          this.sendToPeer(peer.address).catch((error: Error): void => {
            this.hardwareStatus = 'Peer send failed: ' + error.message;
          });
        }
      },
      onMessage: (address: string, packet: string): void => {
        this.receive(address, packet).catch((error: Error): void => {
          this.lastPacketStatus = 'Packet processing failed: ' + error.message;
        });
      },
      onError: (operation: string, code: number, message: string): void => {
        this.hardwareStatus = operation + ': ' + message + ' (' + code + ')';
      }
    };
    this.transport = new NearLinkTransport(callbacks);
  }

  setContext(context: common.UIAbilityContext): void { this.context = context; }
  async probe(): Promise<void> { await this.transport.probe(); }
  async startHardware(): Promise<void> {
    if (this.context === undefined) { return; }
    if (await this.transport.start(this.context)) {
      if (this.peerName.trim().length > 0) { await this.transport.discover(this.peerName.trim()); }
    }
  }
  async connect(address: string): Promise<void> { await this.transport.connect(address); }
  async stop(): Promise<void> { await this.transport.stop(); }

  async receive(address: string, packet: string): Promise<void> {
    try {
      const envelope: SignedAlertEnvelope | undefined = decodeEnvelope(packet);
      if (envelope === undefined) {
        this.rejectedCount++;
        this.lastPacketStatus = 'Malformed packet rejected';
        return;
      }
      const result: RelayResult = await this.alertVM.receive(envelope);
      this.lastPacketStatus = result.status + ': ' + result.detail;
      if (result.status === 'accepted' && result.envelope !== undefined) {
        this.acceptedCount++;
        const next: string = this.alertVM.nextPacket(result.envelope);
        if (next.length > 0) { await this.transport.broadcast(next, address); }
      } else { this.rejectedCount++; }
    } catch (error) {
      this.lastPacketStatus = 'Radio packet processing failed; verified alerts retained';
    }
  }

  private async sendToPeer(address: string): Promise<void> {
    await this.alertVM.restore();
    const packet: string = this.alertVM.nextPacket();
    if (packet.length > 0) { await this.transport.send(address, packet); }
  }

  async share(): Promise<void> {
    try {
      await this.alertVM.restore();
      const packet: string = this.alertVM.nextPacket();
      if (packet.length === 0) { this.hardwareStatus = 'Load a valid signed drill first.'; return; }
      const sent: number = await this.transport.broadcast(packet);
      this.hardwareStatus = 'Sent to ' + sent + ' connected NearLink peers.';
    } catch (error) { this.hardwareStatus = 'Radio send failed; signed alert retained'; }
  }

  private add(title: string, detail: string, good: boolean): void {
    this.events = this.events.concat([new RelayEvent(String(this.events.length), title, detail, good)]);
  }

  async simulate(): Promise<void> {
    if (this.running) { return; }
    this.running = true; this.stage = 0; this.events = [];
    try {
      const nodeA: RelayEngine = new RelayEngine();
      const nodeB: RelayEngine = new RelayEngine();
      const nodeC: RelayEngine = new RelayEngine();
      const signed: SignedAlertEnvelope = createDemoAlert();
      const a: RelayResult = await nodeA.ingest(signed);
      this.add('A · message received', a.status + ' · native ECDSA verification', a.status === 'accepted');
      if (a.status !== 'accepted') { this.testStatus = a.detail; return; }
      this.stage = 1;
      await new Promise<void>((resolve) => { setTimeout(resolve, 400); });
      const ab: SignedAlertEnvelope | undefined = nodeA.nextHop(signed);
      if (ab === undefined) { return; }
      const b: RelayResult = await nodeB.ingest(ab);
      this.add('B · verified and stored', b.status + ' · hop 1 · no internet', b.status === 'accepted');
      this.stage = 2;
      await new Promise<void>((resolve) => { setTimeout(resolve, 400); });
      const bc: SignedAlertEnvelope | undefined = nodeB.nextHop(ab);
      if (bc === undefined) { return; }
      const c: RelayResult = await nodeC.ingest(bc);
      this.add('C · warning delivered', c.status + ' · hop 2 · same authority signature', c.status === 'accepted');
      this.stage = 3;
      const replay: RelayResult = await nodeC.ingest(bc);
      this.add('Duplicate suppressed', replay.status + ' · packet is not forwarded again', replay.status === 'duplicate');
      const tampered: RelayResult = await new RelayEngine().ingest(createTamperedAlert());
      this.add('Forged text rejected', tampered.status + ' · signature no longer matches', tampered.status === 'invalid');
      const expired: RelayResult = await new RelayEngine().ingest(createExpiredAlert());
      this.add('Expired warning rejected', expired.status + ' · stale alerts do not propagate', expired.status === 'expired');
      const passed: boolean = this.events.every((event: RelayEvent) => event.good);
      this.testStatus = passed ? '6 / 6 checks passed on this device' : 'A check failed · see the results below';
      console.info('SAFEMESH_NATIVE_DIAGNOSTICS ' + (passed ? 'PASS' : 'FAIL') + ' ' + JSON.stringify(this.events));
      await this.alertVM.loadDrill();
    } catch (error) {
      this.testStatus = 'Verification error: ' + String(error);
      this.add('Verification could not complete', String(error), false);
      console.error('SAFEMESH_NATIVE_DIAGNOSTICS FAIL ' + String(error));
    } finally { this.running = false; }
  }
}
