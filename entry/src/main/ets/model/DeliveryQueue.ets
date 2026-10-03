import { SignedAlertEnvelope, copyEnvelope, decodeEnvelope } from './AlertProtocol';
import { DeliveryAck, createDeliveryId, encodeDataPacket } from './DeliveryProtocol';

export interface DeliveryHooks {
  send: (address: string, packet: string) => Promise<boolean>;
  prepare: (envelope: SignedAlertEnvelope) => string;
  nonce?: () => string;
}

export interface DeliveryMetrics {
  pending: number;
  acknowledged: number;
  retries: number;
  failed: number;
}

class PendingDelivery {
  envelope: SignedAlertEnvelope;
  deliveryId: string;
  attempts: number = 0;
  nextAttemptAt: number = 0;
  state: string = 'pending';
  constructor(envelope: SignedAlertEnvelope, deliveryId: string) {
    this.envelope = copyEnvelope(envelope); this.deliveryId = deliveryId;
  }
}

class PeerQueue {
  address: string;
  items: Map<string, PendingDelivery> = new Map<string, PendingDelivery>();
  constructor(address: string) { this.address = address; }
}

class ControlPacket {
  address: string;
  packet: string;
  deliveryId: string;
  expiresAt: number;
  constructor(address: string, packet: string, deliveryId: string, expiresAt: number) {
    this.address = address; this.packet = packet; this.deliveryId = deliveryId; this.expiresAt = expiresAt;
  }
}

class SendCandidate {
  peer: PeerQueue;
  item: PendingDelivery;
  constructor(peer: PeerQueue, item: PendingDelivery) { this.peer = peer; this.item = item; }
}

/** Foreground only. At most 8 peers * 128 alerts, 3 attempts/connection, 4 writes/batch. */
export class DeliveryQueue {
  private hooks: DeliveryHooks;
  private peers: Map<string, PeerQueue> = new Map<string, PeerQueue>();
  private controls: ControlPacket[] = [];
  private pumping: Promise<void> | undefined = undefined;
  private generation: number = 0;
  private acknowledged: number = 0;
  private retries: number = 0;
  private failed: number = 0;
  private sendTimer: number = -1;
  private finishSend: ((success: boolean) => void) | undefined = undefined;

  constructor(hooks: DeliveryHooks) { this.hooks = hooks; }

  connect(address: string, envelopes: SignedAlertEnvelope[]): void {
    if (!this.peers.has(address) && this.peers.size < 8) { this.peers.set(address, new PeerQueue(address)); }
    this.synchronize(address, envelopes);
  }

  disconnect(address: string): void {
    this.peers.delete(address);
    this.controls = this.controls.filter((packet: ControlPacket) => packet.address !== address);
  }

  synchronize(address: string, envelopes: SignedAlertEnvelope[]): void {
    const peer: PeerQueue | undefined = this.peers.get(address);
    if (peer === undefined) { return; }
    const retained: Set<string> = new Set<string>();
    for (const envelope of envelopes.slice(0, 128)) {
      const key: string = this.identity(envelope);
      retained.add(key);
      const old: PendingDelivery | undefined = peer.items.get(key);
      if (old === undefined || old.envelope.payload.revision !== envelope.payload.revision) {
        this.enqueue(peer, envelope);
      }
    }
    peer.items.forEach((item: PendingDelivery, key: string) => {
      if (!retained.has(key)) { peer.items.delete(key); }
    });
  }

  offer(envelope: SignedAlertEnvelope, excludeAddress: string = ''): void {
    this.peers.forEach((peer: PeerQueue) => {
      if (peer.address !== excludeAddress) { this.enqueue(peer, envelope); }
    });
  }

  queueAcknowledgement(address: string, ack: DeliveryAck, now: number = Date.now()): void {
    if (!this.peers.has(address) || this.controls.length >= 64 || this.controls.some((item: ControlPacket) =>
      item.address === address && item.deliveryId === ack.deliveryId)) { return; }
    this.controls.push(new ControlPacket(address, JSON.stringify(ack), ack.deliveryId, now + 5000));
  }

  acknowledge(address: string, ack: DeliveryAck, now: number = Date.now()): boolean {
    const peer: PeerQueue | undefined = this.peers.get(address);
    if (peer === undefined) { return false; }
    const item: PendingDelivery | undefined = peer.items.get(JSON.stringify([ack.keyId, ack.alertId]));
    if (item === undefined || item.state !== 'pending' || item.attempts === 0 ||
      item.deliveryId !== ack.deliveryId || item.envelope.payload.revision !== ack.revision ||
      item.envelope.payload.expiresAt <= now) { return false; }
    item.state = 'acknowledged';
    this.acknowledged++;
    return true;
  }

  async flush(now: number = Date.now()): Promise<void> {
    if (this.pumping !== undefined) { await this.pumping; return; }
    const generation: number = this.generation;
    this.pumping = this.pump(now, generation);
    try { await this.pumping; } finally { this.pumping = undefined; }
  }

