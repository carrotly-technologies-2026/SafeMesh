import { SignedAlertEnvelope, copyEnvelope } from './AlertProtocol';
export { DEMO_KEY_ID, DEMO_PUBLIC_KEY_DER } from './DemoTrust';

// Generated signed drills. Regenerate with: node scripts/generate-demo-alerts.mjs
const DEMO_ALERT: SignedAlertEnvelope = {
  "payload": {
    "version": 1,
    "keyId": "safemesh-demo-authority-v1",
    "alertId": "krakow-hackyeah-exercise-001",
    "revision": 1,
    "issuedAt": 1791040772456,
    "expiresAt": 1791299972456,
    "severity": "warning",
    "area": "Kraków · centrum",
    "title": "Network outage exercise",
    "body": "EXERCISE ONLY. Mobile service is unavailable in this simulated scenario. Keep the app open to relay this signed drill. The offline map lists PSP protective points; check access and follow official instructions.",
    "shelterIds": [],
    "drill": true,
    "maxHops": 8
  },
  "signature": "MEYCIQDr0OHgxwwrXhMPeFVxdWBXnPAIVmDDQzq5uKpjcSuAVgIhAIGJoaa1ABg/dxiXfitMyfUeg3ChmF5HvO9n07+GB2Ah",
  "hops": 0
};

const EXPIRED_ALERT: SignedAlertEnvelope = {
  "payload": {
    "version": 1,
    "keyId": "safemesh-demo-authority-v1",
    "alertId": "krakow-expired-exercise-001",
    "revision": 1,
    "issuedAt": 1790778032456,
    "expiresAt": 1791037232456,
    "severity": "warning",
    "area": "Kraków · centrum",
    "title": "Network outage exercise",
    "body": "EXERCISE ONLY. Mobile service is unavailable in this simulated scenario. Keep the app open to relay this signed drill. The offline map lists PSP protective points; check access and follow official instructions.",
    "shelterIds": [],
    "drill": true,
    "maxHops": 8
  },
  "signature": "MEYCIQDQFjh22qSOKVQ1f5EsmQFOYJn6nEHtP9uUsQDKx2hP/wIhAJvQxzGhtvcRZq0HMIlaveS3AQxCp9W9tkpJaBazPbmd",
  "hops": 0
};

export function createDemoAlert(): SignedAlertEnvelope {
  return copyEnvelope(DEMO_ALERT);
}

export function createTamperedAlert(): SignedAlertEnvelope {
  const alert: SignedAlertEnvelope = createDemoAlert();
  alert.payload.body = "FORGED INSTRUCTION: This content was changed after signing.";
  return alert;
}

export function createExpiredAlert(): SignedAlertEnvelope {
  return copyEnvelope(EXPIRED_ALERT);
}
