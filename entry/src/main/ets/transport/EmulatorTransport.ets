import type { common } from '@kit.AbilityKit';
import type { BusinessError } from '@kit.BasicServicesKit';
import { webSocket } from '@kit.NetworkKit';
import type { NearLinkCallbacks, NearLinkPeer, NearLinkStatus } from './RelayTransport';

interface LabHello {
  type: string;
  node: string;
  protocol: number;
}

interface LabSend {
  type: string;
  to: string;
  packet: string;
}

interface LabMessage {
  type?: string;
  peers?: string[];
  from?: string;
  packet?: string;
  message?: string;
}

/** Loopback test transport for separate emulator apps. This does not use NearLink radio. */
export class EmulatorTransport {
  private readonly url: string;
  private readonly maxPacketBytes: number = 16384;
  private readonly maxOuterBytes: number = 65536;
  private readonly startTimeout: number = 10000;
  private readonly sendTimeout: number = 5000;
  private readonly closeTimeout: number = 1000;
  private callbacks: NearLinkCallbacks;
  private nodeId: string;
  private socket: webSocket.WebSocket | undefined = undefined;
  private generation: number = 0;
  private opened: boolean = false;
  private ready: boolean = false;
  private state: string = 'lab_disconnected';
  private peers: Set<string> = new Set();
  private starting: Promise<boolean> | undefined = undefined;
  private resolveStart: ((success: boolean) => void) | undefined = undefined;
  private startTimer: number = -1;
  private writeSequence: number = 0;
  private writes: Map<number, (success: boolean) => void> = new Map();

  constructor(callbacks: NearLinkCallbacks, nodeId: string) {
    this.callbacks = callbacks;
    this.nodeId = nodeId;
    const port: number = nodeId === 'B' ? 8766 : nodeId === 'C' ? 8767 : 8765;
    this.url = 'ws://127.0.0.1:' + port + '/mesh';
  }

  async probe(): Promise<NearLinkStatus> {
    return this.notify(this.state);
  }

  start(_context: common.UIAbilityContext): Promise<boolean> {
    if (this.ready) { return Promise.resolve(true); }
    if (this.starting !== undefined) { return this.starting; }
    if (!this.validNode(this.nodeId)) {
      this.callbacks.onError('start', 401, 'Choose emulator node A, B or C.');
      this.notify('lab_error');
      return Promise.resolve(false);
    }
    const generation: number = ++this.generation;
    const result: Promise<boolean> = new Promise<boolean>((resolve: (success: boolean) => void) => {
      this.resolveStart = resolve;
    });
    this.starting = result;
    this.startTimer = setTimeout(() => {
      if (generation === this.generation) { this.fail('start', 408, 'Local hub handshake timed out.'); }
    }, this.startTimeout);
    this.notify('lab_connecting');
    this.openSocket(generation);
    return result;
  }

  private async openSocket(generation: number): Promise<void> {
    try {
      if (generation !== this.generation) { return; }
      const socket: webSocket.WebSocket = webSocket.createWebSocket();
      this.socket = socket;
      socket.on('open', (error: BusinessError, _value: Object) => {
        if (!this.current(socket, generation)) { return; }
        if (error && error.code) { this.fail('open', error.code, this.errorDetail('Local hub connection failed.', error)); return; }
        if (this.opened) { return; }
        this.opened = true;
        console.info('SAFEMESH_LAB_TRANSPORT node=' + this.nodeId + ' event=open');
        const hello: LabHello = { type: 'hello', node: this.nodeId, protocol: 1 };
        this.write(socket, generation, JSON.stringify(hello)).then((accepted: boolean) => {
          if (!accepted && this.current(socket, generation)) {
            this.fail('hello', 0, 'The local hub handshake could not be sent.');
          }
        });
      });
      socket.on('message', (error: BusinessError, value: string | ArrayBuffer) => {
        if (!this.current(socket, generation)) { return; }
        if (error && error.code) { this.fail('receive', error.code, this.errorDetail('Local hub message failed.', error)); return; }
        this.receive(value);
      });
      socket.on('close', (_error: BusinessError, value: webSocket.CloseResult) => {
        if (this.current(socket, generation)) {
          console.info('SAFEMESH_LAB_TRANSPORT node=' + this.nodeId + ' event=close code=' + value?.code);
          this.shutdown('lab_disconnected');
        }
      });
      socket.on('error', (error: BusinessError) => {
        if (this.current(socket, generation)) {
          this.fail('socket', error?.code ?? 0,
            this.errorDetail('Local hub connection failed. Check the hub and HDC reverse port.', error));
        }
      });
      const accepted: boolean = await socket.connect(this.url);
      // Native connect() confirms request creation. Only a later peers frame confirms the handshake.
      if (!accepted && this.current(socket, generation)) {
        this.fail('connect', 0, 'The local connection request was rejected.');
      }
    } catch (error) {
      if (generation === this.generation) {
        this.fail('connect', (error as BusinessError)?.code ?? 0,
          this.errorDetail('The local test transport could not start.', error as BusinessError));
      }
    }
  }

