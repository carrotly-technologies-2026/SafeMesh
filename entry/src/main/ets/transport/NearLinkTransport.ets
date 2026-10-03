import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import type { dataTransfer, scan } from '@kit.NearLinkKit';

export interface NearLinkStatus {
  state: string;
  message: string;
  supported: boolean;
  connectedPeers: number;
}

export interface NearLinkPeer {
  address: string;
  name: string;
  rssi: number;
  connectable: boolean;
  connected: boolean;
  mtu: number;
}

export interface NearLinkCallbacks {
  onStatus: (status: NearLinkStatus) => void;
  onPeer: (peer: NearLinkPeer) => void;
  onMessage: (address: string, packet: string) => void;
  onError: (operation: string, code: number, message: string) => void;
}

class PartialPacket {
  bytes: Uint8Array = new Uint8Array(0);
  updatedAt: number = Date.now();
}

/** Real radio adapter. The emulator never fabricates radio discovery or delivery. */
export class NearLinkTransport {
  private readonly uuid: string = 'A39B6D32-81C4-4DA8-B730-D2E0629A7441';
  private readonly maxPacketBytes: number = 16384;
  private readonly maxPeers: number = 8;
  private readonly frameMagic: number = 0x534D0100;
  private callbacks: NearLinkCallbacks;
  private supported: boolean = false;
  private loaded: boolean = false;
  private started: boolean = false;
  private scanning: boolean = false;
  private advertisingId: number = -1;
  private portCreated: boolean = false;
  private scanSubscribed: boolean = false;
  private connectionSubscribed: boolean = false;
  private readSubscribed: boolean = false;
  private sending: boolean = false;
  private peers: Map<string, NearLinkPeer> = new Map();
  private partials: Map<string, PartialPacket> = new Map();
  private pendingConnections: Set<string> = new Set();
  private encoder: util.TextEncoder = new util.TextEncoder();
  private decoder: util.TextDecoder = util.TextDecoder.create('utf-8', { fatal: true });

  constructor(callbacks: NearLinkCallbacks) {
    this.callbacks = callbacks;
  }

  isSupported(): boolean {
    return this.supported;
  }

  connectedCount(): number {
    let count: number = 0;
    this.peers.forEach((peer: NearLinkPeer) => {
      if (peer.connected) {
        count++;
      }
    });
    return count;
  }

  async probe(): Promise<NearLinkStatus> {
    if (!canIUse('SystemCapability.Communication.NearLink.Core')) {
      this.supported = false;
      return this.notify('unsupported', 'NearLink radio is unavailable on this device. Emulator relay uses simulation.');
    }
    try {
      // Loading an unsupported Huawei Kit statically can crash an emulator at startup.
      const kit = await import('@kit.NearLinkKit');
      this.loaded = true;
      this.supported = kit.manager.isNearLinkSupported();
      if (!this.supported) {
        return this.notify('unsupported', 'NearLink needs supported physical hardware; this emulator has no NearLink radio.');
      }
      if (kit.manager.getState() !== kit.manager.NearlinkState.STATE_ON) {
        return this.notify('off', 'Enable NearLink in the device settings, then start the relay.');
      }
      return this.notify(this.started ? 'ready' : 'available', 'NearLink hardware detected. Radio delivery still requires another device.');
    } catch (error) {
      this.supported = false;
      this.report('probe', error as BusinessError);
      return this.notify('unsupported', 'NearLink Kit is unavailable here. Use supported physical phones for radio tests.');
    }
  }

