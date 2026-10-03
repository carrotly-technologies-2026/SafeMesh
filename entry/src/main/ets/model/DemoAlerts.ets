import { SignedAlertEnvelope, copyEnvelope } from './AlertProtocol';
export { DEMO_KEY_ID, DEMO_PUBLIC_KEY_DER } from './DemoTrust';

// Generated signed drills. Regenerate with: node scripts/generate-demo-alerts.mjs
const DEMO_ALERT: SignedAlertEnvelope = {
  "payload": {
    "version": 2,
    "keyId": "safemesh-demo-authority-v1",
    "alertId": "krakow-hackyeah-exercise-001",
    "revision": 1,
    "issuedAt": 1791053385616,
    "expiresAt": 1791312585616,
    "severity": "warning",
    "area": "Kraków centrum",
    "title": "Przerwa w łączności",
    "body": "To ćwiczenie — do aplikacji dotarła podpisana wiadomość. Pozostaw aplikację otwartą, aby przekazać ją dalej; punkty ochronne PSP znajdziesz na mapie offline, a ich dostępność trzeba sprawdzić.",
    "shelterIds": [],
    "drill": true,
    "maxHops": 8,
    "language": "pl",
    "translations": [
      {
        "language": "en",
        "area": "Kraków centre",
        "title": "Connection outage",
        "body": "This is an exercise: a signed message has reached the app. Keep the app open to relay it; the offline map lists PSP protective points, whose current access needs checking."
      }
    ]
  },
  "signature": "MEQCIE4Ma0S1fVAliOK6JJL5dn2eFPfv233Kz42icgc78rwZAiBT6Z7X9XH2umsvxeFteb9veuKXwCndo3YgHCdVZn3bqQ==",
  "hops": 0
};

const EXPIRED_ALERT: SignedAlertEnvelope = {
  "payload": {
    "version": 2,
    "keyId": "safemesh-demo-authority-v1",
    "alertId": "krakow-expired-exercise-001",
    "revision": 1,
    "issuedAt": 1790790645616,
    "expiresAt": 1791049845616,
    "severity": "warning",
    "area": "Kraków centrum",
    "title": "Przerwa w łączności",
    "body": "To ćwiczenie — do aplikacji dotarła podpisana wiadomość. Pozostaw aplikację otwartą, aby przekazać ją dalej; punkty ochronne PSP znajdziesz na mapie offline, a ich dostępność trzeba sprawdzić.",
    "shelterIds": [],
    "drill": true,
    "maxHops": 8,
    "language": "pl",
    "translations": [
      {
        "language": "en",
        "area": "Kraków centre",
        "title": "Connection outage",
        "body": "This is an exercise: a signed message has reached the app. Keep the app open to relay it; the offline map lists PSP protective points, whose current access needs checking."
      }
    ]
  },
  "signature": "MEUCIQCJS2mZ8KzVfPFsvRQk/evkv9FmPOn4o2GooMoX785mjwIgDvosKR8GwSy2AuuDOILiFzR6WyKEK2yltMPprjK8IWg=",
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
