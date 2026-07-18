# Development & Release

← [Knowledge Base](README.md)

## The gate: `make verify`

```bash
cd app
make verify   # flutter analyze + dart format --set-exit-if-changed + flutter test
```

This is the full local gate and the same one CI runs. It must be green before every
handoff and every release. Coverage floor is **70%** on `lib/`
(`flutter test --coverage`).

Two gotchas learned the hard way:

- **Format after committing bites.** `dart format --set-exit-if-changed` can
  reformat a file you already committed. Run `make verify` *before* committing, or
  amend.
- **One native test can flake** under full-suite concurrency and pass in isolation.
  Re-run to confirm before treating it as a real failure.

## Test on-device before EVERY deploy

No build reaches testers until the changed path is verified working by a human/agent
in the emulator or on a device — not just in unit tests. A feature that passes tests
but crashes or dead-ends on-device is **not done**.

This rule exists because of a real failure: v0.2.2 shipped a download path that
passed tests but crashed every download on Android 14+ (a foreground-service
permission/type mismatch — see
[`../orchestra/VIDEO_FIXES.md`](../orchestra/VIDEO_FIXES.md) and
[Architecture](architecture.md#downloads-on-android-14)). The crash was only caught
by reading the actual on-device stack trace. Anything genuinely unverifiable on the
build machine goes to [`RISKS.md`](../orchestra/RISKS.md), never silently shipped.

## The loop process

Work moves in loops: **PLAN → BUILD → TEST → REVIEW → REFLECT → COMMIT**
(full protocol in [`../orchestra/PROTOCOL.md`](../orchestra/PROTOCOL.md)). Each loop
uses a `loop/<nn>-<slug>` branch, conventional commits, a reviewer verdict on the
blackboard, and a squash-merge with CI green. The running history is in
[`../orchestra/LOOP_LOG.md`](../orchestra/LOOP_LOG.md).

CI pins **Flutter 3.41.2** — match it locally.

## Versioning

`version:` in `app/pubspec.yaml` (e.g. `0.3.1+7`) is the source of truth. It's
mirrored by hand in `app/lib/features/settings/app_info.dart` (`appVersion`,
`appBuildNumber`) so the About screen never drifts. Bump both together.

## Distribution

Release builds go to testers via **Firebase App Distribution** — and that is the
*only* thing Firebase is used for. **No Firebase SDK is in the app**; nothing at
runtime touches it (see [Privacy](privacy.md#what-firebase-is-and-isnt-used-for)).

```bash
scripts/distribute.sh   # builds the arm64 release + uploads to FAD
```

`BUILD_NUMBER` comes from `git rev-list --count HEAD`; `BUILD_NAME` from the pubspec
version. Distributed to the `internal-testers` group. The precondition for running
it is always the same: `make verify` green **and** the changed path verified
on-device.