  async start(context: common.UIAbilityContext): Promise<boolean> {
    if (this.started) {
      return true;
    }
    const status: NearLinkStatus = await this.probe();
    if (!status.supported || status.state === 'off') {
      return false;
    }
    try {
      const permissions: Permissions[] = ['ohos.permission.ACCESS_NEARLINK'];
      const result = await abilityAccessCtrl.createAtManager().requestPermissionsFromUser(context, permissions);
      if (result.authResults.length !== 1 || result.authResults[0] !== 0) {
        this.notify('permission-denied', 'Allow nearby NearLink access to exchange alerts.');
        return false;
      }
      const kit = await import('@kit.NearLinkKit');
      kit.dataTransfer.createPort(this.uuid);
      this.portCreated = true;
      kit.dataTransfer.on('connectionStateChanged', this.onConnection);
      this.connectionSubscribed = true;
      kit.dataTransfer.on('readData', this.onRead);
      this.readSubscribed = true;
      kit.scan.on('deviceFound', this.onDiscovered);
      this.scanSubscribed = true;
      this.advertisingId = await kit.advertising.startAdvertising({
        advertisingSettings: { interval: 5000, isConnectable: true },
        advertisingData: { serviceUuids: [this.uuid], includeDeviceName: true }
      });
      this.started = true;
      this.notify('ready', 'Radio listening. Find another phone by its NearLink device name.');
      return true;
    } catch (error) {
      this.report('start', error as BusinessError);
      await this.stop();
      this.notify('error', 'NearLink could not start. Check permission, radio settings and hardware support.');
      return false;
    }
  }

  async discover(peerDeviceName: string): Promise<boolean> {
    if (!this.started) {
      this.callbacks.onError('discover', 0, 'Start NearLink before discovering peers.');
      return false;
    }
    const name: string = peerDeviceName.trim();
    if (name.length === 0 || name.length > 30) {
      this.callbacks.onError('discover', 401, 'API 24 requires the other phone\'s exact NearLink name (1-30 characters).');
      return false;
    }
    try {
      const kit = await import('@kit.NearLinkKit');
      if (this.scanning) {
        await kit.scan.stopScan();
      }
      await kit.scan.startScan([{ deviceName: name }], { scanMode: kit.scan.ScanMode.SCAN_MODE_LOW_POWER });
      this.scanning = true;
      this.notify('discovering', `Looking for ${name}. Select a discovered peer to connect.`);
      return true;
    } catch (error) {
      this.report('discover', error as BusinessError);
      return false;
    }
  }

  async connect(address: string): Promise<boolean> {
    const peer: NearLinkPeer | undefined = this.peers.get(address);
    if (!this.started || !peer || !peer.connectable || this.pendingConnections.has(address)) {
      this.callbacks.onError('connect', 0, 'Select a connectable device returned by discovery.');
      return false;
    }
    if (peer.connected) {
      return true;
    }
    if (this.connectedCount() + this.pendingConnections.size >= this.maxPeers) {
      this.callbacks.onError('connect', 0, 'Peer limit reached.');
      return false;
    }
    this.pendingConnections.add(address);
    try {
      const kit = await import('@kit.NearLinkKit');
      await kit.dataTransfer.connect({
        address: address,
        uuid: this.uuid,
        mtu: 1024,
        transferMode: kit.dataTransfer.TransferMode.RELIABLE
      });
      // Only the actual connection callback counts the peer as connected.
      setTimeout(() => {
        if (this.pendingConnections.delete(address)) {
          this.callbacks.onError('connect', 0, 'No channel confirmation within 30 seconds. Try connecting again.');
        }
      }, 30000);
      return true;
    } catch (error) {
      this.pendingConnections.delete(address);
      this.report('connect', error as BusinessError);
      return false;
    }
  }

