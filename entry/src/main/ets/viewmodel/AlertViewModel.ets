import { RelayEngine, SignedAlertEnvelope, RelayResult, decodeEnvelope, encodeEnvelope } from '../model/AlertProtocol';
import { createDemoAlert } from '../model/DemoAlerts';
import { LocalStore } from '../model/LocalStore';

@Observed
export class AlertViewModel {
  title: string = '';
  body: string = '';
  area: string = '';
  verification: string = 'No alert loaded';
  verificationState: string = 'none';
  received: boolean = false;
  busy: boolean = false;
  expiry: string = '';
  issueTime: string = '';
  issuedAt: number = 0;
  expiresAt: number = 0;
  currentIdentity: string = '';
  contentLanguage: string = 'und';
  languageFallback: boolean = false;
  lastReceiveStatus: string = 'No packet received';
  lastReceiveState: string = 'none';
  persistenceStatus: string = 'No saved alert';
  persistenceState: string = 'none';
  private engine: RelayEngine = new RelayEngine();
  private store: LocalStore;
  private packet: SignedAlertEnvelope | undefined = undefined;
  private pending: number = 0;
  private restoreTask: Promise<void> | undefined = undefined;
  private restored: boolean = false;
  private persistence: Promise<void> = Promise.resolve();
  private expiryTimer: number = -1;
  private language: string = 'pl';
  private active: boolean = true;

  constructor(store: LocalStore) { this.store = store; }

  /** Select only issuer-signed content; never translate or mutate the stored payload. */
  setLanguage(language: string): void {
    if (language !== 'pl' && language !== 'en') { return; }
    this.language = language;
    this.refreshExpiry();
    this.displayContent();
  }

  async restore(): Promise<void> {
    if (this.restoreTask === undefined) { this.restoreTask = this.restoreStored(); }
    const task: Promise<void> = this.restoreTask;
    try { await task; } catch (error) {
      if (this.restoreTask === task) { this.restoreTask = undefined; }
      throw new Error('Saved alert state is unavailable; relay remains paused');
    }
  }

  private async restoreStored(): Promise<void> {
    try {
      const restoredEngine: RelayEngine = new RelayEngine();
      const snapshot: string = await this.store.read('relay_cache_v1');
      if (snapshot.length > 0) { await restoredEngine.restore(snapshot); }
      const cached: string = await this.store.read('verified_alert');
      const alert: SignedAlertEnvelope | undefined = decodeEnvelope(cached);
      if (alert !== undefined) { await restoredEngine.ingest(alert); }
      this.engine = restoredEngine;
      this.restored = true;
      this.selectCurrent();
      this.persistenceStatus = this.received ? 'Saved signatures re-verified' : 'No current saved alert';
      this.persistenceState = this.received ? 'reverified' : 'none';
    } catch (error) {
      console.error('SAFEMESH_RESTORE_ERROR ' + String(error));
      this.persistenceStatus = 'Saved alerts could not be loaded';
      this.persistenceState = 'load_failed';
      this.restored = false;
      throw new Error('Cannot restore verified relay history');
    }
  }

  async loadDrill(): Promise<void> { await this.receive(createDemoAlert()); }

  async receive(envelope: SignedAlertEnvelope): Promise<RelayResult> {
    this.pending++;
    this.busy = true;
    try {
      // Restore replay history before the first network packet can enter the engine.
      await this.restore();
      this.refreshExpiry();
      const result: RelayResult = await this.engine.ingest(envelope);
      this.lastReceiveStatus = result.status + ': ' + result.detail;
      this.lastReceiveState = result.status;
      if (result.status === 'accepted' || result.status === 'duplicate') { this.selectCurrent(); }
      if (result.status === 'accepted') { await this.persist(); }
      // Rejected input cannot overwrite the verification badge of authentic content.
      return result;
    } catch (error) {
      this.lastReceiveStatus = 'Packet processing could not complete';
      this.lastReceiveState = 'processing_failed';
      return { status: 'invalid', detail: 'Packet processing failed. Existing verified content retained.' };
    } finally {
      this.pending--;
      this.busy = this.pending > 0;
    }
  }

  /** Optional candidate keeps a concurrent relay tied to the packet just authenticated. */
  nextPacket(envelope?: SignedAlertEnvelope): string {
    if (!this.restored) { return ''; }
    this.refreshExpiry();
    const selected: SignedAlertEnvelope | undefined = envelope === undefined ? this.packet : envelope;
    if (selected === undefined) { return ''; }
    const next: SignedAlertEnvelope | undefined = this.engine.nextHop(selected);
    return next === undefined ? '' : encodeEnvelope(next);
  }

