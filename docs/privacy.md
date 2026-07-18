# Privacy & the On-Device Contract

← [Knowledge Base](README.md)

This is the point of the whole project. Everything else is downstream of it.

## The contract

- **100% local inference.** Every token is generated on the device's own CPU/GPU
  through `llama.cpp`. There is no cloud path, no fallback, no "if the phone is slow,
  call a server" branch. Turn off the network and Dhruva still works.
- **Zero telemetry.** No analytics SDKs, no crash reporters that phone home, no
  feature flags that call out, no A/B endpoints. Nothing about how you use the app
  leaves the app.
- **The only network call is yours.** A user-initiated model download from Hugging
  Face — nothing else. No background sync, no license check, no "anonymous usage."

## What Firebase is (and isn't) used for

Firebase App Distribution is used **only** to hand release builds to testers. It is
a build-distribution channel, entirely outside the app. **No Firebase SDK ships
inside the app**, and no runtime data ever touches it. See
[Development & Release](development.md#distribution).

## How the contract is enforced

- **Architecture** — network access is confined to the model-download and Hugging
  Face API code under `data/`. Feature code cannot reach the network directly; the
  dependency direction is one-way (`features → data → core`). See
  [Architecture](architecture.md).
- **Review gate** — a feature is not "done" until `flutter analyze` is clean, tests
  pass, and the on-device path is verified. Anything unverifiable on the build
  machine is tracked in [`../orchestra/RISKS.md`](../orchestra/RISKS.md), never
  silently shipped.
- **Auditability** — the app is Apache-2.0 and open source. The claim is checkable,
  not just asserted.

## Why "Dhruva"

ध्रुव is the pole star — the one fixed point in the night sky that never moves.
The app is the same: always there, needs no network, yours alone to navigate by.
That's the value the product states plainly on the website and inside the app, not
just implies.