  async send(address: string, packet: string): Promise<boolean> {
    const peer: NearLinkPeer | undefined = this.peers.get(address);
    if (!this.started || !peer || !peer.connected || peer.mtu < 8) {
      this.callbacks.onError('send', 0, 'No confirmed NearLink channel with a usable MTU.');
      return false;
    }
    if (this.sending) {
      this.callbacks.onError('send', 1009700023, 'Send in progress. Keep the alert queued for the next relay attempt.');
      return false;
    }
    const payload: Uint8Array = this.encoder.encodeInto(packet);
    if (payload.length === 0 || payload.length > this.maxPacketBytes) {
      this.callbacks.onError('send', 401, 'Alert packet must contain 1-16384 UTF-8 bytes.');
      return false;
    }
    const frame: Uint8Array = new Uint8Array(payload.length + 8);
    const header: DataView = new DataView(frame.buffer);
    header.setUint32(0, this.frameMagic);
    header.setUint32(4, payload.length);
    frame.set(payload, 8);
    this.sending = true;
    try {
      const kit = await import('@kit.NearLinkKit');
      const chunkSize: number = Math.min(peer.mtu, 1024);
      for (let offset: number = 0; offset < frame.length; offset += chunkSize) {
        if (!this.started || !this.peers.get(address)?.connected) {
          this.callbacks.onError('send', 0, 'Channel closed during send; alert remains queued.');
          return false;
        }
        const chunk: Uint8Array = frame.slice(offset, Math.min(frame.length, offset + chunkSize));
        await kit.dataTransfer.writeData({ address: address, uuid: this.uuid, data: chunk.buffer });
        // Huawei FAQ recommends pacing writes to avoid queue congestion.
        await new Promise<void>((resolve: () => void) => { setTimeout(resolve, 10); });
      }
      return true; // Local write success, not a signed application-level delivery acknowledgement.
    } catch (error) {
      this.report('send', error as BusinessError);
      return false;
    } finally {
      this.sending = false;
    }
  }

  async broadcast(packet: string, excludeAddress: string = ''): Promise<number> {
    const addresses: string[] = [];
    this.peers.forEach((peer: NearLinkPeer) => {
      if (peer.connected && peer.address !== excludeAddress) {
        addresses.push(peer.address);
      }
    });
    let written: number = 0;
    for (const address of addresses) {
      if (await this.send(address, packet)) {
        written++;
      }
    }
    return written;
  }

  async stop(): Promise<void> {
    this.started = false;
    if (this.loaded) {
      try {
        const kit = await import('@kit.NearLinkKit');
        if (this.scanning) {
          await this.cleanup('stopScan', async (): Promise<void> => { await kit.scan.stopScan(); });
        }
        if (this.advertisingId >= 0) {
          await this.cleanup('stopAdvertising', async (): Promise<void> => {
            await kit.advertising.stopAdvertising(this.advertisingId);
          });
        }
        if (this.scanSubscribed) {
          await this.cleanup('unsubscribeScan', async (): Promise<void> => { kit.scan.off('deviceFound', this.onDiscovered); });
        }
        if (this.connectionSubscribed) {
          await this.cleanup('unsubscribeConnection', async (): Promise<void> => {
            kit.dataTransfer.off('connectionStateChanged', this.onConnection);
          });
        }
        if (this.readSubscribed) {
          await this.cleanup('unsubscribeRead', async (): Promise<void> => { kit.dataTransfer.off('readData', this.onRead); });
        }
        const addresses: string[] = Array.from(this.peers.keys());
        for (const address of addresses) {
          await this.cleanup('disconnect', async (): Promise<void> => {
            await kit.dataTransfer.disconnect({ address: address, uuid: this.uuid });
          });
        }
        if (this.portCreated) {
          await this.cleanup('destroyPort', async (): Promise<void> => { kit.dataTransfer.destroyPort(this.uuid); });
        }
      } catch (error) {
        this.report('stop', error as BusinessError);
      }
    }
    this.scanning = false;
    this.advertisingId = -1;
    this.portCreated = false;
    this.scanSubscribed = false;
    this.connectionSubscribed = false;
    this.readSubscribed = false;
    this.peers.clear();
    this.pendingConnections.clear();
    this.partials.clear();
    this.notify('stopped', 'NearLink relay stopped. Saved alerts remain available offline.');
  }

