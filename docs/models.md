# Models & the Curated Catalog

← [Knowledge Base](README.md)

## Curated over comprehensive

The default Models screen shows a small, hand-verified catalog of GGUF models that
genuinely run on phones — each with a friendly name, a one-line "best for…", size,
a device verdict, and **one** download button that auto-picks the right quant. No
cryptic `bartowski/…` repo rows, no quant menus in the default flow.

The raw Hugging Face firehose is still reachable behind an explicit
**"Search all of Hugging Face (advanced)"** button, which filters to
mobile-runnable GGUF (small params + a Q4-class quant + size within the device tier).

Curated starters (Q4_K_M unless noted): Llama-3.2 1B/3B Instruct, Qwen2.5
0.5B/1.5B/3B Instruct, Gemma 2 2B, Phi-3.5-mini, SmolLM2 1.7B, TinyLlama 1.1B, a
vision model (SmolVLM / Qwen2-VL 2B with `mmproj`), and the voice bundle. Each entry
is pinned to a known-good repo + quant so downloads "just work."

## Device tiers

`classifyModelTier` (in `core/device_info/model_tier.dart`) answers "will this run
well here?" from the model's file size and the device's RAM. It's pure — no I/O — so
it's cheap to call per card and fully unit-tested.

**RAM floors by file-size class** (binary GiB, marketed capacity):

| Model file size | Class | RAM floor |
|-----------------|-------|-----------|
| ≤ 1.2 GiB | ~1B | **4 GiB** |
| 1.2 – 3 GiB | ~3–4B | **6 GiB** |
| > 3 GiB | 4B+ | **8 GiB** |

**Verdict** (with `RAM` = device RAM, `floor` = the floor above):

- `notRecommended` — `RAM < floor` (loading may OOM)
- `possible` — `floor ≤ RAM < floor × 1.5` (meets the floor, little headroom)
- `comfortable` — `RAM ≥ floor × 1.5`

Two wrinkles handled in code:

- **Vision models** add the `mmproj` projector's size to the model's before
  classifying — both load into memory together.
- **Reported RAM is rounded up to the next whole GiB.** The OS reports *less* than
  marketed capacity (kernel + GPU carve-outs eat ~5–20%), so a nominal 4 GB phone
  reads ~3.7 GiB and would otherwise fail its own floor. `nominalRamBytes()` ceils
  back to the marketed tier (4 / 6 / 8 / 12 GiB).

## How the catalog uses tiers

The [Models Hub](features.md#models-hub--featuresmodels_hub) segments the curated
list: everything **not** `notRecommended` goes under *"Runs great on your phone"*,
sorted best-tier-first then smallest, and the top pick gets the **Recommended**
badge (smallest comfortable model = fastest time to first chat). `notRecommended`
models collapse into a *"Larger models"* group. When device RAM is unknown, nothing
is judged and all models stay in the main list.

## Adding a curated model

1. Add an entry to the starter catalog (`features/models_hub/state/`), pinning a
   known-good repo id, quant, and the approximate file size (drives the tier).
2. Verify it actually downloads and chats on a device/emulator — this is a
   [test-on-device](development.md#test-on-device-before-every-deploy) requirement,
   not a paper change.
3. Add/adjust a widget test if the catalog's segmentation behavior is affected.

## RAM guidance (rule of thumb)

- **1B models** → 4 GB+ RAM
- **3–4B models** → 6 GB+ RAM
- **7B+ models** → 8 GB+ RAM
