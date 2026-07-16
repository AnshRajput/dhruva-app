# Contributing to Dhruva

Thanks for helping build a private, on-device AI. Contributions of every size
are welcome — code, docs, translations, bug reports, model catalog entries.

## Ground rules

1. **Privacy is the product.** PRs that add telemetry, analytics, or any
   network call other than user-initiated Hugging Face downloads will be
   declined. There is no cloud inference path — not even behind a flag.
2. **Tested is done.** `make verify` must pass: `flutter analyze` clean,
   `dart format` clean, tests green. New features need tests (coverage floor
   is 70% on `lib/`).
3. **Small, conventional commits.** `feat:`, `fix:`, `test:`, `docs:`,
   `ci:`, `chore:`.

## Getting started

```bash
git clone https://github.com/AnshRajput/dhruva-app.git
cd dhruva-app/app
flutter pub get
flutter test
```

See `docs/` for architecture (ADRs) and the user guide.

## Project structure

- `app/` — the Flutter application
- `engine/` — native inference glue (llama.cpp family)
- `docs/adr/` — architecture decision records; significant changes need one
- `orchestra/` — internal engineering log (interesting reading, not API)

## Pull requests

- Branch from `main`, open a PR with a clear description and linked issue.
- CI must be green; a maintainer reviews and squash-merges.
- Architectural changes: open an issue or draft ADR first so we can discuss
  before you invest time.

## Reporting bugs

Use the bug template. Include device model, RAM, OS version, the model
(repo + quant) you were running, and steps to reproduce. Crash logs help
enormously.

## Code of conduct

Be kind, assume good faith, critique code not people.
