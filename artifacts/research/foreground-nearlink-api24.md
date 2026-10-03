# NearLink loading and foreground lifecycle — API 24

Checked 2026-10-03 against the installed DevEco Studio SDK. This records source/API evidence and host tests, not physical NearLink validation.

## Lazy Kit bindings

`NearLinkTransport.ets` uses `import lazy { manager, advertising, dataTransfer, scan } from '@kit.NearLinkKit'`. The first runtime access occurs only after `canIUse('SystemCapability.Communication.NearLink.Core')` succeeds. Namespace types do not require radio access.

The local official-guide copy `C:/Users/user/.codex/skills/hmos-arkts-knowledge-retriever/docs/ArkTS-Language-Guide/05-Runtime/arkts-lazy-import.md`, section **Syntax Specifications and Supported Versions**, documents named Kit lazy imports from API 18. Our target is API 24. Local SDK evidence:

- `sdk/default/hms/ets/kits/@kit.NearLinkKit.d.ts` exports those four names.
- `sdk/default/hms/ets/build-tools/ets-loader/kit_configs/@kit.NearLinkKit.json` maps each name to its `@hms.nearlink.*` default binding.
- `sdk/default/openharmony/ets/build-tools/ets-loader/lib/process_kit_import.js` preserves `importClause.isLazy` when it creates the underlying import clauses.

All SDK paths above are relative to `C:/Users/user/DevEcoStudio`. The targeted CLI ArkTS check passes for the changed adapter and ViewModel. A complete app build and emulator cold launch remain separate evidence; a host CommonJS test cannot prove Ark runtime lazy-module behavior.

Host tests adapt erased CommonJS imports with a binding-access proxy. They verify that an unsupported capability causes no native binding access, permission request or fabricated peer, and cover cancellation during permission, advertising, channel connection and chunked writes. The adapter cancels connection deadlines and cleans up an advertisement or connection that completes after cancellation.

## Background API boundaries

API 24 includes public continuous-task APIs requiring `ohos.permission.KEEP_BACKGROUND_RUNNING`. The installed `@ohos.resourceschedule.backgroundTaskManager.d.ts` documents task notifications, typed background modes and errors. Its `BackgroundMode` enum includes data transfer, Bluetooth interaction and multi-device connection; it does not define a NearLink mode.

Continuous tasks must match an actual supported use case; they are not a general process keep-alive. Bluetooth transfer and distributed connection/casting are separately described examples. The platform can cancel or suspend tasks that cease matching their requested service. The API also requires a declared mode and a user-visible notification. [OpenHarmony continuous-task guide](https://raw.githubusercontent.com/openharmony/docs/master/en/application-dev/task-management/continuous-task.md)

That evidence does not establish that a passive NearLink emergency relay qualifies for an existing mode on Huawei API 24 phones. No unrelated background mode or permission is added. Eligibility, retention during lock/suspension, power consumption and actual radio behavior still require supported phones and Huawei-specific confirmation.

## Implemented lifecycle contract

`RelayViewModel.suspend()` closes the active transport, cancels retry work and retains verified alert storage plus the selected mode/role. `foreground()` resumes only a connection that was active before suspension. First appearance does not start networking. Explicit `stop()` cancels pending resume intent, including while cleanup is still running. A connection canceled during initial startup is not treated as a formerly active connection.

The page must call `suspend()` when hidden and `foreground()` when shown; final disposal calls `stop()`. The alert ViewModel separately resumes its expiry timer. This supports returning to the foreground and does not promise delivery while the app is hidden, killed or suspended.

Host regressions cover cache synchronization after resume, stale callbacks, concurrent foreground notifications, explicit stop during pending cleanup, and suspension during initial startup. Native lifecycle tests are recorded separately after the integrated build.
