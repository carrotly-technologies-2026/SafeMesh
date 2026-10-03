import { common } from '@kit.AbilityKit';
import { NearLinkTransport, NearLinkStatus, NearLinkPeer, NearLinkCallbacks } from '../transport/NearLinkTransport';
import { RelayTransport } from '../transport/RelayTransport';
import { EmulatorTransport } from '../transport/EmulatorTransport';
import { RelayEngine, RelayResult, SignedAlertEnvelope, decodeEnvelope } from '../model/AlertProtocol';
import { createDemoAlert, createTamperedAlert, createExpiredAlert } from '../model/DemoAlerts';
import { DeliveryQueue, DeliveryHooks, DeliveryMetrics } from '../model/DeliveryQueue';
import { DeliveryData, DeliveryAck, decodeDataPacket, decodeAcknowledgement, makeAcknowledgement } from '../model/DeliveryProtocol';
import { AlertViewModel } from './AlertViewModel';

export class RelayEvent {
  id: string;
  titleKey: string;
  detailKey: string;
  status: string;
  good: boolean;
  constructor(id: string, titleKey: string, detailKey: string, status: string, good: boolean) {
    this.id = id; this.titleKey = titleKey; this.detailKey = detailKey; this.status = status; this.good = good;
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
  testState: string = 'idle';
  testFailureState: string = 'none';
  acceptedCount: number = 0;
  rejectedCount: number = 0;
  lastPacketState: string = 'none';
  lifecycleState: string = 'idle';
  deliveryStatus: string = 'idle';
  pendingCount: number = 0;
  acknowledgedCount: number = 0;
  retryCount: number = 0;
  failedCount: number = 0;
  transportMode: string = 'nearlink';
  emulatorNode: string = 'A';
  private alertVM: AlertViewModel;
  private transport: RelayTransport;
  private delivery: DeliveryQueue;
  private context: common.UIAbilityContext | undefined = undefined;
  private deliveryTimer: number = -1;
  private stopped: boolean = false;
  private generation: number = 0;
  private transportGeneration: number = 0;
  private inForeground: boolean = true;
  private connectionActive: boolean = false;
  private resumeOnForeground: boolean = false;
  private lifecycleGeneration: number = 0;
  private pendingSuspend: Promise<void> | undefined = undefined;

  constructor(alertVM: AlertViewModel) {
    this.alertVM = alertVM;
    this.transport = this.createTransport('nearlink', this.emulatorNode);
    const hooks: DeliveryHooks = {
      send: async (address: string, packet: string): Promise<boolean> => this.transport.send(address, packet),
      prepare: (envelope: SignedAlertEnvelope): string => this.alertVM.nextPacket(envelope)
    };
    this.delivery = new DeliveryQueue(hooks);
  }

  private createTransport(mode: string, node: string): RelayTransport {
    const transportGeneration: number = ++this.transportGeneration;
    const callbacks: NearLinkCallbacks = {
      onStatus: (status: NearLinkStatus): void => {
        if (transportGeneration !== this.transportGeneration || this.stopped) { return; }
        console.info('SAFEMESH_TRANSPORT_STATUS mode=' + mode + ' state=' + status.state +
          ' peers=' + status.connectedPeers);
        this.hardwareStatus = status.message;
        this.hardwareState = status.state.replace('-', '_');
        this.hardwareSupported = status.supported;
        this.peerCount = status.connectedPeers;
        if (['lab_error', 'lab_disconnected', 'error', 'stopped', 'unsupported', 'off', 'permission_denied']
          .includes(this.hardwareState)) {
          this.connectionActive = false;
          if (this.inForeground) { this.lifecycleState = 'idle'; }
        }
      },
      onPeer: (peer: NearLinkPeer): void => {
        if (transportGeneration !== this.transportGeneration || this.stopped) { return; }
        const previous: PeerViewModel | undefined = this.peers.find((old: PeerViewModel) => old.address === peer.address);
        if (previous === undefined || previous.connected !== peer.connected) {
          // Repeated scan results are not logged; only first discovery and link changes.
          console.info('SAFEMESH_TRANSPORT_PEER mode=' + mode + ' connected=' + peer.connected +
            ' name=' + peer.name.replace(/[^A-Za-z0-9 _.-]/g, '_').slice(0, 32));
        }
        const item: PeerViewModel = new PeerViewModel();
        item.address = peer.address; item.name = peer.name; item.connected = peer.connected;
        this.peers = this.peers.filter((old: PeerViewModel) => old.address !== item.address).concat([item]).slice(-8);
        if (!peer.connected) {
          this.delivery.disconnect(peer.address);
          this.updateDeliveryMetrics();
        } else if (previous === undefined || !previous.connected) {
          this.delivery.connect(peer.address, []);
          this.synchronizePeer(peer.address).catch((error: Error): void => {
            if (transportGeneration !== this.transportGeneration || this.stopped) { return; }
            this.deliveryStatus = 'restore_failed';
            this.hardwareStatus = 'Peer synchronization paused: ' + error.message;
            this.hardwareState = 'restore_failed';
          });
        }
      },
      onMessage: (address: string, packet: string): void => {
        if (transportGeneration !== this.transportGeneration || this.stopped) { return; }
        this.receive(address, packet).catch((error: Error): void => {
          if (transportGeneration !== this.transportGeneration || this.stopped) { return; }
          this.lastPacketState = 'processing_failed';
          console.error('SAFEMESH_RELAY_ERROR operation=receive');
        });
      },
      onError: (operation: string, code: number, message: string): void => {
        if (transportGeneration !== this.transportGeneration || this.stopped) { return; }
        // Platform error codes are diagnostic metadata; packets and alert text are never logged.
        console.error('SAFEMESH_TRANSPORT_ERROR mode=' + mode + ' op=' + operation + ' code=' + code +
          ' message=' + message.replace(/[\r\n]/g, ' ').slice(0, 200));
        this.hardwareStatus = operation + ': ' + message + ' (' + code + ')';
        this.hardwareState = mode === 'emulator' ? 'lab_error' : 'error';
        // Invalid individual packets do not close a ready lab socket. The
        // adapter emits terminal onStatus first for fatal protocol failures.
        // NearLink discovery/write errors likewise leave its listener active.
        const packetRejected: boolean = this.connectionActive && code === 401 &&
          (operation === 'send' || operation === 'receive');
        const disconnected: boolean = mode === 'emulator' ? !packetRejected :
          (operation === 'start' || operation === 'probe' || operation === 'stop');
        if (disconnected) {
          this.connectionActive = false;
          if (this.inForeground) { this.lifecycleState = 'idle'; }
        }
      }
    };
    return mode === 'emulator' ? new EmulatorTransport(callbacks, node) : new NearLinkTransport(callbacks);
  }

  setContext(context: common.UIAbilityContext): void { this.context = context; }

  /** Active foreground transport, independent of queue/operation diagnostic labels. */
  get isConnected(): boolean { return this.connectionActive && !this.stopped && this.inForeground; }

  /** Suspension stops sockets/timers; only a previously active user connection can resume. */
  async suspend(): Promise<void> {
    if (!this.inForeground) { await this.pendingSuspend; return; }
    this.inForeground = false;
    this.resumeOnForeground = this.connectionActive;
    this.lifecycleState = this.resumeOnForeground ? 'paused' : 'idle';
    const pending: Promise<void> = this.stopTransport();
    this.pendingSuspend = pending;
    try { await pending; } finally {
      if (this.pendingSuspend === pending) { this.pendingSuspend = undefined; }
    }
  }

  /** No work on first appearance; resumes only the transport/role suspended above. */
  async foreground(): Promise<void> {
    this.inForeground = true;
    const generation: number = this.lifecycleGeneration;
    await this.pendingSuspend;
    if (!this.inForeground || generation !== this.lifecycleGeneration || !this.resumeOnForeground) { return; }
    this.resumeOnForeground = false;
    await this.startSelectedTransport(this.transportMode, this.emulatorNode);
  }

  /** Hardware checks explicitly leave the emulator link and its per-session delivery counters. */
  async probe(): Promise<void> {
    if (!this.inForeground) { return; }
    let transport: RelayTransport | undefined = this.transport;
    if (this.transportMode !== 'nearlink' || this.stopped) {
      transport = await this.selectTransport('nearlink', this.emulatorNode);
    }
    if (transport === undefined || transport !== this.transport || this.stopped) { return; }
    const generation: number = this.generation;
    try { await transport.probe(); } catch (error) {
      if (generation !== this.generation || this.stopped) { return; }
      this.hardwareStatus = 'NearLink hardware check could not complete.';
      this.hardwareState = 'error';
    }
  }

  async startHardware(): Promise<void> { await this.startSelectedTransport('nearlink', this.emulatorNode); }

  /** Starts a real packet connection between app processes, never a physical NearLink claim. */
  async startEmulator(node: string): Promise<void> {
    if (node !== 'A' && node !== 'B' && node !== 'C') {
      this.hardwareStatus = 'Choose emulator A, B or C.';
      this.hardwareState = 'lab_error';
      return;
    }
    await this.startSelectedTransport('emulator', node);
  }

  private async selectTransport(mode: string, node: string): Promise<RelayTransport | undefined> {
    const generation: number = this.generation + 1;
    await this.stop();
    if (generation !== this.generation) { return undefined; }
    this.transportMode = mode;
    this.emulatorNode = node;
    this.stopped = false;
    this.hardwareSupported = false;
    this.hardwareState = mode === 'emulator' ? 'lab_connecting' : 'not_checked';
    this.hardwareStatus = mode === 'emulator' ? 'Connecting emulator ' + node + ' to the local test link.' :
      'Hardware not checked';
    this.lastPacketState = 'none';
    this.deliveryStatus = 'idle';
    this.transport = this.createTransport(mode, node);
    return this.transport;
  }

  private async startSelectedTransport(mode: string, node: string): Promise<void> {
    if (this.context === undefined || !this.inForeground) { return; }
    const transport: RelayTransport | undefined = await this.selectTransport(mode, node);
    if (transport === undefined || transport !== this.transport || this.stopped) { return; }
    const generation: number = this.generation;
    let restored: boolean = false;
    try {
      await this.alertVM.restore();
      if (generation !== this.generation || this.stopped) { return; }
      restored = true;
      const started: boolean = await transport.start(this.context);
      if (generation !== this.generation || this.stopped) { await transport.stop(); return; }
      if (started) {
        this.connectionActive = true;
        this.lifecycleState = 'active';
        if (mode === 'nearlink' && this.peerName.trim().length > 0) {
          await transport.discover(this.peerName.trim());
        }
        if (generation !== this.generation || this.stopped) { await transport.stop(); }
      }
    } catch (error) {
      if (generation !== this.generation || this.stopped) { return; }
      this.deliveryStatus = restored ? 'queue_error' : 'restore_failed';
      this.hardwareStatus = restored ? 'The packet link could not start.' :
        'Saved alert state unavailable. Relay is paused.';
      this.hardwareState = restored ? (mode === 'emulator' ? 'lab_error' : 'error') : 'restore_failed';
    }
  }
  async connect(address: string): Promise<void> {
    if (!this.stopped) { await this.transport.connect(address); }
  }
  async stop(): Promise<void> {
    this.lifecycleGeneration++;
    this.resumeOnForeground = false;
    this.lifecycleState = 'idle';
    await this.stopTransport();
  }

  private async stopTransport(): Promise<void> {
    const transport: RelayTransport = this.transport;
    this.stopped = true;
    this.connectionActive = false;
    const generation: number = ++this.generation;
    this.transportGeneration++;
    if (this.deliveryTimer >= 0) { clearTimeout(this.deliveryTimer); this.deliveryTimer = -1; }
    this.delivery.clear();
    this.peers = []; this.peerCount = 0;
    this.deliveryStatus = 'stopped';
    this.updateDeliveryMetrics();
    this.hardwareState = 'stopped';
    this.hardwareStatus = this.transportMode === 'emulator' ? 'Emulator packet link stopped.' :
      'NearLink relay stopped. Saved alerts remain available offline.';
    try { await transport.stop(); } catch (error) {
      if (generation !== this.generation) { return; }
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
        this.lastPacketState = matched ? 'ack_matched' : 'ack_unmatched';
        this.logReceive(matched ? 'ack_matched' : 'ack_unmatched', ack.alertId);
        this.updateDeliveryMetrics();
        return;
      }
      const frame: DeliveryData | undefined = decodeDataPacket(packet);
      const envelope: SignedAlertEnvelope | undefined = frame === undefined ? decodeEnvelope(packet) : frame.envelope;
      if (envelope === undefined) {
        this.rejectedCount++;
        this.lastPacketState = 'malformed';
        this.logReceive('malformed');
        return;
      }
      const result: RelayResult = await this.alertVM.receive(envelope, address);
      if (this.stopped || generation !== this.generation) { return; }
      this.lastPacketState = result.status;
      this.logReceive(result.status, envelope.payload.alertId, envelope.hops);
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
      if (this.stopped || generation !== this.generation) { return; }
      this.lastPacketState = 'processing_failed';
      this.logReceive('processing_failed');
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

  /** Loads the bundled signed exercise; an active link offers it to connected peers at once. */
  async loadDrill(): Promise<void> {
    await this.alertVM.loadDrill();
    if (this.isConnected) { await this.share(); }
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
      if (this.stopped || generation !== this.generation) { return; }
      this.hardwareStatus = this.peers.some((peer: PeerViewModel) => peer.connected) ?
        'Signed messages queued. Delivery needs an app acknowledgement from each peer.' :
        'Signed messages saved. Waiting for a connected NearLink peer.';
      this.hardwareState = this.peers.some((peer: PeerViewModel) => peer.connected) ? 'queued' : 'waiting_peer';
    } catch (error) {
      if (this.stopped || generation !== this.generation) { return; }
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
    const generation: number = this.generation;
    this.deliveryTimer = setTimeout((): void => {
      this.deliveryTimer = -1;
      this.pumpDelivery().catch((error: Error): void => {
        if (this.stopped || generation !== this.generation) { return; }
        this.deliveryStatus = 'queue_error';
        this.hardwareStatus = 'Relay queue paused: ' + error.message;
        this.hardwareState = 'queue_error';
      });
    }, 500);
  }

  private logReceive(status: string, alertId: string = '', hops: number = -1): void {
    const safeId: string = alertId.replace(/[^A-Za-z0-9_.:-]/g, '_').slice(0, 96);
    console.info('SAFEMESH_RELAY_RECEIVE node=' + (this.transportMode === 'emulator' ? this.emulatorNode : 'nearlink') +
      ' status=' + status + ' alertId=' + safeId + ' hops=' + hops);
  }
  private add(key: string, status: string, good: boolean): void {
    this.events = this.events.concat([new RelayEvent(String(this.events.length),
      'relay_event_' + key, 'relay_detail_' + key, status, good)]);
  }

  async simulate(): Promise<void> {
    if (this.running) { return; }
    const generation: number = this.generation;
    this.running = true; this.stage = 0; this.events = []; this.testState = 'running'; this.testFailureState = 'none';
    try {
      const nodeA: RelayEngine = new RelayEngine();
      const nodeB: RelayEngine = new RelayEngine();
      const nodeC: RelayEngine = new RelayEngine();
      const signed: SignedAlertEnvelope = createDemoAlert();
      const a: RelayResult = await nodeA.ingest(signed);
      if (generation !== this.generation) { return; }
      this.add('a', a.status, a.status === 'accepted');
      if (a.status !== 'accepted') { this.testState = 'failed'; this.testFailureState = a.status; return; }
      this.stage = 1;
      await new Promise<void>((resolve) => { setTimeout(resolve, 400); });
      if (generation !== this.generation) { return; }
      const ab: SignedAlertEnvelope | undefined = nodeA.nextHop(signed);
      if (ab === undefined) { this.testState = 'failed'; this.testFailureState = 'expired'; return; }
      const b: RelayResult = await nodeB.ingest(ab);
      if (generation !== this.generation) { return; }
      this.add('b', b.status, b.status === 'accepted');
      this.stage = 2;
      await new Promise<void>((resolve) => { setTimeout(resolve, 400); });
      if (generation !== this.generation) { return; }
      const bc: SignedAlertEnvelope | undefined = nodeB.nextHop(ab);
      if (bc === undefined) { this.testState = 'failed'; this.testFailureState = 'expired'; return; }
      const c: RelayResult = await nodeC.ingest(bc);
      if (generation !== this.generation) { return; }
      this.add('c', c.status, c.status === 'accepted');
      this.stage = 3;
      const replay: RelayResult = await nodeC.ingest(bc);
      if (generation !== this.generation) { return; }
      this.add('duplicate', replay.status, replay.status === 'duplicate');
      const tampered: RelayResult = await new RelayEngine().ingest(createTamperedAlert());
      if (generation !== this.generation) { return; }
      this.add('tampered', tampered.status, tampered.status === 'invalid');
      const expired: RelayResult = await new RelayEngine().ingest(createExpiredAlert());
      if (generation !== this.generation) { return; }
      this.add('expired', expired.status, expired.status === 'expired');
      const passed: boolean = this.events.every((event: RelayEvent) => event.good);
      if (generation !== this.generation) { return; }
      this.testState = passed ? 'passed' : 'failed';
      console.info('SAFEMESH_NATIVE_DIAGNOSTICS ' + (passed ? 'PASS' : 'FAIL') + ' ' + JSON.stringify(this.events));
      await this.alertVM.loadDrill();
    } catch (error) {
      if (generation !== this.generation) { return; }
      this.testState = 'error';
      this.testFailureState = 'processing_failed';
      this.add('error', 'processing_failed', false);
      console.error('SAFEMESH_NATIVE_DIAGNOSTICS FAIL ' + String(error));
    } finally {
      this.running = false;
      if (this.testState === 'running') { this.testState = 'idle'; }
    }
  }
}