  hasWork(now: number = Date.now()): boolean {
    this.prune(now);
    return this.controls.length > 0 || this.metrics(now).pending > 0;
  }

  metrics(now: number = Date.now()): DeliveryMetrics {
    this.prune(now);
    let pending: number = 0;
    this.peers.forEach((peer: PeerQueue) => {
      peer.items.forEach((item: PendingDelivery) => { if (item.state === 'pending') { pending++; } });
    });
    return { pending: pending, acknowledged: this.acknowledged, retries: this.retries, failed: this.failed };
  }

  clear(): void {
    this.generation++;
    if (this.sendTimer >= 0) { clearTimeout(this.sendTimer); this.sendTimer = -1; }
    const finish: ((success: boolean) => void) | undefined = this.finishSend;
    this.finishSend = undefined;
    if (finish !== undefined) { finish(false); }
    this.peers.clear(); this.controls = [];
    this.acknowledged = 0; this.retries = 0; this.failed = 0;
  }

  private enqueue(peer: PeerQueue, envelope: SignedAlertEnvelope): void {
    if (envelope.payload.expiresAt <= Date.now() || this.hooks.prepare(envelope).length === 0) { return; }
    const key: string = this.identity(envelope);
    const old: PendingDelivery | undefined = peer.items.get(key);
    if (old !== undefined && old.envelope.payload.revision >= envelope.payload.revision) { return; }
    if (old === undefined && peer.items.size >= 128) { return; }
    const nonce: string = this.hooks.nonce === undefined ? createDeliveryId() : this.hooks.nonce();
    peer.items.set(key, new PendingDelivery(envelope, nonce));
  }

  private async pump(now: number, generation: number): Promise<void> {
    this.prune(now);
    let writes: number = 0;
    while (this.controls.length > 0 && writes < 4 && generation === this.generation) {
      const packet: ControlPacket = this.controls.shift() as ControlPacket;
      if (packet.expiresAt <= Date.now() || !this.peers.has(packet.address)) { continue; }
      try { await this.sendBounded(packet.address, packet.packet); } catch (error) { /* sender retries its data */ }
      writes++;
    }
    const candidates: SendCandidate[] = [];
    this.peers.forEach((peer: PeerQueue) => {
      peer.items.forEach((item: PendingDelivery) => {
        if (item.state === 'pending' && item.nextAttemptAt <= now) { candidates.push(new SendCandidate(peer, item)); }
      });
    });
    candidates.sort((a: SendCandidate, b: SendCandidate) => a.item.nextAttemptAt - b.item.nextAttemptAt);
    for (const candidate of candidates) {
      if (writes >= 4 || generation !== this.generation) { break; }
      const peer: PeerQueue = candidate.peer;
      const item: PendingDelivery = candidate.item;
      if (this.peers.get(peer.address) !== peer || item.state !== 'pending') { continue; }
      if (item.attempts >= 3) { item.state = 'failed'; this.failed++; continue; }
      const packet: string = this.hooks.prepare(item.envelope);
      const outgoing: SignedAlertEnvelope | undefined = decodeEnvelope(packet);
      if (outgoing === undefined || item.envelope.payload.expiresAt <= Date.now()) {
        peer.items.delete(this.identity(item.envelope)); continue;
      }
      if (item.attempts > 0) { this.retries++; }
      item.attempts++;
      item.nextAttemptAt = now + Math.min(8000, 2000 * Math.pow(2, item.attempts - 1));
      writes++;
      try { await this.sendBounded(peer.address, encodeDataPacket(item.deliveryId, outgoing)); }
      catch (error) { /* failure consumes this bounded attempt; next tick retries */ }
    }
  }

  private prune(now: number): void {
    this.controls = this.controls.filter((packet: ControlPacket) => packet.expiresAt > now && this.peers.has(packet.address));
    this.peers.forEach((peer: PeerQueue) => {
      peer.items.forEach((item: PendingDelivery, key: string) => {
        if (item.envelope.payload.expiresAt <= now) { peer.items.delete(key); }
        else if (item.state === 'pending' && item.attempts >= 3 && item.nextAttemptAt <= now) {
          item.state = 'failed'; this.failed++;
        }
      });
    });
  }

  /** Bounds the app's wait; native writes cannot be forcibly cancelled by this API. */
  private async sendBounded(address: string, packet: string): Promise<boolean> {
    const deadline: Promise<boolean> = new Promise<boolean>((resolve: (value: boolean) => void) => {
      this.finishSend = resolve;
      this.sendTimer = setTimeout((): void => { resolve(false); }, 3000);
    });
    try {
      return await Promise.race([this.hooks.send(address, packet), deadline]);
    } finally {
      if (this.sendTimer >= 0) { clearTimeout(this.sendTimer); this.sendTimer = -1; }
      this.finishSend = undefined;
    }
  }

  private identity(envelope: SignedAlertEnvelope): string {
    return JSON.stringify([envelope.payload.keyId, envelope.payload.alertId]);
  }
}
