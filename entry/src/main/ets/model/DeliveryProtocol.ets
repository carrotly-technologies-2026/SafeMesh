import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';
import { SignedAlertEnvelope, decodeEnvelope, copyEnvelope } from './AlertProtocol';

export interface DeliveryData {
  type: string;
  deliveryId: string;
  envelope: SignedAlertEnvelope;
}

export interface DeliveryAck {
  type: string;
  deliveryId: string;
  keyId: string;
  alertId: string;
  revision: number;
}

function nonceValid(value: string): boolean {
  return typeof value === 'string' && /^[a-f0-9]{32}$/.test(value);
}

function bounded(value: string, maximum: number): boolean {
  return typeof value === 'string' && value.length > 0 && value.length <= maximum;
}

/** Native CSPRNG, 128-bit request token. An ACK is a peer receipt, not an authority signature. */
export function createDeliveryId(): string {
  const bytes: Uint8Array = cryptoFramework.createRandom().generateRandomSync(16).data;
  let value: string = '';
  for (let index: number = 0; index < bytes.length; index++) {
    value += bytes[index].toString(16).padStart(2, '0');
  }
  return value;
}

export function decodeDataPacket(packet: string): DeliveryData | undefined {
  if (typeof packet !== 'string' || packet.length > 9216 ||
    new util.TextEncoder().encodeInto(packet).length > 9216) { return undefined; }
  try {
    const candidate: DeliveryData = JSON.parse(packet) as DeliveryData;
    if (candidate === null || typeof candidate !== 'object' || candidate.type !== 'safemesh.data.v1' ||
      !nonceValid(candidate.deliveryId)) { return undefined; }
    const envelope: SignedAlertEnvelope | undefined = decodeEnvelope(JSON.stringify(candidate.envelope));
    if (envelope === undefined) { return undefined; }
    return { type: candidate.type, deliveryId: candidate.deliveryId, envelope: envelope };
  } catch (error) { return undefined; }
}

export function encodeDataPacket(deliveryId: string, envelope: SignedAlertEnvelope): string {
  if (!nonceValid(deliveryId)) { throw new Error('Invalid delivery token'); }
  const packet: DeliveryData = { type: 'safemesh.data.v1', deliveryId: deliveryId, envelope: copyEnvelope(envelope) };
  return JSON.stringify(packet);
}

export function makeAcknowledgement(data: DeliveryData): DeliveryAck {
  return {
    type: 'safemesh.ack.v1', deliveryId: data.deliveryId, keyId: data.envelope.payload.keyId,
    alertId: data.envelope.payload.alertId, revision: data.envelope.payload.revision
  };
}

export function decodeAcknowledgement(packet: string): DeliveryAck | undefined {
  if (typeof packet !== 'string' || packet.length > 1024) { return undefined; }
  try {
    const ack: DeliveryAck = JSON.parse(packet) as DeliveryAck;
    if (ack === null || typeof ack !== 'object' || ack.type !== 'safemesh.ack.v1' ||
      !nonceValid(ack.deliveryId) || !bounded(ack.keyId, 64) || !bounded(ack.alertId, 96) ||
      !Number.isSafeInteger(ack.revision) || ack.revision < 1) { return undefined; }
    return {
      type: ack.type, deliveryId: ack.deliveryId, keyId: ack.keyId,
      alertId: ack.alertId, revision: ack.revision
    };
  } catch (error) { return undefined; }
}
