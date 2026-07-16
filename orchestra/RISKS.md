# RISKS

| ID | Risk | Severity | Mitigation / status |
|---|---|---|---|
| R1 | On-device inference speed/memory cannot be verified in this environment (no physical phone) | HIGH | Build per docs, unit-test the FFI layer, log every unverified path here as "needs on-device verification"; human tester pass via Firebase App Distribution (Loop 13) |
| R2 | iOS ad-hoc distribution needs Apple Developer account + tester UDIDs | MEDIUM | H4 checkpoint; Android distribution proceeds independently |
| R3 | Android signing keys + Firebase CI token needed for release lane | MEDIUM | H3 checkpoint at Loop 13; debug builds until then |
| R4 | Packages in the on-device-AI space move fast; digest may be stale | MEDIUM | Loop 0 live verification before locking stack (Rule 9) |
| R5 | iOS build requires Xcode; verify availability before Loop 1 gate | MEDIUM | Check `xcodebuild -version` in Loop 1; if absent, CI macOS runner covers iOS builds |
