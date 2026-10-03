import { RelayEngine, SignedAlertEnvelope, RelayResult, decodeEnvelope, encodeEnvelope } from '../model/AlertProtocol';
import { createDemoAlert } from '../model/DemoAlerts';
import { LocalStore } from '../model/LocalStore';

interface InboxMetadata {
  identity: string;
  read: boolean;
  receivedAt: number;
  sourcePeer: string;
  hops: number;
}

interface StoredInbox {
  version: number;
  alerts: SignedAlertEnvelope[];
  metadata: InboxMetadata[];
}

/** Detached display snapshot. Receipt time, sourcePeer and hops are unsigned local metadata. */
export class AlertInboxItem {
  readonly identity: string;
  readonly keyId: string;
  readonly alertId: string;
  readonly revision: number;
  readonly title: string;
  readonly body: string;
  readonly area: string;
  readonly severity: string;
  readonly drill: boolean;
  readonly issuedAt: number;
  readonly expiresAt: number;
  readonly contentLanguage: string;
  readonly languageFallback: boolean;
  readonly unread: boolean;
  readonly receivedAt: number;
  readonly sourcePeer: string;
  readonly hops: number;

  constructor(envelope: SignedAlertEnvelope, metadata: InboxMetadata, language: string) {
    const payload = envelope.payload;
    this.identity = metadata.identity;
    this.keyId = payload.keyId; this.alertId = payload.alertId; this.revision = payload.revision;
    this.title = payload.title; this.body = payload.body; this.area = payload.area;
    this.severity = payload.severity; this.drill = payload.drill;
    this.issuedAt = payload.issuedAt; this.expiresAt = payload.expiresAt;
    this.contentLanguage = payload.language === undefined ? 'und' : payload.language;
    if (payload.version === 2 && payload.translations !== undefined) {
      for (const translation of payload.translations) {
        if (translation.language === language) {
          this.title = translation.title; this.body = translation.body; this.area = translation.area;
          this.contentLanguage = translation.language;
        }
      }
    }
    this.languageFallback = this.contentLanguage !== language;
    this.unread = !metadata.read; this.receivedAt = metadata.receivedAt;
    this.sourcePeer = metadata.sourcePeer; this.hops = metadata.hops;
  }
}

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
  inbox: AlertInboxItem[] = [];
  unreadCount: number = 0;
  selectedIdentity: string = '';
  arrivalIdentity: string = '';
  arrivalSequence: number = 0;
  private engine: RelayEngine = new RelayEngine();
  private metadata: Map<string, InboxMetadata> = new Map<string, InboxMetadata>();
  private store: LocalStore;
  private packet: SignedAlertEnvelope | undefined = undefined;
  private pending: number = 0;
  private restoreTask: Promise<void> | undefined = undefined;
  private restored: boolean = false;
  private persistence: Promise<void> = Promise.resolve();
  private expiryTimer: number = -1;
  private language: string = 'pl';
  private active: boolean = true;
  private nextExpiryAt: number = 0;

  constructor(store: LocalStore) { this.store = store; }

  /** Select only issuer-signed content; never translate or mutate the stored payload. */
  setLanguage(language: string): void {
    if (language !== 'pl' && language !== 'en') { return; }
    this.language = language;
    this.refreshExpiry();
    this.displayContent();
    this.synchronizeInbox(this.engine.accepted());
  }

  /** Resolves from the verified cache, never from a caller-mutated display snapshot. */
  getMessage(identity: string): AlertInboxItem | undefined {
    if (!this.restored) { return undefined; }
    const envelope: SignedAlertEnvelope | undefined = this.engine.accepted().find(
      (candidate: SignedAlertEnvelope) => this.identityOf(candidate) === identity);
    return envelope === undefined ? undefined : this.itemFor(envelope);
  }

  selectedMessage(): AlertInboxItem | undefined { return this.getMessage(this.selectedIdentity); }

  selectMessage(identity: string): boolean {
    this.refreshExpiry();
    if (this.getMessage(identity) === undefined) { return false; }
    this.selectedIdentity = identity;
    return true;
  }

  /** True means a valid message was opened; persistenceState reports durable-write failure. */
  async openMessage(identity: string): Promise<boolean> {
    await this.restore();
    if (!this.selectMessage(identity)) { return false; }
    return this.markRead(identity);
  }

  async markRead(identity: string): Promise<boolean> {
    await this.restore();
    if (this.getMessage(identity) === undefined) { return false; }
    const metadata: InboxMetadata | undefined = this.metadata.get(identity);
    if (metadata === undefined) { return false; }
    if (this.arrivalIdentity === identity) { this.dismissArrival(); }
    if (metadata.read) {
      // A failed earlier read-state commit is retryable without toggling unread.
      if (this.persistenceState === 'save_failed') { await this.persist(); }
      return true;
    }
    metadata.read = true;
    this.synchronizeInbox(this.engine.accepted());
    await this.persist();
    return true;
  }

  dismissArrival(): void { this.arrivalIdentity = ''; }

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
      const savedInbox: string = await this.store.read('inbox_state_v1');
      let records: InboxMetadata[] = [];
      if (savedInbox.length > 0) {
        if (savedInbox.length > 128 * 8192) { throw new Error('Oversized saved inbox'); }
        const stored: StoredInbox = JSON.parse(savedInbox) as StoredInbox;
        if (stored === null || typeof stored !== 'object' || stored.version !== 1 ||
          !Array.isArray(stored.alerts) || stored.alerts.length > 128 ||
          !Array.isArray(stored.metadata) || stored.metadata.length > 128) {
          throw new Error('Invalid saved inbox');
        }
        await restoredEngine.restore(JSON.stringify(stored.alerts));
        records = stored.metadata;
      } else {
        const snapshot: string = await this.store.read('relay_cache_v1');
        if (snapshot.length > 0) { await restoredEngine.restore(snapshot); }
        const cached: string = await this.store.read('verified_alert');
        const alert: SignedAlertEnvelope | undefined = decodeEnvelope(cached);
        if (alert !== undefined) { await restoredEngine.ingest(alert); }
      }
      this.engine = restoredEngine;
      this.metadata.clear();
      const validIdentities: Set<string> = new Set<string>();
      this.engine.accepted().forEach((envelope: SignedAlertEnvelope) => { validIdentities.add(this.identityOf(envelope)); });
      for (const record of records) {
        if (this.validMetadata(record) && validIdentities.has(record.identity) && !this.metadata.has(record.identity)) {
          this.metadata.set(record.identity, {
            identity: record.identity, read: record.read, receivedAt: record.receivedAt,
            sourcePeer: record.sourcePeer, hops: record.hops
          });
        }
      }
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

  async loadDrill(): Promise<void> { await this.receive(createDemoAlert(), 'local_test'); }

  async receive(envelope: SignedAlertEnvelope, sourcePeer: string = ''): Promise<RelayResult> {
    this.pending++;
    this.busy = true;
    try {
      // Restore replay history before the first network packet can enter the engine.
      await this.restore();
      this.refreshExpiry();
      const result: RelayResult = await this.engine.ingest(envelope);
      this.lastReceiveStatus = result.status + ': ' + result.detail;
      this.lastReceiveState = result.status;
      if (result.status === 'accepted' && result.envelope !== undefined && result.envelope.payload.expiresAt > Date.now()) {
        const identity: string = this.identityOf(result.envelope);
        this.metadata.set(identity, {
          identity: identity, read: false, receivedAt: Date.now(),
          sourcePeer: typeof sourcePeer === 'string' ? sourcePeer.replace(/[\u0000-\u001f\u007f]/g, '').slice(0, 96) : '',
          hops: result.envelope.hops
        });
      }
      if (result.status === 'accepted' || result.status === 'duplicate') { this.selectCurrent(); }
      if (result.status === 'accepted' && result.envelope !== undefined) {
        const identity: string = this.identityOf(result.envelope);
        if (this.metadata.has(identity)) {
          this.arrivalIdentity = identity;
          this.arrivalSequence++;
        }
        await this.persist();
      } else if (result.status === 'duplicate' && this.persistenceState === 'save_failed') {
        // Idempotent publisher/network retry can repair storage; it cannot
        // create a new arrival or overwrite the first local receipt metadata.
        await this.persist();
      }
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
    if (this.nextExpiryAt > 0 && Date.now() >= this.nextExpiryAt) {
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
    this.synchronizeInbox(alerts);
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
    this.currentIdentity = this.identityOf(latest);
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
    const alerts: SignedAlertEnvelope[] = this.engine.accepted();
    const snapshot: string = JSON.stringify(alerts);
    const current: string = this.packet === undefined ? '' : encodeEnvelope(this.packet);
    const metadata: InboxMetadata[] = [];
    for (const alert of alerts) {
      const record: InboxMetadata = this.metadataFor(alert);
      metadata.push({ identity: record.identity, read: record.read, receivedAt: record.receivedAt,
        sourcePeer: record.sourcePeer, hops: record.hops });
    }
    const stored: StoredInbox = { version: 1, alerts: alerts, metadata: metadata };
    const inboxSnapshot: string = JSON.stringify(stored);
    // Serialize writes so a slower earlier flush cannot overwrite newer accepted state.
    this.persistence = this.persistence.then(async (): Promise<void> => {
      try {
        // Publish the authoritative pair first; failed first commits cannot
        // leave a newer legacy cache with missing read/receipt metadata.
        await this.store.write('inbox_state_v1', inboxSnapshot);
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
    if (!this.active || this.nextExpiryAt <= 0) { return; }
    const delay: number = Math.max(1, Math.min(60000, this.nextExpiryAt - Date.now()));
    this.expiryTimer = setTimeout((): void => {
      this.expiryTimer = -1;
      this.refreshExpiry();
      if (this.packet !== undefined) { this.scheduleExpiry(); }
    }, delay);
  }

  private clearExpiryTimer(): void {
    if (this.expiryTimer >= 0) { clearTimeout(this.expiryTimer); this.expiryTimer = -1; }
  }

  private identityOf(envelope: SignedAlertEnvelope): string {
    return JSON.stringify([envelope.payload.keyId, envelope.payload.alertId,
      String(envelope.payload.revision), String(envelope.payload.issuedAt)]);
  }

  private metadataFor(envelope: SignedAlertEnvelope): InboxMetadata {
    const identity: string = this.identityOf(envelope);
    let metadata: InboxMetadata | undefined = this.metadata.get(identity);
    if (metadata === undefined) {
      // Legacy restored content is already known, with no invented receipt time.
      metadata = { identity: identity, read: true, receivedAt: 0, sourcePeer: '', hops: envelope.hops };
      this.metadata.set(identity, metadata);
    }
    return metadata;
  }

  private itemFor(envelope: SignedAlertEnvelope): AlertInboxItem {
    return new AlertInboxItem(envelope, this.metadataFor(envelope), this.language);
  }

  private synchronizeInbox(alerts: SignedAlertEnvelope[]): void {
    const identities: Set<string> = new Set<string>();
    const items: AlertInboxItem[] = [];
    let nextExpiry: number = 0;
    let unread: number = 0;
    for (const alert of alerts) {
      const item: AlertInboxItem = this.itemFor(alert);
      items.push(item); identities.add(item.identity);
      if (item.unread) { unread++; }
      if (nextExpiry === 0 || item.expiresAt < nextExpiry) { nextExpiry = item.expiresAt; }
    }
    this.metadata.forEach((_record: InboxMetadata, identity: string) => {
      if (!identities.has(identity)) { this.metadata.delete(identity); }
    });
    items.sort((left: AlertInboxItem, right: AlertInboxItem): number => {
      return right.receivedAt - left.receivedAt || right.issuedAt - left.issuedAt ||
        right.revision - left.revision || left.identity.localeCompare(right.identity);
    });
    this.inbox = items;
    this.unreadCount = unread;
    this.nextExpiryAt = nextExpiry;
    if (!identities.has(this.arrivalIdentity)) { this.arrivalIdentity = ''; }
  }

  private validMetadata(record: InboxMetadata): boolean {
    return record !== null && typeof record === 'object' && typeof record.identity === 'string' &&
      record.identity.length > 0 && record.identity.length <= 1024 && typeof record.read === 'boolean' &&
      Number.isSafeInteger(record.receivedAt) && record.receivedAt >= 0 && record.receivedAt <= 8640000000000000 &&
      typeof record.sourcePeer === 'string' && record.sourcePeer.length <= 96 &&
      !/[\u0000-\u001f\u007f]/.test(record.sourcePeer) && Number.isSafeInteger(record.hops) && record.hops >= 0 && record.hops <= 8;
  }
}
