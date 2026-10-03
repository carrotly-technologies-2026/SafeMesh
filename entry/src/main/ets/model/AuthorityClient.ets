import { http } from '@kit.NetworkKit';
import { SignedAlertEnvelope, decodeEnvelope } from './AlertProtocol';
import { createDeliveryId } from './DeliveryProtocol';
import { DEMO_KEY_ID, DEMO_PUBLIC_KEY_DER } from './DemoTrust';

export interface AuthorityDraft {
  requestId: string;
  title: string;
  body: string;
  area: string;
  language: string;
  severity: string;
  expiresInMinutes: number;
}

interface AuthoritySession {
  service: string;
  protocol: number;
  keyId: string;
  publicKeyDer: string;
  exerciseOnly: boolean;
  authorized: boolean;
}

interface AuthorityEnvelopeResponse { envelope: SignedAlertEnvelope; }
interface AuthorityErrorResponse { error: string; }

export interface AuthorityHttpResponse { status: number; body: string; }
export interface AuthorityHttp {
  request(path: string, token: string, body: string): Promise<AuthorityHttpResponse>;
  cancel(): void;
}

/** Local demo issuing station; never the mesh transport or a public signing endpoint. */
class NativeAuthorityHttp implements AuthorityHttp {
  private active: http.HttpRequest | undefined = undefined;

  async request(path: string, token: string, body: string): Promise<AuthorityHttpResponse> {
    const request: http.HttpRequest = http.createHttp();
    this.active = request;
    try {
      const response: http.HttpResponse = await request.request('http://127.0.0.1:8768' + path, {
        method: body.length > 0 ? http.RequestMethod.POST : http.RequestMethod.GET,
        header: { 'Authorization': 'Bearer ' + token, 'Content-Type': 'application/json' },
        extraData: body,
        expectDataType: http.HttpDataType.STRING,
        usingCache: false,
        usingProxy: false,
        maxRedirects: 0,
        maxLimit: 16384,
        connectTimeout: 4000,
        readTimeout: 8000
      });
      if (typeof response.result !== 'string' || response.result.length > 16384) {
        throw new Error('invalid_response');
      }
      return { status: response.responseCode, body: response.result };
    } finally {
      if (this.active === request) { this.active = undefined; }
      request.destroy();
    }
  }

  cancel(): void {
    const request: http.HttpRequest | undefined = this.active;
    this.active = undefined;
    if (request !== undefined) { try { request.destroy(); } catch (error) {} }
  }
}

/** Holds the authorization credential in memory only. The mobile app has no signing key. */
export class AuthorityClient {
  private transport: AuthorityHttp;
  private token: string = '';
  private generation: number = 0;

  constructor(transport?: AuthorityHttp) {
    this.transport = transport === undefined ? new NativeAuthorityHttp() : transport;
  }

  async login(token: string): Promise<void> {
    this.logout();
    if (!/^[a-f0-9]{64}$/.test(token)) { throw new Error('invalid_token'); }
    const generation: number = this.generation;
    const response: AuthorityHttpResponse = await this.request('/session', token, '');
    if (generation !== this.generation) { throw new Error('cancelled'); }
    if (response.status !== 200) { throw new Error(this.errorState(response)); }
    let session: AuthoritySession;
    try { session = JSON.parse(response.body) as AuthoritySession; }
    catch (error) { throw new Error('invalid_response'); }
    if (session === null || typeof session !== 'object' || session.authorized !== true ||
      session.service !== 'safemesh-demo-authority' || session.protocol !== 1 || session.exerciseOnly !== true) {
      throw new Error('invalid_response');
    }
    if (session.keyId !== DEMO_KEY_ID || session.publicKeyDer !== DEMO_PUBLIC_KEY_DER) {
      throw new Error('wrong_authority');
    }
    this.token = token;
  }

  async publish(draft: AuthorityDraft): Promise<SignedAlertEnvelope> {
    if (this.token.length === 0) { throw new Error('invalid_token'); }
    const generation: number = this.generation;
    const response: AuthorityHttpResponse = await this.request('/alerts', this.token, JSON.stringify(draft));
    if (generation !== this.generation) { throw new Error('cancelled'); }
    if (response.status !== 200 && response.status !== 201) {
      if (response.status === 401) { this.logout(); }
      throw new Error(this.errorState(response));
    }
    let received: AuthorityEnvelopeResponse;
    try { received = JSON.parse(response.body) as AuthorityEnvelopeResponse; }
    catch (error) { throw new Error('invalid_response'); }
    if (received === null || typeof received !== 'object') { throw new Error('invalid_response'); }
    const envelope: SignedAlertEnvelope | undefined = decodeEnvelope(JSON.stringify(received.envelope));
    if (envelope === undefined || envelope.hops !== 0 || envelope.payload.version !== 2 ||
      envelope.payload.keyId !== DEMO_KEY_ID || !envelope.payload.drill ||
      envelope.payload.alertId !== 'authority-' + draft.requestId || envelope.payload.revision !== 1 ||
      envelope.payload.title !== draft.title || envelope.payload.body !== draft.body ||
      envelope.payload.area !== draft.area || envelope.payload.language !== draft.language ||
      envelope.payload.severity !== draft.severity ||
      envelope.payload.expiresAt - envelope.payload.issuedAt !== draft.expiresInMinutes * 60000) {
      throw new Error('invalid_response');
    }
    // The caller must pass this through the same native verifier as received radio data.
    return envelope;
  }

  createRequestId(): string { return createDeliveryId(); }

  logout(): void {
    this.generation++;
    this.token = '';
    this.transport.cancel();
  }

  private async request(path: string, token: string, body: string): Promise<AuthorityHttpResponse> {
    try { return await this.transport.request(path, token, body); }
    catch (error) {
      // Network errors must not echo a credential or response into UI/log output.
      throw new Error('unavailable');
    }
  }

  private errorState(response: AuthorityHttpResponse): string {
    if (response.status === 401) { return 'invalid_token'; }
    if (response.status === 413) { return 'too_large'; }
    if (response.status === 429) { return 'rate_limited'; }
    try {
      const body: AuthorityErrorResponse = JSON.parse(response.body) as AuthorityErrorResponse;
      if (body !== null && body.error === 'storage_failed') { return 'storage_failed'; }
      if (response.status === 409 && body !== null && body.error === 'request_expired') { return 'request_expired'; }
    } catch (error) {}
    if (response.status === 409) { return 'request_conflict'; }
    return response.status === 400 ? 'invalid_draft' : 'failed';
  }
}
