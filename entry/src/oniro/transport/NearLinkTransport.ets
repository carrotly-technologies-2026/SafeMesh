import { common } from '@kit.AbilityKit';
import type { NearLinkCallbacks, NearLinkStatus } from '../../main/ets/transport/RelayTransport';

/** OpenHarmony (Oniro) build: NearLink Kit is HarmonyOS-only, so the radio is always unavailable. */
export class NearLinkTransport {
  private callbacks: NearLinkCallbacks;

  constructor(callbacks: NearLinkCallbacks) {
    this.callbacks = callbacks;
  }

  isSupported(): boolean {
    return false;
  }

  connectedCount(): number {
    return 0;
  }

  async probe(): Promise<NearLinkStatus> {
    const status: NearLinkStatus = {
      state: 'unsupported',
      message: 'NearLink is not available on OpenHarmony. Use the local emulator transport.',
      supported: false,
      connectedPeers: 0
    };
    this.callbacks.onStatus(status);
    return status;
  }

  async start(context: common.UIAbilityContext): Promise<boolean> {
    await this.probe();
    return false;
  }

  async discover(peerDeviceName: string): Promise<boolean> {
    return false;
  }

  async connect(address: string): Promise<boolean> {
    return false;
  }

  async send(address: string, packet: string): Promise<boolean> {
    return false;
  }

  async broadcast(packet: string, excludeAddress: string = ''): Promise<number> {
    return 0;
  }

  async stop(): Promise<void> {
  }
}
