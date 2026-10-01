# Dhruva — Product Review & Council Verdict

**Date:** 2026-09-11 · **Method:** facts extracted from `dhruva-app`, `dhruva-website`, the `orchestra/` state files and memory notes, then reviewed by a 3-agent Agents Council. Full transcript: `PRODUCT-REVIEW-COUNCIL-TRANSCRIPT-2026-09-11.md`.

---

## Verified state

- Open-source Flutter app running quantized LLMs **100% on-device** — no network inference, no telemetry, no cloud fallback. Chat, voice (whisper.cpp STT + sherpa-onnx TTS + VAD), vision (SmolVLM2), embeddings, model hub with Hugging Face search.
- **209 commits (app) + 26 (website).** v0.5.0+94, Apache 2.0. Website live at `dhruvaai.vercel.app`.
- **Distribution: Firebase App Distribution to 2 internal testers.** Not on Play Store or App Store.
- **No pricing, no payment provider, no users, no revenue.**
- Measured 64.9 tok/s for SmolLM2-135M **on macOS Metal**. Android is CPU-only (AAR wired, no GPU offload). iOS xcframework vendored, ad-hoc single device.
- `orchestra/RISKS.md` tracks 14 risks; R1, R9, R11, R14 all resolve to one blocker: **no physical device.**
- Blocked for launch: H3 (Android upload keystore + CI token), H4 (iOS tester UDIDs), on-device QA. Loops 8–14 (image gen, RAG, toolbox, AI News, release pipeline) unshipped.

---

## Council verdict

> **The single most damning fact: 906 unit tests, 0 device tests. He has never run this app on a phone.** The entire value proposition is "LLMs run well on your phone" and that claim is **100% unverified**. A used 8GB Android is ₹8,000–12,000 — and he probably already owns a phone. **This is a ₹0–12,000 unblock gating a 209-commit product.**

**It rhymes with ParkOS but is a different failure mode.** ParkOS never asked anyone to pay; **Dhruva never asked anyone to *use* it.** Both are "the loop kept closing on engineering because engineering is the part that gives clean feedback."

**Verdict: 10 days to public launch, then let data decide. Do not budget 6 months.** Dhruva is not a revenue product. It is three other real things: a **shipped credential** in on-device AI (the scarcest skill on his résumé and the one that converts to paid work), an **extractable asset** (the `engine_bindings`/voice/vision layer is genuinely unavailable in the Flutter ecosystem), and an **audience asset that costs ₹0/month** because there are no servers.

### The strategic threat to price in now

**Apple shipped the Foundation Models framework in iOS 26 — any app can call a system on-device ~3B model for free. Android has Gemini Nano via ML Kit on flagships. On-device inference has been commoditized by the platform vendors on new hardware.** Dhruva's remaining defensible ground is precisely: **bring-your-own-model, uncensored, swappable, works on cheap/old Android, works with no SIM, works in Hindi.** Lean all the way into that and stop competing on "on-device" as a generic feature — that fight is over.

### The arithmetic

| Case | Assumption | Result |
|---|---|---|
| Realistic | 5,000 installs × 2% × ₹499 × 0.70 store cut | **₹35,000/yr** — noise |
| Optimistic | 30,000 installs × 3% × ₹799 × 0.70 | **₹5.0 lakh/yr** — still not a salary |
| Ceiling | *The* on-device app for a niche, 2–3 years | ₹15–30 lakh/yr — a different life decision |

**The model that actually fits: services pulled through by the artifact.** One on-device-AI contract at ₹2–6 lakh (India) or $10–20k (remote) equals **10–30 years of this app's IAP revenue.** The app's job is lead generation, not ARR. Second line: extract the inference layer as a `flutter_local_llm` package — 3 companies × $2,000 > everything the consumer app will ever earn.

---

## Where the council split

Very little. **All three independently rejected any paid tier or subscription**, and one pre-registered a disagreement with anyone proposing one. The differences are only in the ask:

- **A:** GitHub Sponsors + a "Support" row + a **"Hire me" consulting link** (the actual revenue channel, 30 minutes of work). An iOS-only $9.99 Pro *later*, gating strictly non-core things (extra TTS voices, benchmark history, themes) — never a model, never chat.
- **B:** Free forever, no paid tier at all — *"you'd be charging for convenience while advertising the bypass."* Add a Support screen with Sponsors + a UPI QR **and an unmissable "Need this in your product? Let's talk" link.**

**Both framed the same warning:** *"don't do free-forever-with-no-ask — that's the ParkOS mistake in reverse. The failure mode across this whole portfolio is never putting a door in the wall."*

---

## Features to ADD — ranked

