import { RelayEngine, SignedAlertEnvelope, RelayResult, decodeEnvelope, encodeEnvelope } from '../model/AlertProtocol';
import { createDemoAlert } from '../model/DemoAlerts';
import { LocalStore } from '../model/LocalStore';

@Observed
export class AlertViewModel {
  title: string = 'Ready when it matters.';
  body: string = 'Verified warnings and your local map, kept on your phone.';
  area: string = 'Kraków · central district';
  verification: string = 'No alert loaded';
  received: boolean = false;
  busy: boolean = false;
  expiry: string = '';
  issueTime: string = '';
  lastReceiveStatus: string = 'No packet received';
  persistenceStatus: string = 'No saved alert';
  private engine: RelayEngine = new RelayEngine();
  private store: LocalStore;
  private packet: SignedAlertEnvelope | undefined = undefined;
  private pending: number = 0;
  private restoreTask: Promise<void> | undefined = undefined;
  private persistence: Promise<void> = Promise.resolve();
  private expiryTimer: number = -1;

  constructor(store: LocalStore) { this.store = store; }

  async restore(): Promise<void> {
    if (this.restoreTask === undefined) { this.restoreTask = this.restoreStored(); }
    await this.restoreTask;
  }

  private async restoreStored(): Promise<void> {
    try {
      const snapshot: string = await this.store.read('relay_cache_v1');
      if (snapshot.length > 0) { await this.engine.restore(snapshot); }
      const cached: string = await this.store.read('verified_alert');
      const alert: SignedAlertEnvelope | undefined = decodeEnvelope(cached);
      if (alert !== undefined) { await this.engine.ingest(alert); }
      this.selectCurrent();
      this.persistenceStatus = this.received ? 'Saved signatures re-verified' : 'No current saved alert';
    } catch (error) {
      this.persistenceStatus = 'Saved alerts could not be loaded';
      this.selectCurrent();
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
      if (result.status === 'accepted' || result.status === 'duplicate') { this.selectCurrent(); }
      if (result.status === 'accepted') { await this.persist(); }
      // Rejected input cannot overwrite the verification badge of authentic content.
      return result;
    } catch (error) {
      this.lastReceiveStatus = 'Packet processing could not complete';
      return { status: 'invalid', detail: 'Packet processing failed. Existing verified content retained.' };
    } finally {
      this.pending--;
      this.busy = this.pending > 0;
    }
  }

  /** Optional candidate keeps a concurrent relay tied to the packet just authenticated. */
  nextPacket(envelope?: SignedAlertEnvelope): string {
    this.refreshExpiry();
    const selected: SignedAlertEnvelope | undefined = envelope === undefined ? this.packet : envelope;
    if (selected === undefined) { return ''; }
    const next: SignedAlertEnvelope | undefined = this.engine.nextHop(selected);
    return next === undefined ? '' : encodeEnvelope(next);
  }

  refreshExpiry(): void {
    if (this.packet !== undefined && Date.now() >= this.packet.payload.expiresAt) {
      this.packet = undefined;
      this.received = false;
      this.verification = 'Expired · not relayed';
      this.title = 'No current verified alert';
      this.body = 'The cached exercise alert has expired. The offline map remains available.';
      this.expiry = '';
      this.issueTime = '';
      this.clearExpiryTimer();
    }
  }

  /** Call when the owning page is permanently disposed. Forwarding still checks expiry. */
  dispose(): void { this.clearExpiryTimer(); }

  private selectCurrent(): void {
    this.refreshExpiry();
    const alerts: SignedAlertEnvelope[] = this.engine.accepted();
    let latest: SignedAlertEnvelope | undefined = undefined;
    for (const alert of alerts) {
      if (latest === undefined || alert.payload.issuedAt > latest.payload.issuedAt ||
        (alert.payload.issuedAt === latest.payload.issuedAt && alert.payload.revision > latest.payload.revision)) {
        latest = alert;
      }
    }
    if (latest === undefined) { return; }
    this.packet = latest;
    this.title = latest.payload.title;
    this.body = latest.payload.body;
    this.area = latest.payload.area;
    this.issueTime = new Date(latest.payload.issuedAt).toLocaleString();
    this.expiry = new Date(latest.payload.expiresAt).toLocaleString();
    this.received = true;
    this.verification = 'Signature verified · demo authority';
    this.scheduleExpiry();
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
      } catch (error) { this.persistenceStatus = 'Verified in memory · local save failed'; }
    });
    await this.persistence;
  }

  private scheduleExpiry(): void {
    this.clearExpiryTimer();
    if (this.packet === undefined) { return; }
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