# ADR-003 — Brand identity: DHRUVA

- **Status:** ACCEPTED (2026-07-17, brand ceremony complete)
- **Date:** 2026-07-17
- **Deciders:** orchestrator (scout-3 verification, designer proposal, reviewer critique)
- **Loop:** 0

## Name verification (scout-3, orchestra/NAMING.md)

**DHRUVA — PASS.** No AI/chat app named Dhruva on Google Play or the App Store;
no Class-42 software trademark conflict; dhruva.app/.dev/.ai appear unregistered.
One soft collision: github.com/AI4Bharat/Dhruva-Platform (speech-serving backend,
different category) — mitigated by repo names `dhruva-app`/`dhruva-website` and a
README disambiguation line. Store display name: **"Dhruva AI"**. Fallbacks
(Ekant/Antara/Charcha) not needed. Checkpoint H2 not triggered.

## Identity (designer proposal, reviewer-critiqued, one fix pass)

Derived from the name's story — the pole star: constancy, night sky, quiet
guidance, self-reliance.

- **Canonical source:** `design-tokens.json` at repo root — consumed by Flutter
  `ThemeData` and fetched at build time by dhruva-website (pinned to a tag).
  Any color not from the tokens file is a bug.
- **Palette:** dark theme is the hero — midnight `#0E1220` background with
  star-gold `#EBBA47` primary; light theme recalibrated (deep bronze-gold
  `#8A5A16` primary on `#F7F8FC`), not hex-inverted. Secondary polaris-blue,
  tertiary ember. No purple, no Material seed defaults.
- **Typography:** Fraunces (display/headline/titleLarge — the myth) + Manrope
  (titleMedium→label — the tool); Noto Serif/Sans Devanagari fallbacks per role
  for Hindi. Token roles mirror Flutter TextTheme 1:1, with `heightMultiplier`
  precomputed for TextStyle.height.
- **Logo:** vertical-elongated 4-point star / compass-needle hybrid with
  concave Bézier waists and a 2px open pinhole at center (collapses to a dot at
  favicon size). Deliberately not the symmetric 8-point "AI sparkle".
- **Contrast:** every text-bearing pair computed ≥4.5:1 (WCAG AA); documented
  exceptions: `inversePrimary` dark (4.36:1, large-text/UI use only) and
  `outlineVariant` (decorative divider, M3-exempt from contrast minimums).

## Review trail

Reviewer verdict REQUEST_CHANGES (M3 token completeness: onSurfaceVariant,
container pairs, inverse/scrim/outlineVariant, surfaceTint, lineHeight units) →
designer fix pass closed all six findings → ratified.

## Consequences

- Flutter theme (Loop 1+) and website (Loop 12) build from the same JSON; a CI
  drift check on the website enforces it.
- Logo SVG assets to be produced from the geometry spec in
  orchestra/research/brand-proposal.md (Loop 11 icon/splash task).
