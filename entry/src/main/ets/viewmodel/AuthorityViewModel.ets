import { AuthorityClient, AuthorityDraft } from '../model/AuthorityClient';
import { RelayResult, SignedAlertEnvelope } from '../model/AlertProtocol';
import { AlertViewModel } from './AlertViewModel';
import { RelayViewModel } from './RelayViewModel';

/** The issuing station authorizes a draft; recipient devices only verify and forward. */
@Observed
export class AuthorityViewModel {
  tokenInput: string = '';
  authenticated: boolean = false;
  busy: boolean = false;
  state: string = 'signed_out';
  draftTitle: string = '';
  draftBody: string = '';
  draftArea: string = 'Kraków centrum';
  draftLanguage: string = 'pl';
  severity: string = 'warning';
  validForMinutes: number = 60;
  lastPublishedIdentity: string = '';
  lastPublishedTitle: string = '';
  private client: AuthorityClient;
  private alerts: AlertViewModel;
  private relay: RelayViewModel;
  private generation: number = 0;
  private pendingDraft: string = '';
  private requestId: string = '';

  constructor(alerts: AlertViewModel, relay: RelayViewModel, client?: AuthorityClient) {
    this.alerts = alerts;
    this.relay = relay;
    this.client = client === undefined ? new AuthorityClient() : client;
  }

  async login(): Promise<void> {
    if (this.busy) { return; }
    const token: string = this.tokenInput.trim();
    this.tokenInput = '';
    const generation: number = ++this.generation;
    this.busy = true;
    this.authenticated = false;
    this.state = 'signing_in';
    try {
      await this.client.login(token);
      if (generation !== this.generation) { return; }
      this.authenticated = true;
      this.state = 'ready';
    } catch (error) {
      if (generation === this.generation) { this.state = this.errorState(error as Error); }
    } finally { if (generation === this.generation) { this.busy = false; } }
  }

  async publish(): Promise<boolean> {
    if (this.busy) { return false; }
    if (!this.authenticated) { this.state = 'invalid_token'; return false; }
    const title: string = this.draftTitle.trim();
    const body: string = this.draftBody.trim();
    const area: string = this.draftArea.trim();
    if (title.length === 0 || title.length > 160 || body.length === 0 || body.length > 1200 ||
      area.length === 0 || area.length > 120 ||
      (this.draftLanguage !== 'pl' && this.draftLanguage !== 'en') ||
      (this.severity !== 'info' && this.severity !== 'warning' && this.severity !== 'critical') ||
      !Number.isInteger(this.validForMinutes) || this.validForMinutes < 15 || this.validForMinutes > 1440) {
      this.state = 'invalid_draft'; return false;
    }
    const generation: number = this.generation;
    this.busy = true;
    this.state = 'publishing';
    try {
      const fingerprint: string = JSON.stringify([title, body, area, this.draftLanguage, this.severity, this.validForMinutes]);
      if (fingerprint !== this.pendingDraft || this.requestId.length === 0) {
        this.requestId = this.client.createRequestId();
        this.pendingDraft = fingerprint;
      }
      const draft: AuthorityDraft = {
        requestId: this.requestId, title: title, body: body, area: area,
        language: this.draftLanguage, severity: this.severity, expiresInMinutes: this.validForMinutes
      };
      const envelope: SignedAlertEnvelope = await this.client.publish(draft);
      if (generation !== this.generation) { return false; }
      const result: RelayResult = await this.alerts.receive(envelope, 'authority');
      if (generation !== this.generation) { return false; }
      if (result.status !== 'accepted' && result.status !== 'duplicate') {
        this.state = 'verification_failed'; return false;
      }
      if (this.alerts.persistenceState !== 'saved' && this.alerts.persistenceState !== 'reverified') {
        // Keep the same idempotency key and draft. A retry receives the same
        // signature and repairs local persistence before claiming it is saved.
        this.state = 'storage_failed'; return false;
      }
      this.lastPublishedIdentity = JSON.stringify([
        envelope.payload.keyId, envelope.payload.alertId, String(envelope.payload.revision), String(envelope.payload.issuedAt)
      ]);
      this.lastPublishedTitle = envelope.payload.title;
      // Publishing seeds a verified packet; every later recipient relays it automatically.
      await this.relay.share();
      if (generation !== this.generation) { return false; }
      this.state = this.relay.isConnected && this.relay.peerCount > 0 ? 'published' : 'published_waiting';
      this.draftTitle = '';
      this.draftBody = '';
      this.pendingDraft = '';
      this.requestId = '';
      return true;
    } catch (error) {
      if (generation === this.generation) {
        this.state = this.errorState(error as Error);
        if (this.state === 'invalid_token') { this.authenticated = false; }
        if (this.state === 'request_expired') {
          // Never issue again automatically. Preserve the text; the operator's
          // next explicit Publish action starts a fresh validity window and ID.
          this.pendingDraft = '';
          this.requestId = '';
        }
      }
      return false;
    } finally { if (generation === this.generation) { this.busy = false; } }
  }

  logout(): void {
    this.generation++;
    this.client.logout();
    this.tokenInput = '';
    this.authenticated = false;
    this.busy = false;
    this.state = 'signed_out';
  }

  dispose(): void { this.logout(); }

  private errorState(error: Error): string {
    const states: string[] = ['invalid_token', 'unavailable', 'wrong_authority', 'invalid_draft', 'too_large',
      'rate_limited', 'request_conflict', 'request_expired', 'storage_failed', 'invalid_response', 'cancelled'];
    return states.includes(error.message) ? error.message : 'failed';
  }
}
