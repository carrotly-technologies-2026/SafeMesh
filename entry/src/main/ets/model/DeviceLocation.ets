import { common, abilityAccessCtrl, Permissions } from '@kit.AbilityKit';
import { geoLocationManager } from '@kit.LocationKit';
import { BusinessError } from '@kit.BasicServicesKit';

export interface DevicePosition {
  status: string;
  latitude: number;
  longitude: number;
  accuracy: number;
}

// Foreground, explicit one-shot request. Location is never written to disk or relayed.
export class DeviceLocation {
  async locate(context: common.UIAbilityContext): Promise<DevicePosition> {
    try {
      if (!canIUse('SystemCapability.Location.Location.Core')) { return this.failure('unavailable'); }
      const permissions: Permissions[] = ['ohos.permission.APPROXIMATELY_LOCATION', 'ohos.permission.LOCATION'];
      const result = await abilityAccessCtrl.createAtManager().requestPermissionsFromUser(context, permissions);
      if (result.authResults.length !== 2 || result.authResults[0] !== 0) {
        return this.failure('permission_denied');
      }
      if (!geoLocationManager.isLocationEnabled()) { return this.failure('disabled'); }
      const request: geoLocationManager.CurrentLocationRequest = {
        priority: geoLocationManager.LocationRequestPriority.ACCURACY,
        timeoutMs: 10000
      };
      const location: geoLocationManager.Location = await geoLocationManager.getCurrentLocation(request);
      if (!Number.isFinite(location.latitude) || !Number.isFinite(location.longitude) ||
        location.latitude < -90 || location.latitude > 90 || location.longitude < -180 || location.longitude > 180 ||
        !Number.isFinite(location.accuracy) || location.accuracy <= 0) { return this.failure('unavailable'); }
      return { status: 'ready', latitude: location.latitude, longitude: location.longitude, accuracy: location.accuracy };
    } catch (error) {
      const code: number = (error as BusinessError).code;
      return this.failure(code === 201 ? 'permission_denied' : code === 3301100 ? 'disabled' : 'unavailable');
    }
  }

  private failure(status: string): DevicePosition {
    return { status: status, latitude: 0, longitude: 0, accuracy: 0 };
  }
}
