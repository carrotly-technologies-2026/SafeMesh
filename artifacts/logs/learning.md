# Learning Log

- 2026-10-03: Baseline native build succeeded with minimum API20/target API24; the supplied emulator accepts the debug unsigned HAP through DevEco CLI. This does not imply physical phones will accept it.
- Integrated ArkTS check: callback interface method declarations cannot contextualise object literal function properties here. Use explicit function-valued interface properties. Keep typed callbacks and no `any`.
- NearLink ACCESS_NEARLINK is declared and requested at runtime. Static checker permission advisories persist; physical permission/device behavior remains untested. Emulator capability detection must avoid loading unsupported native kits.
- Exception advisories in native cryptography/storage wrappers are handled by their calling trust/persistence boundaries. Verification fails closed.
