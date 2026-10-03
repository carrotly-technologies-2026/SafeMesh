import { SignedAlertEnvelope, copyEnvelope } from './AlertProtocol';
export { DEMO_KEY_ID, DEMO_PUBLIC_KEY_DER } from './DemoTrust';

// Generated signed drills. Regenerate with: node scripts/generate-demo-alerts.mjs
const DEMO_ALERT: SignedAlertEnvelope = {
  "payload": {
    "version": 1,
    "keyId": "safemesh-demo-authority-v1",
    "alertId": "krakow-hackyeah-exercise-001",
    "revision": 1,
    "issuedAt": 1791049551662,
    "expiresAt": 1791308751662,
    "severity": "warning",
    "area": "Kraków · centrum",
    "title": "Network outage exercise",
    "body": "EXERCISE ONLY. Mobile service is unavailable in this simulated scenario. Keep the app open to relay this signed drill. The offline map lists PSP protective points; check access and follow official instructions.",
    "shelterIds": [],
    "drill": true,
    "maxHops": 8
  },
  "signature": "MEUCIQCgD6+afT1eZHwtRQi+fCBqk9u2lvPjUoSpb78DKdhVJAIgC5KDZYFod1iNIqe8RwOEKilt7h5rcjwi9FbnKwVqdqM=",
  "hops": 0
};

const EXPIRED_ALERT: SignedAlertEnvelope = {
  "payload": {
    "version": 1,
    "keyId": "safemesh-demo-authority-v1",
    "alertId": "krakow-expired-exercise-001",
    "revision": 1,
    "issuedAt": 1790786811662,
    "expiresAt": 1791046011662,
    "severity": "warning",
    "area": "Kraków · centrum",
    "title": "Network outage exercise",
    "body": "EXERCISE ONLY. Mobile service is unavailable in this simulated scenario. Keep the app open to relay this signed drill. The offline map lists PSP protective points; check access and follow official instructions.",
    "shelterIds": [],
    "drill": true,
    "maxHops": 8
  },
  "signature": "MEUCIQD1aabPebQxv/zV7kPxu7bp1rxyUZJw8dzn33ooHodr4wIgQm0uUfeRmG0nVmpwntl2vYhaYTysLUA8upMJ7ATAORw=",
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
