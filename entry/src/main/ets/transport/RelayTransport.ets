import type { common } from '@kit.AbilityKit';
import type { NearLinkStatus } from './NearLinkTransport';

/** A packet link. Alert authority, expiry, forwarding and receipts stay in the relay engine. */
export interface RelayTransport {
  probe(): Promise<NearLinkStatus>;
  start(context: common.UIAbilityContext): Promise<boolean>;
  discover(peerDeviceName: string): Promise<boolean>;
  connect(address: string): Promise<boolean>;
  send(address: string, packet: string): Promise<boolean>;
  stop(): Promise<void>;
}
