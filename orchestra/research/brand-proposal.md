# Brand proposal — Dhruva

Source of truth for the tokens below: `/Users/ansh/AppuInsideEngineering/dhruva-app/design-tokens.json` (v0.1.0). This document is the rationale; the JSON is what ships into Flutter `ThemeData` and the Astro site.

## a. Brand narrative

Dhruva is the boy who sat still until the sky organized itself around him, and the star he became: the one point in a turning night that every navigator can still find without a signal, a satellite, or anyone's permission. Every token group below is that story translated into a property. Color starts from **midnight**, the ramp the whole app lives inside — a deep, slightly warm-tinted navy rather than a cold neutral black, because a real night sky is never truly black; **starGold** is Dhruva himself, used sparingly and only where the app needs to be found (primary actions, the one fixed point in each screen), never smeared across the whole surface the way a "brand color wash" would defeat the metaphor of a *single* point of light. Secondary reuses the sky's own blue starlight for anything wayfinding-adjacent (links, active tabs — the small stars you steer by, not the pole star itself), and tertiary borrows an ember tone for warmth and resolve (the boy's tapasya, his inner fire) so the palette has three deliberate hues instead of the generic two-tone SaaS default. Dark is the literal night sky and therefore the default theme, tuned to be rich rather than merely "not light" (no `#000`, warm-tinted navy throughout); light is dawn after the vigil ends — recalibrated, not just inverted, so it never reads as an afterthought. Typography pairs an editorial serif (the myth, told) against a plain-spoken UI sans (the tool, used) — see section (c). Spacing, radius, and elevation stay quiet and regular, because Dhruva's whole story is about *not* needing drama to be noticed; motion settles rather than bounces, because a star that jiggled for attention would have missed the point of the story entirely.

## b. Logo mark concept — the fixed-point star

A four-point star, elongated on the vertical axis like a compass needle seated on true north — not the symmetric eight-point "sparkle" that has become AI-generic shorthand, and not a generic compass rose (no ring, no cardinal ticks, no N/S/E/W labels). Precise geometry, 64×64 viewBox, center at (32,32):

- **Four tips**, each a sharp point: N at (32, 4), E at (58, 32), S at (32, 60), W at (6, 32). Vertical span is 56px (4→60); horizontal span is 52px (6→58) — a small, deliberate 4px asymmetry so the mark reads as a needle pointing north, not a snowflake with four-fold symmetry.
- **Waist**: each tip is flanked by two base corners sitting 5px out from center along the perpendicular axis. For the N tip, the base corners are (27, 32) and (37, 32); rotate this pattern 90°/180°/270° for the other three tips.
- **Edges**: each of the 8 edges (base-corner → tip) is a single quadratic Bézier. The control point sits 40% of the way from the base corner toward the center, then is pulled 3px further inward than the straight-line midpoint — this is what pinches the waist concave and gives the silhouette its glint, rather than a rigid diamond/rhombus.
- **The pinhole (the one non-obvious move)**: where the four base corners nearly converge at the exact center, do *not* close the shape solid. Cut a 2px-radius circular aperture at (32,32), filled with the background color behind the mark. The star has a still, empty point at its own core — the fixed point inside the fixed point. It also does double duty at small sizes: shrink the mark to a 16px favicon and the four spikes disappear into the corner radius while the pinhole reads as a single dot — the mark degrades gracefully into a literal period, the pole star reduced to the smallest true thing it is.
- **Fill**: solid `color.brand.starGold.400` (`#EBBA47`) on dark surfaces, solid `color.light.primary` (`#8A5A16`) on light surfaces. No gradient fill — flat color only, per the house ban on gradient-as-decoration.
- **Stroke**: none in the default lockup. Add a 1.5px stroke in `midnight.900` only for the rare case of the mark sitting on a busy photographic background (e.g. an app-store screenshot's cover image), never in-app.
- **Clearspace**: minimum clearspace on all sides equals the vertical tip-to-tip span ÷ 4 (14px at this scale) — keeps the mark from ever touching a container edge or being crowded by adjacent UI.

## c. Typography rationale + Devanagari strategy

**Display / headline / titleLarge → Fraunces.** Fraunces is a variable serif built for editorial warmth without tipping into costume-drama — soft ball terminals, slightly old-style figures, real personality at large sizes. It carries the *myth* register: onboarding copy, empty states, the app name itself, screen titles. It is deliberately not a geometric sans at this size — a mythological pole star told in the same face as a settings toggle would flatten the one thing that makes this app's story land.

**titleMedium/Small, body, label → Manrope.** Once the story has done its job, the interface needs to get out of the way: Manrope is a humanist-geometric sans with generous x-height and calm rhythm at 12–16px, the sizes where a chat UI actually lives. It reads as considered rather than default (Inter was ruled out specifically for being the reflexive AI-product choice) while staying completely unfussy at small sizes and in dense token/s-per-second readouts.

**Devanagari strategy (verified, not assumed):** neither Fraunces nor Manrope ships Devanagari glyphs, so Hindi strings never fall back to a system default — each role in `design-tokens.json` carries an explicit `devanagariFallback`. Fraunces-driven roles (display/headline/titleLarge) fall back to **Noto Serif Devanagari** — matching serif-for-serif, so a Hindi headline keeps the same editorial weight as its English counterpart instead of a jarring sans substitution mid-hierarchy. Manrope-driven roles (titleMedium/Small, body, label) fall back to **Noto Sans Devanagari** — the Noto family exists specifically to be a robust, metrically-considered cross-script pairing partner for exactly this situation, so x-height and stroke weight stay visually consistent with Manrope at UI sizes. Both fallbacks are real, currently-available Google Fonts families, loadable identically via `google_fonts` in Flutter and the Google Fonts CDN/self-host on the Astro site — the same token drives both platforms with no additional mapping layer.

## d. Hero / onboarding screen description

The first screen is near-black midnight (`#0E1220`) filling the entire frame, unbroken by any card or container; a thin field of pin-prick stars (the `midnight.400`–`600` ramp at low opacity, static — no parallax gimmick) recedes into the top two-thirds of the screen, and the fixed-point star mark sits alone in the exact optical center at rest, rendered large (roughly 96px), holding for a beat before a single line of Fraunces headline text fades up beneath it: "Your AI. Your phone. Nobody else's business." A second, smaller Manrope line follows half a second later, quieter (`onBackground` at reduced opacity, `bodyLarge`): "No account. No cloud. No one watching." One primary button in `starGold.400` anchors the bottom third — "Get started" — and nothing else competes with it: no secondary "learn more" link, no skip-in-the-corner affordance, no scroll-hint chevron. The whole screen is built to hold still, exactly like the thing it is named after.

## e. Contrast verification (WCAG 2.1)

Computed via relative-luminance formula (not eyeballed) — script: `luminance = 0.2126·R + 0.7152·G + 0.0722·B` (linearized sRGB), `contrast = (L_light + 0.05) / (L_dark + 0.05)`. Threshold: **≥4.5:1** for normal text; **≥3:1** for large text (≥24px / ≥19px bold) and non-text UI component boundaries — pairs meeting only the 3:1 bar are labeled explicitly.

### Dark theme (default)

| Pair | Foreground | Background | Ratio | Verdict |
|---|---|---|---|---|
| onBackground / background | `#EDEFF8` | `#0E1220` | 16.25:1 | AA text PASS |
| onSurface / surface | `#EDEFF8` | `#1F263D` | 13.05:1 | AA text PASS |
| onSurface / surfaceVariant | `#EDEFF8` | `#2D385C` | 9.99:1 | AA text PASS |
| primary / onPrimary | `#EBBA47` | `#0E1220` | 10.34:1 | AA text PASS |
| secondary / onSecondary | `#8FB0DE` | `#0E1220` | 8.38:1 | AA text PASS |
| tertiary / onTertiary | `#C97B5A` | `#21120A` | 5.59:1 | AA text PASS |
| error / onError | `#E5484D` | `#1A0506` | 5.02:1 | AA text PASS |
| success / onSuccess | `#4FAE8A` | `#0A1F17` | 6.35:1 | AA text PASS |
| warning / onWarning | `#E2933A` | `#241505` | 7.15:1 | AA text PASS |
| onBackground / primaryContainer | `#EDEFF8` | `#3F3212` | 10.92:1 | AA text PASS |
| outline / surface | `#647199` | `#1F263D` | 3.11:1 | **3:1 UI-component pair** — non-text border/divider only, not for text |
| outline / background | `#647199` | `#0E1220` | 3.88:1 | **3:1 UI-component pair** |

### Light theme

| Pair | Foreground | Background | Ratio | Verdict |
|---|---|---|---|---|
| onBackground / background | `#12182B` | `#F7F8FC` | 16.61:1 | AA text PASS |
| onSurface / surface | `#12182B` | `#FFFFFF` | 17.63:1 | AA text PASS |
| onSurface / surfaceVariant | `#12182B` | `#E9ECF5` | 14.93:1 | AA text PASS |
| primary / onPrimary | `#8A5A16` | `#FFF8E8` | 5.58:1 | AA text PASS |
| secondary / onSecondary | `#35538F` | `#F5F8FF` | 7.09:1 | AA text PASS |
| tertiary / onTertiary | `#9C4A2E` | `#FFF4EE` | 5.66:1 | AA text PASS |
| error / onError | `#C4373A` | `#FFFFFF` | 5.31:1 | AA text PASS |
| success / onSuccess | `#1F7A5C` | `#F2FBF7` | 4.98:1 | AA text PASS |
| warning / onWarning | `#A85E12` | `#FFF6EC` | 4.60:1 | AA text PASS |
| onBackground / primaryContainer | `#12182B` | `#FCEFD2` | 15.46:1 | AA text PASS |
| outline / surface | `#7C8598` | `#FFFFFF` | 3.71:1 | **3:1 UI-component pair** |
| outline / background | `#7C8598` | `#F7F8FC` | 3.49:1 | **3:1 UI-component pair** |

**Compromises, stated plainly:** the two `outline` pairs in each theme are held to the 3:1 non-text threshold, not 4.5:1 — this is correct per WCAG 2.1 SC 1.4.11 (non-text contrast) since `outline` is only ever used for dividers, input borders, and other non-text UI boundaries in this token set, never for rendering text. Every pair that carries text meets or exceeds 4.5:1. `onPrimary` in the dark theme intentionally equals `background` (`#0E1220`) rather than a separate near-black — same hex, reused on purpose, still verified independently at 10.34:1.