  async discover(_name: string): Promise<boolean> {
    // The hub sends topology-constrained peers; this adapter does not invent discovery results.
    return this.ready;
  }

  async connect(address: string): Promise<boolean> {
    return this.ready && this.peers.has(address);
  }

  async send(address: string, packet: string): Promise<boolean> {
    const socket: webSocket.WebSocket | undefined = this.socket;
    if (!socket || !this.ready || !this.peers.has(address)) { return false; }
    if (typeof packet !== 'string' || packet.length === 0 || !this.withinBytes(packet, this.maxPacketBytes)) {
      this.callbacks.onError('send', 401, 'Lab packet must contain 1-16384 UTF-8 bytes.');
      return false;
    }
    const frame: LabSend = { type: 'send', to: address, packet: packet };
    const encoded: string = JSON.stringify(frame);
    if (!this.withinBytes(encoded, this.maxOuterBytes)) {
      this.callbacks.onError('send', 401, 'Encoded lab frame exceeds 65536 UTF-8 bytes.');
      return false;
    }
    const generation: number = this.generation;
    const accepted: boolean = await this.write(socket, generation, encoded);
    // A local WebSocket write is not an application-level acknowledgement.
    return accepted && this.current(socket, generation) && this.ready && this.peers.has(address);
  }

  async stop(): Promise<void> { await this.shutdown('lab_disconnected'); }

  private current(socket: webSocket.WebSocket, generation: number): boolean {
    return this.socket === socket && this.generation === generation;
  }

  private write(socket: webSocket.WebSocket, generation: number, data: string): Promise<boolean> {
    if (!this.current(socket, generation) || !this.opened || this.writes.size >= 8) {
      return Promise.resolve(false);
    }
    return new Promise<boolean>((resolve: (success: boolean) => void) => {
      const id: number = ++this.writeSequence;
      const timer: number = setTimeout(() => {
        if (this.writes.has(id) && this.current(socket, generation)) {
          this.fail('send', 408, 'Local hub write timed out.');
        }
      }, this.sendTimeout);
      const finish = (success: boolean): void => {
        if (!this.writes.delete(id)) { return; }
        clearTimeout(timer);
        resolve(success && this.current(socket, generation));
      };
      this.writes.set(id, finish);
      try {
        socket.send(data).then((accepted: boolean) => { finish(accepted); }).catch((error: BusinessError) => {
          if (this.current(socket, generation)) {
            this.logFailure('send', error?.code ?? 0, this.errorDetail('Native write failed.', error));
          }
          finish(false);
        });
      } catch (error) {
        this.logFailure('send', (error as BusinessError)?.code ?? 0,
          this.errorDetail('Native write failed.', error as BusinessError));
        finish(false);
      }
    });
  }

  private receive(value: string | ArrayBuffer): void {
    if (!this.opened || typeof value !== 'string' || !this.withinBytes(value, this.maxOuterBytes)) {
      this.fail('receive', 401, 'Invalid or oversized local hub frame.');
      return;
    }
    let message: LabMessage;
    try { message = JSON.parse(value) as LabMessage; }
    catch (error) { this.fail('receive', 401, 'Malformed local hub JSON.'); return; }
    if (!message || typeof message !== 'object' || Array.isArray(message)) {
      this.fail('receive', 401, 'Invalid local hub message.'); return;
    }
    if (message.type === 'peers') {
      const peers: string[] | undefined = message.peers;
      if (!this.exactKeys(message, ['type', 'peers']) || !Array.isArray(peers) || peers.length > 2) {
        this.fail('receive', 401, 'Invalid local peer list.'); return;
      }
      const next: Set<string> = new Set();
      for (const peer of peers) {
        if (typeof peer !== 'string' || !this.validNode(peer) || peer === this.nodeId || next.has(peer)) {
          this.fail('receive', 401, 'Invalid local peer identity.'); return;
        }
        next.add(peer);
      }
      const previous: Set<string> = this.peers;
      this.peers = next;
      this.ready = true;
      this.notify('lab_ready');
      this.finishStart(true);
      previous.forEach((peer: string) => { if (!next.has(peer)) { this.emitPeer(peer, false); } });
      next.forEach((peer: string) => { if (!previous.has(peer)) { this.emitPeer(peer, true); } });
      return;
    }
    if (message.type === 'packet') {
      if (!this.exactKeys(message, ['type', 'from', 'packet']) || !this.ready ||
        typeof message.from !== 'string' || !this.peers.has(message.from) ||
        typeof message.packet !== 'string' || message.packet.length === 0 ||
        !this.withinBytes(message.packet, this.maxPacketBytes)) {
        this.callbacks.onError('receive', 401, 'Unrecognized peer or invalid local packet rejected.'); return;
      }
      this.callbacks.onMessage(message.from, message.packet);
      return;
    }
    if (message.type === 'error' && this.exactKeys(message, ['type', 'message']) &&
      typeof message.message === 'string' && message.message.length > 0 && this.withinBytes(message.message, 512)) {
      // Hub text is diagnostic only; user-facing state remains a stable localization key.
      this.fail('hub', 0, message.message);
      return;
    }
    this.fail('receive', 401, 'Unknown or invalid local hub message.');
  }

