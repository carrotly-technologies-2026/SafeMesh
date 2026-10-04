import { vibrator } from '@kit.SensorServiceKit';

const PRESET_EFFECT: string = 'haptic.notice.warning';

/** Short haptic cue for a newly verified alert. The phone's silent and vibration settings still apply. */
export class AlertFeedback {
  /** True when the vibration started. Phones without a vibrator (emulators) keep the visual banner only. */
  async vibrate(severity: string): Promise<boolean> {
    const critical: boolean = severity === 'critical';
    const attribute: vibrator.VibrateAttribute = { usage: critical ? 'alarm' : 'notification' };
    try {
      if (await vibrator.isSupportEffect(PRESET_EFFECT)) {
        await vibrator.startVibration({ type: 'preset', effectId: PRESET_EFFECT, count: critical ? 3 : 1 }, attribute);
      } else {
        await vibrator.startVibration({ type: 'time', duration: critical ? 900 : 300 }, attribute);
      }
      console.info('SAFEMESH_ALERT_FEEDBACK vibrated=true severity=' + severity);
      return true;
    } catch (error) {
      console.warn('SAFEMESH_ALERT_FEEDBACK vibrated=false severity=' + severity);
      return false;
    }
  }
}
