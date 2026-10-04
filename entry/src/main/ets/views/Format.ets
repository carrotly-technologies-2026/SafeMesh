import { intl } from '@kit.LocalizationKit';
import { RelayViewModel } from '../viewmodel/RelayViewModel';

/** Short UTC date and time for alert metadata, e.g. "3 Oct, 19:57 UTC". */
export function formatUtc(value: number, language: string): string {
  if (value <= 0) { return ''; }
  try {
    return new intl.DateTimeFormat(language === 'pl' ? 'pl-PL' : 'en-GB', {
      day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit', hour12: false, timeZone: 'UTC'
    }).format(new Date(value)) + ' UTC';
  } catch (error) { return new Date(value).toISOString().slice(0, 16).replace('T', ' ') + ' UTC'; }
}

/** Resource key for the relay connection headline shared by Home and Relay. */
export function connectionKey(relay: RelayViewModel, connecting: boolean): string {
  if (relay.lifecycleState === 'paused') { return 'connection_paused'; }
  if (relay.isConnected) { return 'connection_active'; }
  if (connecting) { return 'connection_connecting'; }
  return 'connection_off';
}