  private exactKeys(message: LabMessage, expected: string[]): boolean {
    const keys: string[] = Object.keys(message);
    return keys.length === expected.length && keys.every((key: string) => expected.includes(key));
  }

  private validNode(node: string): boolean { return node === 'A' || node === 'B' || node === 'C'; }

  private withinBytes(value: string, limit: number): boolean {
    if (value.length > limit) { return false; }
    let bytes: number = 0;
    for (let index: number = 0; index < value.length; index++) {
      const code: number = value.charCodeAt(index);
      if (code < 0x80) { bytes++; }
      else if (code < 0x800) { bytes += 2; }
      else if (code >= 0xD800 && code <= 0xDBFF && index + 1 < value.length &&
        value.charCodeAt(index + 1) >= 0xDC00 && value.charCodeAt(index + 1) <= 0xDFFF) {
        bytes += 4; index++;
      } else { bytes += 3; }
      if (bytes > limit) { return false; }
    }
    return true;
  }

  private emitPeer(address: string, connected: boolean): void {
    const peer: NearLinkPeer = {
      address: address, name: 'Lab ' + address, rssi: 127,
      connectable: connected, connected: connected, mtu: this.maxPacketBytes
    };
    this.callbacks.onPeer(peer);
  }

  private finishStart(success: boolean): void {
    if (this.startTimer !== -1) { clearTimeout(this.startTimer); this.startTimer = -1; }
    const resolve: ((success: boolean) => void) | undefined = this.resolveStart;
    this.resolveStart = undefined;
    this.starting = undefined;
    if (resolve !== undefined) { resolve(success); }
  }

  private fail(operation: string, code: number, message: string): void {
    this.logFailure(operation, code, message);
    // shutdown publishes the disconnected peer/status state before its first
    // await. Emit the diagnostic last so consumers retain the actual failure.
    this.shutdown('lab_error');
    this.callbacks.onError(operation, code, message);
  }

  private errorDetail(prefix: string, error: BusinessError | undefined): string {
    const detail: string = typeof error?.message === 'string' ? error.message.slice(0, 200).replace(/[\r\n]/g, ' ') : '';
    return detail.length > 0 ? prefix + ' ' + detail : prefix;
  }

  private logFailure(operation: string, code: number, message: string): void {
    // Diagnostic metadata only. Never log a packet, alert, signature or WebSocket frame.
    const detail: string = operation === 'hub' ? 'Local hub rejected the session.' : message.slice(0, 256).replace(/[\r\n]/g, ' ');
    console.error('SAFEMESH_LAB_TRANSPORT node=' + this.nodeId + ' event=fail op=' + operation +
      ' code=' + code + ' message=' + detail);
  }

  private async shutdown(state: string): Promise<void> {
    const socket: webSocket.WebSocket | undefined = this.socket;
    this.generation++;
    this.socket = undefined;
    this.opened = false;
    this.ready = false;
    this.finishStart(false);
    this.writes.forEach((finish: (success: boolean) => void) => { finish(false); });
    const previous: string[] = Array.from(this.peers);
    this.peers.clear();
    previous.forEach((peer: string) => { this.emitPeer(peer, false); });
    this.notify(state);
    if (!socket) { return; }
    try { socket.off('open'); } catch (error) {}
    try { socket.off('message'); } catch (error) {}
    try { socket.off('close'); } catch (error) {}
    try { socket.off('error'); } catch (error) {}
    await new Promise<void>((resolve: () => void) => {
      const timer: number = setTimeout(resolve, this.closeTimeout);
      const finish = (): void => { clearTimeout(timer); resolve(); };
      try { socket.close().then(finish).catch(finish); } catch (error) { finish(); }
    });
  }

  private notify(state: string): NearLinkStatus {
    this.state = state;
    const status: NearLinkStatus = {
      state: state, supported: true, connectedPeers: this.peers.size,
      message: 'Local emulator test transport (' + this.nodeId + '): ' + state + '. No NearLink radio.'
    };
    this.callbacks.onStatus(status);
    return status;
  }
}
