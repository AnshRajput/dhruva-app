# RISKS

| ID | Risk | Severity | Mitigation / status |
|---|---|---|---|
| R1 | On-device inference speed/memory cannot be verified in this environment (no physical phone) | HIGH | Build per docs, unit-test the FFI layer, log every unverified path here as "needs on-device verification"; human tester pass via Firebase App Distribution (Loop 13) |
| R2 | iOS ad-hoc distribution needs Apple Developer account + tester UDIDs | MEDIUM | H4 checkpoint; Android distribution proceeds independently |
| R3 | Android signing keys + Firebase CI token needed for release lane | MEDIUM | H3 checkpoint at Loop 13; debug builds until then |
| R4 | Packages in the on-device-AI space move fast; digest may be stale | MEDIUM | Loop 0 live verification before locking stack (Rule 9) |
| R5 | iOS build requires Xcode; verify availability before Loop 1 gate | MEDIUM | Check `xcodebuild -version` in Loop 1; if absent, CI macOS runner covers iOS builds |
| R6 | Pinned llama_cpp_dart LlamaEngine leaks ~167MB/model-reload (no free path at commit c6e377) — our LlamaEngineService bypasses it and disposes properly; risk is future contributors using LlamaEngine directly | MEDIUM | Lint/review rule: only engine_bindings/ may import the package; consider upstream PR. Re-evaluate at every engine pin bump |
| R7 | ggml Metal assert at process exit on macOS dev builds after model load (upstream PR #17869) | LOW | Cosmetic, dev-only; track upstream fix at next pin bump |
| R8 | Android AAR not yet wired (build_native.sh android unimplemented at pin; package ships CPU+Hexagon AARs via releases) | MEDIUM | Wire AAR into android/app/libs/ in Loop 3 gate prep; Android CI release build currently builds without native inference exercised |
| R9 | On-device (phone) inference perf/thermals unverified — macOS Metal 64.9 tok/s is NOT a phone number | HIGH | Needs on-device verification via Firebase App Distribution testers (Loop 13) |