| # | Feature | Why | Est. |
|---|---|---|---|
| 1 | **Share-sheet target** ("Share to Dhruva" → summarize / translate / rewrite / extract, offline) | The difference between an app used once and one used daily. Small models are *good* at these four verbs and *bad* at open-ended chat — this inverts the product around what the tech actually does well. | 3–5 d |
| 2 | **First-run on-device benchmark** — real tok/s + battery/thermals on *this* phone; label the catalog by measured throughput, not RAM heuristics | Turns his biggest risk into his strongest trust feature and only defensible differentiator. Also generates the crowd-sourced benchmark dataset that becomes the marketing asset. | 2–3 d |
| 3 | **Fast first answer** — bundle/fast-path a ~300MB Q4 0.5B model so install→first token is **<2 min** | A 2GB download before first value kills 60–90% of installers. This single metric decides whether 5% or 40% convert. | 2 d |
| 4 | **Sideload GGUF** from file or URL | r/LocalLLaMA's #1 demand; without it power users bounce. | 0.5 d |
| 5 | **Indic catalog + Hindi/Hinglish voice** (Sarvam, Airavata, Navarasa; Whisper-Hindi) | Genuine unfair advantage. *"AI that works with no internet, in Hindi, on a ₹15,000 phone"* is a story no competitor can tell. | 1 wk |
| 6 | **Document RAG (Loop 9)** — keep it | The strongest reason a *normal* person uses private AI: medical report, legal doc, salary slip, without uploading it anywhere. | 1–2 wk |
| 7 | Android quick-settings tile / notification input | Cheap daily-use surface. | 2 d |

**CUT NOW — ~4 weeks of planned work deleted, which is 4 weeks earlier to real users:**
- **Loop 8 image generation** — biggest waste on the roadmap. SD on mobile CPU is 1–3 min/image, huge binary, off-strategy. Delete the loop.
- **Loop 10.5 AI News** — an RSS reader that needs network, inside an app whose pitch is no network. Strategically incoherent.
- **Loop 10 Toolbox** — undefined; defer until users ask. **Loop 11 Arena** — Playground covers 80%; fold the useful 20% into #2.

## Per-surface improvements

- **Onboarding (weakest surface by far).** Weak: "pick model → download 2GB → chat." Good: install → tiny model already present → real answer in 90 seconds → *then* offer bigger models with measured tok/s for this device. Instrument with **local-only counters the user can view** (no telemetry) and have testers read them out.
- **Model catalog honesty.** Weak: "Comfortable / Possible" from RAM tiers. Good: *"Qwen2.5-1.5B — 11 tok/s on your Redmi Note 13, ~8% battery per 10 min."* Nobody else does this, and it is unfakeable without doing the benchmark work.
- **Android acceleration — R8 is mislabelled.** "Closed via wiring the AAR, CPU-only, no GPU offload" isn't closed, it's *accepted*, and it's the central product risk, not medium. If a 3B Q4 lands at 3–5 tok/s, llama.cpp's OpenCL (Adreno) or Vulkan backend is existential; at 10–12 tok/s, ignore it. **Decide from a measurement, not a risk register.**
- **Positioning fallback.** If real mid-range numbers are bad, the honest product shrinks to 0.5B–1.5B models doing short tasks — i.e. the share-sheet product. **Discover this in one day, not after Loop 14.**
- **Website.** Weak: a features page. Good: a 15-second **airplane-mode video** above the fold, the live crowd-sourced benchmark table (phone → model → tok/s), store buttons. The benchmark table is the page people link to.
- **GitHub README.** Animated GIF in the first screenful, benchmark table, install links, and one paragraph on the isolate-lifecycle/leak work — **that paragraph is what makes an engineer email him about contract work.**
- **Build/CI.** Debug keys after 209 commits is the tell. Generating an upload keystore is a 30-minute task that has blocked launch for six weeks.

## Top 1%

1. **Honesty about performance** — everyone lists models; nobody tells you what they do on *your* phone.
2. **Time-to-first-token from cold install under 2 minutes** — in practice this is the whole retention curve.
3. **Designed around what small models are actually good at** (summarize/translate/rewrite/extract) rather than pretending to be ChatGPT.
4. **Never OOMs, never loses a chat** — the R6 leak work is already best-in-class thinking; make it a stated guarantee.

**Unfair advantages:** he has built the hardest layer in the Flutter ecosystem — FFI + isolate lifecycle + a leak workaround upstream hasn't merged + vendored xcframework + AAR + multimodal mtmd + sherpa, **cross-platform from one codebase**. Competitors are single-platform (Private LLM = iOS, Layla/ChatterUI = Android). Plus **India / Indic / low-end device / genuinely offline**, which Western indies don't care about and the platform vendors underserve.

**Deliberately NOT:** cloud fallback · accounts · any telemetry · subscriptions · image generation · an agent framework · desktop · self-hosted model distribution · and notably **not** the companion/NSFW pivot — it's where the money in this category actually is, but it's a different product, an App Store liability, and it burns the trust brand that is the only moat.