  /** Reconnection synchronizes every current verified alert, not just the visible one. */
  allAccepted(): SignedAlertEnvelope[] {
    if (!this.restored) { return []; }
    this.refreshExpiry();
    return this.engine.accepted();
  }

  refreshExpiry(): void {
    if (this.packet !== undefined && Date.now() >= this.packet.payload.expiresAt) {
      // Selection prunes expiry and may reveal an older, still-current alert.
      // It never calls refreshExpiry, so this also works from the timer callback.
      this.selectCurrent();
    }
  }

  /** Stop UI timers while hidden/disposed; a late restore cannot restart them. */
  dispose(): void { this.active = false; this.clearExpiryTimer(); }

  /** Foreground refresh also handles expiry that happened while timers were paused. */
  resume(): void { this.active = true; this.selectCurrent(); }

  private selectCurrent(): void {
    const now: number = Date.now();
    const expired: boolean = this.packet !== undefined && this.packet.payload.expiresAt <= now;
    const alerts: SignedAlertEnvelope[] = this.engine.accepted(now);
    let latest: SignedAlertEnvelope | undefined = undefined;
    for (const alert of alerts) {
      if (latest === undefined || alert.payload.issuedAt > latest.payload.issuedAt ||
        (alert.payload.issuedAt === latest.payload.issuedAt && alert.payload.revision > latest.payload.revision)) {
        latest = alert;
      }
    }
    if (latest === undefined) {
      this.packet = undefined;
      this.received = false;
      this.title = '';
      this.body = '';
      this.area = '';
      this.expiry = '';
      this.issueTime = '';
      this.issuedAt = 0;
      this.expiresAt = 0;
      this.currentIdentity = '';
      this.contentLanguage = 'und';
      this.languageFallback = false;
      if (expired || this.verificationState === 'expired') {
        this.verification = 'Expired · not relayed';
        this.verificationState = 'expired';
      } else {
        this.verification = 'No alert loaded';
        this.verificationState = 'none';
      }
      this.clearExpiryTimer();
      return;
    }
    this.packet = latest;
    this.displayContent();
    this.issuedAt = latest.payload.issuedAt;
    this.expiresAt = latest.payload.expiresAt;
    this.currentIdentity = JSON.stringify([
      latest.payload.keyId, latest.payload.alertId, String(latest.payload.revision), String(latest.payload.issuedAt)
    ]);
    this.issueTime = new Date(latest.payload.issuedAt).toISOString().slice(0, 16).replace('T', ' ') + ' UTC';
    this.expiry = new Date(latest.payload.expiresAt).toISOString().slice(0, 16).replace('T', ' ') + ' UTC';
    this.received = true;
    this.verification = 'Signature verified · demo authority';
    this.verificationState = 'verified';
    this.scheduleExpiry();
  }

  private displayContent(): void {
    const packet: SignedAlertEnvelope | undefined = this.packet;
    if (packet === undefined) { return; }
    this.title = packet.payload.title;
    this.body = packet.payload.body;
    this.area = packet.payload.area;
    this.contentLanguage = packet.payload.language === undefined ? 'und' : packet.payload.language;
    this.languageFallback = this.contentLanguage !== this.language;
    if (packet.payload.version !== 2 || packet.payload.translations === undefined) { return; }
    for (const translation of packet.payload.translations) {
      if (translation.language === this.language) {
        this.title = translation.title;
        this.body = translation.body;
        this.area = translation.area;
        this.contentLanguage = translation.language;
        this.languageFallback = false;
        return;
      }
    }
  }

  private async persist(): Promise<void> {
    const snapshot: string = this.engine.snapshot();
    const current: string = this.packet === undefined ? '' : encodeEnvelope(this.packet);
    // Serialize writes so a slower earlier flush cannot overwrite newer accepted state.
    this.persistence = this.persistence.then(async (): Promise<void> => {
      try {
        await this.store.write('relay_cache_v1', snapshot);
        await this.store.write('verified_alert', current);
        this.persistenceStatus = 'Saved on this phone';
        this.persistenceState = 'saved';
      } catch (error) {
        this.persistenceStatus = 'Verified in memory · local save failed';
        this.persistenceState = 'save_failed';
      }
    });
    await this.persistence;
  }

  private scheduleExpiry(): void {
    this.clearExpiryTimer();
    if (!this.active || this.packet === undefined) { return; }
    const delay: number = Math.max(1, Math.min(60000, this.packet.payload.expiresAt - Date.now()));
    this.expiryTimer = setTimeout((): void => {
      this.expiryTimer = -1;
      this.refreshExpiry();
      if (this.packet !== undefined) { this.scheduleExpiry(); }
    }, delay);
  }

  private clearExpiryTimer(): void {
    if (this.expiryTimer >= 0) { clearTimeout(this.expiryTimer); this.expiryTimer = -1; }
  }
}
