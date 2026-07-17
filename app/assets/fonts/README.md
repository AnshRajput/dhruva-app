# Bundled fonts

Bundled as assets per Rule 5 (no runtime fetching — `google_fonts` is
forbidden). Pulled from `github.com/google/fonts` (the canonical Google Fonts
source repo), `main` branch, on 2026-07-17. All four are variable fonts —
one file per family covers every weight the tokens use; `pubspec.yaml`
declares each weight as a separate entry pointing at the same file, and
Flutter resolves it against the file's own `wght` axis.

| Family | File | License | Weights used | Source |
|---|---|---|---|---|
| Fraunces | `Fraunces-Variable.ttf` | OFL-1.1 (`OFL-Fraunces.txt`) | 500, 600 | `ofl/fraunces/Fraunces[SOFT,WONK,opsz,wght].ttf` |
| Manrope | `Manrope-Variable.ttf` | OFL-1.1 (`OFL-Manrope.txt`) | 400, 600 | `ofl/manrope/Manrope[wght].ttf` |
| Noto Sans Devanagari | `NotoSansDevanagari-Variable.ttf` | OFL-1.1 (`OFL-NotoSansDevanagari.txt`) | 400, 600 | `ofl/notosansdevanagari/NotoSansDevanagari[wdth,wght].ttf` |
| Noto Serif Devanagari | `NotoSerifDevanagari-Variable.ttf` | OFL-1.1 (`OFL-NotoSerifDevanagari.txt`) | 500, 600 | `ofl/notoserifdevanagari/NotoSerifDevanagari[wdth,wght].ttf` |

All four are SIL Open Font License 1.1 — free to bundle, modify, and
redistribute inside the app, including in a commercial context, provided the
font itself isn't sold on its own. Full license text for each family sits
alongside it in this directory (`OFL-*.txt`) for the license auditor.

Role → family mapping lives in `design-tokens.json` (repo root) and is
mirrored in `lib/core/theme/design_tokens.dart`: Fraunces for
display/headline/titleLarge (+ Noto Serif Devanagari fallback), Manrope for
titleMedium→label (+ Noto Sans Devanagari fallback).
