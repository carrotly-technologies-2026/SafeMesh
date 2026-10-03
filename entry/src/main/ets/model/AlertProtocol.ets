import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';
import { DEMO_KEY_ID, DEMO_PUBLIC_KEY_DER } from './DemoTrust';

export interface AlertPayload {
  version: number;
  keyId: string;
  alertId: string;
  revision: number;
  issuedAt: number;
  expiresAt: number;
  severity: string;
  area: string;
  title: string;
  body: string;
  shelterIds: string[];
  drill: boolean;
  maxHops: number;
}

export interface SignedAlertEnvelope {
  payload: AlertPayload;
  signature: string;
  hops: number;
}

export interface RelayResult {
  status: string;
  detail: string;
  envelope?: SignedAlertEnvelope;
}

export interface SignatureVerifier {
  verify(payload: AlertPayload, signature: string): Promise<boolean>;
}

const MAX_LIFETIME_MS: number = 72 * 60 * 60 * 1000;
const MAX_CLOCK_SKEW_MS: number = 5 * 60 * 1000;
const MAX_CACHE_SIZE: number = 128;
const MAX_IN_FLIGHT: number = 8;

/** A domain-separated, fixed-position array of strings. No JSON key-order dependency. */
export function canonicalPayload(payload: AlertPayload): string {
  const fields: string[] = [
    'SafeMesh.Alert.v1', payload.keyId, payload.alertId,
    String(payload.revision), String(payload.issuedAt), String(payload.expiresAt),
    payload.severity, payload.area, payload.title, payload.body,
    JSON.stringify(payload.shelterIds), payload.drill ? '1' : '0', String(payload.maxHops)
  ];
  return JSON.stringify(fields);
}

function textBounded(value: string, maximum: number): boolean {
  return typeof value === 'string' && value.length > 0 && value.length <= maximum;
}

function validPayload(payload: AlertPayload): boolean {
  if (payload === null || typeof payload !== 'object') {
    return false;
  }
  if (payload.version !== 1 || !textBounded(payload.keyId, 64) ||
    !textBounded(payload.alertId, 96) || !Number.isSafeInteger(payload.revision) ||
    payload.revision < 1 || !Number.isSafeInteger(payload.issuedAt) ||
    !Number.isSafeInteger(payload.expiresAt) || payload.issuedAt <= 0 ||
    payload.expiresAt <= payload.issuedAt ||
    payload.expiresAt - payload.issuedAt > MAX_LIFETIME_MS ||
    !textBounded(payload.area, 120) || !textBounded(payload.title, 160) ||
    !textBounded(payload.body, 1200) || typeof payload.drill !== 'boolean' ||
    !Number.isSafeInteger(payload.maxHops) || payload.maxHops < 1 || payload.maxHops > 8 ||
    !Array.isArray(payload.shelterIds) || payload.shelterIds.length > 12) {
    return false;
  }
  if (payload.severity !== 'critical' && payload.severity !== 'warning' && payload.severity !== 'info') {
    return false;
  }
  for (let index: number = 0; index < payload.shelterIds.length; index++) {
    if (!textBounded(payload.shelterIds[index], 64)) {
      return false;
    }
  }
  return new util.TextEncoder().encodeInto(canonicalPayload(payload)).length <= 4096;
}

export function copyEnvelope(source: SignedAlertEnvelope): SignedAlertEnvelope {
  const payload: AlertPayload = {
    version: source.payload.version,
    keyId: source.payload.keyId,
    alertId: source.payload.alertId,
    revision: source.payload.revision,
    issuedAt: source.payload.issuedAt,
    expiresAt: source.payload.expiresAt,
    severity: source.payload.severity,
    area: source.payload.area,
    title: source.payload.title,
    body: source.payload.body,
    shelterIds: source.payload.shelterIds.slice(),
    drill: source.payload.drill,
    maxHops: source.payload.maxHops
  };
  return { payload: payload, signature: source.signature, hops: source.hops };
}

