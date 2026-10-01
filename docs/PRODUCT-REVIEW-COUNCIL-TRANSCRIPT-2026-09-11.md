

======================================================================
FROM: Claude
======================================================================

# Claude — Dhruva review

I'm first to respond, so no disagreements to register yet. One up-front reframe that colours every answer below.

**The single most damning fact in this brief: 906 unit tests, 0 device tests. He has never run this app on a phone.** The entire value proposition is "LLMs run well on your phone" and that claim is 100% unverified. R1, R9, R11, R14 all resolve to the same one-line blocker: *no physical device*. A used 8GB Android (Poco/Redmi) in India is ₹8,000–12,000, and he almost certainly already owns a phone. This is a ₹0–12,000 unblock gating a 209-commit product.

This is a *different* failure mode than ParkOS, but it rhymes. ParkOS: never asked anyone to pay. Dhruva: never asked anyone to *use it*. Both are "the loop kept closing on engineering because engineering is the part that gives clean feedback." Loops 8–14 are 6 more weeks of building on top of an unmeasured foundation.

---

## 1. Worth continuing? — Yes, but reclassified, and NOT for 6 months

**Verdict: 10 days to public launch, then let data decide. Do not budget 6 months.**

Dhruva is not a revenue product. It is three other things, all real:
1. **A shipped credential** in on-device AI — the scarcest engineering skill on his résumé and the one that converts to paid work.
2. **An extractable asset** — the `engine_bindings`/voice/vision layer is genuinely unavailable in the Flutter ecosystem.
3. **An audience/top-of-funnel** that costs ₹0/month to keep alive (no servers).

**What would have to be true for it to deserve another 6 months** — measured 90 days after public launch, need 2 of 3:
- ≥10,000 installs
- D7 retention ≥20%
- ≥3 inbound "can you build this for us" enquiries

Fewer than 2 of 3 → freeze feature work, keep the repo + website live as a portfolio piece (zero marginal cost), move on. Don't delete; there is nothing to gain from deleting and real option value in leaving it up.

---

## 2. Will it make money? — Do the arithmetic

**Realistic (median) case, 12 months post-launch:**
- Installs with genuine community distribution (r/LocalLLaMA + Show HN + GitHub, no budget): **3,000–8,000**. Take 5,000.
- One-time IAP conversion for a niche free-utility app: **1–3%**. Take 2% → 100 buyers.
- ₹499 × 100 × 0.70 (store cut) = **₹35,000/year.** Noise.

**Optimistic case (post hits front page, sustained community presence):**
- 30,000 installs × 3% × ₹799 × 0.70 = **₹5.0 lakh/year (~$6k).** Still not a salary.

**Ceiling case (becomes *the* on-device app for a specific niche over 2–3 years, Layla-style):**
- **₹15–30 lakh/year.** Achievable but requires being #1 in a niche and sustained multi-year focus. That is a different life decision, not a next-quarter plan.

**The revenue model that actually fits this product and this founder:** *services pulled through by the artifact.* One on-device-AI contract at ₹2–6 lakh (India) or $10–20k (remote) equals **10–30 years of this app's IAP revenue.** The app's job is lead generation, not ARR. Price the effort accordingly: don't spend 6 months to earn ₹35k; spend 10 days to earn a credential that closes one contract.

Second real line: extract the inference layer as `flutter_local_llm`, Apache-licensed with paid integration support. 3 companies × $2,000 = $6,000 > everything the consumer app will ever earn.

---

## 3. Features to ADD — ranked by (value × ease)

| # | Feature | Why it matters | Estimate |
|---|---|---|---|
| 1 | **Share-sheet target** (Android intent filter + iOS Share Extension): "Share to Dhruva" → summarize / translate / rewrite / extract, offline | This is the difference between an app used once and one used daily. Small models are *good* at these four verbs and *bad* at open-ended chat. Inverts the product around what the tech actually does well. | **3–5 days** |
| 2 | **First-run on-device benchmark** — measure real tok/s + battery/thermals on *this* phone, label the catalog by measured throughput not RAM heuristics | Turns his biggest risk (R1/R9) into his strongest trust feature and only defensible differentiator. Also generates the crowd-sourced benchmark dataset that becomes the marketing asset. | **2–3 days** |
| 3 | **Fast first answer** — bundle or fast-path a ~300MB Q4 0.5B model so install→first token is <2 min | 2GB download before first value will kill 60–90% of installers. This single metric decides whether 5% or 40% convert. | **2 days** |
| 4 | **Sideload GGUF** from local file or arbitrary URL | r/LocalLLaMA's #1 demand; without it the power users bounce. | **0.5 day** |
| 5 | **Indic model catalog + Hindi/Hinglish voice** (Sarvam, Airavata, Navarasa; Whisper-Hindi STT; offline translate) | Genuine unfair advantage. No Western indie cares; platform vendors underserve it. "AI that works with no internet, in Hindi, on a ₹15,000 phone" is a story no competitor can tell. | **1 week** |
| 6 | **Document RAG (L9)** — keep it | Strongest reason a *normal* person uses private AI: medical report, legal doc, salary slip, without uploading it anywhere. | **1–2 weeks** |
| 7 | Android quick-settings tile / persistent notification input | Cheap daily-use surface. | **2 days** |
| 8 | Local markdown chat export | Trust signal, trivial. | **1 day** |

**CUT, now:**
- **L8 image generation** — biggest waste on the roadmap. SD on mobile CPU is 1–3 min/image, huge binary, bad UX, off-strategy. Delete the loop.
- **L10.5 AI News** — an RSS reader that needs network, inside an app whose whole pitch is no network. Strategically incoherent. Delete.
- **L10 Toolbox** — undefined. Defer until users ask.
- **L11 Arena** — Playground already covers 80%. Fold the useful 20% into #2 above.

That's ~4 weeks of planned work deleted, which is exactly 4 weeks earlier to real users.

---

## 4. Features to IMPROVE, per surface

**App — onboarding (weakest surface by far).**
Weak: "pick model → download 2GB → chat." Good: install → tiny model already there → real answer in 90 seconds → *then* offer bigger models with measured tok/s for this device. Instrument the funnel with local-only counters the user can view (no telemetry) and ask early testers to read them out.

**App — model catalog honesty.** Weak: "Comfortable / Possible" based on RAM tiers. Good: "Qwen2.5-1.5B — 11 tok/s on your Redmi Note 13, ~8% battery per 10 min." Nobody else does this. It's also unfakeable without his benchmark work.

**App — Android acceleration (R8 is mislabelled).** "Closed via wiring the AAR, CPU-only, no GPU offload" isn't closed, it's *accepted* — and it's the central product risk, not medium. Measure the number first. If a 3B Q4 lands at 3–5 tok/s, then llama.cpp's OpenCL (Adreno) or Vulkan backend is existential, not optional. If it's 10–12 tok/s, ignore it. Either way: **decide from a measurement, not from a risk register.**

