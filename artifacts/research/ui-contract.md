# SafeMesh implementation contract

Purpose: a civilian emergency-information hackathon prototype for HarmonyOS.

Scaffold: DevEco CLI 1.3.4, SafeMesh, org.safemesh.alerts. Compile/target SDK 24, minimum 20.

Routing: REQ -> DEV -> VAL; ARKUI-02-03 component page layout and ARKUI-03-01 state management. Preserve the scaffold's V1 @Component convention. Page state lives in @Observed view models, with stateless visual builders and a dedicated Canvas map component. No V1/V2 mixing.

Evidence read:
- hmos-arkui-scenario-development/references/component-page-building-scenario-development.md: Column/Row/Stack and conditional views.
- hmos-arkui-scenario-development/references/state-management/state-management-v1v2-scenario-development.md: V1 state ownership.
- hmos-arkui-develop-skill/references/quick-apis/05-media.md: CanvasRenderingContext2D/Canvas, paths and drawing.
- hmos-arkui-develop-skill/references/quick-apis/08-state-decorators.md: @State, @Observed, @ObjectLink.
- ohos-app-dev/references/arkts-strict.md: explicit classes/types; no dynamic object shapes.

Views: Home (signed drill alert + offline readiness), Map (bundled central Krakow map and sourced protective points), Relay (honestly labelled emulator mesh simulation and actual NearLink hardware adapter), Guide (short sourced preparedness guidance and trust limitations).

Platform capabilities: native ECDSA signature verification, local preferences, native Canvas, actual NearLinkKit transport adapter where supported. The emulator simulation is separate and labelled. No claim that RCB or PSP has integrated this prototype. No claim that a mapped protective point is open, certified as a bomb shelter, or safe to reach.

Verification: compile, launch, native signature acceptance/tampering/replay/expiry, visible map and selection, relay simulation A->B->C and duplicate suppression, persistence restore, truthful unsupported NearLink result.
