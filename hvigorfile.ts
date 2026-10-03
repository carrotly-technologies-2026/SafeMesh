// @ts-nocheck: hvigor 5.1 (Oniro command-line tools) and 6.x (DevEco) differ in Product typings.
import { appTasks, OhosAppContext, OhosHapContext, OhosPluginId } from '@ohos/hvigor-ohos-plugin';
import { getNode, hvigor, HvigorNode } from '@ohos/hvigor';

// The OpenHarmony/Oniro product has no NearLink Kit and runs on "default" devices.
// Adjust only that product's entry manifest; the HarmonyOS product keeps module.json5 as written.
const ONIRO_PRODUCT = 'oniro';
const NEARLINK_PERMISSION = 'ohos.permission.ACCESS_NEARLINK';

hvigor.nodesEvaluated(() => {
  const appNode: HvigorNode = getNode(__filename);
  const appContext = appNode.getContext(OhosPluginId.OHOS_APP_PLUGIN) as OhosAppContext;
  const product = appContext?.getCurrentProduct();
  const productName: string = product?.getProductName?.() ?? product?.productName ?? '';
  if (productName !== ONIRO_PRODUCT) {
    return;
  }
  appNode.subNodes((moduleNode: HvigorNode) => {
    const hapContext = moduleNode.getContext(OhosPluginId.OHOS_HAP_PLUGIN) as OhosHapContext;
    if (hapContext?.getModuleName() !== 'entry') {
      return;
    }
    const moduleJson = hapContext.getModuleJsonOpt();
    moduleJson.module.deviceTypes = ['default'];
    moduleJson.module.requestPermissions = (moduleJson.module.requestPermissions ?? [])
      .filter((permission: { name: string }) => permission.name !== NEARLINK_PERMISSION);
    hapContext.setModuleJsonOpt(moduleJson);
  });
});

export default {
  system: appTasks /* Built-in plugin of Hvigor. It cannot be modified. */,
  plugins: [] /* Custom plugin to extend the functionality of Hvigor. */,
};
