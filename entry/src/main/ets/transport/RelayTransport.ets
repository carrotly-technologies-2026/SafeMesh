import type { common } from '@kit.AbilityKit';

/** Link state shared by every transport (NearLink radio, its Oniro stub and the emulator link). */
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

/** A packet link. Alert authority, expiry, forwarding and receipts stay in the relay engine. */
export interface RelayTransport {
  probe(): Promise<NearLinkStatus>;
  start(context: common.UIAbilityContext): Promise<boolean>;
  discover(peerDeviceName: string): Promise<boolean>;
  connect(address: string): Promise<boolean>;
  send(address: string, packet: string): Promise<boolean>;
  stop(): Promise<void>;
}