function validEnvelope(envelope: SignedAlertEnvelope): boolean {
  return envelope !== null && typeof envelope === 'object' && validPayload(envelope.payload) &&
    textBounded(envelope.signature, 120) && /^[A-Za-z0-9+/]+={0,2}$/.test(envelope.signature) &&
    Number.isSafeInteger(envelope.hops) && envelope.hops >= 0;
}

/** Bounded parsing only; decoding never implies authentication or permission to forward. */
export function decodeEnvelope(packet: string): SignedAlertEnvelope | undefined {
  if (typeof packet !== 'string' || packet.length === 0 || packet.length > 8192 ||
    new util.TextEncoder().encodeInto(packet).length > 8192) {
    return undefined;
  }
  try {
    const envelope: SignedAlertEnvelope = JSON.parse(packet) as SignedAlertEnvelope;
    return validEnvelope(envelope) ? copyEnvelope(envelope) : undefined;
  } catch (error) {
    return undefined;
  }
}

export function encodeEnvelope(envelope: SignedAlertEnvelope): string {
  if (!validEnvelope(envelope)) {
    throw new Error('Cannot encode malformed alert');
  }
  return JSON.stringify(copyEnvelope(envelope));
}

/** Verifies only the pinned exercise authority. It can never authorize a live alert. */
export class NativeAlertVerifier implements SignatureVerifier {
  async verify(payload: AlertPayload, signature: string): Promise<boolean> {
    if (payload.keyId !== DEMO_KEY_ID || !payload.drill) {
      return false;
    }
    const base64: util.Base64Helper = new util.Base64Helper();
    const publicKeyBlob: cryptoFramework.DataBlob = { data: base64.decodeSync(DEMO_PUBLIC_KEY_DER) };
    const keyPair: cryptoFramework.KeyPair =
      await cryptoFramework.createAsyKeyGenerator('ECC256').convertKey(publicKeyBlob, null);
    const verifier: cryptoFramework.Verify = cryptoFramework.createVerify('ECC256|SHA256');
    await verifier.init(keyPair.pubKey);
    const input: cryptoFramework.DataBlob = {
      data: new util.TextEncoder().encodeInto(canonicalPayload(payload))
    };
    const signatureBlob: cryptoFramework.DataBlob = { data: base64.decodeSync(signature) };
    return verifier.verify(input, signatureBlob);
  }
}

/** Store-and-forward policy shared by every transport. No location or identity tracking. */
export class RelayEngine {
  private verifier: SignatureVerifier;
  private cache: Map<string, SignedAlertEnvelope> = new Map<string, SignedAlertEnvelope>();
  private pending: number = 0;

  constructor(verifier?: SignatureVerifier) {
    this.verifier = verifier === undefined ? new NativeAlertVerifier() : verifier;
  }

