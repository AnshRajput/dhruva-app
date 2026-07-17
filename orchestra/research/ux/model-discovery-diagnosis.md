# Model discovery diagnosis: mobile-optimized / ranking / device-spec asks

Scope: read-only investigation of `features/models_hub/`, `data/hf_api/`,
`core/device_info/model_tier.dart`, `device_info_service.dart`. No code
changed. Answers three user asks: "show models optimised for mobile", "show
model ranking wise", "recommend models according to device spec". Notes
where delete-model (covered elsewhere) intersects.

## 1. What the user sees by default

`ModelsHubScreen` (`lib/features/models_hub/ui/models_hub_screen.dart:47-53`)
opens on the **Search** tab. It is NOT a blank search box: `ModelSearchController.build()`
calls `_fetch('')` (`lib/features/models_hub/state/model_search_controller.dart:55-56`),
which hits `HfApiClient.searchGgufModels(query: '')` with the default
`sort: 'downloads'` (`lib/data/hf_api/hf_api_client.dart:28-30`). So the
default list **is** ranked — by raw HF download count, globally, no query.

Above that list, `RecommendedRail` renders whenever `state.query.isEmpty`
(`models_hub_screen.dart:194-195, 200, 214`) — a curated 5-model "Recommended
for your device" strip (`recommended_rail.dart:1-6, 34-37`) sourced from
`starterModelCatalog` (`recommended_models_provider.dart:30-56`).

So the real default view = [curated device-aware rail] + [HF
popularity-ranked full list]. Better than "blank search box," but the two
halves behave very differently (see §2-3).

## 2. Mobile-optimized: gap

`model_tier.dart` (`classifyModelTier`, lines 42-51) is real, tested,
pure logic: bucket by GGUF file size (≤1.2GiB / ≤3GiB / larger) → RAM floor
(4/6/8 GiB) → comfortable/possible/notRecommended, using `_comfortableMultiplier`
(1.5x floor) for the "comfortable" cut.

It is applied in exactly two places:
- `recommended_rail.dart:52-58` — per starter-catalog card, using the
  catalog's hardcoded `approxSizeBytes`.
- `model_detail_screen.dart:127-131` — per quant file, once the user has
  drilled into a specific repo and `getRepoFiles` has returned real sizes.

It is **not** applied to the main search results list. `HfModelSummary`
(`hf_model_summary.dart:8-19`) carries `id`, `likes`, `downloads`, `tags`,
`pipelineTag`, `license` — no size, no param count. `ModelListTile`
(`model_list_tile.dart:17-53`) shows downloads/likes/license/gated chips
only. There is structurally no way to show a tier chip on a search row
today: HF's search endpoint doesn't return file size, and getting it means
walking each repo's file tree (`getRepoFiles`, `hf_api_client.dart:62-97`) —
an extra HTTP call per row.

So "mobile-optimized" is answered only for the 5-entry curated rail
(genuinely small models: 1-3B, ~770MB-2.4GB — `recommended_models_provider.dart:30-56`),
and not at all for the scrollable HF search results underneath, which can
surface arbitrarily large quantized repos (70B+ GGUFs are heavily downloaded
on HF too) with zero signal that they won't run on a phone.

## 3. Ranking: gap

Sort is `downloads` (`hf_api_client.dart:30`) — global HF popularity across
*all* GGUF repos regardless of size. There is no secondary ranking by
mobile-suitability, no re-sort combining popularity + tier. "Ranking wise"
today literally means "what's most downloaded on HF this includes 70B
models," not "best small models ranked."

The curated rail doesn't rank either — `starterModelCatalog` is rendered in
fixed declaration order (`recommended_rail.dart:45-49`, iterates
`starterModelCatalog` directly), each card gets a tier chip but cards are
never reordered or filtered by tier. A `notRecommended`-tier starter model
sits in the same horizontal position it would on a phone with 16GB RAM.

## 4. Device-spec recommendations: partial

Real signal exists: `DeviceInfoService.getMemoryInfo()`
(`device_info_service.dart:28-31`, real impl at 46-60 via `device_info_plus`,
verified against plugin source per the doc comment) is wired through
`deviceMemoryProvider` (`recommended_models_provider.dart:62-64`) into the
rail (`recommended_rail.dart:25, 52-59`). Each rail card's tier chip is a
genuine per-device computation, not a static label.

Gap: it's used to **annotate**, not to **filter or reorder**. All 5 starter
models always show, regardless of whether the device can run them
comfortably. There's no "recommended for YOUR device" view that actually
prunes/ranks the catalog by the detected RAM tier — the rail's copy
("Recommended for your device") overclaims relative to what the code does
(shows everything, decorates with a verdict).

The main HF search list has zero device-spec awareness (§2) — RAM is never
consulted there at all.

## 5. Curated catalog: fragmented, not one coherent surface