  private onDiscovered = (results: scan.ScanResults[]): void => {
    if (!this.started) {
      return;
    }
    for (const result of results) {
      if (this.peers.size >= this.maxPeers && !this.peers.has(result.address)) {
        continue;
      }
      const previous: NearLinkPeer | undefined = this.peers.get(result.address);
      const peer: NearLinkPeer = {
        address: result.address, name: result.deviceName, rssi: result.rssi,
        connectable: result.isConnectable, connected: previous?.connected ?? false,
        mtu: previous?.mtu ?? 0
      };
      this.peers.set(peer.address, peer);
      this.callbacks.onPeer(peer);
    }
  };

  private onConnection = (result: dataTransfer.ConnectionResult): void => {
    if (result.uuid.toUpperCase() !== this.uuid || !this.started) {
      return;
    }
    this.pendingConnections.delete(result.address);
    // API 24 constant.ConnectionState: 1=connected, 3=disconnected.
    if (result.state !== 1 && result.state !== 3) {
      return;
    }
    const previous: NearLinkPeer | undefined = this.peers.get(result.address);
    if (!previous && this.peers.size >= this.maxPeers) {
      this.callbacks.onError('connect', 0, 'Incoming peer exceeds the bounded peer table.');
      return;
    }
    const peer: NearLinkPeer = {
      address: result.address, name: previous?.name ?? 'Nearby relay', rssi: previous?.rssi ?? 127,
      connectable: true, connected: result.state === 1, mtu: result.mtu
    };
    this.peers.set(peer.address, peer);
    this.partials.delete(peer.address);
    this.callbacks.onPeer(peer);
    this.notify('ready', `${this.connectedCount()} confirmed NearLink channel(s).`);
  };

  private onRead = (result: dataTransfer.DataParams): void => {
    if (!this.started || result.uuid.toUpperCase() !== this.uuid || !this.peers.get(result.address)?.connected) {
      return;
    }
    const now: number = Date.now();
    let partial: PartialPacket | undefined = this.partials.get(result.address);
    if (!partial || now - partial.updatedAt > 15000) {
      partial = new PartialPacket();
    }
    // Allow two bounded frames to be coalesced; reject oversized input before allocation.
    if (result.data.byteLength + partial.bytes.length > 2 * (this.maxPacketBytes + 8)) {
      this.partials.delete(result.address);
      this.callbacks.onError('receive', 401, 'Oversized NearLink frame rejected.');
      return;
    }
    const combined: Uint8Array = new Uint8Array(partial.bytes.length + result.data.byteLength);
    combined.set(partial.bytes, 0);
    combined.set(new Uint8Array(result.data), partial.bytes.length);
    partial.bytes = combined;
    partial.updatedAt = now;
    try {
      while (partial.bytes.length >= 8) {
        const header: DataView = new DataView(partial.bytes.buffer);
        const length: number = header.getUint32(4);
        if (header.getUint32(0) !== this.frameMagic || length === 0 || length > this.maxPacketBytes) {
          this.partials.delete(result.address);
          this.callbacks.onError('receive', 401, 'Malformed NearLink frame rejected.');
          return;
        }
        if (partial.bytes.length < length + 8) {
          break;
        }
        const message: string = this.decoder.decodeToString(partial.bytes.slice(8, length + 8));
        partial.bytes = partial.bytes.slice(length + 8);
        this.callbacks.onMessage(result.address, message);
      }
      if (partial.bytes.length === 0) {
        this.partials.delete(result.address);
      } else {
        this.partials.set(result.address, partial);
      }
    } catch (error) {
      this.partials.delete(result.address);
      this.report('receive', error as BusinessError);
    }
  };

  private notify(state: string, message: string): NearLinkStatus {
    const status: NearLinkStatus = {
      state: state, message: message, supported: this.supported, connectedPeers: this.connectedCount()
    };
    this.callbacks.onStatus(status);
    return status;
  }

  private report(operation: string, error: BusinessError): void {
    this.callbacks.onError(operation, error.code ?? 0, error.message ?? 'NearLink operation failed.');
  }

  private async cleanup(operation: string, action: () => Promise<void>): Promise<void> {
    try {
      await action();
    } catch (error) {
      this.report(operation, error as BusinessError);
    }
  }
}