## Post-dev plan — reject the premise; "done" is 10 days from now

- **Day 0 (today).** Get an Android phone in hand (₹0 if owned, else ₹8–12k used, 8GB). Install the debug APK. Run every shipped feature. Write down real tok/s, thermals, battery drain, every crash. **This closes R1, R9, R11 and R14 in an afternoon.**
- **Day 1.** Generate the upload keystore, wire signing, build a signed AAB (30–60 min — this is H3, and it has cost six weeks). Pay the Play Console fee. **Recruit 12 closed-testing testers today** — if the 12-testers-for-14-continuous-days rule applies to the account, that clock *is* the launch date and every day not started is pure slip regardless of code.
- **Days 2–3.** Fix what the phone revealed. It will reveal a lot.
- **Days 4–5.** Record the airplane-mode demo (mode toggle visible on screen). Rewrite the README with the GIF on top. Draft the r/LocalLLaMA benchmark post.
- **Days 6–8.** Ship the first-run benchmark and the fast-first-answer path.
- **Days 9–10.** Play Store production submission. Post the benchmark data to r/LocalLLaMA; Show HN three days later.
- **iOS: deprioritise.** $99/yr, review friction, and Apple's own free on-device model competing directly. Android first — it's also where the India story lives.

## Marketing

**The message. Not "privacy"** — twenty years of evidence says consumers don't buy privacy, and Apple/Google now ship free on-device models, so privacy is table stakes. Sell the concrete consequence:
- **"Works in airplane mode."** (flights, metro, trains, villages, hospitals, basements)
- **"No subscription. No account. No internet. Ever."**
- **"Your medical report never leaves your phone."**

1. **r/LocalLLaMA — highest leverage by a wide margin.** They punish promo and reward data, so lead with data: *"I benchmarked 12 GGUF models across N Android phones — real tok/s, thermals, battery drain per model. Table inside. Tool is open source."* App link at the bottom. **Also reply to every "which mobile app for local LLMs?" thread — there's one most weeks, and that reply channel alone is worth more than any launch post.**
2. **Show HN**, one shot: *"Show HN: Dhruva – offline LLM chat for Android, bring your own GGUF."* Needs the GIF.
3. **GitHub as the marketing surface** + PRs to `awesome-llm`, `awesome-flutter`, `awesome-local-llm`. Free, permanent, compounding.
4. **30-second vertical video: airplane mode ON, phone answering questions.** That single visual *is* the pitch.
5. X/Twitter (Flutter + local-LLM communities, built on benchmark data not screenshots) · r/india, r/developersIndia once Indic models ship · Product Hunt last, expect little.

**First 100 users:** ~20 from r/LocalLLaMA replies, 20 Show HN, 20 GitHub/awesome-lists, 20 Flutter Discord/X, 20 personal network. **Ask each of the first 30 for exactly one thing: their phone model and measured tok/s.** That closes his highest-severity risks *and* builds the benchmark dataset that becomes his best marketing asset — one ask, three payoffs.

## Pricing

**Free, Apache 2.0, no paid tier.** The arithmetic doesn't clear the noise floor (₹25k–70k/yr), a paywall poisons the only distribution channel he has (r/LocalLLaMA and HN will punish it), and the source is public so he'd be *"charging for convenience while advertising the bypass."*

**Name the alternative return: consulting and employment leads in on-device/edge AI** — ₹1.5–4L/month domestically, $80–150/hr internationally. The conversion asset is the **extracted Flutter package plus a technical writeup**, not the app. Budget one week for it; higher expected value than every monetisation option combined. Target for the 90-day window: **10 B2B conversations, 1 contract at ₹3–8L** — 12–30× the best-case app revenue from the same asset.

**But put a door in the wall:** GitHub Sponsors + UPI QR on a Support screen, and a prominent **"Need this in your product? Let's talk"** with his email on the website and in the app's About screen.

## Kill criterion

**By 2026-12-15 (90 days after public launch): if Dhruva has under ~1,000–5,000 installs AND under 20% D7 retention AND zero inbound consulting/B2B conversations → stop all work.** Archive the app repo, **publish the extracted inference package to pub.dev and keep maintaining only that**, write the technical postmortem, leave the app live and unmaintained as a portfolio piece.

**The earlier and more damning kill: if it hasn't *launched* by ~2026-10-10**, the ParkOS pattern repeated and the decision is about him, not the product.

## Three things to do today — none require a line of code, which is exactly why they haven't happened

1. **Order/find the Android phone.** The highest-information-per-rupee purchase in the entire portfolio, deferred for six weeks.
2. **Check the Play Console account type** — the 12×14 testing gate determines the whole launch calendar.
3. **Send 10 B2B outreach messages this week, before the code is finished.** If nobody replies, the B2B thesis — which is the *entire* monetary case — is wrong and the kill criterion should tighten.