Three separate catalogs/experiences today:
- **GGUF text models**: HF live search, sort=downloads, no size/tier data
  in the list (§2-3).
- **Starter rail**: 5 hardcoded repos (`recommended_models_provider.dart:30-56`,
  doc comment calls a catalog service "YAGNI today"), tier-annotated but not
  filtered/ranked, shown only above an empty query.
- **Voice catalog**: `lib/voice/voice_model_catalog.dart` — separate `_VoiceTab`
  in `ModelsHubScreen` (models_hub_screen.dart:51, 68-107), own curated list
  keyed by `VoiceModelRole` (asr/tts/vad), downloaded through the same
  `DownloadManager` but with **no RAM/tier check at all** — `classifyModelTier`
  is never called on voice entries.
- **Vision**: no curated catalog exists. Grepped the codebase — only
  file-level `mmproj` detection in `hf_api_client.dart` (repo-tree walk finds
  mmproj files for VLM support) and `quant_parser.dart`. No `vision_model_catalog.dart`
  analog to the voice one.

So there is no single "these are great on-device models, ranked, tiered to
your phone" experience — three different surfaces, two different
device-awareness levels (rail: yes-but-decorative; voice: none), one gap
(vision).

Delete-model: not investigated here (covered by another agent) — worth
noting the `_InstalledTab` delete flow (`models_hub_screen.dart:257-337`) is
unrelated to discovery and doesn't need to change for any of this.

## 6. Fix plan — buildable on what exists, smallest lever first

**A. Make the rail actually filter/rank by device tier (cheap, no new infra).**
`recommended_rail.dart`'s `itemBuilder` iterates `starterModelCatalog` in
fixed order (line 45). Change: once `deviceMemoryProvider` resolves, sort
the list by `classifyModelTier` result (comfortable → possible →
notRecommended) before building cards, same `classifyModelTier` call already
made per-card (lines 52-58) — just hoist it to a pre-sort. Optionally drop
`notRecommended` entries below a "not recommended for your device — show
anyway" collapsed section rather than hiding them outright (gated-model
precedent: show but warn, don't silently remove). This alone answers
"recommend models according to device spec" for the curated set — it's the
lowest-risk fix since the data (tier, RAM) is already flowing.

**B. Grow the curated catalog so "ranking wise" + "mobile-optimized" can be
answered without touching the raw HF list.** `starterModelCatalog` is 5
entries in one size class range (1-3B/mobile-friendly by construction, per
its own doc comment). Add a few more verified entries across tiers (per
Amendment 4c precedent — verified repo id + confirmed Q4_K_M size, same
process as the existing 5) so the "default, ranked, device-tiered,
mobile-suitable" view in the diagnosis brief is just this rail, sorted per
(A), made a little deeper. This is the buildable version of "one coherent
curated experience" — stays a `const` list, no catalog service, matches the
existing YAGNI call in the file's doc comment.

**C. Cheap heuristic ranking signal on the raw HF list (optional, approximate).**
`HfModelSummary` has no size field and adding one means an extra HTTP call
per search row (`getRepoFiles`) — expensive against HF's rate limits
(`hf_api_client.dart` already handles 429 explicitly, line 230-234) and not
worth doing for every row of every scroll. Cheaper partial fix: regex the
repo `id` (e.g. `bartowski/Llama-3.2-1B-Instruct-GGUF` → `1B`) for a param-count
token most GGUF repo names already carry, use it to client-side badge/sort
"small" vs "large" in the existing search list — zero extra network calls,
approximate (repos that don't encode size in the name get no badge, sort
last/neutral). Mark as a heuristic ceiling in code
(`// ponytail: name-regex heuristic, replace with real size once search
results carry it`) — do not build size-fetching infra for this.

**D. True per-row tier chips on search results — flag as follow-up, not now.**
Would need `getRepoFiles` (or a smaller HEAD-based size probe) per visible
row, lazily on scroll. Real cost/latency/rate-limit tradeoff; out of scope
for a v0.1.0-alpha hardening pass. Note it so it isn't silently forgotten.

**E. Voice catalog: same tier check, one call site.** `voice_model_catalog.dart`
entries carry `downloadSizeBytes` already (line 39) — wiring
`classifyModelTier` into `VoiceModelTile`/`voice_models_controller.dart` the
same way the rail does is a same-shape, small change, not a new pattern.
Out of this diagnosis's asks (mobile-optimized/ranking/device-spec are about
the GGUF/text flow) but flagged since it's the same gap in a sibling
surface.

**F. Vision catalog: doesn't exist.** Not a discovery-ranking bug per se —
there's nothing to rank. Flag as a real gap if vision model support ships
before a curated catalog does; out of scope for this diagnosis.

No fix here requires new dependencies, a catalog service, or a schema
change — (A) and (B) reuse `classifyModelTier` + `starterModelCatalog`
exactly as they're already called; (C) is a regex; (D)/(E)/(F) are flagged,
not built.
