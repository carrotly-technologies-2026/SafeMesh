import { common } from '@kit.AbilityKit';
import { resourceManager } from '@kit.LocalizationKit';

/** Resource-backed strings; explicit managers make an in-app language switch immediate. */
export class UiCopy {
  private polish: resourceManager.ResourceManager | undefined = undefined;
  private english: resourceManager.ResourceManager | undefined = undefined;

  initialize(context: common.UIAbilityContext): void {
    const pl: resourceManager.Configuration = context.resourceManager.getConfigurationSync();
    pl.locale = 'pl';
    this.polish = context.resourceManager.getOverrideResourceManager(pl);
    const en: resourceManager.Configuration = context.resourceManager.getConfigurationSync();
    en.locale = 'en';
    this.english = context.resourceManager.getOverrideResourceManager(en);
  }

  text(key: string, language: string): string {
    const manager: resourceManager.ResourceManager | undefined = language === 'en' ? this.english : this.polish;
    if (manager === undefined) { return ''; }
    try { return manager.getStringByNameSync(key); }
    catch (error) { return key; }
  }
}
