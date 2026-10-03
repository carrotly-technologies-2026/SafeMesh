import { common } from '@kit.AbilityKit';
import { NearLinkTransport, NearLinkStatus, NearLinkPeer, NearLinkCallbacks } from '../transport/NearLinkTransport';
import { RelayEngine, RelayResult, SignedAlertEnvelope, decodeEnvelope } from '../model/AlertProtocol';
import { createDemoAlert, createTamperedAlert, createExpiredAlert } from '../model/DemoAlerts';
import { DeliveryQueue, DeliveryHooks, DeliveryMetrics } from '../model/DeliveryQueue';
import { DeliveryData, DeliveryAck, decodeDataPacket, decodeAcknowledgement, makeAcknowledgement } from '../model/DeliveryProtocol';
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
  hardwareState: string = 'not_checked';
  hardwareSupported: boolean = false;
  peerCount: number = 0;
  peers: PeerViewModel[] = [];
  peerName: string = '';
  testStatus: string = 'Run the drill to verify a real signature on this device.';
  acceptedCount: number = 0;
  rejectedCount: number = 0;
  lastPacketStatus: string = 'No radio packet received';
  deliveryStatus: string = 'idle';
  pendingCount: number = 0;
  acknowledgedCount: number = 0;
  retryCount: number = 0;
  failedCount: number = 0;
  private alertVM: AlertViewModel;
  private transport: NearLinkTransport;
  private delivery: DeliveryQueue;
  private context: common.UIAbilityContext | undefined = undefined;
  private deliveryTimer: number = -1;
  private stopped: boolean = false;
  private generation: number = 0;

  constructor(alertVM: AlertViewModel) {
    this.alertVM = alertVM;
    const callbacks: NearLinkCallbacks = {
      onStatus: (status: NearLinkStatus): void => {
        this.hardwareStatus = status.message;
        this.hardwareState = status.state.replace('-', '_');
        this.hardwareSupported = status.supported;
        this.peerCount = status.connectedPeers;
      },
      onPeer: (peer: NearLinkPeer): void => {
        if (this.stopped) { return; }
        const previous: PeerViewModel | undefined = this.peers.find((old: PeerViewModel) => old.address === peer.address);
        const item: PeerViewModel = new PeerViewModel();
        item.address = peer.address; item.name = peer.name; item.connected = peer.connected;
        this.peers = this.peers.filter((old: PeerViewModel) => old.address !== item.address).concat([item]).slice(-8);
        if (!peer.connected) {
          this.delivery.disconnect(peer.address);
          this.updateDeliveryMetrics();
        } else if (previous === undefined || !previous.connected) {
          this.delivery.connect(peer.address, []);
          this.synchronizePeer(peer.address).catch((error: Error): void => {
            this.deliveryStatus = 'restore_failed';
            this.hardwareStatus = 'Peer synchronization paused: ' + error.message;
            this.hardwareState = 'restore_failed';
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
        this.hardwareState = 'error';
      }
    };
    this.transport = new NearLinkTransport(callbacks);
    const hooks: DeliveryHooks = {
      send: async (address: string, packet: string): Promise<boolean> => this.transport.send(address, packet),
      prepare: (envelope: SignedAlertEnvelope): string => this.alertVM.nextPacket(envelope)
    };
    this.delivery = new DeliveryQueue(hooks);
  }

  setContext(context: common.UIAbilityContext): void { this.context = context; }
  async probe(): Promise<void> { await this.transport.probe(); }
  async startHardware(): Promise<void> {
    if (this.context === undefined) { return; }
    const generation: number = this.generation;
    try {
      await this.alertVM.restore();
      if (generation !== this.generation) { return; }
      this.stopped = false;
      const started: boolean = await this.transport.start(this.context);
      if (generation !== this.generation || this.stopped) { await this.transport.stop(); return; }
      if (started) {
        if (this.peerName.trim().length > 0) { await this.transport.discover(this.peerName.trim()); }
        if (generation !== this.generation || this.stopped) { await this.transport.stop(); }
      }
    } catch (error) {
      if (generation !== this.generation || this.stopped) { return; }
      this.deliveryStatus = 'restore_failed';
      this.hardwareStatus = 'Saved alert state unavailable. Relay is paused.';
      this.hardwareState = 'restore_failed';
    }
  }
  async connect(address: string): Promise<void> {
    if (!this.stopped) { await this.transport.connect(address); }
  }
  async stop(): Promise<void> {
    this.stopped = true;
    this.generation++;
    if (this.deliveryTimer >= 0) { clearTimeout(this.deliveryTimer); this.deliveryTimer = -1; }
    this.delivery.clear();
    this.peers = []; this.peerCount = 0;
    this.deliveryStatus = 'stopped';
    this.updateDeliveryMetrics();
    try { await this.transport.stop(); } catch (error) {
      this.hardwareStatus = 'Radio cleanup could not complete';
      this.hardwareState = 'cleanup_failed';
    }
  }

  async receive(address: string, packet: string): Promise<void> {
    if (this.stopped) { return; }
    const generation: number = this.generation;
    try {
      const ack: DeliveryAck | undefined = decodeAcknowledgement(packet);
      if (ack !== undefined) {
        const matched: boolean = this.delivery.acknowledge(address, ack);
        this.lastPacketStatus = matched ? 'Peer acknowledged this queued message' : 'Unmatched acknowledgement ignored';
        this.updateDeliveryMetrics();
        return;
      }
      const frame: DeliveryData | undefined = decodeDataPacket(packet);
      const envelope: SignedAlertEnvelope | undefined = frame === undefined ? decodeEnvelope(packet) : frame.envelope;
      if (envelope === undefined) {
        this.rejectedCount++;
        this.lastPacketStatus = 'Malformed packet rejected';
        return;
      }
      const result: RelayResult = await this.alertVM.receive(envelope);
      if (this.stopped || generation !== this.generation) { return; }
      this.lastPacketStatus = result.status + ': ' + result.detail;
      if (result.status === 'accepted' || result.status === 'duplicate') {
        // An ACK is sent only after native signature verification and policy acceptance.
        // Duplicates acknowledge a lost ACK; they are never offered to other peers again.
        if (frame !== undefined && frame.envelope.payload.expiresAt > Date.now()) {
          this.delivery.queueAcknowledgement(address, makeAcknowledgement(frame));
        }
        if (result.status === 'accepted' && result.envelope !== undefined) {
          this.acceptedCount++;
          this.delivery.offer(result.envelope, address);
        }
        await this.pumpDelivery();
      } else { this.rejectedCount++; }
    } catch (error) {
      this.lastPacketStatus = 'Radio packet processing failed; verified alerts retained';
    }
  }

  private async synchronizePeer(address: string): Promise<void> {
    const generation: number = this.generation;
    await this.alertVM.restore();
    if (this.stopped || generation !== this.generation ||
      !this.peers.some((peer: PeerViewModel) => peer.address === address && peer.connected)) { return; }
    this.delivery.synchronize(address, this.alertVM.allAccepted());
    await this.pumpDelivery();
  }

  async share(): Promise<void> {
    if (this.stopped) { this.deliveryStatus = 'stopped'; return; }
    const generation: number = this.generation;
    try {
      await this.alertVM.restore();
      if (this.stopped || generation !== this.generation) { return; }
      const alerts: SignedAlertEnvelope[] = this.alertVM.allAccepted();
      if (alerts.length === 0) {
        this.hardwareStatus = 'Load a valid signed drill first.';
        this.hardwareState = 'load_alert';
        return;
      }
      for (const peer of this.peers) {
        if (peer.connected) { this.delivery.synchronize(peer.address, alerts); }
      }
      await this.pumpDelivery();
      this.hardwareStatus = this.peers.some((peer: PeerViewModel) => peer.connected) ?
        'Signed messages queued. Delivery needs an app acknowledgement from each peer.' :
        'Signed messages saved. Waiting for a connected NearLink peer.';
      this.hardwareState = this.peers.some((peer: PeerViewModel) => peer.connected) ? 'queued' : 'waiting_peer';
    } catch (error) {
      this.deliveryStatus = 'restore_failed';
      this.hardwareStatus = 'Relay paused because saved alert state is unavailable.';
      this.hardwareState = 'restore_failed';
    }
  }

  private async pumpDelivery(): Promise<void> {
    if (this.stopped) { return; }
    const generation: number = this.generation;
    await this.delivery.flush();
    if (this.stopped || generation !== this.generation) { return; }
    this.updateDeliveryMetrics();
    this.scheduleDelivery();
  }

  private updateDeliveryMetrics(): void {
    const metrics: DeliveryMetrics = this.delivery.metrics();
    this.pendingCount = metrics.pending;
    this.acknowledgedCount = metrics.acknowledged;
    this.retryCount = metrics.retries;
    this.failedCount = metrics.failed;
    if (!this.stopped) {
      this.deliveryStatus = metrics.pending > 0 ? 'awaiting_ack' :
        (metrics.failed > 0 ? 'retry_exhausted' : (metrics.acknowledged > 0 ? 'acknowledged' : 'idle'));
    }
  }

  private scheduleDelivery(): void {
    if (this.stopped || this.deliveryTimer >= 0 || !this.delivery.hasWork()) { return; }
    this.deliveryTimer = setTimeout((): void => {
      this.deliveryTimer = -1;
      this.pumpDelivery().catch((error: Error): void => {
        this.deliveryStatus = 'queue_error';
        this.hardwareStatus = 'Relay queue paused: ' + error.message;
        this.hardwareState = 'queue_error';
      });
    }, 500);
  }
  private add(title: string, detail: string, good: boolean): void {
    this.events = this.events.concat([new RelayEvent(String(this.events.length), title, detail, good)]);
  }

  async simulate(): Promise<void> {
    if (this.running) { return; }
    const generation: number = this.generation;
    this.running = true; this.stage = 0; this.events = [];
    try {
      const nodeA: RelayEngine = new RelayEngine();
      const nodeB: RelayEngine = new RelayEngine();
      const nodeC: RelayEngine = new RelayEngine();
      const signed: SignedAlertEnvelope = createDemoAlert();
      const a: RelayResult = await nodeA.ingest(signed);
      if (generation !== this.generation) { return; }
      this.add('A · message received', a.status + ' · native ECDSA verification', a.status === 'accepted');
      if (a.status !== 'accepted') { this.testStatus = a.detail; return; }
      this.stage = 1;
      await new Promise<void>((resolve) => { setTimeout(resolve, 400); });
      if (generation !== this.generation) { return; }
      const ab: SignedAlertEnvelope | undefined = nodeA.nextHop(signed);
      if (ab === undefined) { return; }
      const b: RelayResult = await nodeB.ingest(ab);
      this.add('B · verified and stored', b.status + ' · hop 1 · no internet', b.status === 'accepted');
      this.stage = 2;
      await new Promise<void>((resolve) => { setTimeout(resolve, 400); });
      if (generation !== this.generation) { return; }
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
      if (generation !== this.generation) { return; }
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