**App — positioning fallback.** If real mid-range Android numbers are bad, the honest product shrinks to 0.5B–1.5B models doing short tasks (summarize/translate/extract) rather than open-ended chat. That's the share-sheet product in #3.1. Discover this in one day, not after Loop 14.

**Website.** Weak: a features page. Good: a 15-second airplane-mode video above the fold, the live crowd-sourced benchmark table (phone model → model → tok/s), and store buttons. The benchmark table is the page people link to; it's the whole SEO and credibility play.

**GitHub README.** Weak/unknown. Good: animated GIF in the first screenful, real benchmark table, install links, one-paragraph architecture note about the isolate-lifecycle/leak work (R6). That paragraph is what makes an engineer email him about contract work.

**Build/CI.** Debug keys after 209 commits is the tell. Generating an upload keystore is a 30-minute task that has blocked launch for six weeks.

---

## 5. Top 1%

Competent apps in this category all have: model download, chat, maybe voice. Four things separate top 1%:

1. **Honesty about performance.** Everyone lists models; nobody tells you what they do on *your* phone. Being the only app that measures and shows it is defensible and cannot be faked without doing the same work.
2. **Time-to-first-token from cold install under 2 minutes.** In practice this is the whole retention curve.
3. **Designed around what small models are actually good at** (summarize/translate/rewrite/extract) rather than pretending to be ChatGPT. Chat becomes the secondary surface, not the primary one.
4. **Never OOMs, never loses a chat.** His R6 leak work is already best-in-class thinking; make it a stated guarantee.

**Unfair advantages (two, both real):**
- He has built the hardest layer in the Flutter ecosystem — FFI + isolate lifecycle + a leak workaround upstream hasn't merged + vendored xcframework + AAR + multimodal mtmd + sherpa — **cross-platform from one codebase.** Competitors are single-platform (Private LLM = iOS, Layla/ChatterUI = Android). Nobody has cross-platform on-device multimodal in Flutter.
- **India / Indic / low-end device / genuinely offline.** Western indies don't care; Apple and Google underserve it.

**Deliberately NOT do:** cloud fallback. Accounts/login. Any telemetry. Subscriptions (indefensible with zero server cost — users know). Image generation. An agent/tool framework. Desktop. Self-hosted model distribution. And notably **not** the companion/NSFW pivot — it's where the money in this category actually is, but it's a different product, an App Store liability, and it burns the trust brand that is his only moat.

**Strategic threat to price in now:** Apple shipped the Foundation Models framework in iOS 26 (WWDC 2025) — any app can call a system on-device ~3B model for free. Android has Gemini Nano via ML Kit GenAI on flagships. **On-device inference has been commoditized by the platform vendors on new hardware.** Dhruva's remaining defensible ground is exactly: bring-your-own-model, uncensored, swappable, works on cheap/old Android, works with no SIM, works in Hindi. Lean all the way into that and stop competing on "on-device" as a generic feature — that fight is over.

---

## 6. Plan after dev completes — reject the premise

"After dev completes" is the trap. Redefine done as **10 days from now**, not four loops away.

**Day 0 (today).** Get an Android phone in hand (₹0 if he owns one, else ₹8–12k used, 8GB RAM). Install the current debug APK. Run every shipped feature. Write down real tok/s, thermals, battery drain, and every crash. This closes R1, R9, R11, R14 in an afternoon.

**Day 1.** Generate the upload keystore, wire signing, build a signed AAB (30–60 min — this is H3, and it has cost 6 weeks). Pay the ₹2,000 Play Console one-time fee. **Recruit 12 closed-testing testers today** — Google requires new personal developer accounts to run 12 testers for 14 continuous days before production access. *Verify the current rule in Play Console, but if it applies, that 14-day clock is the real launch date and every day he doesn't start it is a day of pure slip regardless of code.*

**Days 2–3.** Fix what the phone revealed. It will reveal a lot.

**Days 4–5.** Record the airplane-mode demo (30 seconds, mode toggle visible on screen). Rewrite the README with the GIF on top. Draft the r/LocalLLaMA benchmark post.