  async ingest(envelope: SignedAlertEnvelope, now: number = Date.now()): Promise<RelayResult> {
    if (!validEnvelope(envelope) || !Number.isSafeInteger(now) || now <= 0) {
      return { status: 'invalid', detail: 'Malformed or oversized alert. Not stored or forwarded.' };
    }
    const candidate: SignedAlertEnvelope = copyEnvelope(envelope);
    if (candidate.payload.keyId !== DEMO_KEY_ID || !candidate.payload.drill) {
      return { status: 'untrusted', detail: 'No trusted authority key for this alert. Demo keys authorize drills only.' };
    }
    if (candidate.hops > candidate.payload.maxHops) {
      return { status: 'hop_limit', detail: 'Relay hop limit exceeded.' };
    }
    if (candidate.payload.expiresAt <= now) {
      return { status: 'expired', detail: 'Alert has expired. Not stored or forwarded.' };
    }
    if (candidate.payload.issuedAt > now + MAX_CLOCK_SKEW_MS) {
      return { status: 'future', detail: 'Alert is from the future. Check the device clock.' };
    }
    if (this.pending >= MAX_IN_FLIGHT) {
      return { status: 'busy', detail: 'Verification queue full. Retry later.' };
    }
    this.pending++;
    let authentic: boolean = false;
    try {
      authentic = await this.verifier.verify(candidate.payload, candidate.signature);
    } catch (error) {
      authentic = false;
    } finally {
      this.pending--;
    }
    if (!authentic) {
      return { status: 'invalid', detail: 'Signature rejected. Message content was changed or signature is invalid.' };
    }
    this.prune(now);
    const key: string = this.cacheKey(candidate.payload);
    const previous: SignedAlertEnvelope | undefined = this.cache.get(key);
    if (previous !== undefined && previous.payload.revision >= candidate.payload.revision) {
      return { status: 'duplicate', detail: 'Already received this alert revision. Replay suppressed.' };
    }
    if (previous !== undefined && (previous.payload.issuedAt !== candidate.payload.issuedAt ||
      previous.payload.expiresAt !== candidate.payload.expiresAt)) {
      return {
        status: 'invalid',
        detail: 'Revisions must retain the original validity window. A changed window needs a new alert ID.'
      };
    }
    if (previous === undefined && this.cache.size >= MAX_CACHE_SIZE) {
      return { status: 'capacity', detail: 'Relay cache full. Valid alerts retained until expiry.' };
    }
    // No await between replay check and insertion: simultaneous arrivals cannot both win.
    this.cache.set(key, candidate);
    return {
      status: 'accepted',
      detail: 'Demo-authority signature verified on this device. Stored for offline relay.',
      envelope: copyEnvelope(candidate)
    };
  }

  accepted(now: number = Date.now()): SignedAlertEnvelope[] {
    this.prune(now);
    const result: SignedAlertEnvelope[] = [];
    this.cache.forEach((envelope: SignedAlertEnvelope) => {
      result.push(copyEnvelope(envelope));
    });
    return result;
  }

  /** Only previously verified content can enter the outbound queue. Hops are advisory. */
  nextHop(envelope: SignedAlertEnvelope, now: number = Date.now()): SignedAlertEnvelope | undefined {
    this.prune(now);
    const stored: SignedAlertEnvelope | undefined = this.cache.get(this.cacheKey(envelope.payload));
    if (stored === undefined || stored.signature !== envelope.signature ||
      canonicalPayload(stored.payload) !== canonicalPayload(envelope.payload) ||
      !Number.isSafeInteger(envelope.hops) || envelope.hops < 0 ||
      envelope.hops >= envelope.payload.maxHops) {
      return undefined;
    }
    const result: SignedAlertEnvelope = copyEnvelope(envelope);
    result.hops++;
    return result;
  }

  /** Host may persist this locally; restore re-verifies every signature before use. */
  snapshot(now: number = Date.now()): string {
    return JSON.stringify(this.accepted(now));
  }

  async restore(serialized: string, now: number = Date.now()): Promise<number> {
    if (serialized.length > MAX_CACHE_SIZE * 8192) {
      return 0;
    }
    let restored: number = 0;
    try {
      const entries: SignedAlertEnvelope[] = JSON.parse(serialized) as SignedAlertEnvelope[];
      if (!Array.isArray(entries) || entries.length > MAX_CACHE_SIZE) {
        return 0;
      }
      for (let index: number = 0; index < entries.length; index++) {
        const result: RelayResult = await this.ingest(entries[index], now);
        if (result.status === 'accepted') {
          restored++;
        }
      }
    } catch (error) {
      return restored;
    }
    return restored;
  }

  /** Explicit exercise reset, never automatically called when receiving a replay. */
  resetDemo(): void {
    this.cache.clear();
  }

  private cacheKey(payload: AlertPayload): string {
    return JSON.stringify([payload.keyId, payload.alertId]);
  }

  private prune(now: number): void {
    this.cache.forEach((envelope: SignedAlertEnvelope, key: string) => {
      if (envelope.payload.expiresAt <= now) {
        this.cache.delete(key);
      }
    });
  }
}
