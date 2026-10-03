import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';

interface StoreHead {
  version: number;
  slot: string;
  chunks: number;
  length: number;
}

const MAX_VALUE_UNITS: number = 128 * 8192;
const CHUNK_UNITS: number = 2048;
const MAX_CHUNKS: number = Math.ceil(MAX_VALUE_UNITS / (CHUNK_UNITS - 1));

// Preferences strings are limited to 8192 characters. Two bounded slots keep the
// previous complete generation while new chunks are flushed, then publish a head.
// Restored alert contents must still pass signature and expiry checks in the engine.
export class LocalStore {
  private store: preferences.Preferences | undefined = undefined;
  private initialization: Promise<void> | undefined = undefined;
  private operations: Promise<void> = Promise.resolve();

  async init(context: common.UIAbilityContext): Promise<void> {
    if (this.store !== undefined) { return; }
    if (this.initialization === undefined) { this.initialization = this.open(context); }
    try { await this.initialization; } catch (error) {
      this.initialization = undefined;
      throw new Error(String(error));
    }
  }

  async read(key: string): Promise<string> {
    this.validateKey(key);
    let result: string = '';
    const operation: Promise<void> = this.operations.then(async (): Promise<void> => {
      const store: preferences.Preferences = await this.ready();
      const headValue: preferences.ValueType = await store.get(this.headKey(key), '');
      if (typeof headValue !== 'string') { throw new Error('Invalid local storage head'); }
      if (headValue.length === 0) {
        // Read small values saved by the first prototype before chunking existed.
        const legacy: preferences.ValueType = await store.get(key, '');
        if (typeof legacy !== 'string' || legacy.length > MAX_VALUE_UNITS) {
          throw new Error('Invalid legacy local value');
        }
        result = legacy;
        return;
      }
      const head: StoreHead = this.parseHead(headValue);
      const parts: string[] = [];
      let units: number = 0;
      for (let index: number = 0; index < head.chunks; index++) {
        const part: preferences.ValueType = await store.get(this.chunkKey(key, head.slot, index), '');
        if (typeof part !== 'string' || part.length === 0 || part.length > CHUNK_UNITS) {
          throw new Error('Incomplete local storage generation');
        }
        units += part.length;
        if (units > head.length) { throw new Error('Oversized local storage generation'); }
        parts.push(part);
      }
      if (units !== head.length) { throw new Error('Incomplete local storage generation'); }
      result = parts.join('');
    });
    this.operations = operation.catch((): void => {});
    await operation;
    return result;
  }

  async write(key: string, value: string): Promise<void> {
    this.validateKey(key);
    if (typeof value !== 'string' || value.length > MAX_VALUE_UNITS) {
      throw new Error('Local value exceeds bounded storage capacity');
    }
    const operation: Promise<void> = this.operations.then(async (): Promise<void> => {
      const store: preferences.Preferences = await this.ready();
      const oldValue: preferences.ValueType = await store.get(this.headKey(key), '');
      if (typeof oldValue !== 'string') { throw new Error('Invalid local storage head'); }
      const previous: StoreHead | undefined = oldValue.length === 0 ? undefined : this.parseHead(oldValue);
      const slot: string = previous === undefined || previous.slot === 'b' ? 'a' : 'b';
      let index: number = 0;
      let offset: number = 0;
      while (offset < value.length) {
        let end: number = Math.min(value.length, offset + CHUNK_UNITS);
        // Native string encoding must never receive half of an emoji/surrogate pair.
        if (end < value.length) {
          const last: number = value.charCodeAt(end - 1);
          if (last >= 0xD800 && last <= 0xDBFF) { end--; }
        }
        await store.put(this.chunkKey(key, slot, index), value.slice(offset, end));
        offset = end;
        index++;
      }
      // The old head still references the untouched previous slot during this flush.
      await store.flush();
      const head: StoreHead = { version: 1, slot: slot, chunks: index, length: value.length };
      try {
        await store.put(this.headKey(key), JSON.stringify(head));
        await store.flush();
      } catch (error) {
        // A failed publication must not make the in-process cache claim a commit.
        // On restart either durable head is safe: its complete chunks flushed first.
        try { await store.put(this.headKey(key), oldValue); } catch (rollbackError) {
          this.store = undefined;
          this.initialization = undefined;
        }
        throw new Error(String(error));
      }
    });
    this.operations = operation.catch((): void => {});
    await operation;
  }

  private async open(context: common.UIAbilityContext): Promise<void> {
    this.store = await preferences.getPreferences(context, { name: 'safemesh_v1' });
  }

  private async ready(): Promise<preferences.Preferences> {
    if (this.initialization !== undefined) { await this.initialization; }
    if (this.store === undefined) { throw new Error('LocalStore.init must complete before reading or writing'); }
    return this.store;
  }

  private validateKey(key: string): void {
    if (typeof key !== 'string' || !/^[A-Za-z0-9_-]{1,48}$/.test(key)) {
      throw new Error('Invalid local storage key');
    }
  }

  private headKey(key: string): string { return 'sm2:' + key + ':head'; }

  private chunkKey(key: string, slot: string, index: number): string {
    return 'sm2:' + key + ':' + slot + ':' + String(index);
  }

  private parseHead(value: string): StoreHead {
    const head: StoreHead = JSON.parse(value) as StoreHead;
    if (head === null || typeof head !== 'object' || head.version !== 1 ||
      (head.slot !== 'a' && head.slot !== 'b') || !Number.isSafeInteger(head.chunks) ||
      head.chunks < 0 || head.chunks > MAX_CHUNKS || !Number.isSafeInteger(head.length) ||
      head.length < 0 || head.length > MAX_VALUE_UNITS ||
      (head.chunks === 0) !== (head.length === 0)) {
      throw new Error('Invalid local storage generation');
    }
    return head;
  }
}