**Days 6–8.** Ship the first-run benchmark feature (#3.2) and the fast-first-answer path (#3.3).

**Days 9–10.** Play Store production submission. Post the benchmark data to r/LocalLLaMA. Show HN 3 days later.

**iOS: deprioritise.** $99/year, review friction, and Apple's own free on-device model competing directly. Android first — it's also where the India/low-end story lives. Do iOS after Android shows signal.

Then, and only then, L9 RAG and the Indic catalog — informed by what real users said.

---

## 7. Marketing plan — zero budget, in priority order

**1. r/LocalLLaMA (several hundred thousand members) — highest leverage by a wide margin.**
They punish promo and reward data. So the post is **data first, app second**: *"I benchmarked 12 GGUF models across N Android phones — real tok/s, thermals, and battery drain per model. Table inside. Tool is open source."* The app is a link at the bottom. Also: reply to every "which mobile app for local LLMs?" thread — there's one most weeks. That reply channel alone is worth more than any launch post.

**2. Show HN.** One shot; the title carries it. *"Show HN: Dhruva – offline LLM chat for Android, bring your own GGUF."* Needs the GIF. 5k–30k visits if it lands.

**3. GitHub as the marketing surface.** GIF above the fold, benchmark table, install links. PRs to `awesome-llm`, `awesome-flutter`, `awesome-local-llm`, `awesome-selfhosted`. Free, permanent, compounding.

**4. 30-second vertical video: airplane mode ON, phone answering questions.** That single visual *is* the pitch. Post to Shorts / Reels / X. Costs nothing, is the most shareable thing he will ever make about this product.

**5. X/Twitter** — Flutter community + local-LLM community. Build-in-public thread built on the benchmark data, not on screenshots.

**6. r/india, r/developersIndia, r/Android** — the Hindi/offline/cheap-phone angle, once Indic models ship.

**7. Product Hunt** — do it, expect little; this category doesn't index there.

**The actual message.** Not "privacy." Twenty years of evidence says consumers don't buy privacy. Sell the concrete consequence:
- **"Works in airplane mode."** (flights, metro, trains, villages, hospitals, basements)
- **"No subscription. No account. No internet. Ever."**
- **"Your medical report never leaves your phone."**

**First 100 users:** 20 from r/LocalLLaMA comment replies, 20 from Show HN, 20 from GitHub + awesome-lists, 20 from Flutter Discord/X, 20 from his own network and dev WhatsApp groups. **Ask each of the first 30 for exactly one thing: their phone model and measured tok/s.** That simultaneously closes his highest-severity risks and builds the benchmark dataset that becomes his best marketing asset. One ask, three payoffs.

**Measure 5 numbers weekly, nothing else:** installs; % completing first model download; D7 retention; messages/user/week; GitHub stars. If #2 is under 30%, onboarding is the product problem and no feature work matters.

---

## 8. Pricing

**Core app: free, Apache 2.0. Keep it.** Three reasons: the audience that will find this is anti-paywall and will fork within a week; charging for a wrapper around free models with zero server cost is indefensible and users see through it; and the actual return is credibility, not cash.

**One paid thing, and be honest about what it is:** **Dhruva Pro, one-time IAP, ₹499 India / $7.99 global.** One-time, not subscription — he has no recurring cost, and pretending otherwise is the fastest way to lose the trust that is his only moat.

Behind it: *convenience the source code doesn't give you* — pre-quantized model bundles on fast CDN, extra voice packs, per-character voices, unlimited RAG documents, and plainly "support development." **Nothing that's already free in the OSS build goes behind it** — that breaks the promise and is the one mistake that would actually damage him. The F-Droid / GitHub build stays 100% functional. This is the Organic Maps / Syncthing model: it earns tens of thousands of rupees, not lakhs. Ship it because it's 2 days of work and it validates whether anyone values this at all — the ParkOS lesson is *ask for money once, early*, even if the number is small. **The information is worth more than the revenue.**

**Where the money actually is (name it explicitly):**
- On-device AI implementation work: **$60–100/hr remote, or ₹2–6 lakh fixed-scope in India.** Dhruva is the portfolio piece that wins it. Put "available for on-device AI work" in the README and on the website.
- `flutter_local_llm` as an extracted package with paid integration support: **$1,500–3,000 per engagement.**

---

## 9. Kill criterion

**If by 2026-12-15 Dhruva has <2,000 Play Store installs or <15% D7 retention, feature work stops permanently; the repo and website stay live as a portfolio and lead-gen artifact only.**

---

## What I'd need to know, and how to get it cheap

| Unknown | Why it decides things | Cheapest way to find out |
|---|---|---|
| Real tok/s for 1B / 3B Q4 on a mid-range Android | Determines whether this is a chat product or a summarize/translate product | One afternoon, one phone. ₹0–12,000. |
| Battery drain per 10 min of generation | The #1 reason users delete on-device AI apps | Same afternoon. |
| iOS Metal tok/s on real hardware | Whether iOS is worth $99/yr against Apple's free system model | Firebase App Distribution to any friend's iPhone. ₹0. |
| Onboarding completion rate | Whether feature work matters at all yet | Local counters + 30 testers. ₹0. |
| Whether the Play 12-tester/14-day rule applies to his account | It sets the real launch date | Open Play Console today. 10 minutes. |
| Does anyone pay ₹499 | The ParkOS lesson, applied early | Ship the IAP with launch, not later. 2 days. |

**Bottom line: the code is not the bottleneck and hasn't been for six weeks. A phone, a keystore, and 12 testers are the bottleneck — total cost ₹10–14k and about two days of work. Everything on Loops 8–14 is a more comfortable way to avoid that.**

======================================================================
FROM: Claude
======================================================================

# Dhruva review — Claude

**Bottom line up front:** Dhruva is not the ParkOS failure. ParkOS was 11 months of sunk cost with a broken paywall. Dhruva is ~2 weeks of build (Jul 17 – Aug 1, 209 commits) sitting 2 weeks from shipped, with a plan that calls for 8+ more weeks of features first. The failure mode here isn't "never charged" — it's "never shipped." Same disease, different costume. Invert the order: ship the 2 weeks of unglamorous work, kill Loops 8/10/10.5/11 entirely.

And the honest part he won't like: **this will not make meaningful money, and he should stop trying to make it make money.** The correct return on Dhruva is audience, credibility, and one extractable asset. I'll show the arithmetic.

---

## 0. The single most damning fact

**The app has never run on a phone.** Not "insufficiently tested" — never executed on the hardware its entire value proposition depends on. 64.9 tok/s on macOS Metal is a number about an M-series Mac, not about a phone; it is closer to marketing copy than to evidence. R1, R9, R11, R14 are all the same risk wearing four hats.

This isn't a Loop 13 checkpoint. It's an unvalidated core assumption sitting behind 906 passing unit tests, which is exactly the shape of "everything reports success while the thing that matters is unverified."

Cheapest fix, today, ₹0: **Samsung Remote Test Lab** (free, real Galaxy hardware over the web, requires only a Samsung account). Install the debug APK, load Qwen2.5-1.5B Q4_K_M, measure tok/s and time-to-first-token. Second cheapest: ₹8,000 for a used Redmi Note with 6GB RAM — the exact device his home market actually owns. Do this **before** any further code.

My prediction, stated so it can be falsified: **on a mid-range Android with CPU-only inference (R8), a 1.5B Q4_K_M model runs at 4–9 tok/s with 2–6s time-to-first-token, and thermal-throttles inside 3 minutes of sustained generation.** If that's true, the product as currently built is unusable on the majority of its addressable Android devices and Android GPU offload becomes the #1 engineering priority, ahead of every planned loop. If I'm wrong and it's 15+ tok/s, ship immediately and ignore the rest of this paragraph. Either way, the measurement costs one afternoon and reprioritizes the entire roadmap.

---

## 1. Worth continuing? Yes — with a hard time box and a changed goal

**Continue, but reframe from "product" to "credibility asset + one extractable package," and cap it at 3 weeks of work.**

Sunk cost is low (~2 weeks), marginal cost to ship is low (keystore ≈ 1 hour, store listing ≈ 1 day, device QA ≈ 3 days), and the artifact has standalone career value. Killing something 2 weeks from done is worse than shipping it.

**What would have to be true for it to deserve another 6 months** — all three, measured at the Dec 15 gate:
1. ≥5,000 installs with ≥25% day-7 retention (proves people actually use a local LLM, not just try one)
2. ≥500 GitHub stars *or* ≥3 inbound consulting/collaboration inquiries traceable to it
3. Verified ≥12 tok/s on a ₹20,000-class Android phone

Miss any one → it stays a portfolio piece, not a project. Miss all three → archive.

**If it gets shelved:** do *not* delete. Extract `engine_bindings/` + the isolate lifecycle management + the download/integrity manager + the vendored xcframework build script into a standalone pub.dev package (`flutter_local_llm` or similar). That's the genuinely scarce artifact here — see §5.

---

## 2. Money: the arithmetic

**Comparables (directionally, from public knowledge — verify before betting on them):** PocketPal AI (open source, free, large install base, no revenue model). Private LLM (iOS/macOS, ~$10–20 one-time, the clearest proof that iOS users *will* pay for a local LLM). Layla (Android, ~$20 one-time, roleplay/companion — the other category that demonstrably converts). ChatterUI, LM Playground, MLC Chat, Google's own AI Edge Gallery — all free.

**Structural headwind he must price in:** both platform vendors now ship an on-device model *for free to every app*. Apple's Foundation Models framework (iOS 26) exposes a ~3B on-device model via API; Android has Gemini Nano via ML Kit GenAI. "Runs AI on your phone privately" stopped being a product in 2025 and became an OS feature. What's left as differentiation is **model choice, model quality above what the OS gives you, and uncensored/unrestricted** — not "on-device" as such.

**Funnel, honest:**

| Stage | Realistic | Optimistic |
|---|---|---|
| Launch-week installs (strong r/LocalLLaMA post + Show HN) | 1,500 | 6,000 |
| Year-1 installs, no sustained marketing | 6,000 | 25,000 |
| Paid conversion, free app + $9.99 one-time Pro IAP | 1.5% | 3% |
| Paying users | 90 | 750 |
| Gross | $900 | $7,500 |
| Net after 15–30% store cut | **~$700** | **~$5,800** |

**Realistic year 1: ₹60,000 – ₹5,00,000. Most likely near the bottom.** Paid-upfront instead trades a 20–50× download collapse for a higher rate and lands in the same band.

Two corrections that make this worse for him specifically:
- **India is the wrong home market for this product.** Median Indian Android device is 4–6GB RAM with no usable GPU offload path, and Play Store India ARPU on paid utilities is near zero. His nearest, cheapest users are his least monetizable users. iOS/US/EU is where the ~$10 one-time actually converts, and that's the market he has no distribution into.
- **Support cost is not zero even though infra cost is.** "Model download failed," "app crashed on my Poco," "why is it slow" — a free app with 10,000 installs generates real inbound. At ₹700/year of revenue that's negative hourly.

**Verdict: no revenue model clears ₹1 lakh/month here. Stop optimizing for app revenue.** The revenue model that fits is indirect: this artifact sources **on-device/edge-AI contract work**, which bills ₹1.5–4L/month domestically or $80–150/hr internationally. One contract > every rupee this app will ever earn. Optimize the product for *legibility to that buyer*, not for IAP conversion.

**The one exception, stated plainly because it's true:** the on-device LLM apps that actually make money are the companion/roleplay ones, because that user pays *specifically* for private and uncensored. Characters is already shipped. A roleplay-first fork with a ₹1,499 one-time unlock is the single highest-revenue path available from this codebase, by maybe 10×. It's a different product with different marketing, different content-moderation exposure, and probably not what he wants to be known for. Naming it so the decision is conscious rather than accidental.

---

## 3. Features to ADD, ranked by value × ease

Every item here is chosen because it serves distribution or the core perf story. Nothing that just adds surface area.

**1. On-device benchmark + one-tap share (3–4 days) — do this first, before launch.**
App measures tok/s, TTFT, peak RAM, and thermal state for the loaded model on *this* device, and renders a shareable card. Then post on r/LocalLLaMA *pre-launch*: "I built a Flutter local-LLM app but I only have 2 devices. Will you run this 60-second benchmark and post your numbers?" This simultaneously (a) closes R1/R9/R11/R14, the highest-severity risks in the file, (b) recruits the first 200 users, (c) generates the exact content that audience upvotes, and (d) builds a public device-performance database nobody else has. It is the highest-leverage thing in this entire review.

**2. Measured-not-declared device tiering (2 days).** Today tiers come from a spec sheet (1B→4GB, 3B→6GB). Replace with: on first run, benchmark the actual device, then recommend from measured throughput. Prevents the #1 one-star review — "downloaded 2GB, phone got hot, app crashed."

**3. Android GPU/NPU offload — Vulkan or the Adreno OpenCL backend (4–7 days, uncertain).** R8 is marked "closed" because the AAR is wired in. It is not closed; CPU-only on Android is the difference between a usable product and a demo. If §0's measurement comes back under 10 tok/s, this jumps to #1. Fiddly per-SoC, so time-box it and ship whichever backend works on Snapdragon 7-series and up.

**4. Import GGUF from device storage / SAF (1 day).** Power users have models already. Trivial to build, disproportionately loved by the exact audience that'll star the repo.

**5. Local OpenAI-compatible server mode (2–3 days).** Phone exposes `/v1/chat/completions` on the LAN. Genuinely novel, extremely legible to the r/LocalLLaMA crowd, and it's the demo that makes people share the app.

**6. Document RAG — Loop 9 (1–2 weeks, post-launch, only if requested).** The one planned feature with a real answer to "why not just use ChatGPT": *"summarize this confidential PDF without it leaving my phone."* But it is the third-hardest thing here (chunking, retrieval quality, PDF parsing on mobile) and it must not block launch. Hold it as the v0.6 headline.

**Explicitly cut: Loop 8 (image generation), Loop 10 (Toolbox), Loop 10.5 (AI News), Loop 11 (Arena).**
- Image gen: SD on a phone is 30–90s per image, hot device, mediocre output at mobile quantization. Weeks of work for a feature that is strictly worse than free cloud alternatives and will generate most of the crash reports.
- AI News: an RSS reader with zero relationship to the core value, requiring perpetual curation he won't do.
- Toolbox: OS-integration surface (alarms, intents) with permission and platform-fragmentation cost, no pull.
- Arena: feature #1 above already delivers the useful 20% of it.

That's ~6–8 weeks recovered.

---

## 4. Improvements per surface

**Engine layer (the actual product).** Weak: R13 — prefill-time context overflow still *fails*, i.e. a long paste crashes generation. That's a user-visible hard failure and it should not ship. Good = client-side history truncation with a visible "trimmed earlier messages" affordance; do it in Dart today rather than waiting on an engine pin bump. Also R6: the 167MB/reload leak is mitigated by owning the isolate, but "RSS flat after reload" was measured on macOS with GBs of headroom — on a 6GB Android phone under memory pressure the OS kills the app instead. Re-verify on device.

**App / UX.** Weak: the mental model. "Pick a model → download 1–2GB → wait → chat" is a brutal first run. Good = ship a ~350MB model (Qwen2.5-0.5B Q4) *bundled or auto-fetched during onboarding* so the user is chatting inside 60 seconds, and offer the bigger download as an upgrade after they've seen it work. First-run time-to-value is the single biggest lever on retention for this category. Also weak: 70+ tap-target lint violations sitting in TASKS.md — that's an accessibility failure and a Play Store pre-launch-report flag. Fix with the shared IconAction widget before submission, it's half a day.

**Website.** It's currently a spec sheet. Weak: no proof, no motion, nothing to do. Good = (a) an autoplaying screen-recording of real generation at real speed on a real phone, above the fold, unedited, with the device name and tok/s overlaid; (b) a live device-performance table populated by feature #1; (c) exactly one CTA. The truthful build-status page is genuinely a brand asset — keep it, and link it from the store listing as "we publish what doesn't work yet." Nobody in this category does that.

**Distribution pipeline.** Weak: debug keys, no CI release path, no store metadata. Good = signed AAB + IPA out of GitHub Actions on tag. Note: **the ParkOS Play Store work already in flight is directly reusable** — same keystore procedure, same Play Console, same service account pattern. Second time is a day, not a week. And if his Play developer account is new/personal, Google's closed-testing requirement (12 testers, 14 continuous days, before production access) is a ~3-week wall clock — **start that timer this week or it becomes the launch blocker**, regardless of code state.

---

## 5. Top 1%, unfair advantage, and what not to do

**What separates top 1% in this category:** it is not features. Every competitor has chat, characters, and a model browser. Top 1% is decided on exactly three axes:
1. **Time-to-first-token and tok/s on mid-range hardware.** The app that makes a ₹20,000 phone feel fast wins. Everything else is decoration on top of that number.
2. **Curation over choice.** Every competitor dumps Hugging Face search on the user, who then downloads a broken quant and concludes local LLMs are bad. The 1% app says: *"For your exact device, these three models. This one is best. Here's why."* Dhruva has half of this already (device-aware verdicts) — this is the differentiator, and it should be the marketing message, not a settings detail.
3. **It does not melt the phone.** Thermal and battery behavior is the thing reviewers actually complain about and the thing nobody engineers for.

**Unfair advantages, ranked by realness:**
- **The Flutter on-device inference stack itself.** Every serious competitor is native Swift/Kotlin or React Native. A working, leak-managed, KV-reusing, iOS-xcframework-vendored, integrity-checked-download Flutter LLM stack does not exist as a package. **This is the most valuable thing he built and it's currently trapped inside an app.** Extract it. A package with 300 stars and 40 dependent apps is a better credibility and lead-generation asset than the app will ever be, and it costs one week.
- **Low-end-device validation.** Western indie devs test on Pixels and iPhone Pros. "Verified on a ₹15,000 Redmi" is unowned positioning, and he's sitting in the market where those devices are.
- **Build velocity.** The loop system means he can turn a Reddit feature request around in 48 hours. That's a marketing weapon if he does it publicly.

**Deliberately NOT:** on-device image generation. A cloud fallback of any kind (it destroys the only claim). Fighting Apple/Google's built-in on-device models on "private AI" as such. Enterprise/B2B ("on-device AI for hospitals") — that's a 9-month sales cycle he has no appetite for. And **no subscription** — there is no server cost, users know it, and it will read as extractive.

---

## 6. Code-finished → users-in-hand

**Do not wait for "code finished." That's the trap.** The sequence, starting this week:

- **Day 0 (today):** Samsung Remote Test Lab. Measure tok/s + TTFT on two real Androids. Write the numbers in RISKS.md. This gates everything after it.
- **Day 1:** Generate the release keystore (`keytool`, 20 minutes — this has been a "checkpoint" for 6 weeks and it's a coffee-break task). Start the Play closed-test 14-day clock if the account needs it. Reuse the ParkOS playbook.
- **Days 2–5:** Fix R13 (client-side truncation), the tap-target sweep, and bundle the small model for instant first-run.
- **Days 6–9:** Build feature #1 (benchmark + share card).
- **Day 10:** Post the benchmark recruitment thread on r/LocalLLaMA *before launch*. Target: 50 device reports. This is the pre-launch audience.
- **Days 11–17:** Fix whatever the 50 devices break. This is the on-device QA pass, done free and in public.
- **Day 18:** Play Store production + TestFlight → App Store submission. iOS review 1–3 days.
- **Day ~21 (≈Oct 3):** Launch day — see §7.
- **Days 22–35:** Respond to every single comment, ship a fix within 48 hours of each valid bug, post the changelog publicly. Velocity *visible in public* is the marketing.
- **Week 6:** Extract the Flutter package, publish to pub.dev, write the "how I got llama.cpp running well in Flutter" post. This is the piece that generates inbound work.

**Day 1 after the last commit is not a thing. There should be no last commit before launch.**

---

## 7. Marketing — zero budget, solo

**The message.** Not privacy. "Privacy" is the thing everyone in this category says and nobody pays for; Apple and Google now say it too, for free. The message is **speed and honesty, backed by numbers:**

> *"A local AI that's actually usable on a normal phone. Qwen2.5-1.5B at 11 tok/s on a Redmi Note 13. Open source, Flutter, no server, no account. Here's the full device benchmark table — including the phones where it's too slow."*

Publishing where it *doesn't* work is the hook. In a category full of overclaiming demos, the honest benchmark table is the thing that gets upvoted and remembered.

**Channels, in order:**
1. **r/LocalLLaMA** — the entire addressable early audience is here. Two posts: the pre-launch benchmark recruitment (day 10) and the launch (day 21). Never lead with the app; lead with the data. This community punishes marketing and rewards artifacts.
2. **Hacker News, Show HN** — "Show HN: Dhruva – open-source local LLM for Android/iOS in Flutter, with the benchmark table." Tuesday–Thursday, ~8am ET. The Flutter angle is the novelty for this crowd.
3. **GitHub** — topics `llama-cpp`, `on-device-ai`, `flutter`, `local-llm`. A README with a GIF above the fold and the device table. Stars are the credibility currency that the consulting buyer actually checks.
4. **The extracted pub.dev package + a technical writeup** — "Running llama.cpp in Flutter: isolate lifecycle, the 167MB leak, and vendoring an xcframework." This is the highest-value single artifact for lead generation, and it's a post he can write from LOOP_LOG.md in an afternoon.
5. **Hugging Face community post + X/Twitter local-model accounts.** Low effort, tag the model authors whose GGUFs he ships — several will reshare.
6. **Indian tech press / r/india / r/developersIndia** — "built by an Indian solo dev, works on the phones we actually own." Weak monetization, real story value.

Product Hunt: skip. Wrong audience, minimal durable traffic for a dev tool in 2026.

**First 100 users:** they come from the day-10 benchmark thread, not from launch. People who ran his benchmark already have the app installed and are personally invested in the results. That's a 100-person pre-launch cohort acquired for the cost of one Reddit post.

**Measure exactly five things** (all obtainable without telemetry — store console + GitHub, consistent with the no-telemetry stance):
- Installs, day 1 / day 7 / day 30
- Day-7 retention (store consoles give this free) — **this is the number that matters**; a local LLM that people try once and abandon is a demo, and I'd expect the honest figure to land in the 10–20% range
- GitHub stars and, more importantly, *issues opened* (issues = real usage)
- Benchmark submissions (his own growth-loop metric)
- Inbound contact: consulting inquiries, contributor PRs, press

If he adds any optional analytics, make it explicitly opt-in with a visible toggle — a telemetry SDK in a "no telemetry" app is the one mistake that would permanently destroy the brand.

---

## 8. Pricing

**Core app: free, open source, Apache 2.0. Correct — keep it.** Reasons: (a) the audience that adopts local LLMs is the same audience that will not pay for one and *will* fork a paid one within a week; (b) zero server cost means no economic pressure to charge; (c) the return here is audience and credibility, and a price tag reduces both by an order of magnitude for a gain of ~₹60k/year.

**The alternative return, named concretely:** consulting and employment leads in on-device/edge AI. That's ₹1.5–4L/month domestically, $80–150/hr internationally. The conversion asset is the *extracted Flutter package + technical writeup*, not the app. Budget one week for that; it has a higher expected value than every monetization option below combined.

**But he must ask for something.** ParkOS failed because nobody was ever asked to pay. Dhruva's version of that mistake is nobody ever being asked for anything at all. Three asks, in priority order — all cheap, none compromising:
1. **GitHub Sponsors + a "Support" row in the About screen.** Expect ₹0–5,000/month. The point is the option existing, not the revenue.
2. **"Hire me" / consulting link in About and in the website footer,** with a one-line statement of what he does. This is the actual revenue channel; it costs 30 minutes.
3. **iOS one-time "Dhruva Pro" at $9.99 / ₹499, but only after ≥5,000 installs and only if unsolicited requests appear.** iOS is the only side that converts. Unlock must be strictly non-core so the OSS promise holds: extra TTS voices, benchmark history and comparison, theme packs, priority issue triage. Never gate a model, never gate chat.

**Explicitly reject:** any subscription, any ads, any paid-upfront listing.

---

## 9. Kill criterion

> **If by 2026-12-15 Dhruva has not reached 5,000 total installs AND ≥20% day-7 retention AND at least one inbound consulting or contributor lead traceable to it, then archive both repos, publish the extracted Flutter inference package to pub.dev, write the technical postmortem, and stop all further work.**

(If it hasn't *launched* by 2026-10-10, that's the earlier and more damning kill — it means the ParkOS pattern repeated and the decision is about him, not the product.)

---

## What I'd need to know, and how to get it cheaply

| Unknown | Why it matters | Cheapest way | Cost |
|---|---|---|---|
| Real tok/s + TTFT on 2–3 mid-range Androids | Determines whether the product is viable at all; reprioritizes the whole roadmap | Samsung Remote Test Lab | ₹0, today |
| Thermal + battery drain over 10 min sustained generation | The #1 source of one-star reviews in this category | Same, or a used Redmi | ₹0–8,000 |
| Does he already have a Play developer account (via ParkOS) and has it cleared the 12-tester/14-day gate? | Could be a hidden 3-week launch blocker | Check Play Console | 5 min |
| Is the Apple Developer account ($99/yr) active? | Gates the only side that monetizes | Check | 5 min |
| Does *anyone* outside him want this? | The whole thesis | Post the day-10 benchmark thread on r/LocalLLaMA and count replies | ₹0, one post |

I've deliberately not invented install or revenue figures for competitors — the comparables above are directional from public knowledge and should be spot-checked (App Store rank trackers, GitHub star counts) before any of them is used as a forecast anchor.

---

## Where I expect to disagree with the rest of the council

1. **If anyone recommends a freemium tier or subscription as the path to revenue — I disagree.** The math tops out around ₹5L/year in the *good* case and lands near ₹60k in the likely one, while adding store compliance, refund handling, and support load. That's negative on an hourly basis for this founder. Monetize the skill, not the app.
2. **If anyone says "finish Loops 8–11 first, then launch" — strongly disagree.** That's 6–8 weeks of building before a single real user touches it, on an app that has never run on a phone. It's the same instinct that produced ParkOS, just aimed at features rather than at a paywall.
3. **If anyone treats "privacy" as the marketing hook — disagree.** Apple and Google now ship free on-device models. Privacy is table stakes and undifferentiated. Speed on cheap hardware, plus published honest benchmarks, is the position that's actually unoccupied.
4. **If anyone says kill it outright — disagree.** Sunk cost is only ~2 weeks and it's 2 weeks from shipped. The extractable Flutter package alone justifies finishing. Kill it in December if the numbers say so, not now.

**The one-sentence version: measure it on a real phone this week, cut four loops, ship by October 3, and treat the extracted Flutter inference package — not the app — as the thing that actually pays.**

======================================================================
FROM: Claude
======================================================================

# Claude — Dhruva review

**Headline verdict: this is not a business, it is a very good marketing asset that has been mistaken for a business. Finish it in 3 weeks, ship it, then stop. Do not spend 6 more months. Do not build Loops 8, 10, or 10.5.**

The single most damning fact in the brief: RISKS.md has four HIGH-severity risks (R1, R9, R11, and effectively R2), and all four have the same root cause — **he does not own a phone to test on** — and the same fix, which costs about ₹15,000. Instead of buying the phone, he wrote a risk register about not having the phone, then stalled for six weeks. That is the ParkOS pattern in a different costume: ceremony substituting for contact with reality. 906 unit tests and 14 ADRs for an app with 2 users is not rigor, it is avoidance.

---

## 1. Is it worth continuing?

**Yes for 3 more weeks. No for 6 months.**

Ship it as a credibility asset with a B2B funnel bolted on. It deserves another 6 months **only if** by **2026-12-15** (90 days post-launch) it clears one of: 5,000+ Play installs, or 1,000+ GitHub stars, or 3+ inbound B2B conversations from companies wanting offline AI. Any one of those means real distribution exists and is worth feeding. Zero of those means it's a résumé line — archive it, keep it live and unmaintained, and move on.

Do not kill the code. Even in the failure case it retains value (see §3.1, the pub.dev package).

**Portfolio-level call, since you gave me the context:** ParkOS has a real customer and ₹0 revenue because nobody was asked to pay — that is a fixable distribution problem on a real business. Dhruva has no customer and *structurally cannot* have meaningful revenue. Dhruva gets 3 weeks then 2 hours/week. ParkOS gets everything else. If those two compete for the same Tuesday, ParkOS wins every time.

---

## 2. Will it make money? The arithmetic.

**Direct consumer revenue: effectively ₹0. Treat it as ₹0 in every plan.**

Realistic zero-budget launch funnel, based on how this category actually performs:
- r/LocalLLaMA post that lands well (500–1,500 upvotes): ~10k–40k views → 1–3% click → **300–1,200 installs**
- Show HN, ~30% chance of front page: 5k–20k visits → 2–5% → **100–1,000 installs**
- F-Droid + GitHub + organic long tail over 12 months: **500–3,000 installs**
- **Y1 total, realistic median: ~3,000 installs. Downside: 800. Upside: 10,000.**

Monetization scenarios on 3,000 installs:
- **Freemium IAP at ₹499 lifetime:** 2% convert = 60 × ₹499 × 0.85 store cut = **₹25,000/year.** Not a business.
- **Paid upfront at $4.99:** installs collapse 10–20×; ~200 sales × $4.99 × 0.85 ≈ **₹70,000/year.** Also not a business, and it destroys the only distribution channel you have (see §8).
- **Donations (GitHub Sponsors + UPI QR):** a 500–2,000-star project typically nets **₹0–25,000/year.**

**The only path with real money is B2B, and it is consulting, not product.** You have a working Flutter↔llama.cpp FFI layer with owned isolate lifecycle, a fix for a 167MB/reload leak the upstream package still has, prefix-KV reuse, whisper STT, sherpa TTS, and mtmd vision. That is genuinely hard and genuinely rare in the Flutter ecosystem. Indian enterprises with offline field staff or DPDP Act data-residency constraints will pay for it.

- **Realistic B2B outcome Y1:** 0–2 contracts × ₹3–8L = **₹0–16L.**
- **Probability-weighted expected value of the whole product over 12 months: ~₹2–3L**, with a fat tail at ₹0 and a thin tail at ₹15L+.
- **Incremental cost to get there:** 3 weeks of your time + ~₹25,000 cash (phone ₹15k, domain ₹1.5k, Play account $25, Apple $99).

That's a good trade for 3 weeks. It's a terrible trade for 6 months.

**The honest structural problem with the consumer thesis, stated plainly:** a Q4 1B model on a CPU-only mid-range Android will produce visibly worse answers than free Gemini/ChatGPT, slower, while heating the phone and eating battery. The set of people who accept that tradeoff for privacy is small, technical, and — this is the killer — *does not pay for wrappers around llama.cpp, because they can build one*. And your home market is the worst market for this: the median Indian Android phone is 4GB RAM entry-level silicon. You are shipping the most demanding possible app class to the least capable install base.

---

## 3. Features to ADD, ranked by value × ease

**1. Extract and publish `dhruva_engine` to pub.dev — 3–5 days. Highest ROI item in this entire review.**
You already wrote it; this is extraction and documentation, not new code. `llama_cpp_dart` is stale and leaks; you fixed the leak. A clean, maintained, documented Flutter package for on-device LLM inference does not currently exist well. This becomes your developer funnel, your B2B lead source, and your credibility proof — and it survives even if the app flops. Also send the leak fix upstream as a PR: free credibility and a permanent inbound link.

**2. Buy a phone. Build the "Dhruva Device Index." — 4–6 days including the web page.**
Your Playground already measures tok/s, RAM, and thermals. Add a "copy benchmark" button that emits a shareable text blob (no telemetry, user-initiated — brand-consistent). Publish a public table: device × model × tok/s × RAM × thermal throttle point. **Nobody has this data publicly and everybody in r/LocalLLaMA wants it.** This is your top-1% differentiator, your SEO magnet, your permanent citation in that community, and — critically — it's the *content* that makes your launch post work (§7).

**3. Time-to-first-token under 90 seconds. — 2–3 days.**
Today onboarding asks a stranger to download 700MB–1.1GB before they see a single token. You will lose 70%+ there and never know it. Bundle or fast-fetch a ≤400MB model (Qwen2.5-0.5B Q4) as the default first run, with the big models as an upgrade. This is the largest conversion lever in the app.

**4. Thermal and battery guard with honest warnings. — 1–2 days.**
"This model will use roughly X% battery per 10 minutes and may warm your phone." Without it you get 1-star reviews that say "phone got hot" and you cannot recover from those.

**5. Offline Document RAG (your L9), reframed. — 5–7 days.**
Not "document RAG." **"Chat with confidential PDFs. They never leave your phone."** This is the *only* use case in the whole app where on-device is a purchase requirement rather than a preference — legal, medical, HR, finance, journalism. It is also your B2B demo. Keep this loop; it's the one planned feature that earns its cost.

**6. F-Droid listing. — 1–2 days + their review latency.**
Free distribution channel aimed at exactly your audience. Check early whether their reproducible-build requirement conflicts with the downloaded Android AAR — you may need to build llama.cpp from source in the recipe.

**7. Vulkan/OpenCL Android backend (GGML_VULKAN in the AAR). — 5–10 days, uncertain payoff.**
Only after #2 tells you CPU-only is genuinely unusable. This is the difference between "works on Indian Android" and "doesn't." Gate it on measured data, not on principle.

**CUT these outright:**
- **L8 image generation.** Stable Diffusion on a phone CPU is 1–5 minutes per image. It's a bad experience and a large scope. It exists to complete a feature matrix, not to serve a user.
- **L10 Toolbox.** Unrelated OS-integration scope, no user asked for it.
- **L10.5 AI News.** A network-fetching content feed inside an app whose entire brand is "zero network." It contradicts the positioning and commits you to curating content forever.
- **L11 as a full loop.** Fold the useful part into #2 above.

Cutting these three saves roughly 4–6 weeks. Spend it on distribution.

---

## 4. Features to IMPROVE, per surface

**Repo (this is a surface, and for an OSS product it is the most important one):**
- **5.3 GB repo. Fix this first.** That means models or build artifacts are committed. Nobody clones 5.3 GB. It is the single loudest "amateur" signal an OSS project can emit, and it will silently kill your contributor and inspection funnel. `git filter-repo` it down to <100MB, or publish a fresh-history public repo.
- README needs, in order: an animated GIF of it running in airplane mode, the device benchmark table, an honest comparison table vs PocketPal / ChatterUI / Private LLM / Google AI Edge Gallery (including where they beat you — that honesty is what earns HN goodwill), then build instructions.

**App:**
- **Feature sprawl.** Eight features shipped to zero users: chat, characters, voice, vision, playground, imagine, docs_chat, models hub. "Good" is three excellent features. Chat + Models Hub + Playground carry the product; voice and vision are unverified on hardware and will be your first crash reports. Consider shipping voice/vision behind an explicit "experimental" flag rather than as headline features.
- **No device-aware perf prediction.** You have `device_info` and (after #2) a benchmark index. Show "on your device this model runs at ~11 tok/s" *before* the download, not a vague "Comfortable/Possible."
- R13 (context overflow before prefill still fails) is a hard crash path in the core loop. Fix client-side history truncation before launch — it's cheaper than the engine pin bump and it's a guaranteed 1-star bug.

**Website:**
- `dhruvaai.vercel.app` is not a domain. Buy one (~₹1,500/yr). A vercel.app subdomain is disqualifying for B2B credibility and it reads as unfinished on HN.
- No benchmark page, no comparison table, no demo video.
- **No B2B page.** There is no "Need offline AI in your Flutter app? Here's what I built and here's how to hire me." That page *is* the revenue funnel. Its absence is the whole thesis of this review in one missing file.

**Distribution:**
- **Check your Play Console account type today.** If it's a personal account created after Nov 2023, Google requires 12 testers running the app for 14 continuous days before you can access production. That is a hard 14-day calendar block and it is your long pole. Start it *now*, in parallel with everything else, not after the code is done.

---

## 5. How to make it top 1%

A competent local-LLM app is a chat UI over llama.cpp. There are a dozen. The top 1% is defined by one thing: **being the authoritative source of truth for what actually works on real hardware.**

Nobody in this space publishes honest, reproducible, per-device performance data. Everybody ships a chat screen and a privacy claim. If Dhruva becomes the app that tells you *before you download* that Llama-3.2-3B-Q4 will run at 6 tok/s on your Redmi and thermally throttle after 4 minutes — and publishes that table openly — it becomes infrastructure for the community rather than one more entry in it. That's citation, that's inbound links, that's permanent relevance, and it costs you a week.

**Your unfair advantages, ranked honestly:**
1. The engine work is real and hard, and you can package it (§3.1).
2. India + DPDP Act 2023: "the data never leaves the device" is a *compliance answer*, not a feature preference. That's a B2B wedge nobody else in this app category is positioned for.
3. Multi-agent build speed — but note this advantage only compounds if you point it at distribution, and so far it has only ever pointed at more code.

**What it should deliberately NOT do:**
- Not compete on model quality. You will always lose to cloud. Compete on *guarantee* and *measurement*.
- Not add a cloud fallback, ever. It's the one thing that would make it usable and the one thing that would destroy the only reason it exists.
- Not build features that require network (AI News). The brand is the constraint; honor it.
- Not chase iOS first. Private LLM and Apple's own Foundation Models own that ground. Android, and specifically cheap Android, is unoccupied.
- Not charge for it. See §8.

---

## 6. Plan from "code finished" to users

**Day 1 after the last commit you do not write code.** You order an 8GB-RAM Android phone (₹15k) and, the day it arrives, you install Dhruva, put it in airplane mode, and record a 60-second screen capture of it working. That video is your entire marketing asset. Everything downstream depends on it existing.

- **Week 1:** Phone arrives. On-device QA — this will break things; fix only what breaks. Shrink the repo. Buy the domain. **Start the Play 12-tester/14-day clock immediately** (it runs in parallel and it's the long pole).
- **Week 2:** Record the demo. Write the benchmark harness output and the Device Index page. Write the B2B page. Extract and publish `dhruva_engine` to pub.dev. Submit to F-Droid. Prepare store listings + privacy policy.
- **Week 3:** Play open testing → production. Launch: r/LocalLLaMA post, Show HN, pub.dev announcement, upstream leak-fix PR.
- **Then 90 days with a hard rule: zero new features.** Only — respond to every single issue and comment within 24 hours, publish a new device benchmark weekly, and write four technical blog posts (the 167MB leak and how you fixed it; prefix-KV reuse in Flutter; Flutter FFI + isolate lifecycle for native inference; real tok/s across N phones). Those posts are your HN fuel, your SEO, and your B2B credibility, simultaneously.
- **In parallel, weeks 4–12:** 30 targeted outreach messages to Indian companies with offline or DPDP-driven needs — insurance surveyors, agritech field platforms, rural banking correspondents, healthcare triage, defence-adjacent vendors. The message is "here is a working offline AI app I built; here's the package; can I build this into yours?" Ten conversations is the target, one contract is the win.

---

## 7. Marketing plan, zero budget

**Channels, in strict priority order:**
1. **r/LocalLLaMA** — this is 60% of your total available distribution. Everything else is secondary.
2. **Hacker News (Show HN)** — timed for a Tuesday–Thursday morning US Eastern.
3. **GitHub itself** — the README and the pub.dev package are discovery surfaces, not documentation.
4. **F-Droid** — small but perfectly-targeted, and it discovers you rather than the reverse.
5. **X/Twitter local-LLM community** — reply to benchmark threads with your data, don't announce.
6. **LinkedIn / Indian tech networks** — B2B leads only, different message entirely.

**The actual message — and this is the most important tactical point in this review:**

Do NOT lead with "Introducing Dhruva, a private on-device AI app." That post dies at 40 upvotes. That community sees three of them a week.

Lead with the data: **"I benchmarked 8 quantized models across 6 Android phones — here's real tok/s, RAM, and thermal throttle data."** The benchmark table is the post. The app is the call-to-action at the bottom. You are giving that community something it genuinely lacks, and the app arrives as the tool that produced it. This one framing choice is probably worth 5× on the install numbers.

For B2B the message is different and shorter: *"Your field staff have no connectivity and your data can't go to OpenAI. I built a working on-device AI app; the engine is an open Flutter package. Want it in your app?"*

**First 100 users:** they come from the r/LocalLLaMA post's first 48 hours. Reply to every single comment personally. The ones who report a device you don't have are your most valuable users — they're your benchmark contributors. Ask each one directly for their device + tok/s and add it to the index. That turns readers into a data network.

**What to measure — and the honest tension:** you have no telemetry by design, so you are flying blind on the in-app funnel. Don't fix that with an analytics stack. Use what's free: Play Console gives installs, uninstall rate, and crashes with zero in-app instrumentation. **Uninstall rate in the first 7 days is your single most important number** — if it's above 50%, the model download experience is killing you (see §3.3). Supplement with 20 qualitative conversations from the launch thread. That's enough. Resist building a metrics pipeline; it would be the next place to hide.

---

## 8. Pricing

**Free, Apache 2.0, no paid tier. I'll defend this, and I'd disagree directly with anyone on this council who proposes a Pro tier or a paid app.**

Three reasons:
1. **The arithmetic doesn't clear the noise floor.** Best realistic case is ₹25k–70k/year. That is not worth the product complexity, the payment integration, the store compliance, or a single hour of your attention.
2. **It poisons the only distribution channel you have.** r/LocalLLaMA and HN will punish a paywall on an Apache-2.0 llama.cpp wrapper, and their goodwill is worth vastly more than ₹25k.
3. **It's self-defeating on the merits.** The source is public. Anyone can build it free. You'd be charging for convenience while advertising the bypass.

**The alternative return, named specifically:** credibility that converts to consulting. Target for the 90-day window: **10 B2B conversations, 1 contract at ₹3–8L.** That is 12–30× the best-case app revenue and it uses the same asset.

**One thing to add, though:** don't do "free forever, no ask, ever" — that's the ParkOS mistake in reverse (never asking). Ship a Support screen with GitHub Sponsors and a UPI QR code, and — more importantly — a prominent, unmissable **"Need this in your product? Let's talk"** link with your email on both the website and the app's about screen. Free product, but there is always a visible door to money. The failure mode you're correcting for across this whole portfolio is *never putting a door in the wall*.

---

## 9. Kill criterion

**If by 2026-12-15 — 90 days after public launch — Dhruva has fewer than 1,000 Play Store installs AND fewer than 300 GitHub stars AND zero inbound B2B conversations, stop all work: archive the app repo, keep only `dhruva_engine` published and maintained on pub.dev, and leave the app live and unmaintained as a portfolio piece.**

---

## What I'd need to know, and how to get it cheaply

Three unknowns materially change this review. All three cost under ₹20,000 and under a week combined:

1. **Real tok/s on a ₹15,000 Android phone.** If Llama-3.2-1B-Q4 does 15+ tok/s on mid-range CPU, the consumer thesis has legs. If it does 4 tok/s and throttles in three minutes, the consumer app is dead on arrival in India and you should reposition entirely as a developer package + B2B demo. **Cost: one phone.** This is the highest-information-per-rupee purchase in your entire portfolio and it has been deferred for six weeks.
2. **Your Play Console account type.** Personal-account 12×14 testing is a hard 14-day gate that determines your whole launch calendar. **Cost: one login.**
3. **Whether Indian enterprises will actually pay for offline AI.** Don't theorize — send 10 outreach messages this week, before the code is finished. If nobody replies, the B2B thesis (which is the *entire* monetary case in §2) is wrong and the kill criterion should tighten. **Cost: one afternoon.**

Do #2 and #3 today. Order the phone today. None of the three requires a single line of code, which is precisely why they haven't happened.